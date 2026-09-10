#pragma once

#ifdef __cplusplus
// Epoxy must precede Cogl's platform EGL headers in C++ renderers.
#include <epoxy/egl.h>
#endif

#include <glib-object.h>
// Mutter also installs C-only headers without individual linkage guards.
G_BEGIN_DECLS
#include <clutter/clutter.h>

#define WAYLAND_SHADER_TYPE_EFFECT (wayland_shader_effect_get_type())
G_DECLARE_FINAL_TYPE(WaylandShaderEffect, wayland_shader_effect, WAYLAND_SHADER, EFFECT, ClutterEffect)

/**
 * wayland_shader_effect_new:
 *
 * Creates a native stage effect. Attach only to the GNOME Shell stage.
 * All methods must be called on the compositor's main thread.
 * Returns: (transfer full): the new effect
 */
WaylandShaderEffect* wayland_shader_effect_new(void);

/**
 * wayland_shader_effect_get_status:
 * @self: the effect
 * Returns: (transfer full): controller-compatible JSON status
 */
gchar* wayland_shader_effect_get_status(WaylandShaderEffect* self);

/**
 * wayland_shader_effect_export_settings:
 * @self: the effect
 * Returns: (transfer full): versioned persistent configuration JSON
 */
gchar* wayland_shader_effect_export_settings(WaylandShaderEffect* self);

/**
 * wayland_shader_effect_import_settings:
 * @self: the effect
 * @json: versioned configuration, or an empty JSON object for defaults
 * @error: return location for a rejected configuration
 * Returns: whether the configuration was accepted
 */
gboolean wayland_shader_effect_import_settings(WaylandShaderEffect* self, const gchar* json, GError** error);

/**
 * wayland_shader_effect_set_outputs:
 * @self: the effect
 * @json: array of active connector IDs, names and logical geometry
 * @error: return location for invalid or unsupported topology
 * Returns: whether the inventory was accepted
 */
gboolean wayland_shader_effect_set_outputs(WaylandShaderEffect* self, const gchar* json, GError** error);

/**
 * wayland_shader_effect_load_preset:
 * @self: the effect
 * @path: absolute preset filename
 * @error: return location for rejected requests
 *
 * Compilation is asynchronous. Observe status-changed for completion.
 * A compilation failure preserves the previous working preset.
 * Returns: whether the request was accepted
 */
gboolean wayland_shader_effect_load_preset(WaylandShaderEffect* self, const gchar* path, GError** error);

/**
 * wayland_shader_effect_set_enabled:
 * @self: the effect
 * @enabled: master shader and color enablement
 * @error: return location for a rejected mutation
 * Returns: whether the mutation was accepted
 */
gboolean wayland_shader_effect_set_enabled(WaylandShaderEffect* self, gboolean enabled, GError** error);

/**
 * wayland_shader_effect_set_parameter:
 * @self: the effect
 * @name: active preset parameter name
 * @value: finite parameter value within its declared range
 * @error: return location for a rejected mutation
 * Returns: whether the mutation was accepted
 */
gboolean wayland_shader_effect_set_parameter(WaylandShaderEffect* self, const gchar* name, double value, GError** error);

/**
 * wayland_shader_effect_set_output_shader_enabled:
 * @self: the effect
 * @id: active connector ID
 * @enabled: shader enablement independent of color enablement
 * @error: return location for a rejected mutation
 * Returns: whether the mutation was accepted
 */
gboolean wayland_shader_effect_set_output_shader_enabled(WaylandShaderEffect* self, const gchar* id, gboolean enabled, GError** error);

/**
 * wayland_shader_effect_set_output_color_enabled:
 * @self: the effect
 * @id: active connector ID
 * @enabled: color enablement independent of shader enablement
 * @error: return location for a rejected mutation
 * Returns: whether the mutation was accepted
 */
gboolean wayland_shader_effect_set_output_color_enabled(WaylandShaderEffect* self, const gchar* id, gboolean enabled, GError** error);

/**
 * wayland_shader_effect_set_output_gamma:
 * @self: the effect
 * @id: active connector ID
 * @value: gamma from 0.1 through 5
 * @error: return location for a rejected mutation
 * Returns: whether the mutation was accepted
 */
gboolean wayland_shader_effect_set_output_gamma(WaylandShaderEffect* self, const gchar* id, double value, GError** error);

/**
 * wayland_shader_effect_set_output_saturation:
 * @self: the effect
 * @id: active connector ID
 * @value: saturation from 0 through 2
 * @error: return location for a rejected mutation
 * Returns: whether the mutation was accepted
 */
gboolean wayland_shader_effect_set_output_saturation(WaylandShaderEffect* self, const gchar* id, double value, GError** error);

/**
 * wayland_shader_effect_reset_history:
 * @self: the effect
 *
 * Discards scene textures and temporal histories, including across lock and
 * monitor transitions. The selected preset is rebuilt asynchronously.
 */
void wayland_shader_effect_reset_history(WaylandShaderEffect* self);

/**
 * wayland_shader_effect_shutdown:
 * @self: the effect
 *
 * Idempotently disconnects native hooks, stops timelines, drains compilation,
 * and releases GPU resources. Call before the host display is destroyed.
 */
void wayland_shader_effect_shutdown(WaylandShaderEffect* self);

G_END_DECLS
