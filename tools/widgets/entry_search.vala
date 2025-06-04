/*
 * Copyright (c) 2012-2025 Daniele Bartolini et al.
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

namespace Crown
{
public class EntrySearch : Gtk.SearchEntry
{
	public Gtk.EventControllerFocus _controller_focus;

	public EntrySearch()
	{
		_controller_focus = new Gtk.EventControllerFocus();
		_controller_focus.enter.connect(on_focus_enter);
		_controller_focus.leave.connect(on_focus_leave);

		this.add_controller(_controller_focus);
	}

	private void on_focus_enter()
	{
		var app = (LevelEditorApplication)GLib.Application.get_default();
		app.entry_any_focus_in(this);
	}

	private void on_focus_leave()
	{
		var app = (LevelEditorApplication)GLib.Application.get_default();
		app.entry_any_focus_out(this);
	}
}

} /* namespace Crown */
