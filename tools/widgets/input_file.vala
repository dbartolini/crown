/*
 * Copyright (c) 2012-2025 Daniele Bartolini et al.
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

namespace Crown
{
public class InputFile : InputField, Gtk.Button
{
	public string? _path;
	public Gtk.FileChooserAction _action;
	public Gtk.Label _label;

	public void set_inconsistent(bool inconsistent)
	{
	}

	public bool is_inconsistent()
	{
		return false;
	}

	public GLib.Value union_value()
	{
		return this.value;
	}

	public void set_union_value(GLib.Value v)
	{
		this.value = (string)v;
	}

	public string? value
	{
		get
		{
			return _path;
		}
		set
		{
			if (value == null) {
				_path = null;
				_label.set_text("(None)");
			} else {
				GLib.File f = GLib.File.new_for_path(value);
				_path = f.get_path();
				_label.set_text(f.get_basename());
			}
		}
	}

	public InputFile(Gtk.FileChooserAction action = Gtk.FileChooserAction.OPEN)
	{
		_path = null;
		_action = action;

		_label = new Gtk.Label("(None)");
		_label.xalign = 0.0f;

		this.set_child(_label);
		this.clicked.connect(on_selector_clicked);
	}

	private async void on_selector_clicked()
	{
		string label = _action == Gtk.FileChooserAction.SELECT_FOLDER ? "Folder" : "File";
		
		var parent_window = (Gtk.Window)this.get_root();
		
		if (_action == Gtk.FileChooserAction.SELECT_FOLDER) {
			// Use folder dialog for folder selection
			var folder_dialog = new Gtk.FileDialog();
			folder_dialog.set_title("Select %s".printf(label));
			
			try {
				var folder = yield folder_dialog.select_folder(parent_window, null);
				if (folder != null) {
					this.value = folder.get_path();
				}
			} catch (GLib.Error e) {
				// User cancelled
			}
		} else {
			// Use file dialog for file selection
			var file_dialog = new Gtk.FileDialog();
			file_dialog.set_title("Select %s".printf(label));
			
			try {
				var file = yield file_dialog.open(parent_window, null);
				if (file != null) {
					this.value = file.get_path();
				}
			} catch (GLib.Error e) {
				// User cancelled
			}
		}
	}
}

} /* namespace Crown */
