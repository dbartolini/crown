/*
 * Copyright (c) 2012-2026 Daniele Bartolini et al.
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

namespace Crown
{
// Drop-in replacement (sort-of) for HdyClamp from libhandy1.
public class Clamp : Gtk.Widget
{
	public Gtk.Widget? _child;

	public void set_child(Gtk.Widget? widget)
	{
		if (_child != null)
			_child.unparent();

		_child = widget;
		if (_child != null)
			_child.set_parent(this);

		this.queue_resize();
	}

	public override void measure(Gtk.Orientation orientation
		, int for_size
		, out int minimum
		, out int natural
		, out int minimum_baseline
		, out int natural_baseline
		)
	{
		minimum_baseline = -1;
		natural_baseline = -1;

		if (_child == null) {
			minimum = 0;
			natural = 0;
		} else {
			int child_min;
			int child_nat;
			int dummy;
			_child.measure(orientation, for_size, out child_min, out child_nat, out dummy, out dummy);
			if (orientation == Gtk.Orientation.HORIZONTAL) {
				minimum = child_min;
				natural = int.min(child_nat, 600);
			} else {
				minimum = child_min;
				natural = child_nat;
			}
		}
	}

	public override void size_allocate(int width, int height, int baseline)
	{
		if (_child != null) {
			int child_width = int.min(width, 600);
			int child_height = height;
			_child.allocate(child_width, child_height, baseline, null);
		}
	}
}

} /* namespace Crown */
