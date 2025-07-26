/*
 * Copyright (c) 2012-2025 Daniele Bartolini et al.
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

namespace Crown
{
// Returns true if the item should be filtered out
private bool user_filter(string type, string name)
{
	return (type == OBJECT_TYPE_UNIT || type == OBJECT_TYPE_SOUND) && !name.has_prefix("core/");
}

public delegate bool UserFilter(string type, string name);

public class ResourceChooser : Gtk.Box
{
	// Data
	public Project _project;
	public Gtk.ListStore _list_store;
	public Gtk.Stack? _editor_stack;
	public RuntimeInstance? _resource_preview;
	public unowned UserFilter _user_filter;
	public string _name;

	// Widgets
	public EntrySearch _filter_entry;
	public Gtk.EventControllerKey _filter_entry_controller_key;
	public Gtk.TreeModelFilter _tree_filter;          // Keep for compatibility
	public Gtk.TreeModelSort _tree_sort;              // Keep for compatibility
	public Gtk.TreeView _tree_view;                   // Keep for compatibility
	public Gtk.GestureClick _tree_view_gesture_click;
	public Gtk.TreeSelection _tree_selection;         // Keep for compatibility
	public GLib.ListStore _resource_model;            // New GTK4 model
	public Gtk.SingleSelection _selection_model;      // New GTK4 selection
	public Gtk.ColumnView _column_view;               // New GTK4 view
	public Gtk.ScrolledWindow _scrolled_window;
	public Gtk.ScrolledWindow _column_view_window;    // New scrolled window for ColumnView
	public Gtk.Stack _view_stack;                     // Stack to switch between old/new views

	// Signals
	public signal void resource_selected(string type, string name);

	public ResourceChooser(Project? project
		, ProjectStore project_store
		, Gtk.Stack? editor_stack = null
		, RuntimeInstance? resource_preview = null
		)
	{
		Object(orientation: Gtk.Orientation.VERTICAL, spacing: 0);

		// Data
		_project = project;

		_list_store = project_store._list_store;
		_editor_stack = editor_stack;
		_resource_preview = resource_preview;
		_user_filter = user_filter;

		// Widgets
		_filter_entry = new EntrySearch();
		_filter_entry.set_placeholder_text("Search...");
		_filter_entry.search_changed.connect(on_filter_entry_text_changed);

		_filter_entry_controller_key = new Gtk.EventControllerKey();
		_filter_entry_controller_key.key_pressed.connect(on_filter_entry_key_pressed);
		_filter_entry.add_controller(_filter_entry_controller_key);

		_tree_filter = new Gtk.TreeModelFilter(_list_store, null);
		_tree_filter.set_visible_func((model, iter) => {
				Value type;
				Value name;
				model.get_value(iter, ProjectStore.Column.TYPE, out type);
				model.get_value(iter, ProjectStore.Column.NAME, out name);

				string type_str = (string)type;
				string name_str = (string)name;

				return type_str != null
					&& name_str != null
					&& _user_filter(type_str, name_str)
					&& (_filter_entry.text.length == 0 || name_str.index_of(_filter_entry.text) > -1)
					;
			});

		_tree_sort = new Gtk.TreeModelSort.with_model(_tree_filter);
		_tree_sort.set_default_sort_func((model, iter_a, iter_b) => {
				Value id_a;
				Value id_b;
				model.get_value(iter_a, ProjectStore.Column.NAME, out id_a);
				model.get_value(iter_b, ProjectStore.Column.NAME, out id_b);
				return strcmp((string)id_a, (string)id_b);
			});

		_tree_view = new Gtk.TreeView();
		_tree_view.insert_column_with_attributes(-1
			, "Name"
			, new Gtk.CellRendererText()
			, "text"
			, ProjectStore.Column.NAME
			, null
			);
#if 0
		// For debugging.
		_tree_view.insert_column_with_attributes(-1
			, "Type"
			, new Gtk.CellRendererText()
			, "text"
			, ProjectStore.Column.TYPE
			, null
			);
#endif
		_tree_view.model = _tree_sort;
		_tree_view.headers_visible = false;
		_tree_view.can_focus = false;
		_tree_view.row_activated.connect(on_row_activated);

		_tree_view_gesture_click = new Gtk.GestureClick();
		_tree_view_gesture_click.set_button(0);
		_tree_view_gesture_click.released.connect(on_button_released);
		_tree_view.add_controller(_tree_view_gesture_click);

		_tree_selection = _tree_view.get_selection();
		_tree_selection.set_mode(Gtk.SelectionMode.BROWSE);
		_tree_selection.changed.connect(on_tree_selection_changed);

		// GTK4: Create new list model and ColumnView
		_resource_model = new GLib.ListStore(typeof(ProjectFileItem));
		_selection_model = new Gtk.SingleSelection(_resource_model);
		_column_view = new Gtk.ColumnView(_selection_model);
		
		// Create column for ColumnView
		create_column_view_columns();
		
		// Populate GTK4 model from existing TreeModelFilter
		populate_resource_model();

		_scrolled_window = new Gtk.ScrolledWindow();
		_scrolled_window.set_child(_tree_view);
		_scrolled_window.set_size_request(300, 400);
		
		_column_view_window = new Gtk.ScrolledWindow();
		_column_view_window.set_child(_column_view);
		_column_view_window.set_size_request(300, 400);
		
		// Create stack to switch between TreeView and ColumnView
		_view_stack = new Gtk.Stack();
		_view_stack.add_named(_scrolled_window, "tree-view");
		_view_stack.add_named(_column_view_window, "column-view");
		_view_stack.set_visible_child_name("column-view");  // Use GTK4 by default

		this.prepend(_filter_entry);
		if (_editor_stack != null)
			this.prepend(_editor_stack);
		this.prepend(_view_stack);

		this.unmap.connect(on_unmap);
	}

	// GTK4: Create ColumnView columns
	private void create_column_view_columns()
	{
		var factory = new Gtk.SignalListItemFactory();
		
		factory.setup.connect((item) => {
			var list_item = (Gtk.ListItem)item;
			var label = new Gtk.Label("");
			label.set_halign(Gtk.Align.START);
			list_item.set_child(label);
		});
		
		factory.bind.connect((item) => {
			var list_item = (Gtk.ListItem)item;
			var file_item = (ProjectFileItem)list_item.get_item();
			var label = (Gtk.Label)list_item.get_child();
			label.set_text(file_item.name);
		});
		
		var column = new Gtk.ColumnViewColumn("Name", factory);
		column.set_expand(true);
		_column_view.append_column(column);
	}

	// Populate GTK4 model from existing TreeModelFilter
	private void populate_resource_model()
	{
		_resource_model.remove_all();
		
		_tree_filter.foreach((model, path, iter) => {
			Value name, type;
			model.get_value(iter, ProjectStore.Column.NAME, out name);
			model.get_value(iter, ProjectStore.Column.TYPE, out type);
			
			// Create a ProjectFileItem for each resource
			var item = new ProjectFileItem((string)type, (string)name, null, 0, 0);
			_resource_model.append(item);
			
			return false;
		});
	}

	private void on_row_activated(Gtk.TreeView tree_view, Gtk.TreePath path, Gtk.TreeViewColumn? column)
	{
		Gtk.TreePath filter_path = _tree_sort.convert_path_to_child_path(path);
		Gtk.TreePath child_path = _tree_filter.convert_path_to_child_path(filter_path);
		Gtk.TreeIter iter;
		if (_list_store.get_iter(out iter, child_path)) {
			Value name;
			Value type;
			_list_store.get_value(iter, ProjectStore.Column.NAME, out name);
			_list_store.get_value(iter, ProjectStore.Column.TYPE, out type);
			_name = (string)name;
			resource_selected((string)type, (string)name);
		}
	}

	private void on_button_released(int n_press, double x, double y)
	{
		uint button = _tree_view_gesture_click.get_current_button();

		if (button == Gdk.BUTTON_PRIMARY) {
			int bx;
			int by;
			Gtk.TreePath path;
			_tree_view.convert_widget_to_bin_window_coords((int)x, (int)y, out bx, out by);
			if (_tree_view.get_path_at_pos(bx, by, out path, null, null, null)) {
				if (_tree_view.get_selection().path_is_selected(path)) {
					Gtk.TreePath filter_path = _tree_sort.convert_path_to_child_path(path);
					Gtk.TreePath child_path = _tree_filter.convert_path_to_child_path(filter_path);
					Gtk.TreeIter iter;
					if (_list_store.get_iter(out iter, child_path)) {
						Value name;
						Value type;
						_list_store.get_value(iter, ProjectStore.Column.NAME, out name);
						_list_store.get_value(iter, ProjectStore.Column.TYPE, out type);
						_name = (string)name;
						resource_selected((string)type, (string)name);
					}
				}
			}
		}
	}

	private void on_unmap()
	{
		_filter_entry.text = "";
	}

	private void on_filter_entry_text_changed()
	{
		_tree_selection.changed.disconnect(on_tree_selection_changed);
		_tree_filter.refilter();
		_tree_selection.changed.connect(on_tree_selection_changed);
		_tree_view.set_cursor(new Gtk.TreePath.first(), null, false);
	}

	private bool on_filter_entry_key_pressed(uint keyval, uint keycode, Gdk.ModifierType state)
	{
		Gtk.TreeModel model;
		Gtk.TreeIter iter;
		bool selected = _tree_selection.get_selected(out model, out iter);

		if (keyval == Gdk.Key.Down) {
			if (selected && model.iter_next(ref iter)) {
				_tree_selection.select_iter(iter);
				_tree_view.scroll_to_cell(model.get_path(iter), null, true, 1.0f, 0.0f);
			}

			return Gdk.EVENT_STOP;
		} else if (keyval == Gdk.Key.Up) {
			if (selected && model.iter_previous(ref iter)) {
				_tree_selection.select_iter(iter);
				_tree_view.scroll_to_cell(model.get_path(iter), null, true, 1.0f, 0.0f);
			}

			return Gdk.EVENT_STOP;
		} else if (keyval == Gdk.Key.Return) {
			if (selected) {
				Value name;
				Value type;
				model.get_value(iter, ProjectStore.Column.NAME, out name);
				model.get_value(iter, ProjectStore.Column.TYPE, out type);
				_name = (string)name;
				resource_selected((string)type, (string)name);
			}

			return Gdk.EVENT_STOP;
		}

		return Gdk.EVENT_PROPAGATE;
	}

	private void on_tree_selection_changed()
	{
		if (_editor_stack != null) {
			Gtk.TreeModel model;
			Gtk.TreeIter iter;
			if (_tree_selection.get_selected(out model, out iter)) {
				Value name;
				Value type;
				model.get_value(iter, ProjectStore.Column.NAME, out name);
				model.get_value(iter, ProjectStore.Column.TYPE, out type);
				_resource_preview.send_script(UnitPreviewApi.set_preview_resource((string)type, (string)name));
				_resource_preview.send(DeviceApi.frame());
			}
		}
	}

	public void set_type_filter(owned UserFilter filter)
	{
		_user_filter = filter;
		_tree_filter.refilter();
	}
}

} /* namespace Crown */
