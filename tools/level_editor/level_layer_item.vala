/*
 * Copyright (c) 2012-2025 Daniele Bartolini et al.
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

namespace Crown
{
// Data model for a single layer item in the level layers view
public class LevelLayerItem : GLib.Object
{
	public string visible_icon { get; set; }
	public string locked_icon { get; set; }
	public string name { get; set; }

	public LevelLayerItem(string visible_icon, string locked_icon, string name)
	{
		Object(
			visible_icon: visible_icon,
			locked_icon: locked_icon,
			name: name
		);
	}
}

} /* namespace Crown */
