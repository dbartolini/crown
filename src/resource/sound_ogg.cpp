/*
 * Copyright (c) 2012-2025 Daniele Bartolini et al.
 * SPDX-License-Identifier: MIT
 */

#include "config.h"

#define STB_VORBIS_NO_PULLDATA_API
#include <stb_vorbis.c>

#if CROWN_CAN_COMPILE
#   include "core/containers/array.inl"
#   include "core/time.h"
#   include "core/filesystem/file_buffer.inl"
#   include "core/memory/globals.h"
#   include "device/log.h"
#   include "resource/compile_options.inl"
#   include "resource/sound.h"
#   include "resource/sound_ogg.h"
#   include "resource/sound_resource.h"

LOG_SYSTEM(OGG, "ogg")

namespace crown
{
namespace ogg
{
	s32 parse(Sound &s, Buffer &buf, CompileOptions &opts)
	{
		OggStreamMetadata ogg;
		const u8 *data = (u8 *)array::begin(buf);
		const u32 size = array::size(buf);
		int p = 0;
		int q = 1;

		int used;
		int error;
		stb_vorbis *v;
		while (true) {
			v = stb_vorbis_open_pushdata(data, q, &used, &error, NULL);
			if (v != NULL)
				break;

			RETURN_IF_FALSE(error == VORBIS_need_more_data
				, opts
				, "stb_vorbis_open_pushdata: error: %d"
				, error
				);

			q += 1;
		}

		RETURN_IF_FALSE(v != NULL, opts, "stb_vorbis_open_pushdata: error: %d", error);
		logi(OGG, "headers len %d error %d", used, error);
		p += used;
		ogg.headers_size = p;

		stb_vorbis_info info = stb_vorbis_get_info(v);
		logi(OGG, "channels %d sample_rate %d setup_mem %d setup_temp_mem %d temp_mem %d max_frame_size %d"
			, info.channels
			, info.sample_rate
			, info.setup_memory_required
			, info.setup_temp_memory_required
			, info.temp_memory_required
			, info.max_frame_size
			);
		ogg.alloc_buffer_size = info.setup_memory_required
			+ info.setup_temp_memory_required
			+ info.temp_memory_required
			;
		ogg.max_frame_size = info.max_frame_size;

		FileBuffer fb(buf);
		fb.seek(p);

		p = 0;
		unsigned char *mem = (unsigned char *)default_allocator().allocate(info.max_frame_size);

		s64 t0 = time::now();
		while (true) {
			// Try to decode one frame.
			float **output;
			int n;
			q = info.max_frame_size;

		retry:
			if (q > size - p)
				q = size - p;
			if (p < q)
				fb.read(&mem[p], q - p);

			used = stb_vorbis_decode_frame_pushdata(v
				, mem
				, q
				, NULL
				, &output
				, &n
				);

			if (used == 0) {
				if (fb.end_of_file())
					break; // No more data.

				logi(OGG, "NEED MORE DATA");
				goto retry;
			}

			p = q - used;
			memmove(mem, &mem[used], p);
			if (n == 0)
				continue; // Seek/error recovery.

			// Frame successfully decoded.
			for (u32 i = 0; i < n; ++i) {
				for (u32 c = 0; c < info.channels; ++c)
					array::push_back(s._samples, output[c][i]);
			}

			logi(OGG, "decoded %u p %u", n, p);
		}
		logi(OGG, "decode time %.4f", time::seconds(time::now() - t0));

		default_allocator().deallocate(mem);

		logi(OGG, "max_frame_size %u", info.max_frame_size);
		stb_vorbis_close(v);

		s._sample_rate = info.sample_rate;
		s._channels = info.channels;
		s._bit_depth = 32;
		s._stream_format = StreamFormat::OGG;

		// Write metadata.
		FileBuffer meta_fb(s._stream_metadata);
		BinaryWriter bw(meta_fb);
		bw.write(ogg.alloc_buffer_size);
		bw.write(ogg.headers_size);
		bw.write(ogg.max_frame_size);

		// Copy entire vorbis to stream output.
		opts._stream_output.write(array::begin(buf), array::size(buf));
		return 0;
	}

} // namespace fbx

} // namespace crown

#endif // if CROWN_CAN_COMPILE
