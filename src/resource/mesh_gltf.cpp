/*
 * Copyright (c) 2012-2026 Daniele Bartolini et al.
 * SPDX-License-Identifier: MIT
 */

#include "resource/mesh_gltf.h"

#if CROWN_CAN_COMPILE
#   include "core/containers/array.inl"
#   include "core/containers/hash_map.inl"
#   include "core/json/json_object.inl"
#   include "core/json/sjson.h"
#   include "core/math/matrix4x4.inl"
#   include "core/math/vector3.inl"
#   include "core/memory/globals.h"
#   include "core/memory/temp_allocator.inl"
#   include "core/strings/dynamic_string.inl"
#   include "device/log.h"
#   include "resource/compile_options.inl"
#   include "resource/gltf_document.h"
#   include <cgltf.h>
#   include <string.h>

LOG_SYSTEM(MESH_GLTF, "mesh_gltf")

namespace crown
{
namespace gltf
{
	struct RigidAttachment
	{
		cgltf_node *node;
		cgltf_skin *skin;
		cgltf_node *bone;
		cgltf_node *root;
	};

	static cgltf_node *find_node(const GLTFDocument &doc, const char *name)
	{
		for (cgltf_size i = 0; i < doc.data->nodes_count; ++i) {
			cgltf_node *node = &doc.data->nodes[i];
			if (strcmp(node_name(doc, node), name) == 0)
				return node;
		}
		return NULL;
	}

	static cgltf_skin *find_skin(const GLTFDocument &doc, const char *name)
	{
		for (cgltf_size i = 0; i < doc.data->skins_count; ++i) {
			cgltf_skin *skin = &doc.data->skins[i];
			if (strcmp(skin_name(doc, skin), name) == 0)
				return skin;
		}
		return NULL;
	}

	static bool ancestor_or_self(const cgltf_node *ancestor, const cgltf_node *node)
	{
		while (node != NULL) {
			if (node == ancestor)
				return true;
			node = node->parent;
		}
		return false;
	}

	static s32 parse_rigid_attachments(Array<RigidAttachment> &attachments
		, GLTFDocument &doc
		, const char *json
		, CompileOptions &opts
		)
	{
		if (json == NULL)
			return 0;

		TempAllocator4096 ta;
		JsonArray array(ta);
		RETURN_IF_ERROR(sjson::parse_array(array, json));
		for (u32 i = 0; i < array::size(array); ++i) {
			JsonObject obj(ta);
			RETURN_IF_ERROR(sjson::parse(obj, array[i]));

			DynamicString node_name_string(ta);
			DynamicString skin_name_string(ta);
			DynamicString bone_name_string(ta);
			DynamicString root_name_string(ta);
			RETURN_IF_ERROR(sjson::parse_string(node_name_string, obj["node_name"]));
			RETURN_IF_ERROR(sjson::parse_string(skin_name_string, obj["skin_name"]));
			RETURN_IF_ERROR(sjson::parse_string(bone_name_string, obj["bone_name"]));
			RETURN_IF_ERROR(sjson::parse_string(root_name_string, obj["root_name"]));

			RigidAttachment attachment;
			attachment.node = find_node(doc, node_name_string.c_str());
			attachment.skin = find_skin(doc, skin_name_string.c_str());
			attachment.bone = find_node(doc, bone_name_string.c_str());
			attachment.root = root_name_string.empty() ? NULL : find_node(doc, root_name_string.c_str());

			RETURN_IF_FALSE(MESH_GLTF, attachment.node != NULL, opts
				, "No matching glTF rigid mesh node '%s'", node_name_string.c_str());
			RETURN_IF_FALSE(MESH_GLTF, attachment.skin != NULL, opts
				, "No matching glTF rigid mesh skin '%s'", skin_name_string.c_str());
			RETURN_IF_FALSE(MESH_GLTF, attachment.bone != NULL, opts
				, "No matching glTF rigid mesh bone '%s'", bone_name_string.c_str());
			RETURN_IF_FALSE(MESH_GLTF, root_name_string.empty() || attachment.root != NULL, opts
				, "No matching glTF rigid mesh root '%s'", root_name_string.c_str());
			RETURN_IF_FALSE(MESH_GLTF
				, attachment.node->mesh != NULL && attachment.node->skin == NULL
				, opts
				, "glTF rigid attachment '%s' is not an unskinned mesh node"
				, node_name_string.c_str()
				);
			RETURN_IF_FALSE(MESH_GLTF, ancestor_or_self(attachment.bone, attachment.node), opts
				, "glTF rigid mesh bone '%s' is not an ancestor of '%s'"
				, bone_name_string.c_str()
				, node_name_string.c_str()
				);
			RETURN_IF_FALSE(MESH_GLTF
				, attachment.root == NULL || ancestor_or_self(attachment.root, attachment.node)
				, opts
				, "glTF rigid mesh root '%s' is not an ancestor of '%s'"
				, root_name_string.c_str()
				, node_name_string.c_str()
				);
			for (u32 ai = 0; ai < array::size(attachments); ++ai) {
				RETURN_IF_FALSE(MESH_GLTF, attachments[ai].node != attachment.node, opts
					, "Duplicate glTF rigid attachment '%s'", node_name_string.c_str());
			}
			array::push_back(attachments, attachment);
		}
		return 0;
	}

	static const RigidAttachment *rigid_attachment(const Array<RigidAttachment> &attachments
		, const cgltf_node *node
		)
	{
		for (u32 i = 0; i < array::size(attachments); ++i) {
			if (attachments[i].node == node)
				return &attachments[i];
		}
		return NULL;
	}

	static const cgltf_accessor *attribute(const cgltf_primitive &primitive
		, cgltf_attribute_type type
		, cgltf_int index = 0
		)
	{
		return cgltf_find_accessor(&primitive, type, index);
	}

	static bool read_float(const cgltf_accessor *accessor, cgltf_size index, f32 *out, cgltf_size count)
	{
		return accessor != NULL
			&& index < accessor->count
			&& cgltf_accessor_read_float(accessor, index, out, count)
			;
	}

	static s32 append_triangle_indices(Array<cgltf_size> &indices
		, const cgltf_primitive &primitive
		, cgltf_size num_vertices
		, CompileOptions &opts
		)
	{
		Array<cgltf_size> source(default_allocator());
		const cgltf_size count = primitive.indices != NULL ? primitive.indices->count : num_vertices;
		array::resize(source, (u32)count);
		for (cgltf_size i = 0; i < count; ++i) {
			source[(u32)i] = primitive.indices != NULL
				? cgltf_accessor_read_index(primitive.indices, i)
				: i
				;
			RETURN_IF_FALSE(MESH_GLTF, source[(u32)i] < num_vertices, opts
				, "glTF primitive index %zu is out of bounds", source[(u32)i]);
		}

		switch (primitive.type) {
		case cgltf_primitive_type_triangles:
			RETURN_IF_FALSE(MESH_GLTF, count % 3 == 0, opts
				, "glTF triangle primitive has an invalid index count");
			for (cgltf_size i = 0; i < count; ++i)
				array::push_back(indices, source[(u32)i]);
			break;

		case cgltf_primitive_type_triangle_strip:
			for (cgltf_size i = 2; i < count; ++i) {
				if ((i & 1) == 0) {
					array::push_back(indices, source[(u32)i - 2]);
					array::push_back(indices, source[(u32)i - 1]);
				} else {
					array::push_back(indices, source[(u32)i - 1]);
					array::push_back(indices, source[(u32)i - 2]);
				}
				array::push_back(indices, source[(u32)i]);
			}
			break;

		case cgltf_primitive_type_triangle_fan:
			for (cgltf_size i = 2; i < count; ++i) {
				array::push_back(indices, source[0]);
				array::push_back(indices, source[(u32)i - 1]);
				array::push_back(indices, source[(u32)i]);
			}
			break;

		default:
			RETURN_IF_FALSE(MESH_GLTF, false, opts
				, "Unsupported glTF primitive mode %d (points and lines are not supported)"
				, primitive.type
				);
		}

		return 0;
	}

	static void append_vector3(Array<f32> &array, const Vector3 &v)
	{
		array::push_back(array, v.x);
		array::push_back(array, v.y);
		array::push_back(array, v.z);
	}

	static s32 append_skin(Geometry &g
		, const GLTFDocument &doc
		, const cgltf_skin &skin
		, const cgltf_accessor *joints
		, const cgltf_accessor *weights
		, cgltf_size vertex
		, CompileOptions &opts
		)
	{
		cgltf_uint joint_values[4] = {};
		f32 weight_values[4] = {};
		RETURN_IF_FALSE(MESH_GLTF
			, cgltf_accessor_read_uint(joints, vertex, joint_values, 4)
				&& cgltf_accessor_read_float(weights, vertex, weight_values, 4)
			, opts
			, "Failed to read glTF skin weights"
			);

		struct Influence { u16 bone; f32 weight; } influences[4];
		for (u32 i = 0; i < 4; ++i) {
			RETURN_IF_FALSE(MESH_GLTF, joint_values[i] < skin.joints_count, opts
				, "glTF joint index %u is out of bounds", joint_values[i]);
			influences[i].bone = bone_id(doc, skin.joints[joint_values[i]]);
			influences[i].weight = weight_values[i];
			RETURN_IF_FALSE(MESH_GLTF, influences[i].bone != UINT16_MAX, opts
				, "glTF joint is missing from the imported skeleton");
		}

		for (u32 i = 0; i < 4; ++i) {
			for (u32 j = i + 1; j < 4; ++j) {
				if (influences[j].weight > influences[i].weight)
					exchange(influences[i], influences[j]);
			}
		}

		f32 total = 0.0f;
		for (u32 i = 0; i < 4; ++i)
			total += max(influences[i].weight, 0.0f);
		if (total <= FLOAT_EPSILON) {
			influences[0].weight = 1.0f;
			total = 1.0f;
		}

		for (u32 i = 0; i < 4; ++i) {
			array::push_back(g._bones, (f32)influences[i].bone);
			array::push_back(g._weights, max(influences[i].weight, 0.0f) / total);
		}
		return 0;
	}

	static void append_rigid_skin(Geometry &g, u16 bone)
	{
		array::push_back(g._bones, (f32)bone);
		array::push_back(g._bones, 0.0f);
		array::push_back(g._bones, 0.0f);
		array::push_back(g._bones, 0.0f);
		array::push_back(g._weights, 1.0f);
		array::push_back(g._weights, 0.0f);
		array::push_back(g._weights, 0.0f);
		array::push_back(g._weights, 0.0f);
	}

	static Matrix4x4 world_transform(const cgltf_node *node)
	{
		f32 matrix[16];
		cgltf_node_transform_world(node, matrix);
		return matrix4x4(matrix);
	}

	static s32 binding_matrix(Matrix4x4 &binding
		, const GLTFDocument &doc
		, const cgltf_node *bone
		, CompileOptions &opts
		)
	{
		binding = MATRIX4X4_IDENTITY;
		if (doc.skin == NULL || doc.skin->inverse_bind_matrices == NULL)
			return 0;

		for (cgltf_size i = 0; i < doc.skin->joints_count; ++i) {
			if (doc.skin->joints[i] != bone)
				continue;
			f32 matrix[16];
			RETURN_IF_FALSE(MESH_GLTF
				, cgltf_accessor_read_float(doc.skin->inverse_bind_matrices, i, matrix, 16)
				, opts
				, "Failed to read glTF inverse bind matrix for rigid mesh bone '%s'"
				, node_name(doc, bone)
				);
			binding = matrix4x4(matrix);
			break;
		}
		return 0;
	}

	static s32 rigid_geometry_transform(Matrix4x4 &transform
		, GLTFDocument &doc
		, const RigidAttachment &attachment
		, CompileOptions &opts
		)
	{
		s32 err = select_skin(doc, attachment.skin, opts);
		ENSURE_OR_RETURN(MESH_GLTF, err == 0, opts);
		RETURN_IF_FALSE(MESH_GLTF, bone_id(doc, attachment.bone) != UINT16_MAX, opts
			, "glTF rigid mesh bone '%s' is missing from skin '%s'"
			, node_name(doc, attachment.bone)
			, skin_name(doc, attachment.skin)
			);
		Matrix4x4 root_world = attachment.root != NULL
			? world_transform(attachment.root)
			: MATRIX4X4_IDENTITY
			;
		invert(root_world);
		// The imported unit flattens the path from this node up to root because
		// Crown applies the mesh unit's world pose after the skeleton palette.
		// Preserve those discarded transforms in the geometry, in root space.
		const Matrix4x4 relative = world_transform(attachment.node) * root_world;

		Matrix4x4 binding;
		err = binding_matrix(binding, doc, attachment.bone, opts);
		ENSURE_OR_RETURN(MESH_GLTF, err == 0, opts);
		Matrix4x4 bind_pose = binding * world_transform(attachment.bone);
		invert(bind_pose);
		transform = relative * bind_pose;
		return 0;
	}

	static s32 parse_primitive(Geometry &g
		, const GLTFDocument &doc
		, const cgltf_primitive &primitive
		, const cgltf_skin *skin
		, const Matrix4x4 &geometry_transform
		, const Matrix4x4 &normal_transform
		, bool import_tangents
		, bool import_uvs
		, bool import_skin
		, u16 rigid_bone
		, CompileOptions &opts
		)
	{
		const cgltf_accessor *positions = attribute(primitive, cgltf_attribute_type_position);
		const cgltf_accessor *normals = attribute(primitive, cgltf_attribute_type_normal);
		const cgltf_accessor *tangents = attribute(primitive, cgltf_attribute_type_tangent);
		const cgltf_accessor *uvs = attribute(primitive, cgltf_attribute_type_texcoord, 0);
		const cgltf_accessor *joints = attribute(primitive, cgltf_attribute_type_joints, 0);
		const cgltf_accessor *weights = attribute(primitive, cgltf_attribute_type_weights, 0);

		RETURN_IF_FALSE(MESH_GLTF, positions != NULL && positions->type == cgltf_type_vec3, opts
			, "glTF primitive has no valid POSITION attribute");
		RETURN_IF_FALSE(MESH_GLTF
			, (joints == NULL) == (weights == NULL)
			, opts
			, "glTF primitive must provide both JOINTS_0 and WEIGHTS_0"
			);
		RETURN_IF_FALSE(MESH_GLTF
			, !import_skin
				|| rigid_bone != UINT16_MAX
				|| (joints != NULL && weights != NULL)
			, opts
			, "All primitives in a skinned glTF mesh must provide JOINTS_0 and WEIGHTS_0"
			);
		Array<cgltf_size> indices(default_allocator());
		s32 err = append_triangle_indices(indices, primitive, positions->count, opts);
		ENSURE_OR_RETURN(MESH_GLTF, err == 0, opts);

		for (u32 triangle = 0; triangle < array::size(indices); triangle += 3) {
			Vector3 face_positions[3];
			for (u32 corner = 0; corner < 3; ++corner) {
				f32 value[4] = {};
				RETURN_IF_FALSE(MESH_GLTF, read_float(positions, indices[triangle + corner], value, 3), opts
					, "Failed to read glTF positions");
				face_positions[corner] = vector3(value) * geometry_transform;
			}

			Vector3 face_normal = cross(face_positions[1] - face_positions[0], face_positions[2] - face_positions[0]);
			if (length_squared(face_normal) > FLOAT_EPSILON)
				normalize(face_normal);
			else
				face_normal = { 0.0f, 0.0f, 1.0f };

			for (u32 corner = 0; corner < 3; ++corner) {
				const cgltf_size vertex = indices[triangle + corner];
				const u32 expanded = array::size(g._position_indices);
				append_vector3(g._positions, face_positions[corner]);
				array::push_back(g._position_indices, expanded);

				Vector3 normal = face_normal;
				f32 value[4] = {};
				if (normals != NULL) {
					RETURN_IF_FALSE(MESH_GLTF, read_float(normals, vertex, value, 3), opts
						, "Failed to read glTF normals");
					const Vector3 source_normal = vector3(value);
					Vector4 transformed = { source_normal.x, source_normal.y, source_normal.z, 0.0f };
					transformed = transformed * normal_transform;
					normal = { transformed.x, transformed.y, transformed.z };
					if (length_squared(normal) > FLOAT_EPSILON)
						normalize(normal);
				}
				append_vector3(g._normals, normal);
				array::push_back(g._normal_indices, expanded);

				if (import_tangents) {
					RETURN_IF_FALSE(MESH_GLTF, read_float(tangents, vertex, value, 4), opts
						, "Failed to read glTF tangents");
					const Vector3 source_tangent = vector3(value);
					Vector4 transformed = { source_tangent.x, source_tangent.y, source_tangent.z, 0.0f };
					transformed = transformed * geometry_transform;
					Vector3 tangent = { transformed.x, transformed.y, transformed.z };
					if (length_squared(tangent) > FLOAT_EPSILON)
						normalize(tangent);
					Vector3 bitangent = cross(normal, tangent) * value[3];
					append_vector3(g._tangents, tangent);
					append_vector3(g._bitangents, bitangent);
					array::push_back(g._tangent_indices, expanded);
					array::push_back(g._bitangent_indices, expanded);
				}

				if (import_uvs) {
					value[0] = value[1] = 0.0f;
					if (uvs != NULL) {
						RETURN_IF_FALSE(MESH_GLTF, read_float(uvs, vertex, value, 2), opts
							, "Failed to read glTF texture coordinates");
					}
					array::push_back(g._uvs, value[0]);
					// glTF and Crown both use the upper-left texture origin.
					array::push_back(g._uvs, value[1]);
					array::push_back(g._uv_indices, expanded);
				}

				if (import_skin) {
					if (rigid_bone != UINT16_MAX) {
						append_rigid_skin(g, rigid_bone);
					} else {
						err = append_skin(g, doc, *skin, joints, weights, vertex, opts);
						ENSURE_OR_RETURN(MESH_GLTF, err == 0, opts);
					}
					array::push_back(g._bone_indices, expanded);
					array::push_back(g._weight_indices, expanded);
				}
			}
		}

		return 0;
	}

	static s32 parse_geometry(Geometry &g
		, const GLTFDocument &doc
		, const cgltf_mesh &mesh
		, const cgltf_skin *skin
		, u16 rigid_bone
		, const Matrix4x4 &geometry_transform
		, CompileOptions &opts
		)
	{
		bool import_tangents = mesh.primitives_count != 0;
		bool import_uvs = false;
		bool import_skin = false;

		for (cgltf_size i = 0; i < mesh.primitives_count; ++i) {
			const cgltf_primitive &primitive = mesh.primitives[i];
			RETURN_IF_FALSE(MESH_GLTF
				, primitive.type == cgltf_primitive_type_triangles
					|| primitive.type == cgltf_primitive_type_triangle_strip
					|| primitive.type == cgltf_primitive_type_triangle_fan
				, opts
				, "Unsupported glTF primitive mode %d (points and lines are not supported)"
				, primitive.type
				);
			RETURN_IF_FALSE(MESH_GLTF
				, !primitive.has_draco_mesh_compression || primitive.attributes_count != 0
				, opts
				, "Draco-compressed glTF primitive has no uncompressed fallback"
				);
			if (primitive.targets_count != 0)
				opts.warning(MESH_GLTF, "glTF morph targets are not supported and will be ignored");

			const cgltf_accessor *joints = attribute(primitive, cgltf_attribute_type_joints, 0);
			const cgltf_accessor *weights = attribute(primitive, cgltf_attribute_type_weights, 0);
			import_tangents = import_tangents && attribute(primitive, cgltf_attribute_type_tangent) != NULL;
			import_uvs = import_uvs || attribute(primitive, cgltf_attribute_type_texcoord, 0) != NULL;
			import_skin = import_skin || joints != NULL || weights != NULL;
		}

		RETURN_IF_FALSE(MESH_GLTF, !import_skin || skin != NULL || rigid_bone != UINT16_MAX, opts
			, "Skinned glTF mesh node has no skin");
		import_skin = import_skin || rigid_bone != UINT16_MAX;

		Matrix4x4 normal_transform = geometry_transform;
		invert(normal_transform);
		transpose(normal_transform);

		for (cgltf_size i = 0; i < mesh.primitives_count; ++i) {
			s32 err = parse_primitive(g
				, doc
				, mesh.primitives[i]
				, skin
				, geometry_transform
				, normal_transform
				, import_tangents
				, import_uvs
				, import_skin
				, rigid_bone
				, opts
				);
			ENSURE_OR_RETURN(MESH_GLTF, err == 0, opts);
		}
		return 0;
	}

	s32 parse(Mesh &m, const char *path, const char *rigid_attachments_json, CompileOptions &opts)
	{
		GLTFDocument doc(default_allocator());
		s32 err = gltf::parse(doc, path, opts);
		ENSURE_OR_RETURN(MESH_GLTF, err == 0, opts);
		Array<RigidAttachment> rigid_attachments(default_allocator());
		err = parse_rigid_attachments(rigid_attachments, doc, rigid_attachments_json, opts);
		ENSURE_OR_RETURN(MESH_GLTF, err == 0, opts);

		for (cgltf_size i = 0; i < doc.data->nodes_count; ++i) {
			cgltf_node *source = &doc.data->nodes[i];
			if (!node_in_scene(doc, source))
				continue;

			Node node(default_allocator());
			node._local_pose = local_transform(source);

			DynamicString name(default_allocator());
			name = node_name(doc, source);
			if (source->mesh != NULL) {
				const RigidAttachment *rigid = rigid_attachment(rigid_attachments, source);
				Matrix4x4 geometry_transform = MATRIX4X4_IDENTITY;
				if (source->skin != NULL) {
					err = select_skin(doc, source->skin, opts);
					ENSURE_OR_RETURN(MESH_GLTF, err == 0, opts);
					geometry_transform = skin_transform(doc, source->skin);
				} else if (rigid != NULL) {
					err = rigid_geometry_transform(geometry_transform, doc, *rigid, opts);
					ENSURE_OR_RETURN(MESH_GLTF, err == 0, opts);
				}

				Geometry geometry(default_allocator());
				const u16 rigid_bone = rigid != NULL ? bone_id(doc, rigid->bone) : UINT16_MAX;
				RETURN_IF_FALSE(MESH_GLTF, rigid == NULL || rigid_bone != 0, opts
					, "Rigid glTF mesh '%s' cannot attach to skeleton root '%s'"
					, node_name(doc, source)
					, node_name(doc, rigid->bone)
					);
				err = parse_geometry(geometry
					, doc
					, *source->mesh
					, source->skin
					, rigid_bone
					, geometry_transform
					, opts
					);
				ENSURE_OR_RETURN(MESH_GLTF, err == 0, opts);
				if (array::size(geometry._position_indices) != 0) {
					node._geometry = name;
					hash_map::set(m._geometries, name, geometry);
				}
			}
			hash_map::set(m._nodes, name, node);
		}

		return 0;
	}

} // namespace gltf
} // namespace crown

#endif // if CROWN_CAN_COMPILE
