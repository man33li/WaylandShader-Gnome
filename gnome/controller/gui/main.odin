package main

import "core:fmt"
import "core:sys/posix"

UI :: #load("controller.ui", string)

main :: proc() {
	// GTK 3 on Wayland uses the program name as app_id (no GApplication), which must
	// match the desktop file for the dash icon [INFERENCE: checked in T-GUI].
	g_set_prgname("org.waylandshader.GnomeController")
	if !gtk_init_check(nil, nil) {
		fmt.eprintln("waylandshader-gnome-controller: cannot open a display")
		posix.exit(1)
	}
	if !build_window(UI) {
		posix.exit(1)
	}
	gtk_widget_show_all(app.win)
	show_errors() // hides the empty error label that show_all made visible
	g_idle_add(startup_idle, nil) // the reconnect (and extension activation) runs from the main loop
	gtk_main()
}
