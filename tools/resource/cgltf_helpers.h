/*
 * Copyright (c) 2012-2026 Daniele Bartolini et al.
 * SPDX-License-Identifier: MIT
 */

#pragma once

#include <cgltf.h>

static inline cgltf_buffer *crown_cgltf_buffer_at(cgltf_data *data, cgltf_size index)
{
	return &data->buffers[index];
}

static inline cgltf_image *crown_cgltf_image_at(cgltf_data *data, cgltf_size index)
{
	return &data->images[index];
}

static inline cgltf_material *crown_cgltf_material_at(cgltf_data *data, cgltf_size index)
{
	return &data->materials[index];
}

static inline cgltf_mesh *crown_cgltf_mesh_at(cgltf_data *data, cgltf_size index)
{
	return &data->meshes[index];
}

static inline cgltf_node *crown_cgltf_node_at(cgltf_data *data, cgltf_size index)
{
	return &data->nodes[index];
}

static inline cgltf_skin *crown_cgltf_skin_at(cgltf_data *data, cgltf_size index)
{
	return &data->skins[index];
}

static inline cgltf_scene *crown_cgltf_scene_at(cgltf_data *data, cgltf_size index)
{
	return &data->scenes[index];
}

static inline cgltf_animation *crown_cgltf_animation_at(cgltf_data *data, cgltf_size index)
{
	return &data->animations[index];
}

static inline cgltf_primitive *crown_cgltf_primitive_at(cgltf_mesh *mesh, cgltf_size index)
{
	return &mesh->primitives[index];
}
