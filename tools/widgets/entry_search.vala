/*
 * Copyright (c) 2012-2026 Daniele Bartolini et al.
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

namespace Crown
{
public class EntrySearch : Gtk.Box
{
	public Gtk.SearchEntry _entry;
	public Gtk.EventControllerFocus _controller_focus;

	public signal void search_changed(EntrySearch entry);

	public EntrySearch()
	{
		Object(orientation: Gtk.Orientation.HORIZONTAL);

		_entry = new Gtk.SearchEntry();
		_entry.search_changed.connect(() => search_changed(this));
		_entry.hexpand = true;

		_controller_focus = new Gtk.EventControllerFocus();
		_controller_focus.enter.connect(on_focus_enter);
		_controller_focus.leave.connect(on_focus_leave);
		_entry.add_controller(_controller_focus);

		this.append(_entry);
	}

	public string text {
		get { return _entry.text; }
		set { _entry.text = value; }
	}

	public void set_placeholder_text(string text)
	{
		_entry.set_property("placeholder-text", text);
	}

	public void on_focus_enter()
	{
		var app = (LevelEditorApplication)GLib.Application.get_default();
		app.entry_any_focus_in(_entry);
	}

	public void on_focus_leave()
	{
		var app = (LevelEditorApplication)GLib.Application.get_default();
		app.entry_any_focus_out(_entry);
	}
}

} /* namespace Crown */
