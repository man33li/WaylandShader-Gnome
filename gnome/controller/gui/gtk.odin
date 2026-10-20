package main

// Hand-written GTK 3 / GLib bindings used only by the controller GUI (design §5.1).
// Every GTK object is a plain rawptr; the aliases below document the intent.

import "base:runtime"
import "core:c"
import "core:strings"

foreign import gtk "system:gtk-3"
foreign import gobject "system:gobject-2.0"
foreign import glib "system:glib-2.0"

Widget :: rawptr
Adjustment :: rawptr
Builder :: rawptr

GError :: struct {
	domain:  u32,
	code:    c.int,
	message: cstring,
}

GList :: struct {
	data: rawptr,
	next: ^GList,
	prev: ^GList,
}

GTK_INPUT_ERROR :: -1
GTK_RESPONSE_ACCEPT :: -3
GTK_RESPONSE_CANCEL :: -6
GTK_FILE_CHOOSER_ACTION_OPEN :: 0
G_LOG_LEVEL_CRITICAL :: 1 << 3
G_LOG_LEVEL_WARNING :: 1 << 4
G_SOURCE_REMOVE :: 0

Callback :: proc "c" ()

@(default_calling_convention = "c")
foreign glib {
	g_set_prgname :: proc(name: cstring) ---
	g_timeout_add :: proc(interval: c.uint, function: proc "c" (data: rawptr) -> b32, data: rawptr) -> c.uint ---
	g_idle_add :: proc(function: proc "c" (data: rawptr) -> b32, data: rawptr) -> c.uint ---
	g_source_remove :: proc(id: c.uint) -> b32 ---
	g_free :: proc(mem: rawptr) ---
	g_list_free :: proc(list: ^GList) ---
	g_error_free :: proc(err: ^GError) ---
	g_log :: proc(domain: cstring, level: c.int, format: cstring, #c_vararg args: ..any) ---
}

@(default_calling_convention = "c")
foreign gobject {
	g_signal_connect_data :: proc(instance: rawptr, signal: cstring, handler: Callback, data: rawptr, destroy: rawptr, flags: c.int) -> c.ulong ---
	g_object_ref_sink :: proc(obj: rawptr) -> rawptr ---
	g_object_unref :: proc(obj: rawptr) ---
}

@(default_calling_convention = "c")
foreign gtk {
	gtk_init_check :: proc(argc: ^c.int, argv: ^[^]cstring) -> b32 ---
	gtk_main :: proc() ---
	gtk_main_quit :: proc() ---

	gtk_builder_new :: proc() -> Builder ---
	gtk_builder_add_from_string :: proc(b: Builder, buffer: [^]u8, length: c.size_t, err: ^^GError) -> c.uint ---
	gtk_builder_get_object :: proc(b: Builder, name: cstring) -> rawptr ---

	gtk_widget_show_all :: proc(w: Widget) ---
	gtk_widget_show :: proc(w: Widget) ---
	gtk_widget_destroy :: proc(w: Widget) ---
	gtk_widget_set_sensitive :: proc(w: Widget, s: b32) ---
	gtk_widget_set_visible :: proc(w: Widget, v: b32) ---
	gtk_widget_set_tooltip_text :: proc(w: Widget, text: cstring) ---
	gtk_widget_has_focus :: proc(w: Widget) -> b32 ---
	gtk_widget_grab_focus :: proc(w: Widget) ---
	gtk_widget_set_hexpand :: proc(w: Widget, e: b32) ---
	gtk_widget_get_toplevel :: proc(w: Widget) -> Widget ---

	gtk_window_set_focus :: proc(w: Widget, focus: Widget) ---

	gtk_container_get_children :: proc(c: Widget) -> ^GList ---

	gtk_entry_set_text :: proc(e: Widget, text: cstring) ---
	gtk_entry_get_text :: proc(e: Widget) -> cstring ---

	gtk_toggle_button_set_active :: proc(b: Widget, a: b32) ---
	gtk_toggle_button_get_active :: proc(b: Widget) -> b32 ---

	gtk_label_new :: proc(text: cstring) -> Widget ---
	gtk_label_set_text :: proc(l: Widget, text: cstring) ---
	gtk_label_set_xalign :: proc(l: Widget, x: f32) ---
	gtk_label_set_line_wrap :: proc(l: Widget, wrap: b32) ---
	gtk_label_set_max_width_chars :: proc(l: Widget, n: c.int) ---
	gtk_label_set_mnemonic_widget :: proc(l: Widget, w: Widget) ---

	gtk_combo_box_text_append :: proc(c: Widget, id: cstring, text: cstring) ---
	gtk_combo_box_text_remove_all :: proc(c: Widget) ---
	gtk_combo_box_set_active :: proc(w: Widget, index: c.int) ---
	gtk_combo_box_get_active_id :: proc(c: Widget) -> cstring ---

	gtk_adjustment_new :: proc(value, lower, upper, step, page, page_size: f64) -> Adjustment ---
	gtk_adjustment_set_value :: proc(a: Adjustment, v: f64) ---
	gtk_adjustment_get_value :: proc(a: Adjustment) -> f64 ---
	gtk_spin_button_new :: proc(a: Adjustment, climb_rate: f64, digits: c.uint) -> Widget ---
	gtk_spin_button_get_adjustment :: proc(s: Widget) -> Adjustment ---
	gtk_spin_button_set_value :: proc(s: Widget, v: f64) ---
	gtk_spin_button_get_value :: proc(s: Widget) -> f64 ---
	gtk_spin_button_set_range :: proc(s: Widget, lo, hi: f64) ---
	gtk_spin_button_set_increments :: proc(s: Widget, step, page: f64) ---
	gtk_spin_button_update :: proc(s: Widget) ---

	gtk_grid_attach :: proc(g: Widget, child: Widget, left, top, width, height: c.int) ---

	gtk_menu_new :: proc() -> Widget ---
	gtk_menu_item_new_with_label :: proc(label: cstring) -> Widget ---
	gtk_menu_shell_append :: proc(menu: Widget, item: Widget) ---
	gtk_menu_button_set_popup :: proc(b: Widget, menu: Widget) ---

	gtk_file_chooser_dialog_new :: proc(title: cstring, parent: Widget, action: c.int, first_button: cstring, #c_vararg args: ..any) -> Widget ---
	gtk_file_chooser_add_filter :: proc(c: Widget, f: rawptr) ---
	gtk_file_chooser_set_filename :: proc(c: Widget, name: cstring) -> b32 ---
	gtk_file_chooser_set_current_folder :: proc(c: Widget, name: cstring) -> b32 ---
	gtk_file_chooser_get_filename :: proc(c: Widget) -> cstring ---
	gtk_file_filter_new :: proc() -> rawptr ---
	gtk_file_filter_set_name :: proc(f: rawptr, name: cstring) ---
	gtk_file_filter_add_pattern :: proc(f: rawptr, pattern: cstring) ---
	gtk_dialog_run :: proc(d: Widget) -> c.int ---
}

// The handler's real signature varies per signal; GLib casts it back.
connect :: proc(obj: rawptr, signal: cstring, handler: $T, data: rawptr) {
	g_signal_connect_data(obj, signal, transmute(Callback)handler, data, nil, 0)
}

// Odin context for every proc "c" entry (design §5.6): a failed assertion is
// logged as CRITICAL and then traps instead of unwinding through GTK.
gui_context :: proc "contextless" () -> runtime.Context {
	ctx := runtime.default_context()
	ctx.assertion_failure_proc = proc(prefix, message: string, loc: runtime.Source_Code_Location) -> ! {
		g_log(nil, G_LOG_LEVEL_CRITICAL, "%.*s: %.*s (%.*s:%d)", c.int(len(prefix)), raw_data(prefix), c.int(len(message)), raw_data(message), c.int(len(loc.file_path)), raw_data(loc.file_path), loc.line)
		runtime.trap()
	}
	return ctx
}

// Temp-allocated C string for action-critical uses; failure is logged and reported.
cstr_try :: proc(s: string) -> (cstring, bool) {
	r, err := strings.clone_to_cstring(s, context.temp_allocator)
	if err != nil {
		g_log(nil, G_LOG_LEVEL_WARNING, "Out of memory")
		return "", false
	}
	return r, true
}

// Display-only conversion (labels, tooltips): an allocation failure is logged and
// shows empty text; never use it for paths or other action inputs.
cstr :: proc(s: string) -> cstring {
	r, _ := cstr_try(s)
	return r
}

// Heap copy of `s` stored in `dst`, freeing the previous value.
set_str :: proc(dst: ^string, s: string) {
	cp, err := strings.clone(s)
	if err != nil {
		g_log(nil, G_LOG_LEVEL_WARNING, "Out of memory")
		return
	}
	if len(dst^) > 0 {
		delete(dst^)
	}
	dst^ = cp
}

clear_str :: proc(dst: ^string) {
	if len(dst^) > 0 {
		delete(dst^)
	}
	dst^ = {}
}
