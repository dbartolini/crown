/*
 * Copyright (c) 2012-2025 Daniele Bartolini et al.
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

namespace Crown
{
public class InputString : InputField, Gtk.Entry
{
	public bool _inconsistent;
	public string _value;
	public Gtk.GestureClick _gesture_click;
	public Gtk.EventControllerFocus _controller_focus;

	public void set_inconsistent(bool inconsistent)
	{
		if (_inconsistent != inconsistent) {
			_inconsistent = inconsistent;

			if (_inconsistent) {
				this.text = INCONSISTENT_LABEL;
			} else {
				this.text = _value;
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
			return _value;
		}
		set
		{
			set_value_safe(value);
		}
	}

	public InputString()
	{
		_inconsistent = false;
		_value = "";

		_gesture_click = new Gtk.GestureClick();
		_gesture_click.pressed.connect(on_button_pressed);
		_gesture_click.released.connect(on_button_released);
		this.add_controller(_gesture_click);

		_controller_focus = new Gtk.EventControllerFocus();
		_controller_focus.enter.connect(on_focus_enter);
		_controller_focus.leave.connect(on_focus_leave);

		this.add_controller(_controller_focus);
		this.activate.connect(on_activate);
	}

	private void on_button_pressed(int n_press, double x, double y)
	{
		this.grab_focus();
	}

	private void on_button_released(int n_press, double x, double y)
	{
		uint button = _gesture_click.get_current_button();

		if (button == Gdk.BUTTON_PRIMARY) {
			if (_inconsistent)
				this.text = "";
			else
				this.text = _value;

			GLib.Idle.add(() => {
					this.set_position(-1);
					this.select_region(0, -1);
					return GLib.Source.REMOVE;
				});
		}
	}

	private void on_activate()
	{
		this.select_region(0, 0);
		this.set_position(-1);
		set_value_safe(this.text);
	}

	private void on_focus_enter()
	{
		var app = (LevelEditorApplication)GLib.Application.get_default();
		app.entry_any_focus_in(this);

		if (_inconsistent)
			this.text = "";
		else
			this.text = _value;

		this.set_position(-1);
		this.select_region(0, -1);
	}

	private void on_focus_leave()
	{
		var app = (LevelEditorApplication)GLib.Application.get_default();
		app.entry_any_focus_out(this);

		if (_inconsistent) {
			if (this.text != "") {
				set_value_safe(this.text);
			} else {
				this.text = INCONSISTENT_LABEL;
			}
		} else {
			set_value_safe(this.text);
		}

		this.select_region(0, 0);
	}

	protected virtual void set_value_safe(string text)
	{
		this.text = text;

		_inconsistent = false;

		// Notify value changed.
		if (_value != text) {
			_value = text;
			value_changed(this);
		}
	}
}

} /* namespace Crown */
