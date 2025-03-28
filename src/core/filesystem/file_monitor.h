/*
 * Copyright (c) 2012-2025 Daniele Bartolini et al.
 * SPDX-License-Identifier: MIT
 */

#pragma once

#include "core/memory/types.h"
#include "core/types.h"

namespace crown
{
/// Enumerates file monitor events.
///
/// @ingroup Filesystem
struct FileMonitorEvent
{
	enum Enum
	{
		CREATED,
		DELETED,
		RENAMED,
		CHANGED,

		COUNT
	};
};

typedef void (*FileMonitorFunction)(void *user_data, FileMonitorEvent::Enum fme, bool is_dir, const char *path, const char *path_modified);

struct FileMonitorImpl;

/// Watches a directory for changes.
///
/// @ingroup Filesystem
struct FileMonitor
{
	FileMonitorImpl *_impl;

	///
	explicit FileMonitor(Allocator &a);

	///
	~FileMonitor();

	///
	FileMonitor(const FileMonitor &) = delete;

	///
	FileMonitor &operator=(const FileMonitor &) = delete;

	/// Starts monitoring the @a paths.
	void start(u32 num, const char **paths, bool recursive, FileMonitorFunction fmf, void *user_data);

	/// Stops monitoring.
	void stop();
};

} // namespace crown
