/*
 * Copyright (c) 2012-2026 Daniele Bartolini et al.
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

namespace Crown
{
public enum ViewportRenderMode
{
	CONTINUOUS,
	PUMPED,

	COUNT
}

public class EditorViewport : Gtk.Box
{
	public const string EDITOR_DISCONNECTED = "editor-disconnected";
	public const string EDITOR_OOPS = "editor-oops";
	public const string EDITOR_VIEWPORT = "editor-viewport";

	public const GLib.ActionEntry[] actions =
	{
		{ "camera-view",           on_camera_view,           "i",  "0" },  // See: Crown.CameraViewType
		{ "camera-frame-selected", on_camera_frame_selected, null, null },
	};

	public DatabaseEditor _database_editor;
	public Project _project;
	public string _boot_dir;
	public string _console_address;
	public uint16 _console_port;
	public ViewportRenderMode _render_mode;
	public bool _input_enabled;
	public RuntimeInstance _runtime;
	public EditorView _editor_view;
	public Gtk.Overlay _overlay;
	public Gtk.Stack _stack;
	public GLib.SimpleActionGroup _action_group;

	public EditorViewport(string name
		, DatabaseEditor database_editor
		, Project project
		, string boot_dir
		, string console_addr
		, uint16 console_port
		, ViewportRenderMode render_mode = ViewportRenderMode.PUMPED
		, bool input_enabled = true
		)
	{
		_database_editor = database_editor;
		_project = project;
		_boot_dir = boot_dir;
		_console_address = console_addr;
		_console_port = console_port;
		_render_mode = render_mode;
		_input_enabled = input_enabled;

		_runtime = new RuntimeInstance(name);
		_runtime.disconnected_unexpected.connect(on_editor_disconnected_unexpected);
		_runtime.connected.connect(on_editor_connected);

		_stack = new Gtk.Stack();
		_stack.halign = Gtk.Align.FILL;
		_stack.valign = Gtk.Align.FILL;
		_stack.add_named(editor_disconnected(), EDITOR_DISCONNECTED);
		_stack.add_named(editor_oops(() => { restart_runtime.begin(); }), EDITOR_OOPS);

		_stack.set_visible_child_name(EDITOR_DISCONNECTED);

		_action_group = new GLib.SimpleActionGroup();
		_action_group.add_action_entries(actions, this);
		this.insert_action_group("viewport", _action_group);

		_editor_view = new EditorView(_runtime, _input_enabled);
		_editor_view.show.connect(() => { restart_runtime(); });
		_overlay = new Gtk.Overlay();
		_overlay.set_child(_editor_view);
		_stack.add_named(_overlay, EDITOR_VIEWPORT);
		_stack.set_visible_child_name(EDITOR_VIEWPORT);

		this.focusable = true;
		this.append(_stack);
	}

	public void on_editor_disconnected_unexpected(RuntimeInstance ri)
	{
		_stack.set_visible_child_name(EDITOR_OOPS);
	}

	public void on_editor_connected()
	{
		_runtime.send(DeviceApi.frame());
		_runtime.send(DeviceApi.frame());
		_runtime.send(DeviceApi.export_backbuffer());

		_editor_view.create();
		_stack.set_visible_child_name(EDITOR_VIEWPORT);
	}

	public async void start_runtime(uint window_xid, int width, int height)
	{
		// Spawn the level editor.
		string args[] =
		{
			ENGINE_EXE,
			"--data-dir",
			_project.data_dir(),
			"--boot-dir",
			_boot_dir,
			"--console-port",
			_console_port.to_string(),
			"--wait-console",
			_render_mode == ViewportRenderMode.PUMPED ? "--pumped" : "",
			"--window-rect", "0", "0", width.to_string(), height.to_string(),
			"--headless",
			"--hidden",
			"--export",
		};

		try {
			_runtime._process_id = _subprocess_launcher.spawnv_async(subprocess_flags(), args, ENGINE_DIR);
		} catch (Error e) {
			loge(e.message);
		}

		// Try to connect to the level editor.
		int tries = yield _runtime.connect_async(_console_address
			, _console_port
			, EDITOR_CONNECTION_TRIES
			, EDITOR_CONNECTION_INTERVAL
			);
		if (tries == EDITOR_CONNECTION_TRIES) {
			loge("Cannot connect to %s".printf(_runtime._name));
			return;
		}
	}

	public async void stop_runtime()
	{
		yield _runtime.stop();
		_stack.set_visible_child_name(EDITOR_DISCONNECTED);
	}

	public async void restart_runtime()
	{
		yield stop_runtime();
		start_runtime.begin(1, 1280, 720);
	}

	public void frame()
	{
		if (_render_mode != ViewportRenderMode.PUMPED)
			return;

		_runtime.send(DeviceApi.frame());
	}

	public void on_camera_view(GLib.SimpleAction action, GLib.Variant? param)
	{
		CameraViewType view_type = (CameraViewType)param.get_int32();

		_runtime.send_script(LevelEditorApi.set_camera_view_type(view_type));
		frame();

		action.set_state(param);
	}

	public void on_camera_frame_selected(GLib.SimpleAction action, GLib.Variant? param)
	{
		Guid?[] selected_objects = _database_editor._selection.to_array();
		_runtime.send_script(LevelEditorApi.frame_objects(selected_objects));
		frame();
	}
}

} /* namespace Crown */
