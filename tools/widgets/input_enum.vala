/*
 * Copyright (c) 2012-2025 Daniele Bartolini et al.
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

namespace Crown
{
public class InputEnum : InputField, Gtk.Widget
{
	public bool _inconsistent;
	public Gtk.StringList _store;
	public Gtk.DropDown _dropdown;
	public Gtk.EventControllerScroll _controller_scroll;
	private string[] _ids;
	private string[] _labels;

	public void set_inconsistent(bool inconsistent)
	{
		if (_inconsistent != inconsistent) {
			_inconsistent = inconsistent;

			update_dropdown();

			if (_inconsistent) {
				// Set to inconsistent item (index 0)
				_dropdown.set_selected(0);
			}
		}
	}

	public bool is_inconsistent()
	{
		return _inconsistent;
	}

	public GLib.Value union_value()
	{
		return this.value;
	}

	public void set_union_value(GLib.Value v)
	{
		this.value = (string)v;
	}

	public string value
	{
		get
		{
			uint selected = _dropdown.get_selected();
			if (selected >= _ids.length)
				return INCONSISTENT_ID;
			return _ids[selected];
		}
		set
		{
			// Find index of value in _ids array
			for (int i = 0; i < _ids.length; i++) {
				if (_ids[i] == value) {
					_dropdown.set_selected(i);
					set_inconsistent(false);
					return;
				}
			}
			// Value not found, set inconsistent
			set_inconsistent(true);
		}
	}

	private void update_dropdown()
	{
		// Rebuild the string list based on inconsistent state
		_store.splice(0, _store.get_n_items(), null);
		
		if (_inconsistent) {
			_store.append(INCONSISTENT_LABEL);
		}
		
		// Add all other items (skip inconsistent entry at index 0 of _labels)
		for (int i = 1; i < _labels.length; i++) {
			_store.append(_labels[i]);
		}
	}

	construct
	{
		set_layout_manager(new Gtk.BinLayout());
	}

	public InputEnum(string default_id = "DEFAULT", string[]? labels = null, string[]? ids = null)
	{
		Object();
		_inconsistent = false;

		// Initialize arrays
		if (labels != null && ids != null) {
			_ids = new string[ids.length + 1];
			_labels = new string[labels.length + 1];
			
			// First entry is always inconsistent
			_ids[0] = INCONSISTENT_ID;
			_labels[0] = INCONSISTENT_LABEL;
			
			// Copy provided data
			for (int i = 0; i < ids.length; i++) {
				_ids[i + 1] = ids[i];
				_labels[i + 1] = labels[i];
			}
		} else {
			_ids = { INCONSISTENT_ID };
			_labels = { INCONSISTENT_LABEL };
		}

		_store = new Gtk.StringList(null);
		_dropdown = new Gtk.DropDown(_store, null);
		
		// Add dropdown as child
		_dropdown.set_parent(this);
		
		// Setup the dropdown with initial values
		update_dropdown();

		if (labels != null && ids != null) {
			this.value = default_id;
		}

		_dropdown.notify["selected"].connect(on_changed);

#if CROWN_GTK3
		this.scroll_event.connect(() => {
				GLib.Signal.stop_emission_by_name(this, "scroll-event");
				return Gdk.EVENT_PROPAGATE;
			});
#else
		_controller_scroll = new Gtk.EventControllerScroll(Gtk.EventControllerScrollFlags.BOTH_AXES);
		_controller_scroll.set_propagation_phase(Gtk.PropagationPhase.CAPTURE);
		_controller_scroll.scroll.connect(() => {
				// Do nothing, just consume the event to stop
				// the annoying scroll default behavior.
				return Gdk.EVENT_PROPAGATE;
			});
		_dropdown.add_controller(_controller_scroll);
#endif
	}

	~InputEnum()
	{
		if (_dropdown != null)
			_dropdown.unparent();
	}

	public void append(string? id, string label)
	{
		_dropdown.notify["selected"].disconnect(on_changed);
		
		// Expand arrays
		string[] new_ids = new string[_ids.length + 1];
		string[] new_labels = new string[_labels.length + 1];
		
		for (int i = 0; i < _ids.length; i++) {
			new_ids[i] = _ids[i];
			new_labels[i] = _labels[i];
		}
		
		new_ids[_ids.length] = id ?? "";
		new_labels[_labels.length] = label;
		
		_ids = new_ids;
		_labels = new_labels;
		
		update_dropdown();
		_dropdown.notify["selected"].connect(on_changed);
	}

	public void clear()
	{
		_dropdown.notify["selected"].disconnect(on_changed);
		_ids = { INCONSISTENT_ID };
		_labels = { INCONSISTENT_LABEL };
		_inconsistent = false;
		update_dropdown();
		_dropdown.notify["selected"].connect(on_changed);
	}

	public string any_valid_id()
	{
		string some_id = INCONSISTENT_ID;

		if (_ids.length > 1) {
			// Return the first non-inconsistent ID
			for (int i = 1; i < _ids.length; i++) {
				if (_ids[i] != INCONSISTENT_ID) {
					some_id = _ids[i];
					break;
				}
			}
		}

		return some_id;
	}

	// Compatibility methods for old ComboBox API
	public string? get_active_id()
	{
		return this.value;
	}

	public void set_active_id(string id)
	{
		this.value = id;
	}

	public int active
	{
		get
		{
			return (int)_dropdown.get_selected();
		}
		set
		{
			_dropdown.set_selected((uint)value);
		}
	}

	private void on_changed()
	{
		uint selected = _dropdown.get_selected();
		if (selected >= _ids.length)
			return;

		string selected_id = _ids[selected];
		
		if (_inconsistent && selected_id == INCONSISTENT_ID)
			return;

		if (_inconsistent) {
			_inconsistent = false;
			update_dropdown();
		}

		value_changed(this);
	}
}

} /* namespace Crown */
