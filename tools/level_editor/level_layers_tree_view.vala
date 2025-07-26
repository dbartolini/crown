/*
 * Copyright (c) 2012-2025 Daniele Bartolini et al.
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

namespace Crown
{
// Data model for a single layer item in the level layers view
public class LevelLayerItem : GLib.Object
{
	public string visible_icon { get; set; }
	public string locked_icon { get; set; }
	public string name { get; set; }

	public LevelLayerItem(string visible_icon, string locked_icon, string name)
	{
		Object(
			visible_icon: visible_icon,
			locked_icon: locked_icon,
			name: name
		);
	}
}

public class LevelLayersTreeView : Gtk.Box
{
	private enum ItemFlags
	{
		VISIBLE = 1,
		LOCKED  = 2
	}

	// Data
	private Level _level;
	private Database _db;

	// Widgets
	private EntrySearch _filter_entry;
	private Gtk.ListStore _list_store;                // Keep for compatibility
	private Gtk.TreeModelFilter _tree_filter;        // Keep for compatibility
	private Gtk.TreeView _tree_view;                 // Keep for compatibility
	private Gtk.GestureClick _tree_view_gesture_click;
	private Gtk.TreeSelection _tree_selection;       // Keep for compatibility
	private GLib.ListStore _layer_model;             // New GTK4 model
	private Gtk.SingleSelection _selection_model;    // New GTK4 selection
	private Gtk.ColumnView _column_view;             // New GTK4 view
	private Gtk.ScrolledWindow _scrolled_window;
	private Gtk.ScrolledWindow _column_view_window;  // New scrolled window for ColumnView
	private Gtk.Stack _view_stack;                   // Stack to switch between old/new views

	public LevelLayersTreeView(Database db, Level level)
	{
		Object(orientation: Gtk.Orientation.VERTICAL, spacing: 0);

		// Data
		_level = level;
		_db = db;

		// Widgets
		_filter_entry = new EntrySearch();
		_filter_entry.set_placeholder_text("Search...");
		_filter_entry.search_changed.connect(on_filter_entry_text_changed);

		_list_store = new Gtk.ListStore(3, typeof(string), typeof(string), typeof(string));
		_list_store.insert_with_values(null, -1
			, 0, "layer-visible"
			, 1, "layer-locked"
			, 2, "Background"
			, -1
			);
		_list_store.insert_with_values(null, -1
			, 0, "layer-visible"
			, 1, "layer-locked"
			, 2, "Default"
			, -1
			);

		_tree_filter = new Gtk.TreeModelFilter(_list_store, null);
		_tree_filter.set_visible_func(filter_tree);

		_tree_view = new Gtk.TreeView();
		_tree_view.insert_column_with_attributes(-1, "Visible", new Gtk.CellRendererPixbuf(), "icon-name", 0, null);
		_tree_view.insert_column_with_attributes(-1, "Locked",  new Gtk.CellRendererPixbuf(), "icon-name", 1, null);
		_tree_view.insert_column_with_attributes(-1, "Name",    new Gtk.CellRendererText(),   "text",      2, null);

		_tree_view.headers_clickable = false;
		_tree_view.headers_visible = false;
		_tree_view.model = _tree_filter;

		_tree_view_gesture_click = new Gtk.GestureClick();
		_tree_view_gesture_click.set_button(0);
		_tree_view_gesture_click.pressed.connect(on_button_pressed);
		_tree_view.add_controller(_tree_view_gesture_click);

		_tree_selection = _tree_view.get_selection();
		_tree_selection.set_mode(Gtk.SelectionMode.MULTIPLE);

		// GTK4: Create new list model and ColumnView
		_layer_model = new GLib.ListStore(typeof(LevelLayerItem));
		_selection_model = new Gtk.SingleSelection(_layer_model);
		_column_view = new Gtk.ColumnView(_selection_model);
		
		// Create columns for ColumnView
		create_column_view_columns();
		
		// Populate both models with the same data
		populate_models();

		_scrolled_window = new Gtk.ScrolledWindow();
		_scrolled_window.set_child(_tree_view);
		
		_column_view_window = new Gtk.ScrolledWindow();
		_column_view_window.set_child(_column_view);
		
		// Create stack to switch between TreeView and ColumnView
		_view_stack = new Gtk.Stack();
		_view_stack.add_named(_scrolled_window, "tree-view");
		_view_stack.add_named(_column_view_window, "column-view");
		_view_stack.set_visible_child_name("column-view");  // Use GTK4 by default

		this.prepend(_filter_entry);
		this.prepend(_view_stack);
	}

	// GTK4: Create ColumnView columns
	private void create_column_view_columns()
	{
		// Visible column
		var visible_factory = new Gtk.SignalListItemFactory();
		visible_factory.setup.connect((item) => {
			var list_item = (Gtk.ListItem)item;
			var icon = new Gtk.Image();
			list_item.set_child(icon);
		});
		visible_factory.bind.connect((item) => {
			var list_item = (Gtk.ListItem)item;
			var layer_item = (LevelLayerItem)list_item.get_item();
			var icon = (Gtk.Image)list_item.get_child();
			icon.set_from_icon_name(layer_item.visible_icon);
		});
		var visible_column = new Gtk.ColumnViewColumn("Visible", visible_factory);
		visible_column.set_fixed_width(50);
		_column_view.append_column(visible_column);

		// Locked column
		var locked_factory = new Gtk.SignalListItemFactory();
		locked_factory.setup.connect((item) => {
			var list_item = (Gtk.ListItem)item;
			var icon = new Gtk.Image();
			list_item.set_child(icon);
		});
		locked_factory.bind.connect((item) => {
			var list_item = (Gtk.ListItem)item;
			var layer_item = (LevelLayerItem)list_item.get_item();
			var icon = (Gtk.Image)list_item.get_child();
			icon.set_from_icon_name(layer_item.locked_icon);
		});
		var locked_column = new Gtk.ColumnViewColumn("Locked", locked_factory);
		locked_column.set_fixed_width(50);
		_column_view.append_column(locked_column);

		// Name column
		var name_factory = new Gtk.SignalListItemFactory();
		name_factory.setup.connect((item) => {
			var list_item = (Gtk.ListItem)item;
			var label = new Gtk.Label("");
			label.set_halign(Gtk.Align.START);
			list_item.set_child(label);
		});
		name_factory.bind.connect((item) => {
			var list_item = (Gtk.ListItem)item;
			var layer_item = (LevelLayerItem)list_item.get_item();
			var label = (Gtk.Label)list_item.get_child();
			label.set_text(layer_item.name);
		});
		var name_column = new Gtk.ColumnViewColumn("Name", name_factory);
		name_column.set_expand(true);
		_column_view.append_column(name_column);
	}

	// Populate both old and new models with layer data
	private void populate_models()
	{
		// Clear both models
		_layer_model.remove_all();
		
		// Add layers to new model
		_layer_model.append(new LevelLayerItem("layer-visible", "layer-locked", "Background"));
		_layer_model.append(new LevelLayerItem("layer-visible", "layer-locked", "Default"));
	}

	private void on_button_pressed(int n_press, double x, double y)
	{
		return;
	}

	private bool filter_tree(Gtk.TreeModel model, Gtk.TreeIter iter)
	{
		Value val;
		model.get_value(iter, 2, out val);

		_tree_view.expand_all();

		string layer_name = ((string)val).down();
		string filter_text = _filter_entry.text.down();
		if (filter_text == "" || layer_name.index_of(filter_text) > -1)
			return true;

		return false;
	}

	private void on_filter_entry_text_changed()
	{
		_tree_filter.refilter();
	}
}

} /* namespace Crown */
