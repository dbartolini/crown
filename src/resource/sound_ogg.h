/*
 * Copyright (c) 2012-2025 Daniele Bartolini et al.
 * SPDX-License-Identifier: MIT
 */

#pragma once

#include "config.h"

namespace crown
{
struct OggStreamMetadata
{
	u32 alloc_buffer_size; ///< Size required by stb_vorbis_alloc.
	u32 headers_size;      ///< OGG headers size to pass to open_pushdata().
	u32 max_frame_size;
};

} // namespace crown

#if CROWN_CAN_COMPILE
#include "resource/sound.h"
#include "resource/types.h"

namespace crown
{
namespace ogg
{
	///
	s32 parse(Sound &s, Buffer &buf, CompileOptions &opts);

} // namespace ogg

} // namespace crown

#endif
