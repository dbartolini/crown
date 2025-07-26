/*
 * Copyright (c) 2012-2025 Daniele Bartolini et al.
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

namespace Crown
{
public class OpenResourceDialog : GLib.Object
{
	public Project _project;
	public string _resource_type;
	private Gtk.Window? _parent;

	public signal void safer_response(int response_id, string? path);

	public OpenResourceDialog(string? title, Gtk.Window? parent, string resource_type, Project p)
	{
		_parent = parent;
		_project = p;
		_resource_type = resource_type;
		
		// Show the open dialog immediately in GTK4 style
		show_open_dialog(title);
	}

	private async void show_open_dialog(string? title)
	{
		var file_dialog = new Gtk.FileDialog();
		
		if (title != null)
			file_dialog.set_title(title);
		
		// Set initial folder
		try {
			var initial_folder = GLib.File.new_for_path(_project.source_dir());
			file_dialog.set_initial_folder(initial_folder);
		} catch (GLib.Error e) {
			loge(e.message);
		}
		
		// Set up file filter
		var filter = new Gtk.FileFilter();
		filter.add_pattern("*.%s".printf(_resource_type));
		
		var filter_list = new GLib.ListStore(typeof(Gtk.FileFilter));
		filter_list.append(filter);
		file_dialog.set_filters(filter_list);
		file_dialog.set_default_filter(filter);
		
		try {
			var file = yield file_dialog.open(_parent, null);
			if (file != null) {
				string path = file.get_path();
				handle_file_selected(path);
			} else {
				safer_response(Gtk.ResponseType.CANCEL, null);
			}
		} catch (GLib.Error e) {
			// User cancelled or error occurred
			safer_response(Gtk.ResponseType.CANCEL, null);
		}
	}

	private void handle_file_selected(string path)
	{
		string final_path = path;
		
		// Ensure the path has the correct extension
		if (!final_path.has_suffix("." + _resource_type))
			final_path += "." + _resource_type;

		// If the path is outside the source dir, show a warning
		if (!_project.path_is_within_source_dir(final_path)) {
			show_warning_dialog("The file must be within the source directory.", () => {
				// Retry with dialog
				show_open_dialog.begin("Open Resource");
			});
			return;
		}

		safer_response(Gtk.ResponseType.ACCEPT, final_path);
	}

	private void show_warning_dialog(string message, owned SimpleCallback callback)
	{
		var dialog = new Gtk.AlertDialog(message);
		dialog.show(_parent);
		callback();
	}
	
	public delegate void SimpleCallback();
}

} /* namespace Crown */
