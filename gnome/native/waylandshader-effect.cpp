#include "waylandshader-effect.h"
#include "shader_runtime.h"

#include "output_settings.h"

#include <epoxy/gl.h>
extern "C" {
#include <meta/meta-backend.h>
#include <meta/meta-monitor.h>
}

#include <QFileInfo>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QJsonParseError>
#include <QSet>
#include <QStringList>

#include <algorithm>
#include <cmath>
#include <exception>
#include <limits>
#include <memory>
#include <stdexcept>
#include <thread>
#include <vector>

// Exported, non-installed Mutter 50.4 / ABI 18 APIs. Only opaque objects and
// function declarations are pinned here; no private object layouts are copied.
extern "C" {
typedef struct _MetaRendererView MetaRendererView;
typedef struct _MetaRenderer MetaRenderer;
typedef struct _MetaCrtc MetaCrtc;
typedef struct _MetaOutput MetaOutput;
GType meta_renderer_view_get_type(void);
MetaCrtc* meta_renderer_view_get_crtc(MetaRendererView* view);
MetaBackend* meta_crtc_get_backend(MetaCrtc* crtc);
const GList* meta_crtc_get_outputs(MetaCrtc* crtc);
MetaMonitor* meta_output_get_monitor(MetaOutput* output);
const char* meta_output_get_name(MetaOutput* output);
MetaCrtc* meta_output_get_assigned_crtc(MetaOutput* output);
GList* meta_monitor_get_outputs(MetaMonitor* monitor);
MetaRenderer* meta_backend_get_renderer(MetaBackend* backend);
MetaRendererView* meta_renderer_get_view_for_crtc(MetaRenderer* renderer, MetaCrtc* crtc);
void meta_backend_inhibit_hw_cursor(MetaBackend* backend);
void meta_backend_uninhibit_hw_cursor(MetaBackend* backend);
void clutter_stage_view_add_redraw_clip(ClutterStageView* view, const MtkRectangle* clip);
void clutter_stage_view_schedule_update(ClutterStageView* view);
}

namespace {
using WaylandShader::OutputSettings;
using WaylandShader::ShaderRuntime;

constexpr qsizetype maxRecentPresets = 10;

struct Engine;
struct Output;

struct Failure : std::runtime_error {
    explicit Failure(const QString& text)
        : std::runtime_error(text.toUtf8().constData())
    {
    }
};

void require(bool condition, const QString& message)
{
    if (!condition)
        throw Failure(message);
}

QString text(const char* value)
{
    require(value && g_utf8_validate(value, -1, nullptr), QStringLiteral("Invalid UTF-8 argument"));
    return QString::fromUtf8(value);
}

QJsonDocument parse(const char* json)
{
    QJsonParseError error;
    const auto document = QJsonDocument::fromJson(text(json).toUtf8(), &error);
    require(error.error == QJsonParseError::NoError, error.errorString());
    return document;
}

bool boolean(const QJsonObject& object, const QString& key, bool fallback)
{
    if (!object.contains(key))
        return fallback;
    require(object[key].isBool(), key + QStringLiteral(" must be boolean"));
    return object[key].toBool();
}

double number(const QJsonObject& object, const QString& key, double fallback, double min, double max)
{
    if (!object.contains(key))
        return fallback;
    const auto value = object[key];
    require(value.isDouble() && std::isfinite(value.toDouble())
            && value.toDouble() >= min && value.toDouble() <= max,
        key + QStringLiteral(" is outside its allowed range"));
    return value.toDouble();
}

QJsonObject settingsJson(const OutputSettings& settings)
{
    return { { "shaderEnabled", settings.shaderEnabled }, { "colorEnabled", settings.colorEnabled },
        { "gamma", settings.gamma }, { "saturation", settings.saturation } };
}

OutputSettings readSettings(const QJsonObject& object)
{
    OutputSettings settings;
    settings.shaderEnabled = boolean(object, QStringLiteral("shaderEnabled"), true);
    settings.colorEnabled = boolean(object, QStringLiteral("colorEnabled"), false);
    settings.gamma = number(object, QStringLiteral("gamma"), 1, OutputSettings::MinimumGamma, OutputSettings::MaximumGamma);
    settings.saturation = number(object, QStringLiteral("saturation"), 1, OutputSettings::MinimumSaturation, OutputSettings::MaximumSaturation);
    return settings;
}

struct ErrorHolder {
    GError* value = nullptr;
    ~ErrorHolder() { g_clear_error(&value); }
    QString message(const char* fallback) const { return QString::fromUtf8(value ? value->message : fallback); }
};

// Restores the exact caller EGL context, surfaces and selected client API.
// Cogl destruction and raw texture deletion always occur in the host context.
struct HostContext {
    EGLDisplay previousDisplay = eglGetCurrentDisplay();
    EGLContext previousContext = eglGetCurrentContext();
    EGLSurface previousDraw = eglGetCurrentSurface(EGL_DRAW);
    EGLSurface previousRead = eglGetCurrentSurface(EGL_READ);
    EGLenum previousApi = eglQueryAPI();
    EGLDisplay display;
    bool changed = false;

    HostContext(EGLDisplay targetDisplay, EGLContext context, EGLSurface draw, EGLSurface read)
        : display(targetDisplay)
    {
        if (display == EGL_NO_DISPLAY || context == EGL_NO_CONTEXT)
            return;
        if (previousDisplay == display && previousContext == context)
            return;
        changed = true;
        if (!eglBindAPI(EGL_OPENGL_API) || !eglMakeCurrent(display, draw, read, context)) {
            restore();
            throw Failure(QStringLiteral("Unable to acquire the GNOME compositor EGL context"));
        }
    }
    void restore() noexcept
    {
        if (!changed)
            return;
        if (!eglMakeCurrent(display, EGL_NO_SURFACE, EGL_NO_SURFACE, EGL_NO_CONTEXT)
            || !eglBindAPI(previousApi)
            || (previousContext != EGL_NO_CONTEXT
                && !eglMakeCurrent(previousDisplay, previousDraw, previousRead, previousContext)))
            g_warning("WaylandShader: failed to restore caller EGL context");
        changed = false;
    }
    ~HostContext() { restore(); }
};

// We only mutate bindings to effect-owned objects, never Cogl's texture state.
struct GLBindings {
    GLint texture = 0, read = 0, draw = 0, unpack = 0;
    GLboolean scissor, srgb;
    GLBindings()
    {
        glGetIntegerv(GL_TEXTURE_BINDING_2D, &texture);
        glGetIntegerv(GL_READ_FRAMEBUFFER_BINDING, &read);
        glGetIntegerv(GL_DRAW_FRAMEBUFFER_BINDING, &draw);
        glGetIntegerv(GL_PIXEL_UNPACK_BUFFER_BINDING, &unpack);
        scissor = glIsEnabled(GL_SCISSOR_TEST);
        srgb = glIsEnabled(GL_FRAMEBUFFER_SRGB);
    }
    ~GLBindings()
    {
        glBindTexture(GL_TEXTURE_2D, texture);
        glBindFramebuffer(GL_READ_FRAMEBUFFER, read);
        glBindFramebuffer(GL_DRAW_FRAMEBUFFER, draw);
        glBindBuffer(GL_PIXEL_UNPACK_BUFFER, unpack);
        if (scissor)
            glEnable(GL_SCISSOR_TEST);
        else
            glDisable(GL_SCISSOR_TEST);
        if (srgb)
            glEnable(GL_FRAMEBUFFER_SRGB);
        else
            glDisable(GL_FRAMEBUFFER_SRGB);
    }
};

struct Surface {
    CoglTexture* texture = nullptr;
    CoglOffscreen* offscreen = nullptr;
    Surface() = default;
    Surface(const Surface&) = delete;
    Surface& operator=(const Surface&) = delete;
    ~Surface()
    {
        g_clear_object(&offscreen);
        g_clear_object(&texture);
    }
    CoglFramebuffer* fb() const { return COGL_FRAMEBUFFER(offscreen); }
    void allocate(CoglContext* context, int width, int height)
    {
        if (texture)
            return;
        Surface pending;
        pending.texture = cogl_texture_2d_new_with_format(context, width, height, COGL_PIXEL_FORMAT_RGBA_FP_16161616_PRE);
        cogl_texture_2d_set_auto_mipmap(COGL_TEXTURE_2D(pending.texture), false);
        ErrorHolder error;
        if (!cogl_texture_allocate(pending.texture, &error.value))
            throw Failure(error.message("Unable to allocate stage texture"));
        pending.offscreen = cogl_offscreen_new_with_texture(pending.texture);
        if (!cogl_framebuffer_allocate(pending.fb(), &error.value))
            throw Failure(error.message("Unable to allocate stage framebuffer"));
        graphene_matrix_t identity;
        graphene_matrix_init_identity(&identity);
        cogl_framebuffer_set_modelview_matrix(pending.fb(), &identity);
        cogl_framebuffer_orthographic(pending.fb(), 0, 0, width, height, -1, 1);
        cogl_framebuffer_set_viewport(pending.fb(), 0, 0, width, height);
        cogl_framebuffer_clear4f(pending.fb(), COGL_BUFFER_BIT_COLOR, 0, 0, 0, 0);
        texture = pending.texture;
        offscreen = pending.offscreen;
        pending.texture = nullptr;
        pending.offscreen = nullptr;
    }
    GLuint name() const
    {
        unsigned int name = 0, target = 0;
        require(cogl_texture_get_gl_texture(texture, &name, &target) && target == GL_TEXTURE_2D,
            QStringLiteral("Cogl did not allocate a desktop GL 2D texture"));
        return name;
    }
};

CoglPipeline* pipeline(CoglContext* context)
{
    auto* result = cogl_pipeline_new(context);
    ErrorHolder error;
    if (!cogl_pipeline_set_blend(result, "RGBA = ADD(SRC_COLOR, 0)", &error.value)) {
        g_object_unref(result);
        throw Failure(error.message("Unable to configure replacement blending"));
    }
    cogl_pipeline_set_layer_filters(result, 0, COGL_PIPELINE_FILTER_NEAREST, COGL_PIPELINE_FILTER_NEAREST);
    cogl_pipeline_set_layer_wrap_mode(result, 0, COGL_PIPELINE_WRAP_MODE_CLAMP_TO_EDGE);
    return result;
}

struct Resources {
    int width, height;
    Surface raw, srgb, destination, final;
    CoglPipeline *toSrgb = nullptr, *toTarget = nullptr;
    ClutterColorState* targetColor = nullptr;
    ClutterColorState* workingColor = nullptr;
    GLuint source = 0, readFbo = 0, drawFbo = 0;
    int gammaUniform = -1, saturationUniform = -1;
    double gamma = -1, saturation = -1;
    bool retainedByRuntime = false, targetIsSrgb = false;

    Resources(CoglContext* context, int w, int h)
        : width(w)
        , height(h)
    {
        raw.allocate(context, w, h);
    }
    ~Resources()
    {
        g_clear_object(&toSrgb);
        g_clear_object(&toTarget);
        g_clear_object(&targetColor);
        g_clear_object(&workingColor);
        if (source)
            glDeleteTextures(1, &source);
        if (readFbo)
            glDeleteFramebuffers(1, &readFbo);
        if (drawFbo)
            glDeleteFramebuffers(1, &drawFbo);
    }
    void configureColor(ClutterColorState* target, ClutterColorState* sRGB)
    {
        if (targetColor == target && toSrgb && toTarget)
            return;
        g_clear_object(&toSrgb);
        g_clear_object(&toTarget);
        g_set_object(&targetColor, target);
        g_clear_object(&workingColor);
        const auto* luminance = CLUTTER_IS_COLOR_STATE_PARAMS(target)
            ? clutter_color_state_params_get_luminance(CLUTTER_COLOR_STATE_PARAMS(target))
            : nullptr;
        if (luminance && luminance->mastering_max > luminance->ref) {
            // Preserve HDR headroom relative to SDR white. A default SDR
            // intermediate would invoke Mutter's irreversible tone mapper.
            const auto* working = clutter_color_state_params_get_luminance(CLUTTER_COLOR_STATE_PARAMS(sRGB));
            ClutterContext* context = nullptr;
            g_object_get(sRGB, "context", &context, nullptr);
            workingColor = clutter_color_state_params_new_full(context,
                CLUTTER_COLORSPACE_SRGB, CLUTTER_TRANSFER_FUNCTION_SRGB_PIECEWISE,
                nullptr, -1.0f, working->min, working->max, working->ref,
                working->ref * luminance->mastering_max / luminance->ref);
            g_object_unref(context);
        } else {
            workingColor = CLUTTER_COLOR_STATE(g_object_ref(sRGB));
        }
        require(workingColor, QStringLiteral("Unable to create the shader working color state"));
        targetIsSrgb = clutter_color_state_equals(target, workingColor);
        auto* context = cogl_framebuffer_get_context(raw.fb());
        toSrgb = pipeline(context);
        clutter_color_state_add_pipeline_transform(target, workingColor, toSrgb,
            static_cast<ClutterColorStateTransformFlags>(0));
        toTarget = pipeline(context);
        // The layer lookup executes before the fragment color transform. Work
        // in unpremultiplied sRGB and restore premultiplication before conversion.
        auto* adjustment = cogl_snippet_new(COGL_SNIPPET_HOOK_TEXTURE_LOOKUP,
            "uniform float wls_gamma; uniform float wls_saturation;",
            "if (wls_gamma != 1.0 || wls_saturation != 1.0) {\n"
            "  if (cogl_texel.a > 0.0) {\n"
            "    vec3 rgb = pow(max(cogl_texel.rgb / cogl_texel.a, vec3(0.0)), vec3(1.0 / wls_gamma));\n"
            "    vec3 linear_rgb = mix(pow((rgb + 0.055) / 1.055, vec3(2.4)), rgb / 12.92, lessThanEqual(rgb, vec3(0.04045)));\n"
            "    float luma = dot(linear_rgb, vec3(0.2126, 0.7152, 0.0722));\n"
            "    linear_rgb = max(mix(vec3(luma), linear_rgb, wls_saturation), vec3(0.0));\n"
            "    rgb = mix(1.055 * pow(linear_rgb, vec3(1.0 / 2.4)) - 0.055, 12.92 * linear_rgb, lessThanEqual(linear_rgb, vec3(0.0031308)));\n"
            "    cogl_texel.rgb = rgb * cogl_texel.a;\n"
            "  } else { cogl_texel.rgb = vec3(0.0); }\n"
            "}");
        cogl_pipeline_add_layer_snippet(toTarget, 0, adjustment);
        g_object_unref(adjustment);
        clutter_color_state_add_pipeline_transform(workingColor, target, toTarget,
            static_cast<ClutterColorStateTransformFlags>(0));
        gammaUniform = cogl_pipeline_get_uniform_location(toTarget, "wls_gamma");
        saturationUniform = cogl_pipeline_get_uniform_location(toTarget, "wls_saturation");
        gamma = saturation = -1;
    }
    void copyShaderSource(Surface& from)
    {
        cogl_framebuffer_flush(from.fb());
        GLBindings bindings;
        glDisable(GL_SCISSOR_TEST);
        glDisable(GL_FRAMEBUFFER_SRGB);
        if (!source) {
            glGenTextures(1, &source);
            glBindTexture(GL_TEXTURE_2D, source);
            glBindBuffer(GL_PIXEL_UNPACK_BUFFER, 0);
            int level = 0;
            for (int w = width, h = height;; w = std::max(1, w / 2), h = std::max(1, h / 2)) {
                glTexImage2D(GL_TEXTURE_2D, level++, GL_RGBA16F, w, h, 0, GL_RGBA, GL_HALF_FLOAT, nullptr);
                if (w == 1 && h == 1)
                    break;
            }
            glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
            glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
            glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
            glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
            glGenFramebuffers(1, &readFbo);
            glGenFramebuffers(1, &drawFbo);
        }
        glBindFramebuffer(GL_READ_FRAMEBUFFER, readFbo);
        glFramebufferTexture2D(GL_READ_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_TEXTURE_2D, from.name(), 0);
        glReadBuffer(GL_COLOR_ATTACHMENT0);
        glBindFramebuffer(GL_DRAW_FRAMEBUFFER, drawFbo);
        glFramebufferTexture2D(GL_DRAW_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_TEXTURE_2D, source, 0);
        glDrawBuffer(GL_COLOR_ATTACHMENT0);
        require(glCheckFramebufferStatus(GL_READ_FRAMEBUFFER) == GL_FRAMEBUFFER_COMPLETE
                && glCheckFramebufferStatus(GL_DRAW_FRAMEBUFFER) == GL_FRAMEBUFFER_COMPLETE,
            QStringLiteral("Incomplete shader source copy framebuffer"));
        glBlitFramebuffer(0, 0, width, height, 0, 0, width, height, GL_COLOR_BUFFER_BIT, GL_NEAREST);
        // Only level 0 holds this frame. Higher levels are uninitialized or a
        // previous preset's stale mips; the patched librashader exposes them
        // only while generating mipmaps that the preset requests.
        glBindTexture(GL_TEXTURE_2D, source);
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAX_LEVEL, 0);
        const GLenum error = glGetError();
        if (error != GL_NO_ERROR)
            throw Failure(QStringLiteral("Shader source GPU copy failed (GL 0x%1)").arg(error, 0, 16));
    }
};

struct Output {
    Engine* engine;
    QString id, name, failure;
    MtkRectangle layout {};
    double scale = 1;
    uintptr_t key;
    OutputSettings settings;
    ClutterStageView* view = nullptr; // strong until destroy; destroy disconnects timeline first
    gulong destroyHandler = 0;
    ClutterTimeline* timeline = nullptr;
    std::unique_ptr<Resources> resources;
    // A chain may still retain the preceding destination until its next render.
    std::unique_ptr<Resources> retired;
    bool clearHistory = true;
    int64_t previousTime = 0;
    int64_t firstFrame = -1;
    int64_t expandedFrame = -1;

    Output(Engine* owner, uintptr_t identity)
        : engine(owner)
        , key(identity)
    {
    }
    ~Output();
    void detach();
};

struct LoadJob {
    QString path, error;
    QMap<QString, double> overrides;
    std::vector<uintptr_t> outputs;
    uint64_t generation;
    std::unique_ptr<ShaderRuntime> result;
};

struct Engine {
    WaylandShaderEffect* self;
    GThread* ownerThread = g_thread_self();
    GMainContext* mainContext = g_main_context_ref_thread_default();
    ClutterActor* stage = nullptr; // ActorMeta owns this lifetime; never create a cycle
    MetaBackend* backend = nullptr;
    ClutterColorState* srgb = nullptr;
    gulong beforePaintHandler = 0, purgeHandler = 0;
    guint statusSource = 0, workSource = 0;
    GSource* completionSource = nullptr;
    std::thread worker;
    std::unique_ptr<LoadJob> job;
    std::unique_ptr<ShaderRuntime> runtime;
    QList<WaylandShader::ShaderParameter> lastParameters;
    std::vector<std::unique_ptr<Output>> outputs;
    QMap<QString, OutputSettings> savedOutputs;
    QMap<QString, QMap<QString, double>> overrides;
    QString preset, requested, error, pending;
    QStringList recent; // successfully compiled presets, most recent first
    QByteArray lastStatus;
    EGLDisplay display = EGL_NO_DISPLAY;
    EGLContext context = EGL_NO_CONTEXT;
    EGLSurface drawSurface = EGL_NO_SURFACE, readSurface = EGL_NO_SURFACE;
    uint64_t generation = 0;
    uintptr_t nextKey = 1;
    bool enabled = true, stopped = false, cursorInhibited = false, mappingDirty = true;
    bool loading = false, rendererFailed = false;

    explicit Engine(WaylandShaderEffect* object)
        : self(object)
    {
    }
    ~Engine() { g_main_context_unref(mainContext); }
    void check() const
    {
        require(g_thread_self() == ownerThread, QStringLiteral("Native effect methods require the compositor main thread"));
        require(!stopped, QStringLiteral("The native effect has shut down"));
    }
    bool shader(const Output& output) const
    {
        return !stopped && !rendererFailed && enabled && stage && runtime && output.view && output.failure.isEmpty() && output.settings.shaderEnabled;
    }
    bool color(const Output& output) const
    {
        return !stopped && !rendererFailed && context != EGL_NO_CONTEXT && enabled && stage && output.view && output.failure.isEmpty() && output.settings.adjustsColor();
    }
    bool active() const
    {
        for (const auto& output : outputs)
            if (shader(*output) || color(*output))
                return true;
        return false;
    }
    Output& output(const char* id)
    {
        const auto key = text(id);
        for (const auto& value : outputs)
            if (value->id == key)
                return *value;
        throw Failure(QStringLiteral("Unknown active output: %1").arg(key));
    }
    QJsonObject status() const;
    void notify();
    void queueWork();
    void redraw();
    void syncActivity();
    void mapOutputs();
    void discover(ClutterStageView* view);
    bool captureContext();
    void request(const QString& path);
    void startLoad();
    void completeLoad();
    void reset(bool rebuild);
    void shutdown();
    void attach(ClutterActor* actor);
    void fail(const QString& message) noexcept;
    void paint(ClutterPaintContext* pc, ClutterEffectPaintFlags flags, bool& continued);
};

} // namespace

struct _WaylandShaderEffect {
    ClutterEffect parent_instance;
    Engine* engine;
};

G_DEFINE_TYPE(WaylandShaderEffect, wayland_shader_effect, CLUTTER_TYPE_EFFECT)

namespace {
guint statusSignal;

void Engine::fail(const QString& message) noexcept
{
    try {
        queueWork();
        if (error == message)
            return;
        error = message;
        notify();
    } catch (...) {
        g_warning("WaylandShader: unable to publish native failure");
    }
}

QJsonObject Engine::status() const
{
    QJsonArray parameterRows, outputRows;
    const auto& parameters = runtime ? runtime->parameters() : lastParameters;
    for (const auto& parameter : parameters) {
        parameterRows.append(QJsonObject { { "name", parameter.name }, { "description", parameter.description },
            { "minimum", parameter.minimum }, { "maximum", parameter.maximum }, { "step", parameter.step },
            { "default", parameter.defaultValue }, { "value", parameter.value } });
    }
    for (const auto& output : outputs) {
        auto row = settingsJson(output->settings);
        row.insert(QStringLiteral("id"), output->id);
        row.insert(QStringLiteral("name"), output->name);
        row.insert(QStringLiteral("shaderActive"), shader(*output));
        row.insert(QStringLiteral("colorActive"), color(*output));
        if (!output->failure.isEmpty()) // shown unfiltered; same field name as niri's status
            row.insert(QStringLiteral("bypass"), output->failure);
        outputRows.append(row);
    }
    return { { "enabled", enabled }, { "active", active() }, { "loading", loading },
        { "preset", preset }, { "requestedPreset", requested }, { "recentPresets", QJsonArray::fromStringList(recent) },
        { "error", error }, { "parameters", parameterRows }, { "outputs", outputRows } };
}

void Engine::notify()
{
    if (statusSource || stopped)
        return;
    auto* source = g_idle_source_new();
    g_source_set_callback(source, [](gpointer data) -> gboolean {
        auto &engine = *static_cast<Engine *>(data);
        engine.statusSource = 0;
        // Emission is never in paint, and a handler may release the last owner.
        g_object_ref(engine.self);
        try {
            const auto json = QJsonDocument(engine.status()).toJson(QJsonDocument::Compact);
            if (json != engine.lastStatus) {
                engine.lastStatus = json;
                g_signal_emit(engine.self, statusSignal, 0, json.constData());
            }
        } catch (const std::exception &exception) {
            g_warning("WaylandShader status: %s", exception.what());
        } catch (...) {
            g_warning("WaylandShader status: unknown native exception");
        }
        g_object_unref(engine.self);
        return G_SOURCE_REMOVE; }, this, nullptr);
    statusSource = g_source_attach(source, mainContext);
    g_source_unref(source);
}

void Engine::redraw()
{
    if (!stage || stopped)
        return;
    for (const auto& output : outputs) {
        if (output->view) {
            clutter_stage_view_add_redraw_clip(output->view, nullptr);
            clutter_stage_view_schedule_update(output->view);
        }
    }
    // Also reaches newly created, not yet mapped views and erases old filtered
    // pixels after a topology change or master disable.
    clutter_actor_queue_redraw(stage);
}

void Engine::queueWork()
{
    if (workSource || stopped)
        return;
    auto* source = g_idle_source_new();
    g_source_set_callback(source, [](gpointer data) -> gboolean {
        auto &engine = *static_cast<Engine *>(data);
        engine.workSource = 0;
        try {
            engine.syncActivity();
            engine.startLoad();
        } catch (const std::exception &exception) {
            engine.error = QString::fromUtf8(exception.what());
            engine.loading = false;
            engine.pending.clear();
            engine.notify();
        } catch (...) {
            engine.error = QStringLiteral("Unknown native scheduling failure");
            engine.loading = false;
            engine.pending.clear();
            engine.notify();
        }
        return G_SOURCE_REMOVE; }, this, nullptr);
    workSource = g_source_attach(source, mainContext);
    g_source_unref(source);
}

void Output::detach()
{
    if (timeline) {
        clutter_timeline_stop(timeline);
        g_clear_object(&timeline);
    }
    if (view && destroyHandler)
        g_signal_handler_disconnect(view, destroyHandler);
    destroyHandler = 0;
    g_clear_object(&view);
    expandedFrame = -1;
}

Output::~Output() { detach(); }

void Engine::syncActivity()
{
    const bool wantsCursor = active();
    if (backend && wantsCursor != cursorInhibited) {
        if (wantsCursor)
            meta_backend_inhibit_hw_cursor(backend);
        else
            meta_backend_uninhibit_hw_cursor(backend);
        cursorInhibited = wantsCursor;
    }
    for (const auto& output : outputs) {
        if (shader(*output)) {
            if (!output->timeline) {
                output->timeline = clutter_timeline_new_for_frame_clock(
                    clutter_stage_view_get_frame_clock(output->view), 1000);
                clutter_timeline_set_repeat_count(output->timeline, -1);
                g_signal_connect(output->timeline, "new-frame", G_CALLBACK(+[](ClutterTimeline*, gint, gpointer data) {
                    auto& output = *static_cast<Output*>(data);
                    if (output.view && output.engine->shader(output)) {
                        clutter_actor_queue_redraw_with_clip(output.engine->stage, &output.layout);
                        clutter_stage_view_add_redraw_clip(output.view, nullptr);
                        clutter_stage_view_schedule_update(output.view);
                    }
                }),
                    output.get());
                clutter_timeline_start(output->timeline);
            }
        } else if (output->timeline) {
            clutter_timeline_stop(output->timeline);
            g_clear_object(&output->timeline);
        }
    }
}

void Engine::mapOutputs()
{
    if (!backend || !mappingDirty)
        return;
    mappingDirty = false;
    auto* manager = meta_backend_get_monitor_manager(backend);
    auto* renderer = meta_backend_get_renderer(backend);
    for (const auto& output : outputs) {
        output->detach();
        output->failure.clear();
        MetaMonitor* monitor = nullptr;
        for (auto* item = meta_monitor_manager_get_monitors(manager); item; item = item->next) {
            auto* candidate = META_MONITOR(item->data);
            if (output->id == QString::fromUtf8(meta_monitor_get_connector(candidate))) {
                monitor = candidate;
                break;
            }
        }
        if (!monitor || !meta_monitor_is_active(monitor)) {
            output->failure = QStringLiteral("Connector has no active physical monitor: %1").arg(output->id);
        } else {
            auto* physical = meta_monitor_get_outputs(monitor);
            if (!physical || physical->next) {
                output->failure = QStringLiteral("Tiled monitors cannot be processed as independent full-frame outputs: %1").arg(output->id);
            } else {
                auto* crtc = meta_output_get_assigned_crtc(static_cast<MetaOutput*>(physical->data));
                const auto* clones = crtc ? meta_crtc_get_outputs(crtc) : nullptr;
                if (!clones || clones->next) {
                    output->failure = QStringLiteral("Shared or missing CRTC prevents independent processing: %1").arg(output->id);
                } else {
                    auto* view = reinterpret_cast<ClutterStageView*>(meta_renderer_get_view_for_crtc(renderer, crtc));
                    MtkRectangle layout {};
                    if (view)
                        clutter_stage_view_get_layout(view, &layout);
                    if (!view || layout.x != output->layout.x || layout.y != output->layout.y
                        || layout.width != output->layout.width || layout.height != output->layout.height) {
                        output->failure = QStringLiteral("Connector geometry does not match its physical stage view: %1").arg(output->id);
                    } else {
                        output->view = CLUTTER_STAGE_VIEW(g_object_ref(view));
                        output->destroyHandler = g_signal_connect(view, "destroy", G_CALLBACK(+[](ClutterStageView*, gpointer data) {
                            auto& output = *static_cast<Output*>(data);
                            try {
                                output.detach();
                                output.engine->mappingDirty = true;
                                // Chains are retired before retained destinations are released.
                                output.engine->reset(true);
                                output.engine->notify();
                            } catch (const std::exception& exception) {
                                output.engine->fail(QString::fromUtf8(exception.what()));
                            } catch (...) {
                                output.engine->fail(QStringLiteral("Native stage-view destruction failed"));
                            }
                        }),
                            output.get());
                    }
                }
            }
        }
        if (!output->failure.isEmpty())
            error = output->failure;
        output->clearHistory = true;
        output->firstFrame = -1;
        output->previousTime = 0;
    }
    queueWork();
    notify();
}

bool Engine::captureContext()
{
    const auto hostDisplay = eglGetCurrentDisplay();
    const auto hostContext = eglGetCurrentContext();
    if (hostDisplay == EGL_NO_DISPLAY || hostContext == EGL_NO_CONTEXT)
        return false;
    if (context == EGL_NO_CONTEXT) {
        EGLint api = 0;
        require(eglQueryContext(hostDisplay, hostContext, EGL_CONTEXT_CLIENT_TYPE, &api)
                && api == EGL_OPENGL_API && eglQueryAPI() == EGL_OPENGL_API,
            QStringLiteral("GNOME must use an EGL desktop OpenGL renderer, not GLES or GLX"));
        display = hostDisplay;
        context = hostContext;
        srgb = clutter_color_state_params_new(clutter_actor_get_context(stage),
            CLUTTER_COLORSPACE_SRGB, CLUTTER_TRANSFER_FUNCTION_SRGB_PIECEWISE);
        queueWork();
        notify();
    }
    require(hostDisplay == display && hostContext == context,
        QStringLiteral("The GNOME compositor EGL share context changed"));
    drawSurface = eglGetCurrentSurface(EGL_DRAW);
    readSurface = eglGetCurrentSurface(EGL_READ);
    return true;
}

void Engine::discover(ClutterStageView* view)
{
    if (!backend) {
        require(g_type_is_a(G_OBJECT_TYPE(view), meta_renderer_view_get_type()),
            QStringLiteral("This stage view is not a Mutter native physical renderer view"));
        auto* crtc = meta_renderer_view_get_crtc(reinterpret_cast<MetaRendererView*>(view));
        require(crtc, QStringLiteral("This stage view has no physical or virtual CRTC"));
        backend = META_BACKEND(g_object_ref(meta_crtc_get_backend(crtc)));
    }
    // before-paint also runs for direct-scanout frames. Discovering the real
    // host here lets compilation finish and activate unredirect inhibition
    // without waiting for an actor paint that direct scanout might suppress.
    captureContext();
    mapOutputs();
    if (active() && !cursorInhibited) {
        meta_backend_inhibit_hw_cursor(backend);
        cursorInhibited = true;
    }
}

void Engine::request(const QString& path)
{
    require(!rendererFailed, error.isEmpty() ? QStringLiteral("The GNOME renderer is unavailable") : error);
    ++generation;
    requested = path;
    pending = path;
    loading = true;
    error.clear();
    queueWork();
    redraw();
    notify();
}

void Engine::startLoad()
{
    if (pending.isEmpty() || job || stopped || rendererFailed || !stage)
        return;
    // A real stage frame hook discovers the actual host context; constructor
    // and DBus calls must not guess at an EGL display or API.
    if (display == EGL_NO_DISPLAY || context == EGL_NO_CONTEXT)
        return;
    auto next = std::make_unique<LoadJob>();
    next->path = pending;
    next->overrides = overrides.value(pending);
    next->generation = generation;
    for (const auto& output : outputs)
        next->outputs.push_back(output->key);
    job = std::move(next);
    pending.clear();
    loading = true;
    completionSource = g_idle_source_new();
    g_source_set_callback(completionSource, [](gpointer data) -> gboolean {
        auto &engine = *static_cast<Engine *>(data);
        try {
            engine.completeLoad();
        } catch (const std::exception &exception) {
            engine.fail(QString::fromUtf8(exception.what()));
        } catch (...) {
            engine.fail(QStringLiteral("Unknown preset completion failure"));
        }
        return G_SOURCE_REMOVE; }, this, nullptr);
    auto* task = job.get();
    auto* completion = completionSource;
    try {
        worker = std::thread([task, completion, main = mainContext, display = display, context = context] {
            try {
                task->result = ShaderRuntime::load(display, context, task->path, task->outputs, task->overrides, task->error);
            } catch (const std::exception& exception) {
                task->error = QString::fromUtf8(exception.what());
            } catch (...) {
                task->error = QStringLiteral("Unknown preset compiler exception");
            }
            // Attach only once the result is complete: no polling, Qt event
            // loop, or concurrent access to the live runtime or owner state.
            g_source_attach(completion, main);
        });
    } catch (...) {
        g_source_unref(completionSource);
        completionSource = nullptr;
        job.reset();
        loading = false;
        throw;
    }
    notify();
}

void Engine::completeLoad()
{
    worker.join();
    g_source_unref(completionSource);
    completionSource = nullptr;
    auto completed = std::move(job);
    HostContext host(display, context, drawSurface, readSurface);
    if (completed->generation == generation && !stopped) {
        if (completed->result) {
            // Retire the old runtime FIRST; its chains can retain destinations.
            runtime.reset();
            for (const auto& output : outputs) {
                output->retired.reset();
                if (output->resources)
                    output->resources->retainedByRuntime = false;
                if (output->view) {
                    if (!output->failure.isEmpty())
                        output->resources.reset();
                    output->failure.clear();
                }
            }
            runtime = std::move(completed->result);
            preset = completed->path;
            recent.removeAll(preset);
            recent.prepend(preset);
            recent = recent.mid(0, maxRecentPresets);
            lastParameters = runtime->parameters();
            if (completed->path == requested)
                error.clear();
            for (const auto& output : outputs) {
                output->clearHistory = true;
                output->firstFrame = -1;
                output->previousTime = 0;
                if (!output->failure.isEmpty())
                    error = output->failure;
            }
        } else {
            error = completed->error.isEmpty() ? QStringLiteral("Preset compilation failed") : completed->error;
            // A topology/privacy reset may have retired the old GPU chains
            // while this replacement compiled. Rebuild the known working
            // selection rather than letting a bad replacement strand it.
            if (!runtime && !preset.isEmpty() && preset != completed->path)
                pending = preset;
        }
    }
    completed.reset();
    loading = !pending.isEmpty();
    syncActivity();
    startLoad();
    redraw();
    notify();
}

void Engine::reset(bool rebuild)
{
    ++generation;
    HostContext host(display, context, drawSurface, readSurface);
    runtime.reset();
    for (const auto& output : outputs) {
        if (output->timeline) {
            clutter_timeline_stop(output->timeline);
            g_clear_object(&output->timeline);
        }
        output->resources.reset();
        output->retired.reset();
        output->clearHistory = true;
        output->firstFrame = -1;
        output->expandedFrame = -1;
        output->previousTime = 0;
        if (output->view)
            output->failure.clear();
    }
    // A compiling replacement contains no scene history, but topology keys may
    // have changed. Drain it normally, discard by generation, then rebuild.
    pending = rebuild && !rendererFailed ? (loading && !requested.isEmpty() ? requested : preset) : QString();
    loading = !rendererFailed && (job || !pending.isEmpty());
    queueWork();
    redraw();
    notify();
}

void removeSource(GMainContext* context, guint& id)
{
    if (id) {
        if (auto* source = g_main_context_find_source_by_id(context, id))
            g_source_destroy(source);
        id = 0;
    }
}

void Engine::shutdown()
{
    if (stopped)
        return;
    stopped = true;
    if (stage && beforePaintHandler)
        g_signal_handler_disconnect(stage, beforePaintHandler);
    if (stage && purgeHandler)
        g_signal_handler_disconnect(stage, purgeHandler);
    beforePaintHandler = purgeHandler = 0;
    removeSource(mainContext, statusSource);
    removeSource(mainContext, workSource);
    for (const auto& output : outputs)
        output->detach();
    if (backend && cursorInhibited)
        meta_backend_uninhibit_hw_cursor(backend);
    cursorInhibited = false;
    if (worker.joinable())
        worker.join();
    if (completionSource) {
        g_source_destroy(completionSource);
        g_source_unref(completionSource);
        completionSource = nullptr;
    }
    HostContext host(display, context, drawSurface, readSurface);
    job.reset();
    runtime.reset();
    outputs.clear();
    g_clear_object(&srgb);
    g_clear_object(&backend);
    stage = nullptr;
    loading = false;
    pending.clear();
}

void Engine::attach(ClutterActor* actor)
{
    if (stage && beforePaintHandler)
        g_signal_handler_disconnect(stage, beforePaintHandler);
    if (stage && purgeHandler)
        g_signal_handler_disconnect(stage, purgeHandler);
    beforePaintHandler = purgeHandler = 0;
    if (stage)
        reset(false);
    for (const auto& output : outputs)
        output->detach();
    if (backend && cursorInhibited)
        meta_backend_uninhibit_hw_cursor(backend);
    cursorInhibited = false;
    g_clear_object(&backend);
    stage = actor;
    mappingDirty = true;
    if (!actor || stopped)
        return;
    require(CLUTTER_IS_STAGE(actor), QStringLiteral("WaylandShader must attach to the original GNOME stage"));
    beforePaintHandler = g_signal_connect(actor, "before-paint", G_CALLBACK(+[](ClutterStage*, ClutterStageView* view, ClutterFrame* frame, gpointer data) {
        auto& engine = *static_cast<Engine*>(data);
        if (engine.stopped || engine.rendererFailed)
            return;
        try {
            engine.discover(view);
            for (const auto& output : engine.outputs) {
                if (output->view == view && (engine.shader(*output) || engine.color(*output))) {
                    // This is consumed by the CURRENT redraw, before frusta,
                    // surface culling, and buffer-age damage are established.
                    clutter_stage_view_add_redraw_clip(view, nullptr);
                    output->expandedFrame = clutter_frame_get_count(frame);
                    break;
                }
            }
        } catch (const std::exception& exception) {
            engine.rendererFailed = true;
            engine.pending.clear();
            engine.loading = false;
            ++engine.generation;
            engine.fail(QString::fromUtf8(exception.what()));
        } catch (...) {
            engine.rendererFailed = true;
            engine.pending.clear();
            engine.loading = false;
            ++engine.generation;
            engine.fail(QStringLiteral("Unknown native before-paint failure"));
        }
    }),
        this);
    if (g_signal_lookup("gl-video-memory-purged", G_OBJECT_TYPE(actor))) {
        purgeHandler = g_signal_connect(actor, "gl-video-memory-purged", G_CALLBACK(+[](ClutterActor*, gpointer data) {
            auto& engine = *static_cast<Engine*>(data);
            try {
                engine.reset(true);
            } catch (const std::exception& exception) {
                engine.fail(QString::fromUtf8(exception.what()));
            } catch (...) {
                engine.fail(QStringLiteral("GPU resource reset failed"));
            }
        }),
            this);
    }
    if (!preset.isEmpty()) {
        pending = preset;
        loading = true;
    }
    queueWork();
    redraw();
    notify();
}

void renderSurface(CoglFramebuffer* framebuffer, CoglPipeline* pipeline, CoglTexture* texture, int width, int height)
{
    cogl_pipeline_set_layer_texture(pipeline, 0, texture);
    cogl_framebuffer_draw_textured_rectangle(framebuffer, pipeline, 0, 0, width, height, 0, 0, 1, 1);
    cogl_framebuffer_flush(framebuffer);
    const auto error = glGetError();
    if (error != GL_NO_ERROR)
        throw Failure(QStringLiteral("Stage color conversion failed (GL 0x%1)").arg(error, 0, 16));
}

void Engine::paint(ClutterPaintContext* pc, ClutterEffectPaintFlags flags, bool& continued)
{
    auto continueScene = [&] {
        if (auto* actor = clutter_actor_meta_get_actor(CLUTTER_ACTOR_META(self))) {
            continued = true;
            clutter_actor_continue_paint(actor, pc);
        }
    };
    auto* view = clutter_paint_context_get_stage_view(pc);
    auto* frame = clutter_paint_context_get_frame(pc);
    if (stopped || rendererFailed || !view || !frame || (flags & CLUTTER_EFFECT_PAINT_BYPASS_EFFECT)) {
        continueScene();
        return;
    }
    auto* target = clutter_paint_context_get_framebuffer(pc);
    // Other stage effects may substitute a framebuffer. It is not a monitor
    // view, and processing it would double-filter snapshots or misroute output.
    if (target != clutter_stage_view_get_framebuffer(view)) {
        continueScene();
        return;
    }
    require(captureContext(), QStringLiteral("GNOME has no current desktop OpenGL EGL context"));
    Output* selected = nullptr;
    for (const auto& output : outputs) {
        if (output->view == view) {
            selected = output.get();
            break;
        }
    }
    if (!selected || (!shader(*selected) && !color(*selected))
        || selected->expandedFrame != clutter_frame_get_count(frame)) {
        continueScene();
        return;
    }
    auto& output = *selected;
    auto* targetColor = clutter_paint_context_get_target_color_state(pc);
    const int width = cogl_framebuffer_get_width(target), height = cogl_framebuffer_get_height(target);
    require(width > 0 && height > 0 && targetColor, QStringLiteral("Invalid stage framebuffer or target color state"));
    bool captured = false, wroteTarget = false;
    try {
        if (!output.resources || output.resources->width != width || output.resources->height != height) {
            auto resources = std::make_unique<Resources>(cogl_framebuffer_get_context(target), width, height);
            // Only a destination actually submitted to librashader needs
            // retirement. Repeated color-only resizes may discard intermediate
            // resources while retaining the last shader attachment.
            if (output.resources && output.resources->retainedByRuntime) {
                output.retired = std::move(output.resources);
            }
            output.resources = std::move(resources);
            output.clearHistory = true;
            output.previousTime = 0;
            output.firstFrame = -1;
        }
        auto& resources = *output.resources;
        resources.configureColor(targetColor, srgb);
        // before-paint provided a full-view clip. Cogl establishes its own
        // framebuffer/clip state here; no raw GL clear can desynchronize it.
        cogl_framebuffer_clear4f(target, COGL_BUFFER_BIT_COLOR, 0, 0, 0, 0);
        continueScene(); // original context preserves all stage recorder watches
        cogl_context_flush(cogl_framebuffer_get_context(target));
        ErrorHolder copyError;
        if (!cogl_framebuffer_blit(target, resources.raw.fb(), 0, 0, 0, 0, width, height, &copyError.value))
            throw Failure(copyError.message("Unable to copy the current stage scene"));
        captured = true;
        auto* coglContext = cogl_framebuffer_get_context(target);
        Surface* processed = &resources.raw;
        if (!resources.targetIsSrgb) {
            resources.srgb.allocate(coglContext, width, height);
            clutter_color_state_update_uniforms(targetColor, resources.workingColor, resources.toSrgb);
            renderSurface(resources.srgb.fb(), resources.toSrgb, resources.raw.texture, width, height);
            processed = &resources.srgb;
        }
        bool renderShader = shader(output);
        int64_t now = 0;
        float refreshRate = 0;
        if (renderShader) {
            if (!clutter_frame_get_expected_presentation_time(frame, &now))
                now = g_get_monotonic_time();
            refreshRate = clutter_frame_clock_get_refresh_rate(clutter_stage_view_get_frame_clock(view));
            // Externally driven views have no nominal refresh rate. Measure
            // their real cadence after one warm-up frame instead of inventing it.
            if (refreshRate == 0) {
                if (output.previousTime > 0 && now > output.previousTime)
                    refreshRate = static_cast<float>(1000000.0 / (now - output.previousTime));
                else {
                    output.previousTime = now;
                    renderShader = false;
                }
            }
        }
        if (renderShader) {
            resources.destination.allocate(coglContext, width, height);
            resources.copyShaderSource(*processed);
            const auto count = clutter_frame_get_count(frame);
            if (output.firstFrame < 0)
                output.firstFrame = count;
            const auto elapsed = output.previousTime > 0 ? std::max<int64_t>(0, (now - output.previousTime) / 1000) : 0;
            WaylandShader::ShaderFrame shaderFrame { resources.source, resources.destination.name(), GL_RGBA16F,
                QSize(width, height), static_cast<uint64_t>(std::max<int64_t>(0, count - output.firstFrame)),
                refreshRate, static_cast<uint32_t>(std::min<int64_t>(elapsed, UINT32_MAX)),
                output.clearHistory };
            QString runtimeError;
            resources.retainedByRuntime = true;
            require(runtime->render(output.key, shaderFrame, runtimeError), runtimeError);
            // Publish shared-context writes even if Cogl's next bind is cached.
            GLint oldTexture = 0;
            glGetIntegerv(GL_TEXTURE_BINDING_2D, &oldTexture);
            glBindTexture(GL_TEXTURE_2D, shaderFrame.destination);
            glBindTexture(GL_TEXTURE_2D, oldTexture);
            output.previousTime = now;
            output.clearHistory = false;
            output.retired.reset();
            processed = &resources.destination;
        } else if (!runtime) {
            output.retired.reset();
        }
        if (!resources.targetIsSrgb || output.settings.adjustsColor()) {
            resources.final.allocate(coglContext, width, height);
            const auto gamma = output.settings.adjustsColor() ? output.settings.gamma : 1.0;
            const auto saturation = output.settings.adjustsColor() ? output.settings.saturation : 1.0;
            if (gamma != resources.gamma) {
                cogl_pipeline_set_uniform_1f(resources.toTarget, resources.gammaUniform, gamma);
                resources.gamma = gamma;
            }
            if (saturation != resources.saturation) {
                cogl_pipeline_set_uniform_1f(resources.toTarget, resources.saturationUniform, saturation);
                resources.saturation = saturation;
            }
            clutter_color_state_update_uniforms(resources.workingColor, targetColor, resources.toTarget);
            renderSurface(resources.final.fb(), resources.toTarget, processed->texture, width, height);
            processed = &resources.final;
        }
        // Pixel-space blits preserve the original viewport and matrices and
        // normalize onscreen/offscreen orientation using Cogl's own contract.
        // The view's monitor transform/color conversion still happens later.
        wroteTarget = true;
        ErrorHolder presentError;
        if (!cogl_framebuffer_blit(processed->fb(), target, 0, 0, 0, 0, width, height, &presentError.value))
            throw Failure(presentError.message("Unable to present the processed stage frame"));
        const auto presentGlError = glGetError();
        if (presentGlError != GL_NO_ERROR)
            throw Failure(QStringLiteral("Stage presentation failed (GL 0x%1)").arg(presentGlError, 0, 16));
    } catch (...) {
        if (captured && wroteTarget) {
            ErrorHolder restoreError;
            if (!cogl_framebuffer_blit(output.resources->raw.fb(), target, 0, 0, 0, 0, width, height, &restoreError.value))
                g_warning("WaylandShader raw-scene restoration: %s", restoreError.value ? restoreError.value->message : "GPU blit failed");
        }
        try {
            throw;
        } catch (const std::exception& exception) {
            output.failure = QString::fromUtf8(exception.what());
        } catch (...) {
            output.failure = QStringLiteral("Unknown stage processing failure");
        }
        fail(output.failure);
        if (!continued)
            continueScene();
    }
}

Engine& get(WaylandShaderEffect* self)
{
    require(WAYLAND_SHADER_IS_EFFECT(self) && self->engine, QStringLiteral("Invalid native effect"));
    self->engine->check();
    return *self->engine;
}

template <typename Function>
gboolean mutate(WaylandShaderEffect* self, GError** error, Function function) noexcept
{
    try {
        function(get(self));
        return true;
    } catch (const std::exception& exception) {
        g_set_error_literal(error, g_quark_from_static_string("wayland-shader-error"), 1, exception.what());
    } catch (...) {
        g_set_error_literal(error, g_quark_from_static_string("wayland-shader-error"), 1, "Unknown native exception");
    }
    return false;
}

void changed(Engine& engine, Output& output)
{
    engine.savedOutputs[output.id] = output.settings;
    if (output.view)
        output.failure.clear();
    engine.syncActivity();
    engine.redraw();
    engine.notify();
}

} // namespace

static void wayland_shader_effect_paint(ClutterEffect* effect, ClutterPaintNode*, ClutterPaintContext* pc, ClutterEffectPaintFlags flags)
{
    auto* self = WAYLAND_SHADER_EFFECT(effect);
    bool continued = false;
    try {
        if (self->engine)
            self->engine->paint(pc, flags, continued);
    } catch (const std::exception& exception) {
        if (self->engine) {
            self->engine->rendererFailed = true;
            self->engine->loading = false;
            self->engine->pending.clear();
            ++self->engine->generation;
            self->engine->fail(QString::fromUtf8(exception.what()));
        }
    } catch (...) {
        if (self->engine) {
            self->engine->rendererFailed = true;
            self->engine->loading = false;
            self->engine->pending.clear();
            ++self->engine->generation;
            self->engine->fail(QStringLiteral("Unknown native paint exception"));
        }
    }
    if (!continued) {
        if (auto* actor = clutter_actor_meta_get_actor(CLUTTER_ACTOR_META(effect)))
            clutter_actor_continue_paint(actor, pc);
    }
}

static void wayland_shader_effect_set_actor(ClutterActorMeta* meta, ClutterActor* actor)
{
    auto* self = WAYLAND_SHADER_EFFECT(meta);
    CLUTTER_ACTOR_META_CLASS(wayland_shader_effect_parent_class)->set_actor(meta, actor);
    try {
        if (self->engine)
            self->engine->attach(actor);
    } catch (const std::exception& exception) {
        if (self->engine)
            self->engine->fail(QString::fromUtf8(exception.what()));
    } catch (...) {
        if (self->engine)
            self->engine->fail(QStringLiteral("Unknown native attachment exception"));
    }
}

static void wayland_shader_effect_dispose(GObject* object)
{
    wayland_shader_effect_shutdown(WAYLAND_SHADER_EFFECT(object));
    G_OBJECT_CLASS(wayland_shader_effect_parent_class)->dispose(object);
}

static void wayland_shader_effect_finalize(GObject* object)
{
    auto* self = WAYLAND_SHADER_EFFECT(object);
    delete self->engine;
    self->engine = nullptr;
    G_OBJECT_CLASS(wayland_shader_effect_parent_class)->finalize(object);
}

static void wayland_shader_effect_class_init(WaylandShaderEffectClass* klass)
{
    G_OBJECT_CLASS(klass)->dispose = wayland_shader_effect_dispose;
    G_OBJECT_CLASS(klass)->finalize = wayland_shader_effect_finalize;
    CLUTTER_ACTOR_META_CLASS(klass)->set_actor = wayland_shader_effect_set_actor;
    CLUTTER_EFFECT_CLASS(klass)->paint = wayland_shader_effect_paint;
    /**
     * WaylandShaderEffect::status-changed:
     * @self: the native stage effect
     * @json: controller-compatible JSON status
     *
     * Emitted from the compositor main context, never during paint.
     */
    statusSignal = g_signal_new("status-changed", G_TYPE_FROM_CLASS(klass), G_SIGNAL_RUN_LAST,
        0, nullptr, nullptr, nullptr, G_TYPE_NONE, 1, G_TYPE_STRING);
}

static void wayland_shader_effect_init(WaylandShaderEffect* self)
{
    try {
        self->engine = new Engine(self);
    } catch (...) {
        self->engine = nullptr;
    }
}

WaylandShaderEffect* wayland_shader_effect_new(void)
{
    auto* self = WAYLAND_SHADER_EFFECT(g_object_new(WAYLAND_SHADER_TYPE_EFFECT, nullptr));
    if (!self->engine) {
        g_object_unref(self);
        return nullptr;
    }
    // ActorMeta starts floating; the GI constructor promises an owned reference.
    g_object_ref_sink(self);
    return self;
}

gchar* wayland_shader_effect_get_status(WaylandShaderEffect* self)
{
    try {
        require(WAYLAND_SHADER_IS_EFFECT(self) && self->engine, QStringLiteral("Invalid native effect"));
        return g_strdup(QJsonDocument(self->engine->status()).toJson(QJsonDocument::Compact).constData());
    } catch (...) {
        return g_strdup("{\"enabled\":false,\"active\":false,\"loading\":false,\"preset\":\"\",\"requestedPreset\":\"\",\"error\":\"Unable to construct native status\",\"parameters\":[],\"outputs\":[]}");
    }
}

gchar* wayland_shader_effect_export_settings(WaylandShaderEffect* self)
{
    try {
        require(WAYLAND_SHADER_IS_EFFECT(self) && self->engine, QStringLiteral("Invalid native effect"));
        const auto& engine = *self->engine;
        QJsonObject outputSettings, parameterSettings;
        for (auto it = engine.savedOutputs.cbegin(); it != engine.savedOutputs.cend(); ++it)
            outputSettings.insert(it.key(), settingsJson(it.value()));
        for (auto it = engine.overrides.cbegin(); it != engine.overrides.cend(); ++it) {
            QJsonObject parameters;
            for (auto parameter = it.value().cbegin(); parameter != it.value().cend(); ++parameter)
                parameters.insert(parameter.key(), parameter.value());
            parameterSettings.insert(it.key(), parameters);
        }
        return g_strdup(QJsonDocument(QJsonObject { { "version", 1 }, { "enabled", engine.enabled }, { "preset", engine.preset },
                                          { "recent_presets", QJsonArray::fromStringList(engine.recent) },
                                          { "parameters", parameterSettings }, { "outputs", outputSettings } })
                .toJson(QJsonDocument::Compact)
                .constData());
    } catch (...) {
        // Never silently overwrite a working configuration with defaults.
        return nullptr;
    }
}

gboolean wayland_shader_effect_import_settings(WaylandShaderEffect* self, const gchar* json, GError** error)
{
    return mutate(self, error, [&](Engine& engine) {
        require(!engine.loading && !engine.job, QStringLiteral("Cannot import settings while a preset is compiling"));
        require(!engine.rendererFailed, engine.error.isEmpty() ? QStringLiteral("The GNOME renderer is unavailable") : engine.error);
        const auto document = parse(json);
        require(document.isObject(), QStringLiteral("Configuration must be a JSON object"));
        const auto object = document.object();
        require(object.isEmpty() || (object["version"].isDouble() && object["version"].toDouble() == 1),
            QStringLiteral("Unsupported settings version"));
        const bool enabled = boolean(object, QStringLiteral("enabled"), true);
        require(!object.contains("preset") || object["preset"].isString(), QStringLiteral("Preset must be a string"));
        const auto preset = object["preset"].toString();
        QMap<QString, OutputSettings> outputSettings;
        QMap<QString, QMap<QString, double>> parameterSettings;
        require(!object.contains("outputs") || object["outputs"].isObject(), QStringLiteral("Output settings must be an object"));
        const auto outputObject = object["outputs"].toObject();
        for (auto it = outputObject.begin(); it != outputObject.end(); ++it) {
            require(!it.key().isEmpty() && it.value().isObject(), QStringLiteral("Invalid saved output settings"));
            outputSettings.insert(it.key(), readSettings(it.value().toObject()));
        }
        require(!object.contains("parameters") || object["parameters"].isObject(), QStringLiteral("Parameter settings must be an object"));
        const auto parameterObject = object["parameters"].toObject();
        for (auto it = parameterObject.begin(); it != parameterObject.end(); ++it) {
            require(it.value().isObject(), QStringLiteral("Invalid saved preset parameters"));
            QMap<QString, double> parameters;
            const auto values = it.value().toObject();
            for (auto value = values.begin(); value != values.end(); ++value) {
                require(!value.key().isEmpty() && value.value().isDouble() && std::isfinite(value.value().toDouble()),
                    QStringLiteral("Saved parameters must have finite numeric values"));
                parameters.insert(value.key(), value.value().toDouble());
            }
            parameterSettings.insert(it.key(), parameters);
        }
        if (!preset.isEmpty()) {
            const QFileInfo file(preset);
            require(file.isAbsolute(), QStringLiteral("Saved preset must be an absolute filename"));
        }
        // History is advisory: skip malformed entries instead of rejecting
        // otherwise valid settings. Stale files stay listed and fail on load.
        QStringList recent;
        for (const auto& entry : object["recent_presets"].toArray()) {
            const auto path = entry.toString();
            if (recent.size() < maxRecentPresets && QFileInfo(path).isAbsolute()
                && path.endsWith(QStringLiteral(".slangp"), Qt::CaseInsensitive) && !recent.contains(path))
                recent.push_back(path);
        }
        engine.recent = std::move(recent);
        engine.savedOutputs = std::move(outputSettings);
        engine.overrides = std::move(parameterSettings);
        engine.enabled = enabled;
        for (const auto& output : engine.outputs)
            output->settings = engine.savedOutputs.value(output->id);
        // Keep a working runtime if restoring a replacement that may fail.
        if (!preset.isEmpty()) {
            // Restoring settings must not remove the control interface when a
            // previously selected file was moved or deleted. Report that real
            // loading error asynchronously, while keeping monitor controls live.
            const auto canonical = QFileInfo(preset).canonicalFilePath();
            const auto restored = canonical.isEmpty() ? QFileInfo(preset).absoluteFilePath() : canonical;
            engine.request(restored);
            // Import restores a known last-working selection. Preserve it in
            // exports while its initial GPU chains are being reconstructed.
            if (!engine.runtime && engine.preset.isEmpty())
                engine.preset = restored;
        } else {
            engine.preset.clear();
            engine.requested.clear();
            engine.lastParameters.clear();
            engine.reset(false);
        }
        engine.syncActivity();
        engine.redraw();
        engine.notify();
    });
}

gboolean wayland_shader_effect_set_outputs(WaylandShaderEffect* self, const gchar* json, GError** error)
{
    return mutate(self, error, [&](Engine& engine) {
        const auto document = parse(json);
        require(document.isArray(), QStringLiteral("Outputs must be a JSON array"));
        std::vector<std::unique_ptr<Output>> outputs;
        QSet<QString> ids;
        for (const auto& value : document.array()) {
            require(value.isObject(), QStringLiteral("Each output must be an object"));
            const auto object = value.toObject();
            require(object["id"].isString() && object["name"].isString(), QStringLiteral("Output IDs and names must be strings"));
            auto output = std::make_unique<Output>(&engine, engine.nextKey++);
            output->id = object["id"].toString();
            output->name = object["name"].toString();
            require(!output->id.isEmpty() && !ids.contains(output->id), QStringLiteral("Output IDs must be nonempty and unique"));
            ids.insert(output->id);
            const auto coordinate = [&](const char* key, int minimum) {
                require(object.contains(key), QStringLiteral("Output is missing geometry"));
                const double value = number(object, QString::fromLatin1(key), 0, minimum, std::numeric_limits<int>::max());
                require(std::floor(value) == value, QStringLiteral("Output geometry must use integer logical coordinates"));
                return static_cast<int>(value);
            };
            output->layout = { coordinate("x", std::numeric_limits<int>::min()), coordinate("y", std::numeric_limits<int>::min()),
                coordinate("width", 1), coordinate("height", 1) };
            require(object.contains("scale"), QStringLiteral("Output is missing its scale"));
            output->scale = number(object, QStringLiteral("scale"), 1, 0.01, 64);
            output->settings = engine.savedOutputs.value(output->id);
            outputs.push_back(std::move(output));
        }
        bool same = outputs.size() == engine.outputs.size();
        for (size_t i = 0; same && i < outputs.size(); ++i) {
            const auto &a = *outputs[i], &b = *engine.outputs[i];
            same = a.id == b.id && a.name == b.name && a.scale == b.scale
                && a.layout.x == b.layout.x && a.layout.y == b.layout.y
                && a.layout.width == b.layout.width && a.layout.height == b.layout.height;
        }
        if (same && !engine.mappingDirty)
            return;
        engine.reset(true);
        engine.outputs = std::move(outputs);
        engine.mappingDirty = true;
        engine.mapOutputs();
        engine.redraw();
        engine.notify();
    });
}

gboolean wayland_shader_effect_load_preset(WaylandShaderEffect* self, const gchar* path, GError** error)
{
    return mutate(self, error, [&](Engine& engine) {
        const QFileInfo file(text(path));
        require(file.isAbsolute() && file.isFile() && file.isReadable(), QStringLiteral("Preset must be an absolute readable file"));
        const auto canonical = file.canonicalFilePath();
        require(!canonical.isEmpty(), QStringLiteral("Unable to resolve preset filename"));
        engine.request(canonical);
    });
}

gboolean wayland_shader_effect_set_enabled(WaylandShaderEffect* self, gboolean enabled, GError** error)
{
    return mutate(self, error, [&](Engine& engine) {
        if (engine.enabled == bool(enabled))
            return;
        engine.enabled = enabled;
        engine.reset(enabled);
        engine.syncActivity();
    });
}

gboolean wayland_shader_effect_set_parameter(WaylandShaderEffect* self, const gchar* name, double value, GError** error)
{
    return mutate(self, error, [&](Engine& engine) {
        require(!engine.loading && !engine.preset.isEmpty(), QStringLiteral("No ready preset, or compilation is in progress"));
        const auto parameterName = text(name);
        QString runtimeError;
        if (engine.runtime) {
            require(engine.runtime->setParameter(parameterName, value, runtimeError), runtimeError);
            engine.lastParameters = engine.runtime->parameters();
        } else {
            // Bypass releases GPU history, not the loaded parameter contract.
            // Save edits against that metadata for the next runtime rebuild.
            const auto parameter = std::find_if(engine.lastParameters.begin(), engine.lastParameters.end(),
                [&](const auto& candidate) { return candidate.name == parameterName; });
            require(parameter != engine.lastParameters.end(), QStringLiteral("Unknown shader parameter '%1'").arg(parameterName));
            require(parameter->validateValue(value, runtimeError), runtimeError);
            parameter->value = static_cast<float>(value);
        }
        engine.overrides[engine.preset][parameterName] = value;
        engine.redraw();
        engine.notify();
    });
}

gboolean wayland_shader_effect_set_output_shader_enabled(WaylandShaderEffect* self, const gchar* id, gboolean enabled, GError** error)
{
    return mutate(self, error, [&](Engine& engine) {
        auto& output = engine.output(id);
        if (output.settings.shaderEnabled == bool(enabled))
            return;
        output.settings.shaderEnabled = enabled;
        output.clearHistory = true;
        output.firstFrame = -1;
        output.previousTime = 0;
        changed(engine, output);
    });
}

gboolean wayland_shader_effect_set_output_color_enabled(WaylandShaderEffect* self, const gchar* id, gboolean enabled, GError** error)
{
    return mutate(self, error, [&](Engine& engine) {
        auto& output = engine.output(id);
        if (output.settings.colorEnabled == bool(enabled))
            return;
        output.settings.colorEnabled = enabled;
        changed(engine, output);
    });
}

gboolean wayland_shader_effect_set_output_gamma(WaylandShaderEffect* self, const gchar* id, double value, GError** error)
{
    return mutate(self, error, [&](Engine& engine) {
        require(std::isfinite(value) && value >= OutputSettings::MinimumGamma && value <= OutputSettings::MaximumGamma,
            QStringLiteral("Gamma must be finite and between 0.1 and 5"));
        auto& output = engine.output(id);
        if (output.settings.gamma == value)
            return;
        output.settings.gamma = value;
        changed(engine, output);
    });
}

gboolean wayland_shader_effect_set_output_saturation(WaylandShaderEffect* self, const gchar* id, double value, GError** error)
{
    return mutate(self, error, [&](Engine& engine) {
        require(std::isfinite(value) && value >= OutputSettings::MinimumSaturation && value <= OutputSettings::MaximumSaturation,
            QStringLiteral("Saturation must be finite and between 0 and 2"));
        auto& output = engine.output(id);
        if (output.settings.saturation == value)
            return;
        output.settings.saturation = value;
        changed(engine, output);
    });
}

void wayland_shader_effect_reset_history(WaylandShaderEffect* self)
{
    try {
        get(self).reset(true);
    } catch (const std::exception& exception) {
        if (self && self->engine)
            self->engine->fail(QString::fromUtf8(exception.what()));
    } catch (...) {
        if (self && self->engine)
            self->engine->fail(QStringLiteral("Unable to reset native history"));
    }
}

void wayland_shader_effect_shutdown(WaylandShaderEffect* self)
{
    try {
        if (self && self->engine)
            self->engine->shutdown();
    } catch (const std::exception& exception) {
        g_warning("WaylandShader shutdown: %s", exception.what());
    } catch (...) {
        g_warning("WaylandShader shutdown: unknown native exception");
    }
}
