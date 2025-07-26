/*
 * Copyright (c) 2012-2025 Daniele Bartolini et al.
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

namespace Crown
{
// Data model for a single item in the level tree view
public class LevelTreeItem : GLib.Object
{
	public int item_type { get; set; }
	public Guid guid { get; set; }
	public string name { get; set; }

	public LevelTreeItem(int type, Guid guid, string name)
	{
		Object(
			item_type: type,
			guid: guid,
			name: name
		);
	}
}

} /* namespace Crown */
