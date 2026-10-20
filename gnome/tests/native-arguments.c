/* Usage: native-arguments <libwaylandshader-gnome.so>. Run once per library (baseline, port). */
#include <dlfcn.h>
#include <glib-object.h>
#include <stdio.h>
#include <string.h>

typedef gpointer (*New)(void);
typedef gboolean (*Json)(gpointer, const gchar *, GError **);
typedef void (*Fn)(gpointer);

static int failures;
#define CHECK(c, ...) do { if (!(c)) { failures++; fprintf(stderr, "FAIL " __VA_ARGS__); fputc('\n', stderr); } } while (0)

static void *sym(void *h, const char *n) {
    void *p = dlsym(h, n);
    if (!p) { fprintf(stderr, "FAIL missing symbol %s\n", n); failures++; }
    return p;
}

int main(int argc, char **argv) {
    if (argc != 2) { fprintf(stderr, "usage: %s LIBRARY\n", argv[0]); return 2; }
    void *h = dlopen(argv[1], RTLD_NOW | RTLD_LOCAL);
    if (!h) { fprintf(stderr, "dlopen: %s\n", dlerror()); return 2; }
    New make = sym(h, "wayland_shader_effect_new");
    Fn shutdown = sym(h, "wayland_shader_effect_shutdown");
    struct { const char *name; Json f; } m[] = {
        {"set_outputs", sym(h, "wayland_shader_effect_set_outputs")},
        {"import_settings", sym(h, "wayland_shader_effect_import_settings")},
        {"load_preset", sym(h, "wayland_shader_effect_load_preset")},
    };
    if (failures) return 1;
    gpointer e = make();
    CHECK(e != NULL, "constructor returned NULL");
    if (!e) return 1;
    const char *args[] = {NULL, "\xff"};
    for (guint i = 0; i < G_N_ELEMENTS(m); i++)
        for (guint j = 0; j < 2; j++) {
            GError *err = NULL;
            gboolean ok = m[i].f(e, args[j], &err);
            const char *a = j ? "byteFF" : "NULL";
            CHECK(!ok, "%s %s returned TRUE", m[i].name, a);
            CHECK(err != NULL, "%s %s no GError", m[i].name, a);
            if (err) {
                CHECK(err->domain == g_quark_from_static_string("wayland-shader-error"), "%s %s domain", m[i].name, a);
                CHECK(err->code == 1, "%s %s code %d", m[i].name, a, err->code);
                CHECK(!g_strcmp0(err->message, "Invalid UTF-8 argument"), "%s %s message '%s'", m[i].name, a, err->message);
                fprintf(stderr, "%s %s: domain=%s code=%d message=%s\n", m[i].name, a, g_quark_to_string(err->domain), err->code, err->message);
                g_error_free(err);
            }
        }
    shutdown(e);
    g_object_unref(e);
    return failures != 0;
}
