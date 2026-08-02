/*
 * Copyright (c) 2012-2026 Daniele Bartolini et al.
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

#include <glib.h>
#include <gdk/gdk.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>

#if defined(__linux__)
#include <errno.h>
#include <gdk/gdkx.h>
#include <gdk/gdkwayland.h>
#include <poll.h>
#include <sys/eventfd.h>
#include <unistd.h>
#include <wayland-client.h>
#include <X11/Xlib.h>
#include <X11/extensions/XInput2.h>
#include <X11/extensions/Xfixes.h>
#include "pointer-constraints-unstable-v1.h"
#include "relative-pointer-unstable-v1.h"
#elif defined(_WIN32)
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#endif /* if defined(__linux__) */

#define SAMPLE_INTERVAL_US 1000
#define SPIN_THRESHOLD_US 100
#define DIAGNOSTIC_INTERVAL_US (2 * G_USEC_PER_SEC)
#define DIAGNOSTIC_INITIAL_MOTIONS 10
#define SAMPLER_LOG(...) g_printerr("InputDouble sampler: " __VA_ARGS__)

#if defined(__linux__)
static void initialize_xlib_threads(void) __attribute__((constructor));

static void initialize_xlib_threads(void)
{
	if (!XInitThreads())
		SAMPLER_LOG("X11 thread initialization failed\n");
}

#endif

typedef enum CrownInputDoubleDragSamplerBackend
{
	CROWN_INPUT_DOUBLE_DRAG_SAMPLER_BACKEND_NONE,
	CROWN_INPUT_DOUBLE_DRAG_SAMPLER_BACKEND_X11,
	CROWN_INPUT_DOUBLE_DRAG_SAMPLER_BACKEND_WAYLAND,
	CROWN_INPUT_DOUBLE_DRAG_SAMPLER_BACKEND_WINDOWS,
} CrownInputDoubleDragSamplerBackend;

typedef struct CrownInputDoubleDragSampler
{
	GThread *thread;
	GMutex mutex;
	gint running;
	gint anchor_x;
	gint anchor_y;
	gdouble delta_x;
	gdouble delta_y;
	gint samples;
	gint released;
	gint64 diagnostic_start_time;
	gint diagnostic_samples;
	gint diagnostic_motions;
	gint diagnostic_total_motions;
	gdouble diagnostic_delta_x;
	gdouble diagnostic_delta_y;
	CrownInputDoubleDragSamplerBackend backend;
#if defined(__linux__)
	struct wl_display *wayland_display;
	struct wl_event_queue *wayland_queue;
	struct wl_registry *wayland_registry;
	struct zwp_pointer_constraints_v1 *pointer_constraints;
	struct zwp_locked_pointer_v1 *locked_pointer;
	struct zwp_relative_pointer_manager_v1 *relative_pointer_manager;
	struct zwp_relative_pointer_v1 *relative_pointer;
	Window x11_window;
	gint x11_wake_fd;
#elif defined(_WIN32)
	HANDLE windows_stop_event;
	GCond windows_setup_cond;
	gboolean windows_setup_complete;
	gboolean windows_setup_success;
	gint windows_absolute_x;
	gint windows_absolute_y;
	gboolean windows_absolute_initialized;
#endif /* if defined(__linux__) */
} CrownInputDoubleDragSampler;

static const char *backend_names[] = { "none", "x11", "wayland", "windows" };

static void diagnostic_log(CrownInputDoubleDragSampler *sampler)
{
	gint64 now = g_get_monotonic_time();
	gint64 elapsed = now - sampler->diagnostic_start_time;
	if (elapsed < DIAGNOSTIC_INTERVAL_US)
		return;

	gdouble frequency = (gdouble)G_USEC_PER_SEC * (gdouble)sampler->diagnostic_samples / (gdouble)elapsed;
	SAMPLER_LOG("stats backend=%s frequency=%.1fHz samples=%d motions=%d delta=(%.3f,%.3f)\n"
		, backend_names[sampler->backend]
		, frequency
		, sampler->diagnostic_samples
		, sampler->diagnostic_motions
		, sampler->diagnostic_delta_x
		, sampler->diagnostic_delta_y
		);
	sampler->diagnostic_start_time = now;
	sampler->diagnostic_samples = 0;
	sampler->diagnostic_motions = 0;
	sampler->diagnostic_delta_x = 0.0;
	sampler->diagnostic_delta_y = 0.0;
}

static void wait_until(CrownInputDoubleDragSampler *sampler, gint64 deadline)
{
	while (g_atomic_int_get(&sampler->running)) {
		gint64 remaining = deadline - g_get_monotonic_time();
		if (remaining <= 0)
			return;
		if (remaining > SPIN_THRESHOLD_US)
			g_usleep((gulong)(remaining - SPIN_THRESHOLD_US));
	}
}

static void store_delta(CrownInputDoubleDragSampler *sampler, gdouble delta_x, gdouble delta_y)
{
	g_mutex_lock(&sampler->mutex);
	sampler->delta_x += delta_x;
	sampler->delta_y += delta_y;
	g_mutex_unlock(&sampler->mutex);

	sampler->diagnostic_motions += 1;
	sampler->diagnostic_total_motions += 1;
	sampler->diagnostic_delta_x += delta_x;
	sampler->diagnostic_delta_y += delta_y;
	if (sampler->diagnostic_total_motions <= DIAGNOSTIC_INITIAL_MOTIONS) {
		SAMPLER_LOG("raw-motion backend=%s event=%d delta=(%.3f,%.3f)\n"
			, backend_names[sampler->backend]
			, sampler->diagnostic_total_motions
			, delta_x
			, delta_y
			);
	}
}

static void store_sample(CrownInputDoubleDragSampler *sampler)
{
	g_mutex_lock(&sampler->mutex);
	sampler->samples += 1;
	g_mutex_unlock(&sampler->mutex);
	sampler->diagnostic_samples += 1;
	diagnostic_log(sampler);
}

#if defined(__linux__)
static void registry_global(void *data, struct wl_registry *registry, uint32_t name, const char *interface, uint32_t version)
{
	CrownInputDoubleDragSampler *sampler = data;
	if (strcmp(interface, zwp_pointer_constraints_v1_interface.name) == 0) {
		SAMPLER_LOG("Wayland global pointer-constraints version=%u\n", version);
		sampler->pointer_constraints = wl_registry_bind(registry
			, name
			, &zwp_pointer_constraints_v1_interface
			, MIN(version, 1u)
			);
	} else if (strcmp(interface, zwp_relative_pointer_manager_v1_interface.name) == 0) {
		SAMPLER_LOG("Wayland global relative-pointer-manager version=%u\n", version);
		sampler->relative_pointer_manager = wl_registry_bind(registry
			, name
			, &zwp_relative_pointer_manager_v1_interface
			, MIN(version, 1u)
			);
	}
}

static void registry_global_remove(void *data, struct wl_registry *registry, uint32_t name)
{
	(void)data;
	(void)registry;
	(void)name;
}

static const struct wl_registry_listener registry_listener =
{
	.global = registry_global,
	.global_remove = registry_global_remove,
};

static void relative_motion(void *data
	, struct zwp_relative_pointer_v1 *relative_pointer
	, uint32_t time_hi
	, uint32_t time_lo
	, wl_fixed_t dx
	, wl_fixed_t dy
	, wl_fixed_t dx_unaccelerated
	, wl_fixed_t dy_unaccelerated
	)
{
	(void)relative_pointer;
	(void)time_hi;
	(void)time_lo;
	(void)dx_unaccelerated;
	(void)dy_unaccelerated;
	store_delta(data, wl_fixed_to_double(dx), wl_fixed_to_double(dy));
}

static const struct zwp_relative_pointer_v1_listener relative_pointer_listener =
{
	.relative_motion = relative_motion,
};

static void pointer_locked(void *data, struct zwp_locked_pointer_v1 *locked_pointer)
{
	(void)data;
	(void)locked_pointer;
	SAMPLER_LOG("Wayland pointer lock activated\n");
}

static void pointer_unlocked(void *data, struct zwp_locked_pointer_v1 *locked_pointer)
{
	(void)data;
	(void)locked_pointer;
	SAMPLER_LOG("Wayland pointer lock deactivated\n");
}

static const struct zwp_locked_pointer_v1_listener locked_pointer_listener =
{
	.locked = pointer_locked,
	.unlocked = pointer_unlocked,
};

static gboolean setup_wayland(CrownInputDoubleDragSampler *sampler, GdkDisplay *display, GdkWindow *window, GdkDevice *device)
{
	sampler->wayland_display = gdk_wayland_display_get_wl_display(display);
	struct wl_surface *surface = gdk_wayland_window_get_wl_surface(window);
	struct wl_pointer *pointer = gdk_wayland_device_get_wl_pointer(device);
	SAMPLER_LOG("Wayland setup display=%p surface=%p pointer=%p\n"
		, (void *)sampler->wayland_display
		, (void *)surface
		, (void *)pointer
		);
	if (sampler->wayland_display == NULL || surface == NULL || pointer == NULL) {
		SAMPLER_LOG("Wayland setup failed: missing display, surface, or pointer\n");
		return FALSE;
	}

	sampler->wayland_queue = wl_display_create_queue(sampler->wayland_display);
	sampler->wayland_registry = wl_display_get_registry(sampler->wayland_display);
	wl_proxy_set_queue((struct wl_proxy *)sampler->wayland_registry, sampler->wayland_queue);
	wl_registry_add_listener(sampler->wayland_registry, &registry_listener, sampler);
	if (wl_display_roundtrip_queue(sampler->wayland_display, sampler->wayland_queue) < 0) {
		SAMPLER_LOG("Wayland setup failed: registry roundtrip\n");
		return FALSE;
	}
	if (sampler->pointer_constraints == NULL || sampler->relative_pointer_manager == NULL) {
		SAMPLER_LOG("Wayland setup failed: constraints=%p relative-manager=%p\n"
			, (void *)sampler->pointer_constraints
			, (void *)sampler->relative_pointer_manager
			);
		return FALSE;
	}

	sampler->locked_pointer = zwp_pointer_constraints_v1_lock_pointer(sampler->pointer_constraints
		, surface
		, pointer
		, NULL
		, ZWP_POINTER_CONSTRAINTS_V1_LIFETIME_PERSISTENT
		);
	sampler->relative_pointer = zwp_relative_pointer_manager_v1_get_relative_pointer(sampler->relative_pointer_manager, pointer);
	if (sampler->locked_pointer == NULL || sampler->relative_pointer == NULL) {
		SAMPLER_LOG("Wayland setup failed: locked-pointer=%p relative-pointer=%p\n"
			, (void *)sampler->locked_pointer
			, (void *)sampler->relative_pointer
			);
		return FALSE;
	}

	wl_proxy_set_queue((struct wl_proxy *)sampler->locked_pointer, sampler->wayland_queue);
	wl_proxy_set_queue((struct wl_proxy *)sampler->relative_pointer, sampler->wayland_queue);
	zwp_locked_pointer_v1_add_listener(sampler->locked_pointer, &locked_pointer_listener, sampler);
	zwp_relative_pointer_v1_add_listener(sampler->relative_pointer, &relative_pointer_listener, sampler);
	wl_display_flush(sampler->wayland_display);
	SAMPLER_LOG("Wayland setup complete locked-pointer=%p relative-pointer=%p\n"
		, (void *)sampler->locked_pointer
		, (void *)sampler->relative_pointer
		);
	return TRUE;
}

static void destroy_wayland(CrownInputDoubleDragSampler *sampler)
{
	if (sampler->relative_pointer != NULL)
		zwp_relative_pointer_v1_destroy(sampler->relative_pointer);
	if (sampler->locked_pointer != NULL)
		zwp_locked_pointer_v1_destroy(sampler->locked_pointer);
	if (sampler->relative_pointer_manager != NULL)
		zwp_relative_pointer_manager_v1_destroy(sampler->relative_pointer_manager);
	if (sampler->pointer_constraints != NULL)
		zwp_pointer_constraints_v1_destroy(sampler->pointer_constraints);
	if (sampler->wayland_registry != NULL)
		wl_registry_destroy(sampler->wayland_registry);
	if (sampler->wayland_display != NULL)
		wl_display_flush(sampler->wayland_display);
	if (sampler->wayland_queue != NULL)
		wl_event_queue_destroy(sampler->wayland_queue);
}

static gpointer sample_pointer_wayland(gpointer data)
{
	CrownInputDoubleDragSampler *sampler = data;
	const struct timespec no_wait = { 0, 0 };
	SAMPLER_LOG("worker started backend=wayland\n");
	gint64 next_sample_time = g_get_monotonic_time();
	while (g_atomic_int_get(&sampler->running)) {
		wait_until(sampler, next_sample_time);
		if (!g_atomic_int_get(&sampler->running))
			break;

		if (wl_display_dispatch_queue_timeout(sampler->wayland_display, sampler->wayland_queue, &no_wait) < 0) {
			SAMPLER_LOG("Wayland dispatch failed\n");
			break;
		}
		store_sample(sampler);

		next_sample_time += SAMPLE_INTERVAL_US;
		gint64 now = g_get_monotonic_time();
		if (now - next_sample_time >= SAMPLE_INTERVAL_US)
			next_sample_time = now + SAMPLE_INTERVAL_US;
	}

	SAMPLER_LOG("worker stopped backend=wayland\n");
	return NULL;
}

typedef struct CrownInputDoubleX11Grab
{
	Window window;
	Window root;
	gint anchor_x;
	gint anchor_y;
	gboolean cursor_hidden;
	gboolean active;
} CrownInputDoubleX11Grab;

/*
 * Keep this Xwayland path as confinement + XFixes cursor hiding + XI2 raw
 * motion. The combination activates Xwayland's relative-pointer device;
 * confinement alone suppresses the motion stream.
 */
static gboolean warp_x11_pointer_to_anchor(Display *display, CrownInputDoubleX11Grab *grab)
{
	int window_x;
	int window_y;
	Window child;
	if (!XTranslateCoordinates(display
		, grab->root
		, grab->window
		, grab->anchor_x
		, grab->anchor_y
		, &window_x
		, &window_y
		, &child
		)) {
		SAMPLER_LOG("X11 anchor translation failed\n");
		return FALSE;
	}

	XWarpPointer(display
		, None
		, grab->window
		, 0
		, 0
		, 0
		, 0
		, window_x
		, window_y
		);
	XSync(display, False);
	return TRUE;
}

static void destroy_x11_pointer_grab(Display *display, CrownInputDoubleX11Grab *grab)
{
	if (grab->active) {
		/* Commit the original position hint before revealing the pointer. */
		if (warp_x11_pointer_to_anchor(display, grab))
			SAMPLER_LOG("X11 pointer restored to anchor=(%d,%d)\n", grab->anchor_x, grab->anchor_y);

		/* Ungrab while hidden or Xwayland may discard the position hint. */
		XUngrabPointer(display, CurrentTime);
		XSync(display, False);
		grab->active = FALSE;
	}
	if (grab->cursor_hidden) {
		XFixesShowCursor(display, grab->window);
		XSync(display, False);
		grab->cursor_hidden = FALSE;
	}
}

static gboolean create_x11_pointer_grab(Display *display
	, Window root
	, Window window
	, gint anchor_x
	, gint anchor_y
	, CrownInputDoubleX11Grab *grab
	)
{
	grab->window = window;
	grab->root = root;
	grab->anchor_x = anchor_x;
	grab->anchor_y = anchor_y;
	int status = XGrabPointer(display
		, window
		, False
		, ButtonReleaseMask
		, GrabModeAsync
		, GrabModeAsync
		, window
		, None
		, CurrentTime
		);
	if (status != GrabSuccess) {
		SAMPLER_LOG("X11 setup failed: pointer grab status=%d\n", status);
		destroy_x11_pointer_grab(display, grab);
		return FALSE;
	}
	grab->active = TRUE;

	XFixesHideCursor(display, window);
	XSync(display, False);
	grab->cursor_hidden = TRUE;

	/*
	 * Xwayland converts hidden-cursor confinement into a Wayland pointer lock
	 * backed by its relative-pointer device. A single warp establishes the
	 * logical anchor; repeated warps would be reported as synthetic raw motion.
	 */
	if (!warp_x11_pointer_to_anchor(display, grab)) {
		destroy_x11_pointer_grab(display, grab);
		return FALSE;
	}
	SAMPLER_LOG("X11 pointer confined and XFixes-hidden window=0x%lx anchor=(%d,%d)\n"
		, window
		, anchor_x
		, anchor_y
		);
	return TRUE;
}

static gpointer sample_pointer_x11(gpointer data)
{
	CrownInputDoubleDragSampler *sampler = data;
	Display *display = XOpenDisplay(NULL);
	if (display == NULL) {
		SAMPLER_LOG("X11 connection failed\n");
		return NULL;
	}
	int screen_number = DefaultScreen(display);
	Window root = RootWindow(display, screen_number);
	SAMPLER_LOG("worker started backend=x11 mode=event-driven screen=%d\n", screen_number);

	int xinput_opcode;
	int xinput_event;
	int xinput_error;
	if (!XQueryExtension(display, "XInputExtension", &xinput_opcode, &xinput_event, &xinput_error)) {
		SAMPLER_LOG("X11 setup failed: XInput extension unavailable\n");
		XCloseDisplay(display);
		return NULL;
	}

	int xinput_major = 2;
	int xinput_minor = 1;
	int status = XIQueryVersion(display, &xinput_major, &xinput_minor);
	if (status != Success
		|| xinput_major < 2
		|| (xinput_major == 2 && xinput_minor < 1)
		) {
		SAMPLER_LOG("X11 setup failed: XInput 2.1 unavailable status=%d\n", status);
		XCloseDisplay(display);
		return NULL;
	}
	SAMPLER_LOG("XInput version=%d.%d opcode=%d\n"
		, xinput_major
		, xinput_minor
		, xinput_opcode
		);

	int xfixes_event;
	int xfixes_error;
	int xfixes_major = 4;
	int xfixes_minor = 0;
	if (!XFixesQueryExtension(display, &xfixes_event, &xfixes_error)
		|| !XFixesQueryVersion(display, &xfixes_major, &xfixes_minor)
		|| xfixes_major < 4
		) {
		SAMPLER_LOG("X11 setup failed: XFixes 4 unavailable\n");
		XCloseDisplay(display);
		return NULL;
	}
	SAMPLER_LOG("XFixes version=%d.%d\n"
		, xfixes_major
		, xfixes_minor
		);

	unsigned char mask[XIMaskLen(XI_RawMotion)] = { 0 };
	XISetMask(mask, XI_RawMotion);
	XISetMask(mask, XI_RawButtonRelease);
	XIEventMask event_mask =
	{
		.deviceid = XIAllMasterDevices,
		.mask_len = sizeof(mask),
		.mask = mask,
	};
	if (XISelectEvents(display, root, &event_mask, 1) != Success) {
		SAMPLER_LOG("X11 setup failed: select raw motion\n");
		XCloseDisplay(display);
		return NULL;
	}
	XSync(display, False);

	CrownInputDoubleX11Grab pointer_grab = { 0 };
	if (!create_x11_pointer_grab(display
		, root
		, sampler->x11_window
		, sampler->anchor_x
		, sampler->anchor_y
		, &pointer_grab
		)) {
		XCloseDisplay(display);
		return NULL;
	}

	SAMPLER_LOG("X11 raw motion selected on root=0x%lx\n", root);

	while (g_atomic_int_get(&sampler->running)) {
		while (XPending(display) > 0) {
			XEvent event;
			XNextEvent(display, &event);
			if (event.type == ButtonRelease) {
				g_atomic_int_set(&sampler->released, TRUE);
				g_atomic_int_set(&sampler->running, FALSE);
				SAMPLER_LOG("X11 button released detail=%u\n", event.xbutton.button);
			} else if (event.type == GenericEvent
				&& event.xcookie.extension == xinput_opcode
				&& XGetEventData(display, &event.xcookie)
				) {
				XIRawEvent *raw = event.xcookie.data;
				if (event.xcookie.evtype == XI_RawButtonRelease) {
					g_atomic_int_set(&sampler->released, TRUE);
					g_atomic_int_set(&sampler->running, FALSE);
					SAMPLER_LOG("XInput raw button released detail=%u\n", raw->detail);
				} else if (event.xcookie.evtype == XI_RawMotion) {
					int value_index = 0;
					gdouble delta_x = 0.0;
					gdouble delta_y = 0.0;
					for (int axis = 0; axis < raw->valuators.mask_len * 8; ++axis) {
						if (!XIMaskIsSet(raw->valuators.mask, axis))
							continue;
						gdouble value = raw->valuators.values[value_index];
						if (axis == 0)
							delta_x = value;
						else if (axis == 1)
							delta_y = value;
						value_index += 1;
					}
					if (sampler->diagnostic_total_motions < DIAGNOSTIC_INITIAL_MOTIONS) {
						SAMPLER_LOG("XInput motion device=%u source=%u flags=0x%x\n"
							, raw->deviceid
							, raw->sourceid
							, raw->flags
							);
					}
					store_delta(sampler, delta_x, delta_y);
					store_sample(sampler);
				}
				XFreeEventData(display, &event.xcookie);
			}
		}

		if (!g_atomic_int_get(&sampler->running))
			break;

		struct pollfd descriptors[] =
		{
			{ .fd = ConnectionNumber(display), .events = POLLIN },
			{ .fd = sampler->x11_wake_fd, .events = POLLIN },
		};
		int poll_result;
		do {
			poll_result = poll(descriptors, G_N_ELEMENTS(descriptors), -1);
		} while (poll_result < 0 && errno == EINTR);
		if (poll_result < 0) {
			SAMPLER_LOG("X11 poll failed error=%d\n", errno);
			break;
		}
		if ((descriptors[1].revents & POLLIN) != 0) {
			uint64_t wake_value;
			while (read(sampler->x11_wake_fd, &wake_value, sizeof(wake_value)) < 0 && errno == EINTR) {
			}
		}
		if ((descriptors[0].revents & (POLLERR | POLLHUP | POLLNVAL)) != 0) {
			SAMPLER_LOG("X11 socket poll error=0x%x\n", descriptors[0].revents);
			break;
		}
	}

	destroy_x11_pointer_grab(display, &pointer_grab);
	XCloseDisplay(display);
	SAMPLER_LOG("worker stopped backend=x11\n");
	return NULL;
}

#elif defined(_WIN32)
static const wchar_t WINDOWS_RAW_INPUT_CLASS_NAME[] = L"CrownInputDoubleRawInput";

/*
 * Keep Windows event-driven: consume Raw Input deltas while ClipCursor keeps the
 * visible pointer at the anchor. Do not replace this with cursor-position
 * polling or repeated SetCursorPos calls.
 */

static void complete_windows_setup(CrownInputDoubleDragSampler *sampler, gboolean success)
{
	g_mutex_lock(&sampler->mutex);
	sampler->windows_setup_success = success;
	sampler->windows_setup_complete = TRUE;
	g_cond_signal(&sampler->windows_setup_cond);
	g_mutex_unlock(&sampler->mutex);
}

static gboolean register_windows_raw_input(HWND target)
{
	RAWINPUTDEVICE mouse =
	{
		.usUsagePage = 0x01,
		.usUsage = 0x02,
		.dwFlags = target != NULL ? RIDEV_INPUTSINK : RIDEV_REMOVE,
		.hwndTarget = target,
	};
	if (RegisterRawInputDevices(&mouse, 1, sizeof(mouse)))
		return TRUE;

	SAMPLER_LOG("Windows RegisterRawInputDevices failed error=%lu\n", GetLastError());
	return FALSE;
}

static void process_windows_raw_mouse(CrownInputDoubleDragSampler *sampler, const RAWMOUSE *mouse)
{
	gint delta_x = 0;
	gint delta_y = 0;
	if ((mouse->usFlags & MOUSE_MOVE_ABSOLUTE) != 0) {
		gboolean virtual_desktop = (mouse->usFlags & MOUSE_VIRTUAL_DESKTOP) != 0;
		gint screen_x = virtual_desktop ? GetSystemMetrics(SM_XVIRTUALSCREEN) : 0;
		gint screen_y = virtual_desktop ? GetSystemMetrics(SM_YVIRTUALSCREEN) : 0;
		gint screen_width = virtual_desktop ? GetSystemMetrics(SM_CXVIRTUALSCREEN) : GetSystemMetrics(SM_CXSCREEN);
		gint screen_height = virtual_desktop ? GetSystemMetrics(SM_CYVIRTUALSCREEN) : GetSystemMetrics(SM_CYSCREEN);
		gint absolute_x = screen_x + MulDiv(mouse->lLastX, MAX(screen_width - 1, 1), 65535);
		gint absolute_y = screen_y + MulDiv(mouse->lLastY, MAX(screen_height - 1, 1), 65535);
		if (sampler->windows_absolute_initialized) {
			delta_x = absolute_x - sampler->windows_absolute_x;
			delta_y = absolute_y - sampler->windows_absolute_y;
		}
		sampler->windows_absolute_x = absolute_x;
		sampler->windows_absolute_y = absolute_y;
		sampler->windows_absolute_initialized = TRUE;
	} else {
		delta_x = mouse->lLastX;
		delta_y = mouse->lLastY;
		sampler->windows_absolute_initialized = FALSE;
	}

	if (delta_x != 0 || delta_y != 0) {
		store_delta(sampler, delta_x, delta_y);
		store_sample(sampler);
	}

	if ((mouse->usButtonFlags & RI_MOUSE_LEFT_BUTTON_UP) != 0) {
		g_atomic_int_set(&sampler->released, TRUE);
		g_atomic_int_set(&sampler->running, FALSE);
		SetEvent(sampler->windows_stop_event);
		SAMPLER_LOG("Windows raw button released\n");
	}
}

static LRESULT CALLBACK windows_raw_input_window_proc(HWND window, UINT message, WPARAM wparam, LPARAM lparam)
{
	if (message == WM_NCCREATE) {
		CREATESTRUCTW *create = (CREATESTRUCTW *)lparam;
		SetWindowLongPtrW(window, GWLP_USERDATA, (LONG_PTR)create->lpCreateParams);
		return TRUE;
	}

	CrownInputDoubleDragSampler *sampler = (CrownInputDoubleDragSampler *)GetWindowLongPtrW(window, GWLP_USERDATA);
	if (message == WM_INPUT && sampler != NULL) {
		RAWINPUT input;
		UINT input_size = sizeof(input);
		UINT result = GetRawInputData((HRAWINPUT)lparam
			, RID_INPUT
			, &input
			, &input_size
			, sizeof(RAWINPUTHEADER)
			);
		if (result == (UINT)-1) {
			SAMPLER_LOG("Windows GetRawInputData failed error=%lu\n", GetLastError());
		} else if (input.header.dwType == RIM_TYPEMOUSE) {
			process_windows_raw_mouse(sampler, &input.data.mouse);
		}
	}

	return DefWindowProcW(window, message, wparam, lparam);
}

static HWND create_windows_raw_input_window(CrownInputDoubleDragSampler *sampler)
{
	HINSTANCE instance = GetModuleHandleW(NULL);
	WNDCLASSEXW window_class =
	{
		.cbSize = sizeof(window_class),
		.lpfnWndProc = windows_raw_input_window_proc,
		.hInstance = instance,
		.lpszClassName = WINDOWS_RAW_INPUT_CLASS_NAME,
	};
	if (RegisterClassExW(&window_class) == 0 && GetLastError() != ERROR_CLASS_ALREADY_EXISTS) {
		SAMPLER_LOG("Windows RegisterClassEx failed error=%lu\n", GetLastError());
		return NULL;
	}

	HWND window = CreateWindowExW(0
		, WINDOWS_RAW_INPUT_CLASS_NAME
		, L""
		, 0
		, 0
		, 0
		, 0
		, 0
		, HWND_MESSAGE
		, NULL
		, instance
		, sampler
		);
	if (window == NULL)
		SAMPLER_LOG("Windows CreateWindowEx failed error=%lu\n", GetLastError());
	return window;
}

static void drain_windows_raw_input_messages(void)
{
	MSG message;
	while (PeekMessageW(&message, NULL, WM_INPUT, WM_INPUT, PM_REMOVE))
		DispatchMessageW(&message);
}

static gpointer sample_pointer_windows(gpointer data)
{
	CrownInputDoubleDragSampler *sampler = data;
	SAMPLER_LOG("worker started backend=windows mode=raw-input\n");
	HWND window = create_windows_raw_input_window(sampler);
	gboolean registered = FALSE;
	if (window == NULL)
		goto setup_failed;

	if (!register_windows_raw_input(window))
		goto setup_failed;
	registered = TRUE;

	RECT clip =
	{
		.left = sampler->anchor_x,
		.top = sampler->anchor_y,
		.right = sampler->anchor_x + 1,
		.bottom = sampler->anchor_y + 1,
	};
	if (!ClipCursor(&clip)) {
		SAMPLER_LOG("Windows ClipCursor failed error=%lu\n", GetLastError());
		goto setup_failed;
	}
	SAMPLER_LOG("Windows raw input registered and cursor clipped anchor=(%d,%d)\n", sampler->anchor_x, sampler->anchor_y);
	complete_windows_setup(sampler, TRUE);

	while (g_atomic_int_get(&sampler->running)) {
		DWORD wait_result = MsgWaitForMultipleObjects(1
			, &sampler->windows_stop_event
			, FALSE
			, INFINITE
			, QS_RAWINPUT
			);
		if (wait_result == WAIT_OBJECT_0)
			break;
		if (wait_result == WAIT_FAILED) {
			SAMPLER_LOG("Windows message wait failed error=%lu\n", GetLastError());
			break;
		}

		drain_windows_raw_input_messages();
	}

	/* GTK may observe the release just before this worker does. */
	drain_windows_raw_input_messages();

	/* Preserve the release invariant: restore, unconfine, then reveal in GTK. */
	if (!SetCursorPos(sampler->anchor_x, sampler->anchor_y))
		SAMPLER_LOG("Windows cursor restore failed error=%lu\n", GetLastError());
	else
		SAMPLER_LOG("Windows pointer restored to anchor=(%d,%d)\n", sampler->anchor_x, sampler->anchor_y);
	if (!ClipCursor(NULL))
		SAMPLER_LOG("Windows ClipCursor release failed error=%lu\n", GetLastError());

	register_windows_raw_input(NULL);
	DestroyWindow(window);
	SAMPLER_LOG("worker stopped backend=windows\n");
	return NULL;

setup_failed:
	if (registered)
		register_windows_raw_input(NULL);
	if (window != NULL)
		DestroyWindow(window);
	g_atomic_int_set(&sampler->running, FALSE);
	complete_windows_setup(sampler, FALSE);
	return NULL;
}

#endif /* if defined(__linux__) */

static gpointer sample_pointer(gpointer data)
{
	CrownInputDoubleDragSampler *sampler = data;
#if defined(__linux__)
	return sampler->backend == CROWN_INPUT_DOUBLE_DRAG_SAMPLER_BACKEND_WAYLAND
		? sample_pointer_wayland(data)
		: sample_pointer_x11(data);
#elif defined(_WIN32)
	return sample_pointer_windows(data);
#endif
	return NULL;
}

void *crown_input_double_drag_sampler_start(GdkDisplay *display, GdkWindow *window, GdkDevice *device, gint anchor_x, gint anchor_y)
{
	CrownInputDoubleDragSampler *sampler = g_new0(CrownInputDoubleDragSampler, 1);
	g_mutex_init(&sampler->mutex);
#if defined(__linux__)
	sampler->x11_wake_fd = -1;
#endif
	g_atomic_int_set(&sampler->running, TRUE);
	sampler->anchor_x = anchor_x;
	sampler->anchor_y = anchor_y;
	sampler->diagnostic_start_time = g_get_monotonic_time();
#if defined(__linux__)
	if (GDK_IS_WAYLAND_DISPLAY(display)) {
		sampler->backend = CROWN_INPUT_DOUBLE_DRAG_SAMPLER_BACKEND_WAYLAND;
		SAMPLER_LOG("start backend=wayland anchor=(%d,%d) display-type=%s\n"
			, anchor_x
			, anchor_y
			, G_OBJECT_TYPE_NAME(display)
			);
		if (!setup_wayland(sampler, display, window, device)) {
			destroy_wayland(sampler);
			g_mutex_clear(&sampler->mutex);
			g_free(sampler);
			return NULL;
		}
	} else {
		sampler->backend = CROWN_INPUT_DOUBLE_DRAG_SAMPLER_BACKEND_X11;
		sampler->x11_wake_fd = eventfd(0, EFD_CLOEXEC | EFD_NONBLOCK);
		if (sampler->x11_wake_fd < 0) {
			SAMPLER_LOG("X11 setup failed: eventfd error=%d\n", errno);
			g_mutex_clear(&sampler->mutex);
			g_free(sampler);
			return NULL;
		}
		GdkWindow *toplevel = gdk_window_get_toplevel(window);
		sampler->x11_window = gdk_x11_window_get_xid(toplevel);
		SAMPLER_LOG("start backend=x11 anchor=(%d,%d) display-type=%s\n"
			, anchor_x
			, anchor_y
			, G_OBJECT_TYPE_NAME(display)
			);
		SAMPLER_LOG("X11 toplevel window=0x%lx\n", sampler->x11_window);
		GdkSeat *seat = gdk_device_get_seat(device);
		if (seat != NULL) {
			gdk_seat_ungrab(seat);
			gdk_display_sync(display);
			SAMPLER_LOG("released GTK pointer grab for XInput worker\n");
		}
	}
#elif defined(_WIN32)
	(void)display;
	(void)window;
	(void)device;
	sampler->backend = CROWN_INPUT_DOUBLE_DRAG_SAMPLER_BACKEND_WINDOWS;
	g_cond_init(&sampler->windows_setup_cond);
	sampler->windows_stop_event = CreateEventW(NULL, TRUE, FALSE, NULL);
	if (sampler->windows_stop_event == NULL) {
		SAMPLER_LOG("Windows setup failed: stop event error=%lu\n", GetLastError());
		g_cond_clear(&sampler->windows_setup_cond);
		g_mutex_clear(&sampler->mutex);
		g_free(sampler);
		return NULL;
	}
	SAMPLER_LOG("start backend=windows anchor=(%d,%d)\n", anchor_x, anchor_y);
#else
	(void)display;
	(void)window;
	(void)device;
#endif /* if defined(__linux__) */
	sampler->thread = g_thread_new("input-double-drag", sample_pointer, sampler);
#if defined(_WIN32)
	g_mutex_lock(&sampler->mutex);
	while (!sampler->windows_setup_complete)
		g_cond_wait(&sampler->windows_setup_cond, &sampler->mutex);
	gboolean setup_success = sampler->windows_setup_success;
	g_mutex_unlock(&sampler->mutex);
	if (!setup_success) {
		g_thread_join(sampler->thread);
		CloseHandle(sampler->windows_stop_event);
		g_cond_clear(&sampler->windows_setup_cond);
		g_mutex_clear(&sampler->mutex);
		g_free(sampler);
		return NULL;
	}
#endif
	return sampler;
}

void crown_input_double_drag_sampler_drain(void *data, gdouble *delta_x, gdouble *delta_y, gint *samples)
{
	CrownInputDoubleDragSampler *sampler = data;
	g_mutex_lock(&sampler->mutex);
	*delta_x = sampler->delta_x;
	*delta_y = sampler->delta_y;
	*samples = sampler->samples;
	sampler->delta_x = 0;
	sampler->delta_y = 0;
	sampler->samples = 0;
	g_mutex_unlock(&sampler->mutex);
}

gboolean crown_input_double_drag_sampler_released(void *data)
{
	CrownInputDoubleDragSampler *sampler = data;
	return g_atomic_int_get(&sampler->released);
}

void crown_input_double_drag_sampler_stop(void *data, gdouble *delta_x, gdouble *delta_y, gint *samples)
{
	CrownInputDoubleDragSampler *sampler = data;
	SAMPLER_LOG("stop requested backend=%s\n", backend_names[sampler->backend]);
	g_atomic_int_set(&sampler->running, FALSE);
#if defined(__linux__)
	if (sampler->x11_wake_fd >= 0) {
		uint64_t wake_value = 1;
		while (write(sampler->x11_wake_fd, &wake_value, sizeof(wake_value)) < 0 && errno == EINTR) {
		}
	}
#elif defined(_WIN32)
	SetEvent(sampler->windows_stop_event);
#endif
	g_thread_join(sampler->thread);
	crown_input_double_drag_sampler_drain(sampler, delta_x, delta_y, samples);
#if defined(__linux__)
	if (sampler->backend == CROWN_INPUT_DOUBLE_DRAG_SAMPLER_BACKEND_WAYLAND)
		destroy_wayland(sampler);
	if (sampler->x11_wake_fd >= 0)
		close(sampler->x11_wake_fd);
#elif defined(_WIN32)
	CloseHandle(sampler->windows_stop_event);
	g_cond_clear(&sampler->windows_setup_cond);
#endif
	g_mutex_clear(&sampler->mutex);
	SAMPLER_LOG("stop complete backend=%s final-samples=%d final-delta=(%.3f,%.3f)\n"
		, backend_names[sampler->backend]
		, *samples
		, *delta_x
		, *delta_y
		);
	g_free(sampler);
}
