/*
 * Copyright (c) 2012-2025 Daniele Bartolini et al.
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

namespace Crown
{
public class EntrySearch : Gtk.Box
{
	public Gtk.EventControllerFocus _controller_focus;
	private Gtk.SearchEntry _search_entry;

	public EntrySearch()
	{
		Object(orientation: Gtk.Orientation.HORIZONTAL);
		
		_search_entry = new Gtk.SearchEntry();
		
		_controller_focus = new Gtk.EventControllerFocus();
		_controller_focus.enter.connect(on_focus_enter);
		_controller_focus.leave.connect(on_focus_leave);

		_search_entry.add_controller(_controller_focus);
		
		this.append(_search_entry);
		
		setup_signal_forwarding();
	}

	// Delegate common search entry properties and methods
	public string text {
		get { return _search_entry.text; }
		set { _search_entry.text = value; }
	}
	
	public void set_placeholder_text(string text) {
		_search_entry.set_placeholder_text(text);
	}
	
	// Delegate signal
	public signal void search_changed();
	
	private void setup_signal_forwarding() {
		_search_entry.search_changed.connect(() => search_changed());
	}

	private void on_focus_enter()
	{
		var app = (LevelEditorApplication)GLib.Application.get_default();
		app.entry_any_focus_in(_search_entry);
	}

	private void on_focus_leave()
	{
		var app = (LevelEditorApplication)GLib.Application.get_default();
		app.entry_any_focus_out(_search_entry);
	}
}

} /* namespace Crown */
