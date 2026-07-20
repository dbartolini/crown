// gcc infdrag.c pointer-constraints-unstable-v1.c relative-pointer-unstable-v1.c -o infdrag `pkg-config --cflags --libs gtk+-3.0 wayland-client` && ./infdrag
#include <gtk/gtk.h>
#include <gdk/gdkwayland.h>
#include <wayland-client.h>
#include <wayland-util.h>
#include <stdio.h>
#include "pointer-constraints-unstable-v1.h"
#include "relative-pointer-unstable-v1.h"

static GtkWidget *label;
static gboolean dragging = FALSE;
static double pos = 0.0;
static gboolean is_wayland = FALSE;

/* Wayland globals */
static struct wl_display *wl_display = NULL;
static struct wl_registry *registry = NULL;
static struct wl_compositor *compositor = NULL;
static struct wl_seat *seat = NULL;
static struct wl_pointer *wl_pointer = NULL;
static struct wl_surface *wl_surface = NULL;
static struct zwp_pointer_constraints_v1 *pointer_constraints = NULL;
static struct zwp_locked_pointer_v1 *locked_pointer = NULL;
static struct zwp_relative_pointer_manager_v1 *relative_pointer_manager = NULL;
static struct zwp_relative_pointer_v1 *relative_pointer = NULL;

static void update(void) {
	char b[32];
	snprintf(b, sizeof(b), "%.0f", pos);
	gtk_label_set_text(GTK_LABEL(label), b);
}

/* Relative pointer listener */
static void relative_motion(void *data,
														struct zwp_relative_pointer_v1 *zrp,
														uint32_t utime_hi, uint32_t utime_lo,
														wl_fixed_t dx, wl_fixed_t dy,
														wl_fixed_t dx_unaccel, wl_fixed_t dy_unaccel) {
	if (dragging) {
		pos += wl_fixed_to_double(dx);
		update();
	}
}

static const struct zwp_relative_pointer_v1_listener rel_listener = {
	.relative_motion = relative_motion,
};

/* Seat */
static void seat_capabilities(void *data, struct wl_seat *s, uint32_t caps) {
	if (caps & WL_SEAT_CAPABILITY_POINTER)
		wl_pointer = wl_seat_get_pointer(s);
}

static const struct wl_seat_listener seat_listener = {
	.capabilities = seat_capabilities,
};

/* Registry */
static void registry_global(void *data, struct wl_registry *reg,
														uint32_t name, const char *interface, uint32_t ver) {
	if (!strcmp(interface, wl_compositor_interface.name))
		compositor = wl_registry_bind(reg, name, &wl_compositor_interface, 1);
	else if (!strcmp(interface, zwp_pointer_constraints_v1_interface.name))
		pointer_constraints = wl_registry_bind(reg, name, &zwp_pointer_constraints_v1_interface, 1);
	else if (!strcmp(interface, wl_seat_interface.name)) {
		seat = wl_registry_bind(reg, name, &wl_seat_interface, 1);
		wl_seat_add_listener(seat, &seat_listener, NULL);
	}
	else if (!strcmp(interface, zwp_relative_pointer_manager_v1_interface.name))
		relative_pointer_manager = wl_registry_bind(reg, name, &zwp_relative_pointer_manager_v1_interface, 1);
}

static const struct wl_registry_listener registry_listener = {
	.global = registry_global,
};

/* Lock / unlock */
static void lock_pointer(void) {
	if (!pointer_constraints || !wl_pointer || !wl_surface)
		return;
	locked_pointer = zwp_pointer_constraints_v1_lock_pointer(
			pointer_constraints, wl_surface, wl_pointer, NULL,
			ZWP_POINTER_CONSTRAINTS_V1_LIFETIME_PERSISTENT);
	if (locked_pointer && relative_pointer_manager && wl_pointer) {
		relative_pointer = zwp_relative_pointer_manager_v1_get_relative_pointer(
				relative_pointer_manager, wl_pointer);
		if (relative_pointer)
			zwp_relative_pointer_v1_add_listener(relative_pointer, &rel_listener, NULL);
	}
}

static void unlock_pointer(void) {
	if (locked_pointer) {
		zwp_locked_pointer_v1_destroy(locked_pointer);
		locked_pointer = NULL;
	}
	if (relative_pointer) {
		zwp_relative_pointer_v1_destroy(relative_pointer);
		relative_pointer = NULL;
	}
}

/* Event handlers */
static gboolean press(GtkWidget *w, GdkEventButton *e) {
	if (e->button != 1) return FALSE;
	dragging = TRUE;

	if (is_wayland) {
		lock_pointer();
		gtk_grab_add(w);
		return TRUE;
	}

	/* X11 fallback */
	GtkAllocation a;
	gtk_widget_get_allocation(w, &a);
	int cx = a.width / 2, cy = a.height / 2;
	gint rx, ry;
	gdk_window_get_root_coords(gtk_widget_get_window(w), cx, cy, &rx, &ry);
	GdkDevice *d = gdk_event_get_device((GdkEvent*)e);
	gdk_device_warp(d, gtk_widget_get_screen(w), rx, ry);
	gtk_grab_add(w);
	return TRUE;
}

static gboolean motion(GtkWidget *w, GdkEventMotion *e) {
	if (!dragging) return FALSE;
	if (is_wayland)
		return TRUE;   /* delta handled by relative pointer */

	/* X11 fallback */
	GtkAllocation a;
	gtk_widget_get_allocation(w, &a);
	int cx = a.width / 2;
	pos += e->x - cx;
	update();

	gint rx, ry;
	gdk_window_get_root_coords(gtk_widget_get_window(w), cx, a.height / 2, &rx, &ry);
	GdkDevice *d = gdk_event_get_device((GdkEvent*)e);
	gdk_device_warp(d, gtk_widget_get_screen(w), rx, ry);
	return TRUE;
}

static gboolean release(GtkWidget *w, GdkEventButton *e) {
	if (e->button == 1 && dragging) {
		dragging = FALSE;
		if (is_wayland)
			unlock_pointer();
		gtk_grab_remove(w);
		return TRUE;
	}
	return FALSE;
}

int main(int argc, char **argv) {
	gtk_init(&argc, &argv);

	GtkWidget *win = gtk_window_new(GTK_WINDOW_TOPLEVEL);
	gtk_window_set_title(GTK_WINDOW(win), "infdrag");
	gtk_window_set_default_size(GTK_WINDOW(win), 500, 200);

	label = gtk_label_new("0");
	gtk_label_set_xalign(GTK_LABEL(label), 0.5);
	gtk_label_set_yalign(GTK_LABEL(label), 0.5);

	GtkWidget *eb = gtk_event_box_new();
	gtk_event_box_set_visible_window(GTK_EVENT_BOX(eb), TRUE);
	gtk_widget_add_events(eb, GDK_BUTTON_PRESS_MASK | GDK_BUTTON_RELEASE_MASK | GDK_POINTER_MOTION_MASK);
	g_signal_connect(eb, "button-press-event", G_CALLBACK(press), NULL);
	g_signal_connect(eb, "motion-notify-event", G_CALLBACK(motion), NULL);
	g_signal_connect(eb, "button-release-event", G_CALLBACK(release), NULL);
	gtk_container_add(GTK_CONTAINER(eb), label);

	gtk_container_add(GTK_CONTAINER(win), eb);
	g_signal_connect(win, "destroy", G_CALLBACK(gtk_main_quit), NULL);

	gtk_widget_show_all(win);

	/* Wayland setup */
	GdkDisplay *disp = gtk_widget_get_display(win);
	if (GDK_IS_WAYLAND_DISPLAY(disp)) {
		is_wayland = TRUE;
		wl_display = gdk_wayland_display_get_wl_display(disp);
		registry = wl_display_get_registry(wl_display);
		wl_registry_add_listener(registry, &registry_listener, NULL);
		wl_display_roundtrip(wl_display);

		GdkWindow *eb_win = gtk_widget_get_window(eb);
		if (eb_win)
			wl_surface = gdk_wayland_window_get_wl_surface(eb_win);
	}

	gtk_main();
	return 0;
}
