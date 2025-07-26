/*
 * Copyright (c) 2012-2025 Daniele Bartolini et al.
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

namespace Crown
{
public class SaveResourceDialog : GLib.Object
{
	public Project _project;
	public string _resource_type;
	private Gtk.Window? _parent;

	public signal void safer_response(int response_id, string? path);

	public SaveResourceDialog(string? title, Gtk.Window? parent, string resource_type, string resource_name, Project p)
	{
		_parent = parent;
		_project = p;
		_resource_type = resource_type;
		
		// Show the save dialog immediately in GTK4 style
		show_save_dialog(title, resource_name);
	}

	private async void show_save_dialog(string? title, string resource_name)
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
		
		// Set initial name
		file_dialog.set_initial_name(resource_name + "." + _resource_type);
		
		// Set up file filter
		var filter = new Gtk.FileFilter();
		filter.add_pattern("*.%s".printf(_resource_type));
		
		var filter_list = new GLib.ListStore(typeof(Gtk.FileFilter));
		filter_list.append(filter);
		file_dialog.set_filters(filter_list);
		file_dialog.set_default_filter(filter);
		
		try {
			var file = yield file_dialog.save(_parent, null);
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
				// Retry with corrected path
				show_save_dialog.begin("Save Resource", GLib.Path.get_basename(final_path));
			});
			return;
		}

		// If the path already exists, ask if it should be overwritten
		if (GLib.FileUtils.test(final_path, FileTest.EXISTS)) {
			show_overwrite_dialog(final_path);
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

	private void show_overwrite_dialog(string path)
	{
		string message = "A file named `%s` already exists.\nOverwrite?".printf(GLib.Path.get_basename(path));
		var dialog = new Gtk.AlertDialog(message);
		dialog.set_buttons({"_No", "_Yes"});
		dialog.set_default_button(0);
		dialog.set_cancel_button(0);
		
		dialog.choose.begin(_parent, null, (obj, res) => {
			try {
				int response = dialog.choose.end(res);
				if (response == 1) { // "Yes" button
					safer_response(Gtk.ResponseType.ACCEPT, path);
				}
				// If "No" or cancelled, do nothing (keep dialog open effectively)
			} catch (GLib.Error e) {
				// Dialog was cancelled
			}
		});
	}
}

} /* namespace Crown */
