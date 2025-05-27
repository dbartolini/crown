include = [ "core/shaders/common.shader" ]

render_states = {
	shadow = {
		states = {
			rgb_write_enable = false
			alpha_write_enable = false
			depth_write_enable = true
		}
	}
}

bgfx_shaders = {
	shadow_mapping = {
		includes = [ "common" ]

		code = """
			#define Sampler sampler2DShadow
			#define map_offt atlas_offset.xy
			#define map_size atlas_offset.z

			float hardShadow(Sampler _sampler, vec4 _shadowCoord, float _bias, vec3 atlas_offset)
			{
				vec3 texCoord = _shadowCoord.xyz/_shadowCoord.w;

			#if SHADOW_PACKED_DEPTH
				return step(texCoord.z-_bias, unpackRgbaToFloat(texture2D(_sampler, texCoord.xy) ) );
			#else
				return shadow2D(_sampler, vec3(texCoord.xy * map_size + map_offt, texCoord.z-_bias));
			#endif // SHADOW_PACKED_DEPTH
			}

			float PCF(Sampler _sampler, vec4 _shadowCoord, float _bias, vec2 _texelSize, vec3 atlas_offset)
			{
				vec2 texCoord = _shadowCoord.xy/_shadowCoord.w;
				texCoord = texCoord * atlas_offset.z + atlas_offset.xy;

				bool outside = any(greaterThan(texCoord, map_offt + vec2_splat(map_size)))
							|| any(lessThan   (texCoord, map_offt))
							 ;

				if (outside)
				{
					return 0.0;
				}

				float result = 0.0;
				vec2 offset = _texelSize * _shadowCoord.w;

				result += hardShadow(_sampler, _shadowCoord + vec4(vec2(-1.5, -1.5) * offset, 0.0, 0.0), _bias, atlas_offset);
				result += hardShadow(_sampler, _shadowCoord + vec4(vec2(-1.5, -0.5) * offset, 0.0, 0.0), _bias, atlas_offset);
				result += hardShadow(_sampler, _shadowCoord + vec4(vec2(-1.5,  0.5) * offset, 0.0, 0.0), _bias, atlas_offset);
				result += hardShadow(_sampler, _shadowCoord + vec4(vec2(-1.5,  1.5) * offset, 0.0, 0.0), _bias, atlas_offset);

				result += hardShadow(_sampler, _shadowCoord + vec4(vec2(-0.5, -1.5) * offset, 0.0, 0.0), _bias, atlas_offset);
				result += hardShadow(_sampler, _shadowCoord + vec4(vec2(-0.5, -0.5) * offset, 0.0, 0.0), _bias, atlas_offset);
				result += hardShadow(_sampler, _shadowCoord + vec4(vec2(-0.5,  0.5) * offset, 0.0, 0.0), _bias, atlas_offset);
				result += hardShadow(_sampler, _shadowCoord + vec4(vec2(-0.5,  1.5) * offset, 0.0, 0.0), _bias, atlas_offset);

				result += hardShadow(_sampler, _shadowCoord + vec4(vec2(0.5, -1.5) * offset, 0.0, 0.0), _bias, atlas_offset);
				result += hardShadow(_sampler, _shadowCoord + vec4(vec2(0.5, -0.5) * offset, 0.0, 0.0), _bias, atlas_offset);
				result += hardShadow(_sampler, _shadowCoord + vec4(vec2(0.5,  0.5) * offset, 0.0, 0.0), _bias, atlas_offset);
				result += hardShadow(_sampler, _shadowCoord + vec4(vec2(0.5,  1.5) * offset, 0.0, 0.0), _bias, atlas_offset);

				result += hardShadow(_sampler, _shadowCoord + vec4(vec2(1.5, -1.5) * offset, 0.0, 0.0), _bias, atlas_offset);
				result += hardShadow(_sampler, _shadowCoord + vec4(vec2(1.5, -0.5) * offset, 0.0, 0.0), _bias, atlas_offset);
				result += hardShadow(_sampler, _shadowCoord + vec4(vec2(1.5,  0.5) * offset, 0.0, 0.0), _bias, atlas_offset);
				result += hardShadow(_sampler, _shadowCoord + vec4(vec2(1.5,  1.5) * offset, 0.0, 0.0), _bias, atlas_offset);

				return result / 16.0;
			}
		"""
	}

	shadow = {
		includes = [ "common" ]

		varying = """
			vec3 a_position : POSITION;
			vec4 a_indices  : BLENDINDICES;
			vec4 a_weight   : BLENDWEIGHT;
		"""

		vs_input_output = """
		#if defined(SKINNING)
			$input a_position, a_indices, a_weight
		#else
			$input a_position
		#endif
		"""

		vs_code = """
			void main()
			{
		#if defined(SKINNING)
				mat4 model;
				model  = a_weight.x * u_model[int(a_indices.x)];
				model += a_weight.y * u_model[int(a_indices.y)];
				model += a_weight.z * u_model[int(a_indices.z)];
				model += a_weight.w * u_model[int(a_indices.w)];
				gl_Position = mul(mul(u_modelViewProj, model), vec4(a_position, 1.0));
		#else
				gl_Position = mul(mul(u_viewProj, u_model[0]), vec4(a_position, 1.0));
		#endif
			}
		"""

		fs_input_output = """
		"""

		fs_code = """
			void main()
			{
				gl_FragColor = vec4_splat(0.0);
			}
		"""
	}
}

shaders = {
	shadow = {
		bgfx_shader = "shadow"
		render_state = "shadow"
	}
}

static_compile = [
	{ shader = "shadow" defines = [] }
	{ shader = "shadow" defines = ["SKINNING"] }

]
