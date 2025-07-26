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

	public override void measure(Gtk.Orientation orientation, int for_size, out int minimum, out int natural, out int minimum_baseline, out int natural_baseline)
	{
		minimum = 0;
		natural = 0;
		minimum_baseline = -1;
		natural_baseline = -1;

		if (this._child != null && this._child.get_visible()) {
			this._child.measure(orientation, for_size, out minimum, out natural, out minimum_baseline, out natural_baseline);
		}
	}
}

} /* namespace Crown */
