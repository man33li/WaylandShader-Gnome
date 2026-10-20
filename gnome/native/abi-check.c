#include <stddef.h>
#include <gio/gio.h>
#include <glib-object.h>
#include <clutter/clutter.h>
#include <cogl/cogl.h>
#include <mtk/mtk.h>
#include <graphene.h>
#include <EGL/egl.h>
#include <EGL/eglext.h>
#include <gtk/gtk.h>
#include <librashader.h>

#define SIZE(T, N) _Static_assert(sizeof(T) == (N), #T " size")
#define OFFSET(T, F, N) _Static_assert(offsetof(T, F) == (N), #T "." #F " offset")
#define VALUE(V, N) _Static_assert((V) == (N), #V " value")
SIZE(GObject, 24);
OFFSET(GObject, g_type_instance.g_class, 0);
OFFSET(GObject, ref_count, 8);
OFFSET(GObject, qdata, 16);
SIZE(GList, 24);
OFFSET(GList, data, 0);
OFFSET(GList, next, 8);
OFFSET(GList, prev, 16);
SIZE(GError, 16);
OFFSET(GError, domain, 0);
OFFSET(GError, code, 4);
OFFSET(GError, message, 8);
SIZE(GTypeQuery, 24);
OFFSET(GTypeQuery, type, 0);
OFFSET(GTypeQuery, type_name, 8);
OFFSET(GTypeQuery, class_size, 16);
OFFSET(GTypeQuery, instance_size, 20);
SIZE(GObjectClass, 136);
OFFSET(GObjectClass, dispose, 40);
OFFSET(GObjectClass, finalize, 48);
SIZE(ClutterActorMetaClass, 152);
OFFSET(ClutterActorMetaClass, set_actor, 136);
OFFSET(ClutterActorMetaClass, set_enabled, 144);
SIZE(ClutterEffectClass, 200);
OFFSET(ClutterEffectClass, pre_paint, 152);
OFFSET(ClutterEffectClass, post_paint, 160);
OFFSET(ClutterEffectClass, modify_paint_volume, 168);
OFFSET(ClutterEffectClass, paint, 176);
OFFSET(ClutterEffectClass, paint_node, 184);
OFFSET(ClutterEffectClass, pick, 192);
SIZE(ClutterEffect, 24);
SIZE(ClutterLuminance, 20);
OFFSET(ClutterLuminance, min, 4);
OFFSET(ClutterLuminance, max, 8);
OFFSET(ClutterLuminance, ref, 12);
OFFSET(ClutterLuminance, mastering_max, 16);
SIZE(MtkRectangle, 16);
OFFSET(MtkRectangle, x, 0);
OFFSET(MtkRectangle, y, 4);
OFFSET(MtkRectangle, width, 8);
OFFSET(MtkRectangle, height, 12);
SIZE(graphene_matrix_t, 64);
_Static_assert(_Alignof(graphene_matrix_t) == 16, "graphene matrix alignment");
SIZE(ClutterPaintFlag, 4);
VALUE(COGL_PIXEL_FORMAT_RGBA_FP_16161616_PRE, 155);
VALUE(COGL_SNIPPET_HOOK_TEXTURE_LOOKUP, 6145);
VALUE(CLUTTER_EFFECT_PAINT_BYPASS_EFFECT, 2);
VALUE(COGL_PIPELINE_FILTER_NEAREST, 9728);
VALUE(COGL_PIPELINE_WRAP_MODE_CLAMP_TO_EDGE, 33071);
VALUE(G_SIGNAL_RUN_LAST, 2);
VALUE(G_TYPE_STRING, 64);
VALUE(G_TYPE_NONE, 4);
VALUE(CLUTTER_COLORSPACE_SRGB, 0);
VALUE(CLUTTER_TRANSFER_FUNCTION_SRGB_PIECEWISE, 0);
SIZE(libra_image_gl_t, 16);
OFFSET(libra_image_gl_t, handle, 0);
OFFSET(libra_image_gl_t, format, 4);
OFFSET(libra_image_gl_t, width, 8);
OFFSET(libra_image_gl_t, height, 12);
SIZE(frame_gl_opt_t, 40);
OFFSET(frame_gl_opt_t, version, 0);
OFFSET(frame_gl_opt_t, clear_history, 8);
OFFSET(frame_gl_opt_t, frame_direction, 12);
OFFSET(frame_gl_opt_t, rotation, 16);
OFFSET(frame_gl_opt_t, total_subframes, 20);
OFFSET(frame_gl_opt_t, current_subframe, 24);
OFFSET(frame_gl_opt_t, aspect_ratio, 28);
OFFSET(frame_gl_opt_t, frames_per_second, 32);
OFFSET(frame_gl_opt_t, frametime_delta, 36);
SIZE(filter_chain_gl_opt_t, 16);
OFFSET(filter_chain_gl_opt_t, version, 0);
OFFSET(filter_chain_gl_opt_t, glsl_version, 8);
OFFSET(filter_chain_gl_opt_t, use_dsa, 10);
OFFSET(filter_chain_gl_opt_t, force_no_mipmaps, 11);
OFFSET(filter_chain_gl_opt_t, disable_cache, 12);
SIZE(libra_preset_opt_t, 16);
OFFSET(libra_preset_opt_t, version, 0);
OFFSET(libra_preset_opt_t, original_aspect_uniforms, 8);
OFFSET(libra_preset_opt_t, frametime_uniforms, 9);
SIZE(libra_preset_param_t, 32);
OFFSET(libra_preset_param_t, name, 0);
OFFSET(libra_preset_param_t, description, 8);
OFFSET(libra_preset_param_t, initial, 16);
OFFSET(libra_preset_param_t, minimum, 20);
OFFSET(libra_preset_param_t, maximum, 24);
OFFSET(libra_preset_param_t, step, 28);
SIZE(libra_preset_param_list_t, 16);
OFFSET(libra_preset_param_list_t, parameters, 0);
OFFSET(libra_preset_param_list_t, length, 8);
SIZE(libra_viewport_t, 16);
OFFSET(libra_viewport_t, x, 0);
OFFSET(libra_viewport_t, y, 4);
OFFSET(libra_viewport_t, width, 8);
OFFSET(libra_viewport_t, height, 12);
SIZE(libra_preset_ctx_t, 8);
SIZE(libra_error_t, 8);
SIZE(libra_gl_filter_chain_t, 8);
SIZE(libra_shader_preset_t, 8);
SIZE(EGLDisplay, 8);
SIZE(EGLContext, 8);
SIZE(EGLSurface, 8);
SIZE(EGLConfig, 8);
VALUE(GTK_INPUT_ERROR, -1);
VALUE(GTK_RESPONSE_ACCEPT, -3);
VALUE(GTK_RESPONSE_CANCEL, -6);
VALUE(GTK_FILE_CHOOSER_ACTION_OPEN, 0);
VALUE(G_LOG_LEVEL_CRITICAL, 8);
VALUE(G_LOG_LEVEL_WARNING, 16);
VALUE(G_SOURCE_REMOVE, 0);
VALUE(G_IO_ERROR_CLOSED, 18);
VALUE(G_IO_ERROR_CANCELLED, 19);
VALUE(G_IO_ERROR_TIMED_OUT, 24);
VALUE(EGL_FALSE, 0);
VALUE(EGL_TRUE, 1);
VALUE(EGL_NONE, 0x3038);
VALUE(EGL_OPENGL_API, 0x30A2);
VALUE(EGL_OPENGL_ES_API, 0x30A0);
VALUE(EGL_CONTEXT_CLIENT_TYPE, 0x3097);
VALUE(EGL_VERSION, 0x3054);
VALUE(EGL_EXTENSIONS, 0x3055);
VALUE(EGL_DRAW, 0x3059);
VALUE(EGL_READ, 0x305A);
VALUE(EGL_WIDTH, 0x3057);
VALUE(EGL_HEIGHT, 0x3056);
VALUE(EGL_SURFACE_TYPE, 0x3033);
VALUE(EGL_PBUFFER_BIT, 1);
VALUE(EGL_RENDERABLE_TYPE, 0x3040);
VALUE(EGL_OPENGL_BIT, 8);
VALUE(EGL_RED_SIZE, 0x3024);
VALUE(EGL_GREEN_SIZE, 0x3023);
VALUE(EGL_BLUE_SIZE, 0x3022);
VALUE(EGL_ALPHA_SIZE, 0x3021);
VALUE(EGL_CONTEXT_MAJOR_VERSION, 0x3098);
VALUE(EGL_CONTEXT_MINOR_VERSION, 0x30FB);
VALUE(EGL_CONTEXT_OPENGL_PROFILE_MASK, 0x30FD);
VALUE(EGL_CONTEXT_OPENGL_CORE_PROFILE_BIT, 1);
VALUE(EGL_CONTEXT_OPENGL_ROBUST_ACCESS, 0x31B2);
VALUE(EGL_CONTEXT_OPENGL_RESET_NOTIFICATION_STRATEGY, 0x31BD);
VALUE(EGL_LOSE_CONTEXT_ON_RESET, 0x31BF);
VALUE(EGL_CONTEXT_FLAGS_KHR, 0x30fc);
VALUE(EGL_CONTEXT_OPENGL_ROBUST_ACCESS_BIT_KHR, 4);
VALUE(EGL_NO_RESET_NOTIFICATION, 0x31be);
VALUE(EGL_PLATFORM_SURFACELESS_MESA, 0x31dd);
VALUE(COGL_BUFFER_BIT_COLOR, 1);
