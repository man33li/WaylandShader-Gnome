#include <stddef.h>
#include <glib-object.h>
#include <clutter/clutter.h>
#include <cogl/cogl.h>
#include <mtk/mtk.h>
#include <graphene.h>
#include <EGL/egl.h>
#include <EGL/eglext.h>
#include <librashader.h>

#define SIZE(T, N) _Static_assert(sizeof(T) == (N), #T " size")
#define OFFSET(T, F, N) _Static_assert(offsetof(T, F) == (N), #T "." #F " offset")
#define VALUE(V, N) _Static_assert((V) == (N), #V " value")
SIZE(GObjectClass, 136);
OFFSET(GObjectClass, dispose, 40);
OFFSET(GObjectClass, finalize, 48);
SIZE(ClutterActorMetaClass, 152);
OFFSET(ClutterActorMetaClass, set_actor, 136);
SIZE(ClutterEffectClass, 200);
OFFSET(ClutterEffectClass, paint, 176);
SIZE(ClutterEffect, 24);
SIZE(GTypeQuery, 24);
SIZE(GError, 16);
SIZE(ClutterLuminance, 20);
OFFSET(ClutterLuminance, ref, 12);
OFFSET(ClutterLuminance, mastering_max, 16);
SIZE(MtkRectangle, 16);
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
SIZE(frame_gl_opt_t, 40);
SIZE(filter_chain_gl_opt_t, 16);
SIZE(libra_preset_opt_t, 16);
SIZE(libra_preset_param_t, 32);
SIZE(libra_preset_param_list_t, 16);
SIZE(libra_viewport_t, 16);
SIZE(libra_preset_ctx_t, 8);
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
