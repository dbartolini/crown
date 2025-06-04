/*
 * Copyright (c) 2012-2026 Daniele Bartolini et al.
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

namespace Crown
{
public class SaveResourceDialog : Gtk.Dialog
{
	public Gtk.FileChooserWidget _file_chooser;
	public Project _project;
	public string _resource_type;

	public signal void safer_response(int response_id, string? path);

	public SaveResourceDialog(string? title, Gtk.Window? parent, string resource_type, string resource_name, Project p)
	{
		if (title != null)
			this.title = title;

		if (parent != null)
			this.set_transient_for(parent);

		this.set_modal(true);
		this.add_button("Cancel", Gtk.ResponseType.CANCEL);
		this.add_button("Save", Gtk.ResponseType.ACCEPT);
		this.response.connect(on_response);

		_file_chooser = new Gtk.FileChooserWidget(Gtk.FileChooserAction.SAVE);
		try {
			_file_chooser.set_current_folder(GLib.File.new_for_path(p.source_dir()));
		} catch (GLib.Error e) {
			loge(e.message);
		}
		_file_chooser.set_current_name(resource_name);

		Gtk.FileFilter ff = new Gtk.FileFilter();
		ff.set_filter_name("%s (*.%s)".printf(resource_type, resource_type));
		ff.add_pattern("*.%s".printf(resource_type));
		_file_chooser.add_filter(ff);

		this.get_content_area().append(_file_chooser);

		_project = p;
		_resource_type = resource_type;
	}

	public void on_response(int response_id)
	{
		string? path = _file_chooser.get_file().get_path();

		if (response_id == Gtk.ResponseType.ACCEPT && path != null) {
			if (!path.has_suffix("." + _resource_type))
				path += "." + _resource_type;

			// If the path is outside the source dir, show a warning
			// and point the file chooser back to the source dir.
			if (!_project.path_is_within_source_dir(path)) {
				Gtk.MessageDialog md = new Gtk.MessageDialog(this
					, Gtk.DialogFlags.MODAL
					, Gtk.MessageType.WARNING
					, Gtk.ButtonsType.OK
					, "The file must be within the source directory."
					);
				md.set_default_response(Gtk.ResponseType.OK);
				md.response.connect(() => {
						try {
							_file_chooser.set_current_folder(GLib.File.new_for_path(_project.source_dir()));
						} catch (GLib.Error e) {
							loge(e.message);
						}
						md.destroy();
					});
				md.show();
				return;
			}

			// If the path already exits, ask if it should be overwritten.
			if (GLib.FileUtils.test(path, FileTest.EXISTS)) {
				Gtk.MessageDialog md = new Gtk.MessageDialog(this
					, Gtk.DialogFlags.MODAL
					, Gtk.MessageType.QUESTION
					, Gtk.ButtonsType.NONE
					, "A file named `%s` already exists.\nOverwrite?".printf(GLib.Path.get_basename(path))
					);

				Gtk.Widget btn;
				md.add_button("_No", Gtk.ResponseType.NO);
				btn = md.add_button("_Yes", Gtk.ResponseType.YES);
				btn.add_css_class("destructive-action");

				md.set_default_response(Gtk.ResponseType.NO);
				md.response.connect((response_id) => {
						if (response_id == Gtk.ResponseType.YES)
							this.safer_response(Gtk.ResponseType.ACCEPT, path);
						md.destroy();
					});
				md.show();
				return;
			}
		}

		this.safer_response(response_id, path);
	}
}

} /* namespace Crown */
