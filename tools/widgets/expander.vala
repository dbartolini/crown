/*
 * Copyright (c) 2012-2026 Daniele Bartolini et al.
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

namespace Crown
{
/// Drop-in replacement (sort-of) for Gtk.Expander with
/// ability to set a custom widget alongside Expander's label.
public class Expander : Gtk.Box
{
	public bool _expanded = false;
	public Gtk.GestureClick _gesture_click;
	public Gtk.Box _header_box;
	public Gtk.Image _arrow_image;
	public Gtk.Widget _header_widget;
	public Gtk.Widget _child = null;

	public Expander(string? label = null)
	{
		Object(orientation: Gtk.Orientation.VERTICAL, spacing: 0);
		this.name = "expander2";

		_gesture_click = new Gtk.GestureClick();
		_gesture_click.pressed.connect(on_header_button_pressed);

		_header_box = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 6);
		_header_box.homogeneous = false;
		_header_box.add_controller(_gesture_click);

		_arrow_image = new Gtk.Image.from_icon_name("pan-end-symbolic");
		_header_box.append(_arrow_image);

		_header_widget = new Gtk.Label(label);
		_header_box.prepend(_header_widget);
		_header_box.add_css_class("header");

		this.append(_header_box);
	}

	public bool expanded
	{
		get
		{
			return _expanded;
		}
		set
		{
			if (_expanded == value)
				return;

			_expanded = value;

			if (_expanded)
				_arrow_image.set_from_icon_name("pan-down-symbolic");
			else
				_arrow_image.set_from_icon_name("pan-end-symbolic");

			if (_child != null) {
				if (_expanded)
					_child.show();
				else
					_child.hide();
			}
		}
	}

	public void on_header_button_pressed(int n_press, double x, double y)
	{
		uint button = _gesture_click.get_current_button();

		if (button == Gdk.BUTTON_PRIMARY)
			expanded = !expanded;
	}

	public string label
	{
		get
		{
			if (_header_widget is Gtk.Label)
				return ((Gtk.Label)_header_widget).label;
			else
				return "";
		}
		set
		{
			if (_header_widget is Gtk.Label) {
				((Gtk.Label)_header_widget).label = value;
			} else {
				_header_box.remove(_header_widget);
				_header_widget = new Gtk.Label(value);
				_header_box.append(_header_widget);
			}
		}
	}

	public Gtk.Widget custom_header
	{
		get
		{
			return _header_widget;
		}
		set
		{
			if (_header_widget != null)
				_header_box.remove(_header_widget);

			_header_widget = value;
			_header_box.append(_header_widget);
		}
	}

	public void add(Gtk.Widget widget)
	{
		assert(_child == null);

		_child = widget;
		base.append(_child);

		if (!_expanded)
			_child.hide();
	}

	public void remove(Gtk.Widget widget)
	{
		if (widget == _child)
			_child = null;

		base.remove(widget);
	}

	public override void map()
	{
		if (_child != null) {
			if (!_expanded)
				_child.hide();
		}

		base.map();
	}
}

} /* namespace Crown */
