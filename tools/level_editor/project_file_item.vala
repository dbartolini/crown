/*
 * Copyright (c) 2012-2025 Daniele Bartolini et al.
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

namespace Crown
{
// Data model for a single file/folder item in the project browser
public class ProjectFileItem : GLib.Object
{
	public string item_type { get; set; }
	public string name { get; set; }
	public Gdk.Pixbuf? pixbuf { get; set; }
	public uint64 size { get; set; }
	public uint64 mtime { get; set; }

	public ProjectFileItem(string type, string name, Gdk.Pixbuf? pixbuf, uint64 size, uint64 mtime)
	{
		Object(
			item_type: type,
			name: name,
			pixbuf: pixbuf,
			size: size,
			mtime: mtime
		);
	}
}

} /* namespace Crown */
