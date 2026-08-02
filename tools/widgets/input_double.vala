/*
 * Copyright (c) 2012-2026 Daniele Bartolini et al.
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

[CCode (cname = "crown_input_double_drag_sampler_start")]
extern void* input_double_drag_sampler_start(Gdk.Display display, Gdk.Window window, Gdk.Device device, int anchor_x, int anchor_y);

[CCode (cname = "crown_input_double_drag_sampler_drain")]
extern void input_double_drag_sampler_drain(void* sampler, out double delta_x, out double delta_y, out int samples);

[CCode (cname = "crown_input_double_drag_sampler_released")]
extern bool input_double_drag_sampler_released(void* sampler);

[CCode (cname = "crown_input_double_drag_sampler_stop")]
extern void input_double_drag_sampler_stop(void* sampler, out double delta_x, out double delta_y, out int samples);

namespace Crown
{
public class InputDouble : InputField
{
	public const double INFINITY_VALUE = (double)float.MAX;
	public const string INFINITY_LABEL = "Infinity";
	public const int DEFAULT_PREVIEW_DECIMALS = 4;
	public const int DEFAULT_EDIT_DECIMALS = 5;
	public const int DRAG_ACTIVATION_INTERVAL_MS = 1;
	public const int DRAG_UPDATE_INTERVAL_MS = 8;
	public const double DRAG_ACTIVATION_MARGIN = 5.0;
	public const int64 DRAG_LOG_INTERVAL_US = 2*1000*1000;

	public InputDoubleFlags _flags;
	public bool _inconsistent;
	public double _min;
	public double _max;
	public double _value;
	public int _preview_decimals;
	public int _edit_decimals;
	public Gtk.Entry _entry;
	public Gtk.Label _label;
	public Gtk.EventBox _event_box;
	public Gtk.Overlay _overlay;
	public Gtk.GestureMultiPress _gesture_click;
	public Gtk.EventControllerMotion _controller_motion;
	public Gtk.EventControllerScroll _controller_scroll;

	public uint _drag_update_timeout_id;
	public uint _drag_activation_timeout_id;
	public void* _drag_sampler;

	public bool _pressed;
	public bool _dragging;
	public bool _drag_value_dirty;
	public bool _resetting_click_gesture;
	public double _drag_mouse_x;
	public double _drag_mouse_y;
	public double _drag_start_value;
	public int64 _motion_frequency_start_time;
	public int _motion_frequency_samples;
	public int _diagnostic_drains;
	public int _diagnostic_property_updates;
	public int64 _diagnostic_last_drain_log_time;
	public int64 _diagnostic_last_property_log_time;

	public override void set_inconsistent(bool inconsistent)
	{
		if (_inconsistent != inconsistent) {
			_inconsistent = inconsistent;

			if (_inconsistent) {
				_entry.text = INCONSISTENT_LABEL;
				_label.set_text(_entry.text);
			} else {
				set_value_safe(string_to_double(_entry.text, _value));
			}
		}
	}

	public override bool is_inconsistent()
	{
		return _inconsistent;
	}

	public override GLib.Value union_value()
	{
		return this.value;
	}

	public override void set_union_value(GLib.Value v)
	{
		this.value = (double)v;
	}

	public double value
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

	public InputDouble(double val, double min, double max, int preview_decimals = DEFAULT_PREVIEW_DECIMALS, int edit_decimals = DEFAULT_EDIT_DECIMALS, InputDoubleFlags flags = InputDoubleFlags.NONE)
	{
		_flags = flags;

		_entry = new Gtk.Entry();
		_entry.input_purpose = Gtk.InputPurpose.FREE_FORM;
		_entry.set_width_chars(1);
		_entry.editable = false;

		_entry.activate.connect(on_activate);
		_entry.focus_in_event.connect(on_focus_in);
		_entry.focus_out_event.connect(on_focus_out);

		_label = new Gtk.Label(_entry.text);
		_label.halign = Gtk.Align.FILL;
		_label.get_style_context().add_class("label-button");

		_event_box = new Gtk.EventBox();
		_event_box.add(_label);
		_event_box.can_focus = false;
		_event_box.set_visible_window(false);

		_overlay = new Gtk.Overlay();
		_overlay.add(_entry);
		_overlay.add_overlay(_event_box);

		_inconsistent = false;
		_min = min;
		_max = max;
		_preview_decimals = preview_decimals;
		_edit_decimals = edit_decimals;

		set_value_safe(val);

		_controller_motion = new Gtk.EventControllerMotion(_event_box);
		_controller_motion.enter.connect(on_enter);
		_controller_motion.leave.connect(on_leave);

		_gesture_click = new Gtk.GestureMultiPress(_event_box);
		_gesture_click.pressed.connect(on_button_pressed);
		_gesture_click.released.connect(on_button_released);
		_gesture_click.cancel.connect(on_gesture_cancelled);

#if CROWN_GTK3
		_entry.scroll_event.connect(() => {
				GLib.Signal.stop_emission_by_name(_entry, "scroll-event");
				return Gdk.EVENT_PROPAGATE;
			});
#else
		_controller_scroll = new Gtk.EventControllerScroll(_entry, Gtk.EventControllerScrollFlags.BOTH_AXES);
		_controller_scroll.set_propagation_phase(Gtk.PropagationPhase.CAPTURE);
		_controller_scroll.scroll.connect(() => {
				// Do nothing, just consume the event to stop
				// the annoying scroll default behavior.
			});
#endif

		this.destroy.connect(on_destroy);
		this.add(_overlay);
	}

	public void on_destroy()
	{
		logi("InputDouble drag: widget destroyed pressed=%s dragging=%s sampler=%s".printf(_pressed.to_string(), _dragging.to_string(), (_drag_sampler != null).to_string()));
		_pressed = false;
		stop_drag_timers();
		stop_drag_sampler(false);
	}

	public void stop_drag_timers()
	{
		if (_drag_update_timeout_id != 0)
			GLib.Source.remove(_drag_update_timeout_id);
		if (_drag_activation_timeout_id != 0)
			GLib.Source.remove(_drag_activation_timeout_id);
		_drag_update_timeout_id = 0;
		_drag_activation_timeout_id = 0;
	}

	public void set_pointer_cursor(string name)
	{
		_event_box.get_window().set_cursor(new Gdk.Cursor.from_name(Gdk.Display.get_default(), name));
	}

	public void on_button_pressed(int n_press, double x, double y)
	{
		// Unfocus active widgets
		var window = get_toplevel() as Gtk.Window;
		if (window != null && window.get_focus() != null)
			window.set_focus(null);

		Gdk.Screen screen;
		int pointer_root_x;
		int pointer_root_y;
		this.get_display().get_default_seat().get_pointer().get_position(out screen, out pointer_root_x, out pointer_root_y);

		_pressed = true;
		_dragging = false;
		_drag_value_dirty = false;
		_drag_mouse_x = 0.0;
		_drag_mouse_y = 0.0;
		_drag_start_value = _value;
		_motion_frequency_start_time = GLib.get_monotonic_time();
		_motion_frequency_samples = 0;
		_diagnostic_drains = 0;
		_diagnostic_property_updates = 0;
		_diagnostic_last_drain_log_time = _motion_frequency_start_time;
		_diagnostic_last_property_log_time = _motion_frequency_start_time;
		logi("InputDouble drag: pressed n_press=%d root=(%d,%d) value=%f window=%s".printf(n_press, pointer_root_x, pointer_root_y, _drag_start_value, (_event_box.get_window() != null).to_string()));

		if (_drag_sampler == null) {
			Gdk.Device pointer = this.get_display().get_default_seat().get_pointer();
			_drag_sampler = input_double_drag_sampler_start(this.get_display(), _event_box.get_window(), pointer, pointer_root_x, pointer_root_y);
		}
		if (_drag_sampler == null) {
			loge("InputDouble drag: sampler failed to start");
			return;
		}

		logi("InputDouble drag: sampler started");
		if (_drag_activation_timeout_id == 0)
			_drag_activation_timeout_id = GLib.Timeout.add(DRAG_ACTIVATION_INTERVAL_MS, on_drag_activation_update);
		if (_drag_update_timeout_id == 0)
			_drag_update_timeout_id = GLib.Timeout.add(DRAG_UPDATE_INTERVAL_MS, on_drag_update);
		logi("InputDouble drag: activation timer id=%u interval=%dms property timer id=%u interval=%dms".printf(_drag_activation_timeout_id, DRAG_ACTIVATION_INTERVAL_MS, _drag_update_timeout_id, DRAG_UPDATE_INTERVAL_MS));
	}

	public void on_button_released(int n_press, double x, double y)
	{
		if (!_pressed)
			return;

		logi("InputDouble drag: released dragging=%s dirty=%s accumulated=(%f,%f)".printf(_dragging.to_string(), _drag_value_dirty.to_string(), _drag_mouse_x, _drag_mouse_y));
		_pressed = false;

		stop_drag_timers();
		stop_drag_sampler(true);
		logi("InputDouble drag: sampler stopped after release dragging=%s dirty=%s accumulated=(%f,%f)".printf(_dragging.to_string(), _drag_value_dirty.to_string(), _drag_mouse_x, _drag_mouse_y));

		if (_dragging) {
			logi("InputDouble drag: committing dragged value");
			update_drag_value();
			_dragging = false;

			double drag_end_value = _value;
			set_value_safe(_drag_start_value, -1); // Avoids unnecessary update
			set_value_safe(drag_end_value); // Fires the last commit

			set_pointer_cursor("col-resize");

			return;
		}

		// Begin editing
		_event_box.visible = false;
		_entry.editable = true;
		_entry.grab_focus();

		if (_inconsistent)
			_entry.text = "";
		else
			_entry.text = format_value(_value, _edit_decimals);

		GLib.Idle.add(() => {
				_entry.set_position(-1);
				_entry.select_region(0, -1);
				return GLib.Source.REMOVE;
			});
	}

	public void on_gesture_cancelled(Gdk.EventSequence? sequence)
	{
		if (_resetting_click_gesture) {
			logi("InputDouble drag: gesture reset after sampler-owned release");
			return;
		}

		logi("InputDouble drag: gesture cancelled dragging=%s dirty=%s".printf(_dragging.to_string(), _drag_value_dirty.to_string()));
		_pressed = false;
		_drag_value_dirty = false;

		stop_drag_timers();
		stop_drag_sampler(false);

		if (_dragging) {
			_dragging = false;
			set_value_safe(_drag_start_value, 0); // Revert to old value

			set_pointer_cursor("default");
		}
	}

	public void on_enter()
	{
		if (_dragging)
			return;

		set_pointer_cursor("col-resize");
	}

	public void on_leave()
	{
		if (_dragging)
			return;

		set_pointer_cursor("default");
	}

	public void process_drag_samples(double delta_x, double delta_y, int samples)
	{
		int64 now = GLib.get_monotonic_time();
		_drag_mouse_x += delta_x;
		_drag_mouse_y += delta_y;

		int64 elapsed = now - _motion_frequency_start_time;
		_motion_frequency_samples += samples;
		if (elapsed >= DRAG_LOG_INTERVAL_US) {
			double frequency = 1000.0*1000.0*(double)_motion_frequency_samples/(double)elapsed;
			logi("motion %.1f Hz delta %f %f".printf(frequency, delta_x, delta_y));
			_motion_frequency_start_time = now;
			_motion_frequency_samples = 0;
		}

		if (!_dragging) {
			if (_drag_mouse_x.abs() > DRAG_ACTIVATION_MARGIN) {
				_dragging = true;
				_drag_value_dirty = true;
				logi("InputDouble drag: activated accumulated=(%f,%f) margin=%f".printf(_drag_mouse_x, _drag_mouse_y, DRAG_ACTIVATION_MARGIN));

				set_pointer_cursor("none");
			}
		} else if (delta_x != 0) {
			_drag_value_dirty = true;
		}
	}

	public bool on_drag_activation_update()
	{
		if (!_pressed || _dragging) {
			_drag_activation_timeout_id = 0;
			return GLib.Source.REMOVE;
		}

		if (drain_drag_sampler()) {
			_drag_activation_timeout_id = 0;
			logi("InputDouble drag: release received by sampler during activation");
			on_button_released(1, 0.0, 0.0);
			reset_click_gesture_after_sampler_release();
			return GLib.Source.REMOVE;
		}
		if (_dragging) {
			_drag_activation_timeout_id = 0;
			return GLib.Source.REMOVE;
		}

		return GLib.Source.CONTINUE;
	}

	public void reset_click_gesture_after_sampler_release()
	{
		_resetting_click_gesture = true;
		_gesture_click.reset();
		_resetting_click_gesture = false;
	}

	public bool drain_drag_sampler()
	{
		if (_drag_sampler == null)
			return false;

		double delta_x;
		double delta_y;
		int samples;
		input_double_drag_sampler_drain(_drag_sampler, out delta_x, out delta_y, out samples);
		process_drag_samples(delta_x, delta_y, samples);

		_diagnostic_drains += 1;
		int64 now = GLib.get_monotonic_time();
		if (_diagnostic_drains <= 10 || now - _diagnostic_last_drain_log_time >= DRAG_LOG_INTERVAL_US) {
			logi("InputDouble drag: drain=%d samples=%d delta=(%f,%f) accumulated=(%f,%f) dragging=%s dirty=%s".printf(_diagnostic_drains, samples, delta_x, delta_y, _drag_mouse_x, _drag_mouse_y, _dragging.to_string(), _drag_value_dirty.to_string()));
			_diagnostic_last_drain_log_time = now;
		}

		return input_double_drag_sampler_released(_drag_sampler);
	}

	public void stop_drag_sampler(bool process_samples)
	{
		if (_drag_sampler == null)
			return;

		double delta_x;
		double delta_y;
		int samples;
		input_double_drag_sampler_stop(_drag_sampler, out delta_x, out delta_y, out samples);
		_drag_sampler = null;
		logi("InputDouble drag: final drain process=%s samples=%d delta=(%f,%f)".printf(process_samples.to_string(), samples, delta_x, delta_y));
		if (process_samples)
			process_drag_samples(delta_x, delta_y, samples);
	}

	public bool on_drag_update()
	{
		if (!_pressed) {
			_drag_update_timeout_id = 0;
			return GLib.Source.REMOVE;
		}

		if (drain_drag_sampler()) {
			logi("InputDouble drag: release received by sampler");
			on_button_released(1, 0.0, 0.0);
			reset_click_gesture_after_sampler_release();
			return GLib.Source.REMOVE;
		}
		update_drag_value();
		return GLib.Source.CONTINUE;
	}

	public void update_drag_value()
	{
		if (!_dragging || !_drag_value_dirty)
			return;

		const double SCALE = 0.01;
		double dx_adjusted = _drag_mouse_x - _drag_mouse_x.clamp(-DRAG_ACTIVATION_MARGIN, DRAG_ACTIVATION_MARGIN);
		double new_value = _drag_start_value + dx_adjusted*SCALE;
		_drag_value_dirty = false;
		_diagnostic_property_updates += 1;
		int64 now = GLib.get_monotonic_time();
		if (_diagnostic_property_updates <= 10 || now - _diagnostic_last_property_log_time >= DRAG_LOG_INTERVAL_US) {
			logi("InputDouble drag: property-update=%d old=%f new=%f accumulated-x=%f".printf(_diagnostic_property_updates, _value, new_value, _drag_mouse_x));
			_diagnostic_last_property_log_time = now;
		}
		set_value_safe(new_value);
	}

	public void on_activate()
	{
		_entry.select_region(0, 0);
		_entry.set_position(-1);

		if (_entry.text != format_value(_value, _edit_decimals))
			set_value_safe(string_to_double(_entry.text, _value));
		else
			_entry.text = format_value(_value, _preview_decimals);

		_label.set_text(_entry.text);
	}

	public bool on_focus_in(Gdk.EventFocus ev)
	{
		var app = (LevelEditorApplication)GLib.Application.get_default();
		app.entry_any_focus_in(_entry);

		if (_event_box.visible)
			_event_box.visible = false;

		_entry.editable = true;

		if (_inconsistent)
			_entry.text = "";
		else
			_entry.text = format_value(_value, _edit_decimals);

		_entry.set_position(-1);
		_entry.select_region(0, -1);

		return Gdk.EVENT_PROPAGATE;
	}

	public bool on_focus_out(Gdk.EventFocus ef)
	{
		var app = (LevelEditorApplication)GLib.Application.get_default();
		app.entry_any_focus_out(_entry);

		if (_inconsistent) {
			if (_entry.text != "") {
				set_value_safe(string_to_double(_entry.text, _value));
			} else {
				_entry.text = INCONSISTENT_LABEL;
			}
		} else {
			if (_entry.text != format_value(_value, _edit_decimals))
				set_value_safe(string_to_double(_entry.text, _value));
			else
				_entry.text = format_value(_value, _preview_decimals);
		}

		_entry.select_region(0, 0);
		_entry.editable = false;
		_label.set_text(_entry.text);
		_event_box.visible = true;

		return Gdk.EVENT_PROPAGATE;
	}

	public void set_value_safe(double val, int undo_redo = (int)!_dragging)
	{
		double clamped = val.clamp(_min, _max);

		// Convert to text for displaying.
		_entry.text = format_value(clamped, _preview_decimals);
		_label.set_text(_entry.text);

		_inconsistent = false;

		// Notify value changed.
		if (_value != clamped) {
			_value = clamped;
			value_changed(this, undo_redo);
		}
	}

	/// Returns @a str as double or @a deffault if conversion fails.
	public double string_to_double(string str, double deffault)
	{
		double special_value = 0.0;
		if ((_flags & InputDoubleFlags.INFINITY) != 0
			&& try_parse_special_literal(str, out special_value))
			return special_value;

		TinyExpr.Variable vars[] =
		{
			{ "x", &_value }
		};

		int err;
		TinyExpr.Expr expr = TinyExpr.compile(str, vars, out err);

		return err == 0 ? TinyExpr.eval(expr) : deffault;
	}

	public string format_value(double value, int max_decimals)
	{
		if ((_flags & InputDoubleFlags.INFINITY) != 0
			&& value == INFINITY_VALUE)
			return INFINITY_LABEL;

		return print_max_decimals(value, max_decimals);
	}

	public bool try_parse_special_literal(string str, out double value)
	{
		string normalized = str.strip().down();

		switch (normalized) {
		case "inf":
		case "+inf":
		case "infinity":
		case "+infinity":
			value = INFINITY_VALUE;
			return true;

		default:
			value = 0.0;
			return false;
		}
	}

	public void set_min(double min)
	{
		_min = min;
		set_value_safe(_value);
	}

	public void set_max(double max)
	{
		_max = max;
		set_value_safe(_value);
	}
}

} /* namespace Crown */
