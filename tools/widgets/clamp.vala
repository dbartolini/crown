/*
 * Copyright (c) 2012-2025 Daniele Bartolini et al.
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

namespace Crown
{
// Drop-in replacement (sort-of) for HdyClamp from libhandy1.
public class Clamp : Gtk.Widget
{
	private Gtk.Widget _child;

	public Clamp()
	{
		base.set_can_focus(false);
		// GTK4: set_redraw_on_allocate was removed

		this._child = null;
	}

	public void set_child(Gtk.Widget? widget)
	{
		if (widget == null && this._child == widget) {
			widget.unparent();
			this._child = null;
			if (this.get_visible() && widget.get_visible())
				this.queue_resize();
		} else if (this._child == null) {
			widget.set_parent(this);
			this._child = widget;
		}
	}

	public override Gtk.SizeRequestMode get_request_mode()
	{
		if (this._child != null)
			return this._child.get_request_mode();
		else
			return Gtk.SizeRequestMode.HEIGHT_FOR_WIDTH;
	}

	public Gtk.Widget get_child()
	{
		return this._child;
	}

	public override void size_allocate(int width, int height, int baseline)
	{
		if (this._child == null || !this._child.is_visible())
			return;

		// GTK4: get_preferred_width was removed, use measure instead
		int child_min_width, child_nat_width, child_min_height, child_nat_height;
		this._child.measure(Gtk.Orientation.HORIZONTAL, -1, out child_min_width, out child_nat_width, null, null);
		this._child.measure(Gtk.Orientation.VERTICAL, -1, out child_min_height, out child_nat_height, null, null);

		Gtk.Allocation child_alloc = {};
		child_alloc.width = 600;
		child_alloc.height = height;
		child_alloc.x = (width - child_alloc.width) / 2;
		child_alloc.y = 0;

		this._child.size_allocate(width, height, baseline);
	}

	public new void get_preferred_size(out Gtk.Requisition minimum_size
		, out Gtk.Requisition natural_size
		)
	{
		Gtk.Requisition title_minimum_size = {0, 0};
		Gtk.Requisition title_natural_size = {0, 0};
		Gtk.Requisition child_minimum_size = {0, 0};
		Gtk.Requisition child_natural_size = {0, 0};

		if (this._child != null && this._child.get_visible())
			this._child.get_preferred_size(out child_minimum_size, out child_natural_size);

		minimum_size = {0, 0};
		natural_size = {0, 0};

		minimum_size.width = int.max(title_minimum_size.width, child_minimum_size.width);
		minimum_size.height = title_minimum_size.height + child_minimum_size.height;
		natural_size.width = int.max(title_natural_size.width, child_natural_size.width);
		natural_size.height = title_natural_size.height + child_natural_size.height;
	}
}

} /* namespace Crown */
