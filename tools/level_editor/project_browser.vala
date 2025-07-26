/*
 * Copyright (c) 2012-2025 Daniele Bartolini et al.
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

namespace Crown
{
/*
public const Gtk.TargetEntry[] dnd_targets =
{
	{ "RESOURCE_PATH", Gtk.TargetFlags.SAME_APP, 0 },
};
*/

private string project_path(string type, string name)
{
	if (type == "<folder>")
		return name;

	return ResourceId.path(type, name);
}

// Menu to open when clicking on project's files and folders.
private GLib.Menu? project_entry_menu_create(string type, string name)
{
	GLib.Menu menu = new GLib.Menu();
	GLib.MenuItem mi;

	if (type == "<folder>") {
		if (name == "..")
			return null;

		GLib.Menu import_menu = new GLib.Menu();

		mi = new GLib.MenuItem("Import...", null);
		mi.set_action_and_target_value("app.import", new GLib.Variant.tuple({(string)name, new string[] {}}));
		import_menu.append_item(mi);

		menu.append_section(null, import_menu);

		GLib.Menu create_menu = new GLib.Menu();

		mi = new GLib.MenuItem("New Script...", null);
		mi.set_action_and_target_value("app.create-script", new GLib.Variant.tuple({(string)name, "", true}));
		create_menu.append_item(mi);

		mi = new GLib.MenuItem("New Script (Unit)...", null);
		mi.set_action_and_target_value("app.create-script", new GLib.Variant.tuple({(string)name, "", false}));
		create_menu.append_item(mi);

		mi = new GLib.MenuItem("New Unit...", null);
		mi.set_action_and_target_value("app.create-unit", new GLib.Variant.tuple({(string)name, ""}));
		create_menu.append_item(mi);

		mi = new GLib.MenuItem("New Material...", null);
		mi.set_action_and_target_value("app.create-material", new GLib.Variant.tuple({(string)name, ""}));
		create_menu.append_item(mi);

		mi = new GLib.MenuItem("New Folder...", null);
		mi.set_action_and_target_value("app.create-directory", new GLib.Variant.tuple({(string)name, ""}));
		create_menu.append_item(mi);

		menu.append_section(null, create_menu);

		GLib.Menu destroy_menu = new GLib.Menu();

		if ((string)name != ProjectStore.ROOT_FOLDER) {
			mi = new GLib.MenuItem("Delete Folder", null);
			mi.set_action_and_target_value("app.delete-directory", new GLib.Variant.string((string)name));
			destroy_menu.append_item(mi);
		}

		menu.append_section(null, destroy_menu);
	} else { // If file
		menu = new GLib.Menu();

		mi = new GLib.MenuItem("Delete File", null);
		mi.set_action_and_target_value("app.delete-file", new GLib.Variant.string(project_path(type, name)));
		menu.append_item(mi);

		if (type == OBJECT_TYPE_MESH_SKELETON || type == OBJECT_TYPE_SPRITE) {
			mi = new GLib.MenuItem("New State Machine...", null);
			string skeleton_name;
			if (type == OBJECT_TYPE_SPRITE)
				skeleton_name = "";
			else
				skeleton_name = name;

			mi.set_action_and_target_value("app.create-state-machine", new GLib.Variant.tuple({ResourceId.parent_folder(name), "", skeleton_name}));
			menu.append_item(mi);
		}
	}

	// Add common menu items.
	GLib.Menu common_menu = new GLib.Menu();

	mi = new GLib.MenuItem("Copy Path", null);
	mi.set_action_and_target_value("app.copy-path", new GLib.Variant.string(project_path(type, name)));
	common_menu.append_item(mi);

	mi = new GLib.MenuItem("Copy Name", null);
	mi.set_action_and_target_value("app.copy-name", new GLib.Variant.string(name));
	common_menu.append_item(mi);

	mi = new GLib.MenuItem("Open Containing Folder...", null);
	mi.set_action_and_target_value("app.open-containing", new GLib.Variant.string(name));
	common_menu.append_item(mi);

	if (type != "<folder>" || name != "") {
		mi = new GLib.MenuItem("Add to Favorites", null);
		mi.set_action_and_target_value("app.favorite-resource", new GLib.Variant.tuple({type, name}));
		common_menu.append_item(mi);
	}

	menu.append_section(null, common_menu);

	return menu;
}

// Menu to open when clicking on favorites' entries.
private GLib.Menu? favorites_entry_menu_create(string type, string name)
{
	GLib.Menu menu = new GLib.Menu();
	GLib.MenuItem mi;

	mi = new GLib.MenuItem("Open Containing Folder...", null);
	mi.set_action_and_target_value("app.open-containing", new GLib.Variant.string(name));
	menu.append_item(mi);

	GLib.Menu common_menu = new GLib.Menu();

	mi = new GLib.MenuItem("Copy Path", null);
	string path = project_path(type, name);
	mi.set_action_and_target_value("app.copy-path", new GLib.Variant.string(path));
	common_menu.append_item(mi);

	mi = new GLib.MenuItem("Copy Name", null);
	mi.set_action_and_target_value("app.copy-name", new GLib.Variant.string(name));
	common_menu.append_item(mi);

	mi = new GLib.MenuItem("Remove from Favorites", null);
	mi.set_action_and_target_value("app.unfavorite-resource", new GLib.Variant.tuple({type, name}));
	common_menu.append_item(mi);

	mi = new GLib.MenuItem("Reveal", null);
	mi.set_action_and_target_value("app.reveal-resource", new GLib.Variant.tuple({type, name}));
	common_menu.append_item(mi);

	menu.append_section(null, common_menu);

	return menu;
}

private void set_thumbnail(Gtk.CellRenderer cell, string type, string name, int icon_size, ThumbnailCache thumbnail_cache)
{
	// https://specifications.freedesktop.org/icon-naming-spec/icon-naming-spec-latest.html
	if (type == "<folder>")
		cell.set_property("icon-name", "browser-folder-symbolic");
	else if ((string)type == "<favorites>")
		cell.set_property("icon-name", "browser-favorites");
	else if ((string)type == OBJECT_TYPE_STATE_MACHINE)
		cell.set_property("icon-name", "object-state-machine");
	else if ((string)type == "config")
		cell.set_property("icon-name", "object-config");
	else if ((string)type == OBJECT_TYPE_FONT)
		cell.set_property("icon-name", "object-font");
	else if ((string)type == OBJECT_TYPE_LEVEL)
		cell.set_property("icon-name", "object-level");
	else if ((string)type == OBJECT_TYPE_MATERIAL)
		cell.set_property("pixbuf", thumbnail_cache.get(type, name, icon_size));
	else if ((string)type == OBJECT_TYPE_MESH)
		cell.set_property("icon-name", "object-mesh");
	else if ((string)type == "package")
		cell.set_property("icon-name", "object-package");
	else if ((string)type == "physics_config")
		cell.set_property("icon-name", "object-config");
	else if ((string)type == "lua")
		cell.set_property("icon-name", "object-script");
	else if ((string)type == OBJECT_TYPE_UNIT)
		cell.set_property("pixbuf", thumbnail_cache.get(type, name, icon_size));
	else if ((string)type == "shader")
		cell.set_property("icon-name", "object-shader");
	else if ((string)type == OBJECT_TYPE_SOUND)
		cell.set_property("pixbuf", thumbnail_cache.get(type, name, icon_size));
	else if ((string)type == OBJECT_TYPE_SPRITE_ANIMATION)
		cell.set_property("icon-name", "object-animation");
	else if ((string)type == OBJECT_TYPE_SPRITE)
		cell.set_property("icon-name", "object-sprite");
	else if ((string)type == OBJECT_TYPE_TEXTURE)
		cell.set_property("pixbuf", thumbnail_cache.get(type, name, icon_size));
	else if ((string)type == OBJECT_TYPE_MESH_ANIMATION)
		cell.set_property("icon-name", "object-animation");
	else if ((string)type == OBJECT_TYPE_MESH_SKELETON)
		cell.set_property("icon-name", "object-skeleton");
	else
		cell.set_property("icon-name", "text-x-generic-symbolic");
}
public class ProjectFolderView : Gtk.Box
{
	public enum Column
	{
		TYPE,
		NAME,
		PIXBUF,
		SIZE,
		MTIME,

		COUNT
	}

	public string _selected_type;
	public string _selected_name;
	public ProjectStore _project_store;
	public ThumbnailCache _thumbnail_cache;
	public GLib.ListStore _list_model;     // GTK4 model for ColumnView
	public Gtk.ColumnView _column_view;
	public Gtk.SingleSelection _selection_model;
	public Gdk.Pixbuf _empty_pixbuf;
	public bool _showing_project_folder;
	public Gtk.ScrolledWindow _column_view_window;
	public Gtk.GestureClick _column_view_gesture_click;

	public ProjectFolderView(ProjectStore project_store, ThumbnailCache thumbnail_cache)
	{
		Object(orientation: Gtk.Orientation.VERTICAL);
		
		_project_store = project_store;
		_thumbnail_cache = thumbnail_cache;

		// Create GTK4 list model for ColumnView
		_list_model = new GLib.ListStore(typeof(ProjectFileItem));
		_selection_model = new Gtk.SingleSelection(_list_model);
		
		// Create GTK4 ColumnView 
		_column_view = new Gtk.ColumnView(_selection_model);
		
		// Create column factories
		create_column_view_columns();

		_column_view_gesture_click = new Gtk.GestureClick();
		_column_view_gesture_click.set_button(0);
		_column_view_gesture_click.pressed.connect(on_button_pressed);
		_column_view.add_controller(_column_view_gesture_click);

		_empty_pixbuf = new Gdk.Pixbuf.from_data({ 0x00, 0x00, 0x00, 0x00 }, Gdk.Colorspace.RGB, true, 8, 1, 1, 4);

		_showing_project_folder = true;

		_column_view_window = new Gtk.ScrolledWindow();
		_column_view_window.set_child(_column_view);
		
		this.append(_column_view_window);
	}

	private void create_column_view_columns()
	{
		// Create column for thumbnail/icon
		var thumbnail_factory = new Gtk.SignalListItemFactory();
		thumbnail_factory.setup.connect((listitem) => {
			var image = new Gtk.Image();
			((Gtk.ListItem)listitem).set_child(image);
		});
		thumbnail_factory.bind.connect((listitem) => {
			var file_item = (ProjectFileItem)((Gtk.ListItem)listitem).get_item();
			var image = (Gtk.Image)((Gtk.ListItem)listitem).get_child();
			if (file_item.pixbuf != null)
				image.set_from_pixbuf(file_item.pixbuf);
			else
				image.set_from_icon_name("text-x-generic-symbolic");
		});
		var thumbnail_column = new Gtk.ColumnViewColumn("", thumbnail_factory);
		thumbnail_column.set_fixed_width(50);
		_column_view.append_column(thumbnail_column);

		// Create column for basename
		var basename_factory = new Gtk.SignalListItemFactory();
		basename_factory.setup.connect((listitem) => {
			var label = new Gtk.Label("");
			label.set_halign(Gtk.Align.START);
			((Gtk.ListItem)listitem).set_child(label);
		});
		basename_factory.bind.connect((listitem) => {
			var file_item = (ProjectFileItem)((Gtk.ListItem)listitem).get_item();
			var label = (Gtk.Label)((Gtk.ListItem)listitem).get_child();
			var basename = Path.get_basename(file_item.name);
			if (basename.has_suffix(".unit") || basename.has_suffix(".level"))
				basename = basename.substring(0, basename.last_index_of("."));
			label.set_text(basename);
		});
		var basename_column = new Gtk.ColumnViewColumn("Basename", basename_factory);
		basename_column.set_expand(true);
		_column_view.append_column(basename_column);

		// Create column for type
		var type_factory = new Gtk.SignalListItemFactory();
		type_factory.setup.connect((listitem) => {
			var label = new Gtk.Label("");
			label.set_halign(Gtk.Align.START);
			((Gtk.ListItem)listitem).set_child(label);
		});
		type_factory.bind.connect((listitem) => {
			var file_item = (ProjectFileItem)((Gtk.ListItem)listitem).get_item();
			var label = (Gtk.Label)((Gtk.ListItem)listitem).get_child();
			label.set_text(file_item.item_type);
		});
		var type_column = new Gtk.ColumnViewColumn("Type", type_factory);
		_column_view.append_column(type_column);

		// Create column for size
		var size_factory = new Gtk.SignalListItemFactory();
		size_factory.setup.connect((listitem) => {
			var label = new Gtk.Label("");
			label.set_halign(Gtk.Align.END);
			((Gtk.ListItem)listitem).set_child(label);
		});
		size_factory.bind.connect((listitem) => {
			var file_item = (ProjectFileItem)((Gtk.ListItem)listitem).get_item();
			var label = (Gtk.Label)((Gtk.ListItem)listitem).get_child();
			if (file_item.item_type != "<folder>")
				label.set_text(format_file_size(file_item.size));
			else
				label.set_text("");
		});
		var size_column = new Gtk.ColumnViewColumn("Size", size_factory);
		_column_view.append_column(size_column);

		// Create column for modified time
		var mtime_factory = new Gtk.SignalListItemFactory();
		mtime_factory.setup.connect((listitem) => {
			var label = new Gtk.Label("");
			label.set_halign(Gtk.Align.START);
			((Gtk.ListItem)listitem).set_child(label);
		});
		mtime_factory.bind.connect((listitem) => {
			var file_item = (ProjectFileItem)((Gtk.ListItem)listitem).get_item();
			var label = (Gtk.Label)((Gtk.ListItem)listitem).get_child();
			var dt = new DateTime.from_unix_local((int64)file_item.mtime);
			label.set_text(dt.format("%x %X"));
		});
		var mtime_column = new Gtk.ColumnViewColumn("Modified", mtime_factory);
		_column_view.append_column(mtime_column);

		// Create column for full name
		var name_factory = new Gtk.SignalListItemFactory();
		name_factory.setup.connect((listitem) => {
			var label = new Gtk.Label("");
			label.set_halign(Gtk.Align.START);
			((Gtk.ListItem)listitem).set_child(label);
		});
		name_factory.bind.connect((listitem) => {
			var file_item = (ProjectFileItem)((Gtk.ListItem)listitem).get_item();
			var label = (Gtk.Label)((Gtk.ListItem)listitem).get_child();
			label.set_text(file_item.name);
		});
		var name_column = new Gtk.ColumnViewColumn("Name", name_factory);
		name_column.set_expand(true);
		_column_view.append_column(name_column);
	}

	private string format_file_size(uint64 size)
	{
		double d_size = (double)size;
		string[] units = { "B", "KB", "MB", "GB" };
		int unit = 0;
		
		while (d_size >= 1024.0 && unit < units.length - 1) {
			d_size /= 1024.0;
			unit++;
		}
		
		return "%.1f %s".printf(d_size, units[unit]);
	}

	/*
	private void on_drag_data_get(Gdk.DragContext context, Gtk.SelectionData data, uint info, uint time_)
	{
		// https://valadoc.org/gtk+-3.0/Gtk.Widget.drag_data_get.html
		Gtk.TreePath path;
		if (!selected_path(out path))
			return;

		uint position = (uint)path.get_indices()[0];
		ProjectFileItem? item = (ProjectFileItem?)_list_model.get_item(position);
		if (item == null)
			return;

		string resource_path = ResourceId.path(item.item_type, item.name);
		data.set(Gdk.Atom.intern_static_string("RESOURCE_PATH"), 8, resource_path.data);
	}

	private void on_drag_begin(Gdk.DragContext context)
	{
		// https://valadoc.org/gtk+-3.0/Gtk.Widget.drag_begin.html
		Gtk.drag_set_icon_pixbuf(context, _empty_pixbuf, 0, 0);
	}

	private void on_drag_end(Gdk.DragContext context)
	{
		// https://valadoc.org/gtk+-3.0/Gtk.Widget.drag_end.html
		GLib.Application.get_default().activate_action("cancel-place", null);
	}

	private void on_drag_data_received(Gdk.DragContext context, int x, int y, Gtk.SelectionData selection_data, uint info, uint time_)
	{
		Gtk.TreePath? path = path_at_pos(x, y);

		if (path != null) {
			_icon_view.select_path(path);
			_icon_view.scroll_to_path(path, false, 0.0f, 0.0f);
		}

		string type;
		string name;
		resource_at_path(out type, out name, path);

		if (type == "<folder>") {
			string[] uris = selection_data.get_uris();
			string[] filenames = new string[uris.length];

			// Convert URIs to filenames.
			for (int i = 0; i < uris.length; ++i)
				filenames[i] = GLib.Filename.from_uri(uris[i]);

			GLib.Application.get_default().activate_action("import", new GLib.Variant.tuple({name, filenames}));
		}

		Gtk.drag_finish(context, true, false, time_);
	}
	*/

	private void on_button_pressed(int n_press, double x, double y)
	{
		uint button = _column_view_gesture_click.get_current_button();

		if (button == Gdk.BUTTON_SECONDARY) {
			// Get selected item from selection model
			var selected_item = _selection_model.get_selected_item();
			string type = "";
			string name = "";
			
			if (selected_item != null) {
				var file_item = (ProjectFileItem)selected_item;
				type = file_item.item_type;
				name = file_item.name;
			}

			GLib.Menu? menu_model;
			if (_showing_project_folder)
				menu_model = project_entry_menu_create(type, name);
			else
				menu_model = favorites_entry_menu_create(type, name);

			if (menu_model != null) {
				Gtk.PopoverMenu menu = new Gtk.PopoverMenu.from_model(menu_model);
				menu.set_pointing_to({ (int)x, (int)y, 1, 1 });
				menu.set_position(Gtk.PositionType.BOTTOM);
				menu.popup();
			}

			_column_view_gesture_click.set_state(Gtk.EventSequenceState.CLAIMED);
		} else if (button == Gdk.BUTTON_PRIMARY && n_press == 2) {
			// Handle double-click
			var selected_item = _selection_model.get_selected_item();
			if (selected_item != null) {
				var file_item = (ProjectFileItem)selected_item;
				
				if (file_item.item_type == "<folder>") {
					string dir_name;
					if (file_item.name == "..")
						dir_name = ResourceId.parent_folder((string)_selected_name);
					else
						dir_name = file_item.name;

					GLib.Application.get_default().activate_action("open-directory", new GLib.Variant.string(dir_name));
				} else {
					GLib.Application.get_default().activate_action("open-resource", ResourceId.path(file_item.item_type, file_item.name));
				}
			}
		}
	}

	private void icon_view_pixbuf_func(Gtk.CellLayout cell_layout, Gtk.CellRenderer cell, Gtk.TreeModel model, Gtk.TreeIter iter)
	{
		Value val;
		string type;
		string name;
		model.get_value(iter, Column.TYPE, out val);
		type = (string)val;
		model.get_value(iter, Column.NAME, out val);
		name = (string)val;

		set_thumbnail(cell, type, name, 64, _thumbnail_cache);
	}

	private void icon_view_text_func(Gtk.CellLayout cell_layout, Gtk.CellRenderer cell, Gtk.TreeModel model, Gtk.TreeIter iter)
	{
		Value type;
		Value name;
		model.get_value(iter, Column.TYPE, out type);
		model.get_value(iter, Column.NAME, out name);

		if (name == "..")
			cell.set_property("text", name);
		else
			cell.set_property("text", GLib.Path.get_basename((string)name));
	}

	private void list_view_pixbuf_func(Gtk.CellLayout cell_layout, Gtk.CellRenderer cell, Gtk.TreeModel model, Gtk.TreeIter iter)
	{
		Value val;
		string type;
		string name;
		model.get_value(iter, Column.TYPE, out val);
		type = (string)val;
		model.get_value(iter, Column.NAME, out val);
		name = (string)val;

		set_thumbnail(cell, type, name, 32, _thumbnail_cache);
	}

	private void list_view_basename_text_func(Gtk.CellLayout cell_layout, Gtk.CellRenderer cell, Gtk.TreeModel model, Gtk.TreeIter iter)
	{
		Value name;
		model.get_value(iter, Column.NAME, out name);

		if (name == "..")
			cell.set_property("text", name);
		else
			cell.set_property("text", GLib.Path.get_basename((string)name));
	}

	private void list_view_type_text_func(Gtk.CellLayout cell_layout, Gtk.CellRenderer cell, Gtk.TreeModel model, Gtk.TreeIter iter)
	{
		Value type;
		model.get_value(iter, Column.TYPE, out type);

		cell.set_property("text", prettify_type((string)type));
	}

	private void list_view_size_text_func(Gtk.CellLayout cell_layout, Gtk.CellRenderer cell, Gtk.TreeModel model, Gtk.TreeIter iter)
	{
		Value val;
		model.get_value(iter, Column.SIZE, out val);
		uint64 size = (uint64)val;

		if (size != 0)
			cell.set_property("text", prettify_size(size));
		else
			cell.set_property("text", "n/a");
	}

	private void list_view_mtime_text_func(Gtk.CellLayout cell_layout, Gtk.CellRenderer cell, Gtk.TreeModel model, Gtk.TreeIter iter)
	{
		Value type;
		model.get_value(iter, Column.MTIME, out type);
		uint64 mtime = (uint64)type;

		if (mtime != 0)
			cell.set_property("text", prettify_time(mtime));
		else
			cell.set_property("text", "n/a");
	}

	private void list_view_name_text_func(Gtk.CellLayout cell_layout, Gtk.CellRenderer cell, Gtk.TreeModel model, Gtk.TreeIter iter)
	{
		Value name;
		model.get_value(iter, Column.NAME, out name);

		if (name == "..")
			cell.set_property("text", "n/a");
		else
			cell.set_property("text", (string)name);
	}

	public void reveal(string type, string name)
	{
		uint n_items = _list_model.get_n_items();
		for (uint i = 0; i < n_items; i++) {
			ProjectFileItem? item = (ProjectFileItem?)_list_model.get_item(i);
			if (item != null && item.name == name && item.item_type == type) {
				_selection_model.set_selected(i);
				// GTK4: ColumnView doesn't have scroll_to_cell method
				// This functionality may need to be implemented differently
				break;
			}
		}
	}

	public bool selected_path(out Gtk.TreePath? path)
	{
		uint selected = _selection_model.get_selected();
		if (selected == Gtk.INVALID_LIST_POSITION) {
			path = null;
			return false;
		}

		path = new Gtk.TreePath.from_indices((int)selected, -1);
		return true;
	}

	private bool on_column_view_query_tooltip(int x, int y, bool keyboard_tooltip, Gtk.Tooltip tooltip)
	{
		// For ColumnView, we can use the selection model to get tooltip info
		uint selected = _selection_model.get_selected();
		if (selected == Gtk.INVALID_LIST_POSITION)
			return false;

		ProjectFileItem? item = (ProjectFileItem?)_list_model.get_item(selected);
		if (item == null)
			return false;

		string text = "<b>%s</b>\nType: %s\nSize: %s\nModified: %s".printf(GLib.Markup.escape_text(item.name)
			, GLib.Markup.escape_text(prettify_type(item.item_type))
			, item.size == 0 ? "n/a" : prettify_size(item.size)
			, item.mtime == 0 ? "n/a" : prettify_time(item.mtime)
			);
		tooltip.set_markup(text);

		return true;
	}

	private static string prettify_type(string type)
	{
		if (type == "<folder>")
			return "Folder";
		else
			return type;
	}

	private static string prettify_size(uint64 size)
	{
		uint64 si_size;
		string si_unit;

		if (size >= 1024*1024*1024) {
			si_size = size / (1024*1024*1024);
			si_unit = "GiB";
		} else if (size >= 1024*1024) {
			si_size = size / (1024*1024);
			si_unit = "MiB";
		} else if (size >= 1024) {
			si_size = size / 1024;
			si_unit = "KiB";
		} else {
			si_size = size;
			si_unit = size > 1 ? "bytes" : "byte";
		}

		return "%d %s".printf((int)si_size, si_unit);
	}

	private static string prettify_time(uint64 time)
	{
		int64 mtime_secs = (int64)(time / (1000*1000*1000));
		GLib.DateTime date_time = new GLib.DateTime.from_unix_local(mtime_secs);
		return date_time.format("%d %b %Y; %H:%M:%S");
	}

	private Gtk.TreePath? path_at_pos(int x, int y)
	{
		// GTK4: ColumnView doesn't have direct coordinate-to-path conversion
		// This functionality may need to be implemented differently
		// For now, we'll use the current selection
		uint selected = _selection_model.get_selected();
		if (selected != Gtk.INVALID_LIST_POSITION) {
			return new Gtk.TreePath.from_indices((int)selected, -1);
		}
		return null;
	}

	private void resource_at_path(out string type, out string name, Gtk.TreePath? path)
	{
		if (path != null) {
			uint position = (uint)path.get_indices()[0];
			ProjectFileItem? item = (ProjectFileItem?)_list_model.get_item(position);
			if (item != null) {
				type = item.item_type;
				name = item.name;
			} else {
				type = _selected_type;
				name = _selected_name;
			}
		} else {
			type = _selected_type;
			name = _selected_name;
		}
	}
}

public class ProjectBrowser : Gtk.Box
{
	public enum SortMode
	{
		NAME_AZ,
		NAME_ZA,
		TYPE_AZ,
		TYPE_ZA,
		SIZE_MIN_MAX,
		SIZE_MAX_MIN,
		LAST_MTIME,
		FIRST_MTIME,

		COUNT;

		public string to_label()
		{
			switch (this) {
			case NAME_AZ:
				return "Name A-Z";
			case NAME_ZA:
				return "Name Z-A";
			case TYPE_AZ:
				return "Type A-Z";
			case TYPE_ZA:
				return "Type Z-A";
			case SIZE_MIN_MAX:
				return "Size min-Max";
			case SIZE_MAX_MIN:
				return "Size Max-min";
			case LAST_MTIME:
				return "Last Modified";
			case FIRST_MTIME:
				return "First Modified";
			default:
				return "Unknown";
			}
		}
	}

	// Data
	public ProjectStore _project_store;
	public ThumbnailCache _thumbnail_cache;

	// Widgets
	public Gtk.TreeModelFilter _tree_filter;
	public Gtk.TreeModelSort _tree_sort;
	public Gtk.TreeView _tree_view;
	public Gtk.TreeSelection _tree_selection;
	public Gdk.Pixbuf _empty_pixbuf;
	public ProjectFolderView _folder_view;
	public bool _show_folder_view;
	public Gtk.Image _toggle_folder_view_image;
	public Gtk.Button _toggle_folder_view;
	public Gtk.Box _tree_view_content;
	public Gtk.ListStore _folder_list_store;
	public Gtk.TreeModelSort _folder_list_sort;
	public SortMode _sort_mode;
	public Gtk.Box _sort_items_box;
	public Gtk.Popover _sort_items_popover;
	public Gtk.MenuButton _sort_items;
	public Gtk.Box _empty_favorites_box;
	public Gtk.Stack _folder_stack;
	public Gtk.Box _folder_view_content;
	public Gtk.ScrolledWindow _scrolled_window;
	public Gtk.Paned _paned;
	public Gtk.GestureClick _tree_view_gesture_click;

	public bool _hide_core_resources;

	public ProjectBrowser(ProjectStore project_store, ThumbnailCache thumbnail_cache)
	{
		Object(orientation: Gtk.Orientation.VERTICAL);

		// Data
		_project_store = project_store;
		_thumbnail_cache = thumbnail_cache;
		_thumbnail_cache.changed.connect(() => {
			_tree_view.queue_draw();
			_folder_view.queue_draw();
		});

		// Widgets
		_tree_filter = new Gtk.TreeModelFilter(_project_store._tree_store, null);
		_tree_filter.set_visible_func((model, iter) => {
				if (_project_store.project_root_path() != null)
					_tree_view.expand_row(_project_store.project_root_path(), false);

				Value type;
				Value name;
				model.get_value(iter, ProjectStore.Column.TYPE, out type);
				model.get_value(iter, ProjectStore.Column.NAME, out name);

				bool should_show = (string)type != null
					&& (string)name != null
					&& !row_should_be_hidden((string)type, (string)name)
					;

				if (_show_folder_view) {
					// Hide all descendants of the favorites root.
					Gtk.TreePath? path = model.get_path(iter);
					if (path != null && _project_store.favorites_root_path() != null && path.is_descendant(_project_store.favorites_root_path()))
						return false;

					return should_show && (type == "<folder>" || type == "<favorites>");
				} else {
					return should_show;
				}
			});

		_tree_sort = new Gtk.TreeModelSort.with_model(_tree_filter);
		_tree_sort.set_default_sort_func((model, iter_a, iter_b) => {
				Value type_a;
				Value type_b;
				model.get_value(iter_a, ProjectStore.Column.TYPE, out type_a);
				model.get_value(iter_b, ProjectStore.Column.TYPE, out type_b);

				// Favorites is always on top.
				if ((string)type_a == "<favorites>")
					return -1;
				if ((string)type_b == "<favorites>")
					return 1;

				// Then folders.
				if ((string)type_a == "<folder>") {
					if ((string)type_b != "<folder>")
						return -1;
				} else if ((string)type_b == "<folder>") {
					if ((string)type_a != "<folder>")
						return 1;
				}

				// And finally, regular files.
				Value id_a;
				Value id_b;
				model.get_value(iter_a, ProjectStore.Column.NAME, out id_a);
				model.get_value(iter_b, ProjectStore.Column.NAME, out id_b);
				return strcmp(GLib.Path.get_basename((string)id_a), GLib.Path.get_basename((string)id_b));
			});

		Gtk.CellRendererPixbuf cell_pixbuf = new Gtk.CellRendererPixbuf();
		cell_pixbuf.icon_size = Gtk.IconSize.INHERIT;
		Gtk.CellRendererText cell_text = new Gtk.CellRendererText();
		Gtk.TreeViewColumn column = new Gtk.TreeViewColumn();
		column.pack_start(cell_pixbuf, false);
		column.pack_start(cell_text, true);
		column.set_cell_data_func(cell_pixbuf, pixbuf_func);
		column.set_cell_data_func(cell_text, text_func);
		_tree_view = new Gtk.TreeView();
		_tree_view.append_column(column);
#if 0
		// For debugging.
		_tree_view.insert_column_with_attributes(-1
			, "Segment"
			, new Gtk.CellRendererText()
			, "text"
			, ProjectStore.Column.SEGMENT
			, null
			);
		_tree_view.insert_column_with_attributes(-1
			, "Name"
			, new Gtk.CellRendererText()
			, "text"
			, ProjectStore.Column.NAME
			, null
			);
		_tree_view.insert_column_with_attributes(-1
			, "Type"
			, new Gtk.CellRendererText()
			, "text"
			, ProjectStore.Column.TYPE
			, null
			);
#endif /* if 0 */
		_tree_view.model = _tree_sort;
		_tree_view.headers_visible = false;

		_tree_view_gesture_click = new Gtk.GestureClick();
		_tree_view_gesture_click.set_button(0);
		_tree_view_gesture_click.pressed.connect(on_button_pressed);
		_tree_view.add_controller(_tree_view_gesture_click);

		/*
		_tree_view.enable_model_drag_source(Gdk.ModifierType.BUTTON1_MASK, dnd_targets, Gdk.DragAction.COPY);
		_tree_view.drag_data_get.connect(on_drag_data_get);
		_tree_view.drag_begin.connect_after(on_drag_begin);
		_tree_view.drag_end.connect(on_drag_end);
		*/

		_tree_selection = _tree_view.get_selection();
		_tree_selection.set_mode(Gtk.SelectionMode.BROWSE);
		_tree_selection.changed.connect(() => { update_folder_view(); });

		_empty_pixbuf = new Gdk.Pixbuf.from_data({ 0x00, 0x00, 0x00, 0x00 }, Gdk.Colorspace.RGB, true, 8, 1, 1, 4);

		_project_store._tree_store.row_inserted.connect((path, iter) => { update_folder_view(); });
		_project_store._tree_store.row_changed.connect((path, iter) => { update_folder_view(); });
		_project_store._tree_store.row_deleted.connect((path) => { update_folder_view(); });

		// Create icon view.
		_folder_view = new ProjectFolderView(_project_store, thumbnail_cache);

		// Create switch button.
		_show_folder_view = true;
		_toggle_folder_view_image = new Gtk.Image.from_icon_name("level-tree-symbolic");
		_toggle_folder_view = new Gtk.Button();
		_toggle_folder_view.set_child(_toggle_folder_view_image);
		_toggle_folder_view.add_css_class("flat");
		_toggle_folder_view.add_css_class("image-button");
		_toggle_folder_view.can_focus = false;
		_toggle_folder_view.clicked.connect(() => {
				_show_folder_view = !_show_folder_view;

				if (_show_folder_view) {
					// Save the currently selected resource and a path to its parent. Those will be
					// used later, after the tree has been refiltered, to show the correct folder
					// and reveal the selected resource in the icon view.
					string? selected_type = null;
					string? selected_name = null;
					Gtk.TreePath? parent_path = null;
					Gtk.TreeModel selected_model;
					Gtk.TreeIter selected_iter;
					if (_tree_selection.get_selected(out selected_model, out selected_iter)) {
						Value val;
						selected_model.get_value(selected_iter, ProjectStore.Column.TYPE, out val);
						selected_type = (string)val;
						selected_model.get_value(selected_iter, ProjectStore.Column.NAME, out val);
						selected_name = (string)val;

						if (selected_type != "<folder>") {
							Gtk.TreeIter parent_iter;
							if (selected_model.iter_parent(out parent_iter, selected_iter))
								parent_path = _tree_view.model.get_path(parent_iter);
						}
					}

					_tree_filter.refilter();

					if (parent_path != null) {
						_tree_selection.select_path(parent_path);
						_folder_view.reveal(selected_type, selected_name);
					}

					_folder_view_content.show();
					_toggle_folder_view_image.set_from_icon_name("level-tree-symbolic");
				} else {
					// Save the currently selected resource. This will be used later, after the tree
					// has been refiltered, to reveal the selected resource in the tree view.
					string? selected_type = null;
					string? selected_name = null;

					Gtk.TreePath selected_path;
					if (_folder_view.selected_path(out selected_path)) {
						uint position = (uint)selected_path.get_indices()[0];
						ProjectFileItem? item = (ProjectFileItem?)_folder_view._list_model.get_item(position);
						if (item != null) {
							selected_type = item.item_type;
							selected_name = item.name;
						}
					}

					_tree_filter.refilter();

					if (selected_type != null && selected_type != "<folder>") {
						reveal(selected_type, selected_name);
					}

					_folder_view_content.hide();
					_toggle_folder_view_image.set_from_icon_name("browser-icon-view");

					_tree_view.queue_draw(); // It doesn't draw by itself sometimes...
				}
			});

		// Create paned split-view.
		_scrolled_window = new Gtk.ScrolledWindow();
		_scrolled_window.set_child(_tree_view);

		var _tree_view_control = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 0);
		_tree_view_control.append(_toggle_folder_view);

		_tree_view_content = new Gtk.Box(Gtk.Orientation.VERTICAL, 0);
		_tree_view_content.prepend(_tree_view_control);
		_tree_view_content.prepend(_scrolled_window);

		// Setup sort menu button popover.
		_sort_items_box = new Gtk.Box(Gtk.Orientation.VERTICAL, 0);

		// Note: Sort menu implementation removed for simplification

		_sort_items_popover = new Gtk.Popover();
		_sort_items_popover.set_child(_sort_items_box);
		_sort_items = new Gtk.MenuButton();
		_sort_items.set_child(new Gtk.Image.from_icon_name("list-sort"));
		_sort_items.add_css_class("flat");
		_sort_items.add_css_class("image-button");
		_sort_items.can_focus = false;
		_sort_items.set_popover(_sort_items_popover);

		// Note: Removed icon/list view toggle - always using ColumnView now

		var _folder_view_control = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 0);
		_folder_view_control.append(_sort_items);

		_empty_favorites_box = new Gtk.Box(Gtk.Orientation.VERTICAL, 0);
		_empty_favorites_box.valign = Gtk.Align.CENTER;
		_empty_favorites_box.prepend(new Gtk.Image.from_icon_name("browser-favorites"));
		_empty_favorites_box.prepend(new Gtk.Label("Favorites is empty"));

		_folder_stack = new Gtk.Stack();
		_folder_stack.add_named(_folder_view, "folder-view");
		_folder_stack.add_named(_empty_favorites_box, "empty-favorites");
		_folder_stack.set_visible_child_full("folder-view", Gtk.StackTransitionType.NONE);

		_folder_view_content = new Gtk.Box(Gtk.Orientation.VERTICAL, 0);
		_folder_view_content.prepend(_folder_view_control);
		_folder_view_content.prepend(_folder_stack);

		// Create a paned layout internally since we changed from Gtk.Paned to Gtk.Box
		_paned = new Gtk.Paned(Gtk.Orientation.HORIZONTAL);
		_paned.set_start_child(_tree_view_content);
		_paned.set_end_child(_folder_view_content);
		_paned.set_position(400);
		this.append(_paned);

		_hide_core_resources = true;

		_folder_list_store = new Gtk.ListStore(ProjectStore.Column.COUNT
			, typeof(string) // ProjectStore.Column.NAME
			, typeof(string) // ProjectStore.Column.TYPE
			, typeof(uint64) // ProjectStore.Column.SIZE
			, typeof(uint64) // ProjectStore.Column.MTIME
			);

		_folder_list_sort = new Gtk.TreeModelSort.with_model(_folder_list_store);
		_folder_list_sort.set_default_sort_func((model, iter_a, iter_b) => {
				Value type_a;
				Value type_b;
				model.get_value(iter_a, ProjectStore.Column.TYPE, out type_a);
				model.get_value(iter_b, ProjectStore.Column.TYPE, out type_b);
				Value name_a;
				Value name_b;
				model.get_value(iter_a, ProjectStore.Column.NAME, out name_a);
				model.get_value(iter_b, ProjectStore.Column.NAME, out name_b);

				// Folders are always on top.
				if ((string)type_a == "<folder>" && (string)type_b != "<folder>") {
					return -1;
				} else if ((string)type_a != "<folder>" && (string)type_b == "<folder>") {
					return 1;
				} else if ((string)type_a == "<folder>" && (string)type_b == "<folder>") {
					// Special folders always first.
					if ((string)name_a == "..")
						return -1;
					else if ((string)name_b == "..")
						return 1;
				}

				switch (_sort_mode) {
				case SortMode.NAME_AZ:
				case SortMode.NAME_ZA: {
					int cmp = strcmp((string)name_a, (string)name_b);
					return _sort_mode == SortMode.NAME_AZ ? cmp : -cmp;
				}

				case SortMode.TYPE_AZ:
				case SortMode.TYPE_ZA: {
					int cmp = strcmp((string)type_a, (string)type_b);
					return _sort_mode == SortMode.TYPE_AZ ? cmp : -cmp;

				}

				case SortMode.SIZE_MIN_MAX:
				case SortMode.SIZE_MAX_MIN: {
					Value size_a;
					Value size_b;
					model.get_value(iter_a, ProjectStore.Column.SIZE, out size_a);
					model.get_value(iter_b, ProjectStore.Column.SIZE, out size_b);

					int cmp = (uint64)size_a <= (uint64)size_b ? -1 : 1;
					return _sort_mode == SortMode.SIZE_MIN_MAX ? cmp : -cmp;
				}

				case SortMode.LAST_MTIME:
				case SortMode.FIRST_MTIME: {
					Value mtime_a;
					Value mtime_b;
					model.get_value(iter_a, ProjectStore.Column.MTIME, out mtime_a);
					model.get_value(iter_b, ProjectStore.Column.MTIME, out mtime_b);

					int cmp = (uint64)mtime_a >= (uint64)mtime_b ? -1 : 1;
					return _sort_mode == SortMode.LAST_MTIME ? cmp : -cmp;
				}

				default:
					return 0;
				}
			});

		// Actions.
		GLib.ActionEntry[] action_entries =
		{
			{ "open-directory",      on_open_directory,      "s",    null },
			{ "favorite-resource",   on_favorite_resource,   "(ss)", null },
			{ "unfavorite-resource", on_unfavorite_resource, "(ss)", null }
		};
		GLib.Application.get_default().add_action_entries(action_entries, this);
	}

	/*
	private void on_drag_data_get(Gdk.DragContext context, Gtk.SelectionData data, uint info, uint time_)
	{
		// https://valadoc.org/gtk+-3.0/Gtk.Widget.drag_data_get.html
		Gtk.TreeModel selected_model;
		Gtk.TreeIter selected_iter;
		if (!_tree_selection.get_selected(out selected_model, out selected_iter))
			return;

		Value val;
		string type;
		string name;
		selected_model.get_value(selected_iter, ProjectStore.Column.TYPE, out val);
		type = (string)val;
		selected_model.get_value(selected_iter, ProjectStore.Column.NAME, out val);
		name = (string)val;

		string resource_path = ResourceId.path(type, name);
		data.set(Gdk.Atom.intern_static_string("RESOURCE_PATH"), 8, resource_path.data);
	}

	private void on_drag_begin(Gdk.DragContext context)
	{
		// https://valadoc.org/gtk+-3.0/Gtk.Widget.drag_begin.html
		Gtk.drag_set_icon_pixbuf(context, _empty_pixbuf, 0, 0);
	}

	private void on_drag_end(Gdk.DragContext context)
	{
		// https://valadoc.org/gtk+-3.0/Gtk.Widget.drag_end.html
		GLib.Application.get_default().activate_action("cancel-place", null);
	}
	*/

	// Returns true if the row should be hidden.
	private bool row_should_be_hidden(string type, string name)
	{
		return type == "<folder>" && name == "core" && _hide_core_resources
			|| type == "importer_settings"
			|| name == Project.LEVEL_EDITOR_TEST_NAME
			|| _project_store._project.is_type_importable(type)
			;
	}

	public void reveal(string type, string name)
	{
		if (name.has_prefix("core/")) {
			_hide_core_resources = false;
			_tree_filter.refilter();
		}

		string parent_type = type;
		string parent_name = name;
		Gtk.TreePath filter_path = null;
		do {
			Gtk.TreePath store_path;
			if (!_project_store.path_for_resource_type_name(out store_path, parent_type, parent_name)) {
				break;
			}

			filter_path = _tree_filter.convert_child_path_to_path(store_path);
			if (filter_path == null) {
				// Either the path is not valid or points to a non-visible row in the model.
				parent_type = "<folder>";
				parent_name = ResourceId.parent_folder(parent_name);
				continue;
			}

			Gtk.TreePath sort_path = _tree_sort.convert_child_path_to_path(filter_path);
			if (sort_path == null) {
				// The path is not valid.
				break;
			}

			_tree_view.expand_to_path(sort_path);
			_tree_view.get_selection().select_path(sort_path);
			_tree_view.scroll_to_cell(sort_path, null, false, 0.0f, 0.0f);
			_folder_view.reveal(type, name);
		} while (filter_path == null);
	}

	private void on_open_directory(GLib.SimpleAction action, GLib.Variant? param)
	{
		string dir_name = param.get_string();

		if (dir_name.has_prefix("core/") || dir_name == "core") {
			_hide_core_resources = false;
			_tree_filter.refilter();
		}

		Gtk.TreePath store_path;
		if (_project_store.path_for_resource_type_name(out store_path, "<folder>", dir_name)) {
			Gtk.TreePath filter_path = _tree_filter.convert_child_path_to_path(store_path);
			if (filter_path == null) // Either the path is not valid or points to a non-visible row in the model.
				return;
			Gtk.TreePath sort_path = _tree_sort.convert_child_path_to_path(filter_path);
			if (sort_path == null) // The path is not valid.
				return;

			_tree_view.expand_to_path(sort_path);
			_tree_view.get_selection().select_path(sort_path);
		}
	}

	private void on_favorite_resource(GLib.SimpleAction action, GLib.Variant? param)
	{
		string type = (string)param.get_child_value(0);
		string name = (string)param.get_child_value(1);

		_project_store.add_to_favorites(type, name);
	}

	private void on_unfavorite_resource(GLib.SimpleAction action, GLib.Variant? param)
	{
		string type = (string)param.get_child_value(0);
		string name = (string)param.get_child_value(1);

		_project_store.remove_from_favorites(type, name);
	}

	private void on_button_pressed(int n_press, double x, double y)
	{
		int bx;
		int by;
		Gtk.TreePath path;
		_tree_view.convert_widget_to_bin_window_coords((int)x, (int)y, out bx, out by);
		if (!_tree_view.get_path_at_pos(bx, by, out path, null, null, null))
			return;

		uint button = _tree_view_gesture_click.get_current_button();

		if (button == Gdk.BUTTON_SECONDARY) {
			Gtk.TreeIter iter;
			_tree_view.model.get_iter(out iter, path);

			Value type;
			Value name;
			_tree_view.model.get_value(iter, ProjectStore.Column.TYPE, out type);
			_tree_view.model.get_value(iter, ProjectStore.Column.NAME, out name);

			Gtk.TreePath? filter_path = _tree_sort.convert_path_to_child_path(path);
			Gtk.TreePath? store_path = _tree_filter.convert_path_to_child_path(filter_path);
			GLib.Menu? menu_model;
			if (store_path.is_descendant(_project_store.project_root_path()) || store_path.compare(_project_store.project_root_path()) == 0)
				menu_model = project_entry_menu_create((string)type, (string)name);
			else if (store_path.is_descendant(_project_store.favorites_root_path()))
				menu_model = favorites_entry_menu_create((string)type, (string)name);
			else
				menu_model = null;

			if (menu_model != null) {
				Gtk.PopoverMenu menu = new Gtk.PopoverMenu.from_model(menu_model);
				menu.set_pointing_to({ (int)x, (int)y, 1, 1 });
				menu.set_position(Gtk.PositionType.BOTTOM);
				menu.popup();
			}
		} else if (button == Gdk.BUTTON_PRIMARY && n_press == 2) {
			Gtk.TreeIter iter;
			_tree_view.model.get_iter(out iter, path);

			Value type;
			_tree_view.model.get_value(iter, ProjectStore.Column.TYPE, out type);
			if ((string)type == "<folder>")
				return;

			Value name;
			_tree_view.model.get_value(iter, ProjectStore.Column.NAME, out name);

			GLib.Application.get_default().activate_action("open-resource", ResourceId.path((string)type, (string)name));
		}

		return;
	}

	private void update_folder_view()
	{
		_folder_list_store.clear();
		_folder_view._list_model.remove_all();

		// Get the selected node's type and name.
		Gtk.TreeModel selected_model;
		Gtk.TreeIter selected_iter;
		if (!_tree_selection.get_selected(out selected_model, out selected_iter))
			return;

		string selected_type;
		string selected_name;
		Value val;
		selected_model.get_value(selected_iter, ProjectStore.Column.TYPE, out val);
		selected_type = (string)val;
		selected_model.get_value(selected_iter, ProjectStore.Column.NAME, out val);
		selected_name = (string)val;

		if (selected_type == "<folder>") {
			_folder_view._showing_project_folder = true;

			// Add parent folder.
			if (selected_name != "") {
				Gtk.TreeIter dummy;
				_folder_list_store.insert_with_values(out dummy
					, -1
					, ProjectStore.Column.TYPE
					, "<folder>"
					, ProjectStore.Column.NAME
					, ".."
					, ProjectStore.Column.SIZE
					, 0u
					, ProjectStore.Column.MTIME
					, 0u
					, -1
					);
			}

			// Fill the intermediate icon view list with paths matching the selected node's name.
			_project_store._list_store.foreach((model, path, iter) => {
					string type;
					string name;
					model.get_value(iter, ProjectStore.Column.TYPE, out val);
					type = (string)val;
					model.get_value(iter, ProjectStore.Column.NAME, out val);
					name = (string)val;

					if (row_should_be_hidden(type, name))
						return false;

					// Skip paths without common ancestor.
					if (ResourceId.parent_folder(name) != selected_name)
						return false;

					// Skip paths that are too deep in the hierarchy:
					// selected_name: foo
					// hierarchy:
					//   foo/bar OK
					//   foo/baz OK
					//   foo/bar/baz NOPE
					string name_suffix;
					if (selected_name == "") // Project folder.
						name_suffix = name.substring((selected_name).length);
					else if (selected_name != name) // Folder itself.
						name_suffix = name.substring((selected_name).length + 1);
					else
						return false;

					if (name_suffix.index_of_char('/') != -1)
						return false;

					uint64 size;
					uint64 mtime;
					model.get_value(iter, ProjectStore.Column.SIZE, out val);
					size = (uint64)val;
					model.get_value(iter, ProjectStore.Column.MTIME, out val);
					mtime = (uint64)val;

					// Add the path to the list.
					Gtk.TreeIter dummy;
					_folder_list_store.insert_with_values(out dummy
						, -1
						, ProjectStore.Column.TYPE
						, type
						, ProjectStore.Column.NAME
						, name
						, ProjectStore.Column.SIZE
						, size
						, ProjectStore.Column.MTIME
						, mtime
						, -1
						);
					return false;
				});

			_folder_view._selected_type = selected_type;
			_folder_view._selected_name = selected_name;

			_folder_stack.set_visible_child_full("folder-view", Gtk.StackTransitionType.NONE);
		} else if (selected_type == "<favorites>") {
			_folder_view._showing_project_folder = false;
			int num_items = 0;

			// Fill the icon view list with paths whose ancestor is the favorites root.
			_project_store._tree_store.foreach((model, path, iter) => {
					string type;
					string name;
					model.get_value(iter, ProjectStore.Column.TYPE, out val);
					type = (string)val;
					model.get_value(iter, ProjectStore.Column.NAME, out val);
					name = (string)val;

					if (!path.is_descendant(_project_store.favorites_root_path()))
						return false;

					uint64 size;
					uint64 mtime;
					model.get_value(iter, ProjectStore.Column.SIZE, out val);
					size = (uint64)val;
					model.get_value(iter, ProjectStore.Column.MTIME, out val);
					mtime = (uint64)val;

					// Add the path to the list.
					Gtk.TreeIter dummy;
					_folder_list_store.insert_with_values(out dummy
						, -1
						, ProjectStore.Column.TYPE
						, type
						, ProjectStore.Column.NAME
						, name
						, ProjectStore.Column.SIZE
						, size
						, ProjectStore.Column.MTIME
						, mtime
						, -1
						);
					++num_items;
					return false;
				});

				if (num_items == 0)
					_folder_stack.set_visible_child_full("empty-favorites", Gtk.StackTransitionType.NONE);
				else
					_folder_stack.set_visible_child_full("folder-view", Gtk.StackTransitionType.NONE);
		}

		// Now, fill the actual icon view list with correctly sorted paths.
		_folder_list_sort.foreach((model, path, iter) => {
				string type;
				string name;
				uint64 size;
				uint64 mtime;
				model.get_value(iter, ProjectStore.Column.TYPE, out val);
				type = (string)val;
				model.get_value(iter, ProjectStore.Column.NAME, out val);
				name = (string)val;
				model.get_value(iter, ProjectStore.Column.SIZE, out val);
				size = (uint64)val;
				model.get_value(iter, ProjectStore.Column.MTIME, out val);
				mtime = (uint64)val;

				// Add the path to both models
				var pixbuf = _thumbnail_cache.get(type, name);
				var item = new ProjectFileItem(type, name, pixbuf, size, mtime);
				_folder_view._list_model.append(item);
				
				return false;
			});
	}

	public void select_project_root()
	{
		Gtk.TreePath? filter_path = _tree_filter.convert_child_path_to_path(_project_store.project_root_path());
		if (filter_path == null)
			return;

		Gtk.TreePath? sort_path = _tree_sort.convert_child_path_to_path(filter_path);
		if (sort_path == null)
			return;

		_tree_selection.select_path(sort_path);
	}

	private void pixbuf_func(Gtk.CellLayout cell_layout, Gtk.CellRenderer cell, Gtk.TreeModel model, Gtk.TreeIter iter)
	{
		Value val;
		string type;
		string name;
		model.get_value(iter, ProjectStore.Column.TYPE, out val);
		type = (string)val;
		model.get_value(iter, ProjectStore.Column.NAME, out val);
		name = (string)val;

		set_thumbnail(cell, type, name, 16, _thumbnail_cache);
	}

	private void text_func(Gtk.CellLayout cell_layout, Gtk.CellRenderer cell, Gtk.TreeModel model, Gtk.TreeIter iter)
	{
		Value name;
		Value type;
		model.get_value(iter, ProjectStore.Column.NAME, out name);
		model.get_value(iter, ProjectStore.Column.TYPE, out type);

		string basename = GLib.Path.get_basename((string)name);

		if ((string)type == "<folder>") {
			if ((string)name == "")
				cell.set_property("text", _project_store._project.name());
			else
				cell.set_property("text", basename);
		} else if ((string)type == "<favorites>") {
			cell.set_property("text", "Favorites");
		} else {
			cell.set_property("text", ResourceId.path((string)type, basename));
		}
	}
}

} /* namespace Crown */
