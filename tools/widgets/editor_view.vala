/*
 * Copyright (c) 2012-2026 Daniele Bartolini et al.
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

public struct ExternalTextureInfo
{
	uint16 width;
	uint16 height;
	uint32 stride;
	uint32 offset;
	uint32 size;
	uint32 fourcc;
	uint64 modifier;
	void* handle;
}

extern int create_socket(string path);
extern void read_fd(int sock, int *fd, void *data, size_t data_len);

namespace Crown
{
public class EditorView : Gtk.Box
{
	/*
	public const Gtk.TargetEntry[] dnd_targets =
	{
		{ "RESOURCE_PATH", Gtk.TargetFlags.SAME_APP, 0 },
	};
	*/

	// Data
	public RuntimeInstance _runtime;

	public Gtk.Allocation _allocation;
	public uint _resize_timer_id;
	public uint _enable_accels_id;
	public uint _tick_callback_id;

	public bool _mouse_left;
	public bool _mouse_middle;
	public bool _mouse_right;

	public Gdk.DmabufTextureBuilder _dmabuf_texture_builder;
	public Gtk.Picture? _picture;
	public Gtk.GraphicsOffload _graphics_offload;
	public uint _update_picture_tick_id;

	public Gee.HashMap<uint, bool> _keys;
	public bool _input_enabled;
	public bool _drag_enter;
	public uint _drag_last_time;
	public int64 _motion_last_time;
	public const int MOTION_EVENTS_RATE = 75;

	public GLib.StringBuilder _buffer;

	public Gtk.EventControllerKey _controller_key;
	public Gtk.GestureClick _gesture_click;
	public Gtk.EventControllerMotion _controller_motion;
	public Gtk.EventControllerScroll _controller_scroll;
	public Gtk.EventControllerFocus _controller_focus;

	// Signals
	public signal void native_window_ready(uint window_id, int width, int height);

	public string key_to_string(uint k)
	{
		switch (k) {
		case Gdk.Key.w:         return "w";
		case Gdk.Key.a:         return "a";
		case Gdk.Key.s:         return "s";
		case Gdk.Key.d:         return "d";
		case Gdk.Key.q:         return "q";
		case Gdk.Key.e:         return "e";
		case Gdk.Key.Control_L: return "ctrl_left";
		case Gdk.Key.Shift_L:   return "shift_left";
		case Gdk.Key.Alt_L:     return "alt_left";
		case Gdk.Key.Alt_R:     return "alt_right";
		default:                return "<unknown>";
		}
	}

	public bool camera_modifier_pressed()
	{
		return _keys[Gdk.Key.Alt_L]
			|| _keys[Gdk.Key.Alt_R]
			;
	}

	public void camera_modifier_reset()
	{
		_keys[Gdk.Key.Alt_L] = false;
		_keys[Gdk.Key.Alt_R] = false;
	}

	public EditorView(RuntimeInstance runtime, bool input_enabled = true)
	{
		_runtime = runtime;

		_allocation = { 0, 0, 0, 0 };
		_resize_timer_id = 0;
		_enable_accels_id = 0;
		_tick_callback_id = 0;

		_mouse_left   = false;
		_mouse_middle = false;
		_mouse_right  = false;

		_dmabuf_texture_builder = new Gdk.DmabufTextureBuilder();
		_picture = new Gtk.Picture();
		_picture.set_content_fit(Gtk.ContentFit.FILL);
		_graphics_offload = new Gtk.GraphicsOffload(_picture);

		_keys = new Gee.HashMap<uint, bool>();
		_keys[Gdk.Key.w] = false;
		_keys[Gdk.Key.a] = false;
		_keys[Gdk.Key.s] = false;
		_keys[Gdk.Key.d] = false;
		_keys[Gdk.Key.q] = false;
		_keys[Gdk.Key.e] = false;
		_keys[Gdk.Key.Control_L] = false;
		_keys[Gdk.Key.Shift_L] = false;
		_keys[Gdk.Key.Alt_L] = false;
		_keys[Gdk.Key.Alt_R] = false;

		_input_enabled = input_enabled;
		_drag_enter = false;
		_drag_last_time = 0;
		_motion_last_time = 0;

		_buffer = new GLib.StringBuilder();

		// Widgets
		this.focusable = true;

		_controller_focus = new Gtk.EventControllerFocus();
		_controller_focus.leave.connect(on_event_box_focus_leave);

		if (input_enabled) {
			_controller_key = new Gtk.EventControllerKey();
			_controller_key.key_pressed.connect(on_key_pressed);
			_controller_key.key_released.connect(on_key_released);
			this.add_controller(_controller_key);

			_gesture_click = new Gtk.GestureClick();
			_gesture_click.set_button(0);
			_gesture_click.pressed.connect(on_button_pressed);
			_gesture_click.released.connect(on_button_released);
			this.add_controller(_gesture_click);

			_controller_motion = new Gtk.EventControllerMotion();
			_controller_motion.enter.connect(on_enter);
			_controller_motion.motion.connect(on_motion);
			this.add_controller(_controller_motion);

			_controller_scroll = new Gtk.EventControllerScroll(Gtk.EventControllerScrollFlags.BOTH_AXES);
			_controller_scroll.scroll.connect(on_scroll);
			this.add_controller(_controller_scroll);
		}

		/*
		Gtk.drag_dest_set(this, Gtk.DestDefaults.MOTION, dnd_targets, Gdk.DragAction.COPY);
		this.drag_data_received.connect(on_drag_data_received);
		this.drag_motion.connect(on_drag_motion);
		this.drag_drop.connect(on_drag_drop);
		this.drag_leave.connect(on_drag_leave);
		*/

		_graphics_offload.hexpand = true;
		_graphics_offload.vexpand = true;
		this.append(_graphics_offload);
	}

	/*
	public void on_drag_data_received(Gdk.DragContext context, int x, int y, Gtk.SelectionData data, uint info, uint time_)
	{
		// https://valadoc.org/gtk+-3.0/Gtk.Widget.drag_data_received.html
		unowned uint8[] raw_data = data.get_data_with_length();
		if (raw_data.length == -1)
			return;

		string resource_path = (string)raw_data;
		string type = ResourceId.type(resource_path);
		string name = ResourceId.name(resource_path);

		if (type == OBJECT_TYPE_UNIT || type == OBJECT_TYPE_SOUND) {
			GLib.Application.get_default().activate_action("set-placeable", new GLib.Variant.tuple({ type, name }));

			int scale = this.get_scale_factor();
			_runtime.send_script(LevelEditorApi.mouse_down(x*scale, y*scale));
		}
	}

	public bool on_drag_motion(Gdk.DragContext context, int x, int y, uint _time)
	{
		// https://valadoc.org/gtk+-3.0/Gtk.Widget.drag_motion.html
		Gdk.Atom target;

		target = Gtk.drag_dest_find_target(this, context, null);
		if (target == Gdk.Atom.NONE) {
			Gdk.drag_status(context, 0, _time);
		} else {
			if (_drag_enter == false) {
				Gtk.drag_get_data(this, context, target, _time);
				_drag_enter = true;
			}

			if (_time - _drag_last_time >= 1000/MOTION_EVENTS_RATE) {
				// Drag motion events seem to fire at a very high frequency compared to regular
				// motion notify events. Limit them to 60 hz.
				_drag_last_time = _time;
				int scale = this.get_scale_factor();
				_runtime.send_script(LevelEditorApi.set_mouse_state(x*scale
					, y*scale
					, _mouse_left
					, _mouse_middle
					, _mouse_right
					));

				_runtime.send(DeviceApi.frame());
			}
		}

		return true;
	}

	public bool on_drag_drop(Gdk.DragContext context, int x, int y, uint time_)
	{
		// https://valadoc.org/gtk+-3.0/Gtk.Widget.drag_drop.html
		int scale = this.get_scale_factor();
		_runtime.send_script(LevelEditorApi.mouse_up(x*scale, y*scale));
		GLib.Application.get_default().activate_action("cancel-place", null);
		_runtime.send(DeviceApi.frame());
		Gtk.drag_finish(context, true, false, time_);
		return true;
	}

	public void on_drag_leave(Gdk.DragContext context, uint time_)
	{
		// https://valadoc.org/gtk+-3.0/Gtk.Widget.drag_leave.html
		_drag_enter = false;
	}
	*/

	public void on_button_released(int n_press, double x, double y)
	{
		uint button = _gesture_click.get_current_button();
		int scale = this.get_scale_factor();

		_mouse_left   = button == Gdk.BUTTON_PRIMARY   ? false : _mouse_left;
		_mouse_middle = button == Gdk.BUTTON_MIDDLE    ? false : _mouse_middle;
		_mouse_right  = button == Gdk.BUTTON_SECONDARY ? false : _mouse_right;

		_buffer.append(LevelEditorApi.set_mouse_state((int)x*scale
			, (int)y*scale
			, _mouse_left
			, _mouse_middle
			, _mouse_right
			));

		if (button == Gdk.BUTTON_PRIMARY)
			_buffer.append(LevelEditorApi.mouse_up((int)x*scale, (int)y*scale));

		if (camera_modifier_pressed()) {
			if (!_mouse_left || !_mouse_middle || !_mouse_right)
				_buffer.append("LevelEditor:camera_drag_start('idle')");
		} else if (!_mouse_middle || !_mouse_right) {
			_buffer.append("LevelEditor:camera_drag_start('idle')");

			bool is_flying = _tick_callback_id > 0;

			if (!_mouse_right && is_flying) {
				// Wait a little to prevent camera movement keys
				// from activating unwanted accelerators.
				_enable_accels_id = GLib.Timeout.add_full(GLib.Priority.DEFAULT, 300, on_enable_accels);

				if (_tick_callback_id != 0) {
					remove_tick_callback(_tick_callback_id);
					_tick_callback_id = 0;
				}
			}
		}

		if (_buffer.len != 0) {
			_runtime.send_script(_buffer.str);
			_buffer.erase();
			_runtime.send(DeviceApi.frame());
		}
	}

	public void on_button_pressed(int n_press, double x, double y)
	{
		uint button = _gesture_click.get_current_button();
		int scale = this.get_scale_factor();

		this.grab_focus();

		_mouse_left   = button == Gdk.BUTTON_PRIMARY   ? true : _mouse_left;
		_mouse_middle = button == Gdk.BUTTON_MIDDLE    ? true : _mouse_middle;
		_mouse_right  = button == Gdk.BUTTON_SECONDARY ? true : _mouse_right;

		_buffer.append(LevelEditorApi.set_mouse_state((int)x*scale
			, (int)y*scale
			, _mouse_left
			, _mouse_middle
			, _mouse_right
			));

		if (camera_modifier_pressed()) {
			if (_mouse_left)
				_buffer.append("LevelEditor:camera_drag_start('tumble')");
			if (_mouse_middle)
				_buffer.append("LevelEditor:camera_drag_start('track')");
			if (_mouse_right)
				_buffer.append("LevelEditor:camera_drag_start('dolly')");
		} else if (_mouse_middle) {
			_buffer.append("LevelEditor:camera_drag_start('tumble')");
		} else if (_mouse_right) {
			_buffer.append("LevelEditor:camera_drag_start('flythrough')");

			if (_tick_callback_id == 0)
				_tick_callback_id = add_tick_callback(on_tick);

			if (_enable_accels_id > 0)
				GLib.Source.remove(_enable_accels_id);

			((LevelEditorApplication)GLib.Application.get_default()).set_conflicting_accels(false);
		}

		if (button == Gdk.BUTTON_PRIMARY)
			_buffer.append(LevelEditorApi.mouse_down((int)x*scale, (int)y*scale));

		if (_buffer.len != 0) {
			_runtime.send_script(_buffer.str);
			_buffer.erase();
			_runtime.send(DeviceApi.frame());
		}
	}

	public bool on_key_pressed(uint keyval, uint keycode, Gdk.ModifierType state)
	{
		if (keyval == Gdk.Key.Escape)
			GLib.Application.get_default().activate_action("cancel-place", null);

		if (keyval == Gdk.Key.Up)
			_buffer.append("LevelEditor:key_down(\"move_up\")");
		if (keyval == Gdk.Key.Down)
			_buffer.append("LevelEditor:key_down(\"move_down\")");
		if (keyval == Gdk.Key.Right)
			_buffer.append("LevelEditor:key_down(\"move_right\")");
		if (keyval == Gdk.Key.Left)
			_buffer.append("LevelEditor:key_down(\"move_left\")");

		if (_keys.has_key(keyval)) {
			if (!_keys[keyval]) {
				_buffer.append(LevelEditorApi.key_down(key_to_string(keyval)));

				if (keyval == Gdk.Key.w)
					_buffer.append("LevelEditor._camera.actions.forward = true;");
				if (keyval == Gdk.Key.s)
					_buffer.append("LevelEditor._camera.actions.back = true;");
				if (keyval == Gdk.Key.a)
					_buffer.append("LevelEditor._camera.actions.left = true;");
				if (keyval == Gdk.Key.d)
					_buffer.append("LevelEditor._camera.actions.right = true;");
				if (keyval == Gdk.Key.q)
					_buffer.append("LevelEditor._camera.actions.up = true;");
				if (keyval == Gdk.Key.e)
					_buffer.append("LevelEditor._camera.actions.down = true;");
			}

			_keys[keyval] = true;
		}

		if (_buffer.len != 0) {
			_runtime.send_script(_buffer.str);
			_buffer.erase();
			_runtime.send(DeviceApi.frame());
		}
		return Gdk.EVENT_PROPAGATE;
	}

	public void on_key_released(uint keyval, uint keycode, Gdk.ModifierType state)
	{
		if (_keys.has_key(keyval)) {
			if (_keys[keyval]) {
				_buffer.append(LevelEditorApi.key_up(key_to_string(keyval)));

				if (keyval == Gdk.Key.w)
					_buffer.append("LevelEditor._camera.actions.forward = false");
				if (keyval == Gdk.Key.s)
					_buffer.append("LevelEditor._camera.actions.back = false");
				if (keyval == Gdk.Key.a)
					_buffer.append("LevelEditor._camera.actions.left = false");
				if (keyval == Gdk.Key.d)
					_buffer.append("LevelEditor._camera.actions.right = false");
				if (keyval == Gdk.Key.q)
					_buffer.append("LevelEditor._camera.actions.up = false");
				if (keyval == Gdk.Key.e)
					_buffer.append("LevelEditor._camera.actions.down = false");
			}

			_keys[keyval] = false;
		}

		if (_buffer.len != 0) {
			_runtime.send_script(_buffer.str);
			_buffer.erase();
			_runtime.send(DeviceApi.frame());
		}
	}

	public void on_motion(double x, double y)
	{
		int64 now = GLib.get_monotonic_time();

		if (now - _motion_last_time >= (1000*1000)/MOTION_EVENTS_RATE) {
			_motion_last_time = now;
			int scale = this.get_scale_factor();
			_runtime.send_script(LevelEditorApi.set_mouse_state((int)x*scale
				, (int)y*scale
				, _mouse_left
				, _mouse_middle
				, _mouse_right
				));
			_runtime.send(DeviceApi.frame());
		}
	}

	public bool on_scroll(double dx, double dy)
	{
		if (_keys[Gdk.Key.Shift_L]) {
			_runtime.send_script(LevelEditorApi.mouse_wheel(-dy));
		} else {
			_runtime.send_script("LevelEditor:camera_drag_start_relative('dolly')");
			_runtime.send_script("LevelEditor._camera:update(1,0,%.17f,1,1)".printf(-dy * 32.0));
			_runtime.send_script("LevelEditor:camera_drag_start('idle')");
			_runtime.send(DeviceApi.frame());
		}

		return Gdk.EVENT_PROPAGATE;
	}

	public void on_event_box_focus_leave()
	{
		camera_modifier_reset();

		_keys[Gdk.Key.Control_L] = false;
		_keys[Gdk.Key.Shift_L] = false;
		_runtime.send_script(LevelEditorApi.key_up(key_to_string(Gdk.Key.Control_L)));
		_runtime.send_script(LevelEditorApi.key_up(key_to_string(Gdk.Key.Shift_L)));
	}

	public void on_realize()
	{
#if 0
		if (_allocation.x == ev.x
			&& _allocation.y == ev.y
			&& _allocation.width == ev.width
			&& _allocation.height == ev.height
			)
			return;

		_allocation = ev;
		_runtime.send(DeviceApi.resize(_allocation.width*scale, _allocation.height*scale));

		// Ensure there is some delay between the last resize() and the last frame().
		if (_resize_timer_id == 0) {
			_resize_timer_id = GLib.Timeout.add_full(GLib.Priority.DEFAULT, 200, () => {
					_runtime.send(DeviceApi.frame());
					_resize_timer_id = 0;
					return GLib.Source.REMOVE;
				});
		}
#endif
	}

	public void create()
	{
		try {
			const string SOCKET_CLIENT = "/tmp/test_client";
			ExternalTextureInfo eti = ExternalTextureInfo();
			int fd = 0;

			int sock = create_socket(SOCKET_CLIENT);
			read_fd(sock, &fd, &eti, sizeof(ExternalTextureInfo));

			logi("width     %d".printf(eti.width));
			logi("height    %d".printf(eti.height));
			logi("stride    %u".printf(eti.stride));
			logi("offest    %u".printf(eti.offset));
			logi("size      %u".printf(eti.size));
			logi("fourcc    %.8x".printf(eti.fourcc));
			logi("modifier  %.16llx".printf(eti.modifier));
			logi("fd        %d".printf(fd));

			_dmabuf_texture_builder.set_display (Gdk.Display.get_default());
			_dmabuf_texture_builder.set_width   (eti.width);
			_dmabuf_texture_builder.set_height  (eti.height);
			_dmabuf_texture_builder.set_fourcc  (eti.fourcc);
			_dmabuf_texture_builder.set_modifier(eti.modifier);
			_dmabuf_texture_builder.set_n_planes(1);
			_dmabuf_texture_builder.set_stride  (0, eti.stride);
			_dmabuf_texture_builder.set_offset  (0, eti.offset);
			_dmabuf_texture_builder.set_fd      (0, fd);

			var tex = _dmabuf_texture_builder.build(null, null);
			_picture.set_paintable(tex);
			_update_picture_tick_id = add_tick_callback(on_update_picture);
		} catch (Error e) {
			loge("%s".printf(e.message));
		}
	}

	public void on_enter(double x, double y)
	{
		this.grab_focus();
	}

	public bool on_tick(Gtk.Widget widget, Gdk.FrameClock frame_clock)
	{
		_runtime.send(DeviceApi.frame());
		return GLib.Source.CONTINUE;
	}

	public bool on_update_picture()
	{
		var tex = _dmabuf_texture_builder.build(null, null);
		if (tex != null)
			_picture.set_paintable(tex);
		return GLib.Source.CONTINUE;
	}

	public bool on_enable_accels()
	{
		((LevelEditorApplication)GLib.Application.get_default()).set_conflicting_accels(true);
		_enable_accels_id = 0;
		return GLib.Source.REMOVE;
	}
}

} /* namespace Crown */
