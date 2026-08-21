/*
 * Copyright (c) 2012-2026 Daniele Bartolini et al.
 * SPDX-License-Identifier: MIT
 */

#pragma once

#include "config.h"

#if CROWN_CAN_COMPILE
#   include "resource/mesh.h"
#   include "resource/types.h"

namespace crown
{
namespace gltf
{
	/// Parses the glTF mesh at @a path and applies optional rigid bone attachments.
	s32 parse(Mesh &m, const char *path, const char *rigid_attachments, CompileOptions &opts);

} // namespace gltf
} // namespace crown

#endif // if CROWN_CAN_COMPILE
