#include "shader_runtime.h"

#include <QCoreApplication>
#include <QFile>
#include <QImage>
#include <QTemporaryDir>
#include <array>
#include <bit>
#include <cmath>
#include <epoxy/gl.h>
#include <future>
#include <iostream>
#include <stdexcept>

using namespace WaylandShader;

static void require(bool condition, const QString& message)
{
    if (!condition) {
        throw std::runtime_error(message.toStdString());
    }
}

static GLuint makeTexture(bool source)
{
    GLuint texture = 0;
    glGenTextures(1, &texture);
    glBindTexture(GL_TEXTURE_2D, texture);
    glTexStorage2D(GL_TEXTURE_2D, source ? std::bit_width(64u) : 1, GL_RGBA16F, 64, 32);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_NEAREST);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_NEAREST);
    // Host contract: only the freshly written base level is exposed; the
    // patched librashader exposes the rest while generating requested mips.
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAX_LEVEL, 0);
    if (source) {
        std::array<float, 64 * 32 * 4> pixels;
        for (size_t i = 0; i < pixels.size(); i += 4) {
            pixels[i] = 0.25f;
            pixels[i + 1] = 0.5f;
            pixels[i + 2] = 0.75f;
            pixels[i + 3] = 1.0f;
        }
        glTexSubImage2D(GL_TEXTURE_2D, 0, 0, 0, 64, 32, GL_RGBA, GL_FLOAT, pixels.data());
    }
    return texture;
}

static void exerciseContext(EGLDisplay display, EGLConfig config, bool robust, const QString& preset,
    const QString& baseLevelPreset)
{
    const EGLint attributes[] = {
        EGL_CONTEXT_MAJOR_VERSION_KHR, 3, EGL_CONTEXT_MINOR_VERSION_KHR, 3,
        EGL_CONTEXT_OPENGL_PROFILE_MASK_KHR, EGL_CONTEXT_OPENGL_CORE_PROFILE_BIT_KHR,
        EGL_CONTEXT_FLAGS_KHR, robust ? EGL_CONTEXT_OPENGL_ROBUST_ACCESS_BIT_KHR : 0,
        EGL_CONTEXT_OPENGL_RESET_NOTIFICATION_STRATEGY_KHR,
        robust ? EGL_LOSE_CONTEXT_ON_RESET_KHR : EGL_NO_RESET_NOTIFICATION_KHR, EGL_NONE
    };
    const EGLContext context = eglCreateContext(display, config, EGL_NO_CONTEXT, attributes);
    const EGLint dimensions[] = { EGL_WIDTH, 1, EGL_HEIGHT, 1, EGL_NONE };
    const EGLSurface surface = eglCreatePbufferSurface(display, config, dimensions);
    require(context != EGL_NO_CONTEXT && surface != EGL_NO_SURFACE
            && eglMakeCurrent(display, surface, surface, context),
        QStringLiteral("Cannot create the required host OpenGL context"));
    std::cout << "GL " << glGetString(GL_VERSION) << "; robust=" << robust << '\n';
    const GLuint source = makeTexture(true);
    const GLuint destination = makeTexture(false);
    GLuint readback = 0;
    glGenFramebuffers(1, &readback);

    // A second load must not inherit temporal state from the previous chains.
    for (int cycle = 0; cycle < 2; ++cycle) {
        QString error;
        auto runtime = std::async(std::launch::async, [&] {
            return ShaderRuntime::load(display, context, preset, { 11, 22 }, {}, error);
        }).get();
        require(bool(runtime), error);
        const auto frame = [&](uintptr_t output, unsigned number, bool clear, std::array<float, 3> expected) {
            const ShaderFrame input { source, destination, GL_RGBA16F, QSize(64, 32), number, 60.0f, 17, clear };
            glBindFramebuffer(GL_FRAMEBUFFER, 0);
            glViewport(7, 9, 13, 15);
            require(runtime->render(output, input, error), error);
            require(eglGetCurrentContext() == context, QStringLiteral("Host EGL context was not restored"));
            GLint viewport[4] {};
            glGetIntegerv(GL_VIEWPORT, viewport);
            require(viewport[0] == 7 && viewport[1] == 9 && viewport[2] == 13 && viewport[3] == 15,
                QStringLiteral("Shader rendering changed the host viewport"));
            glBindFramebuffer(GL_FRAMEBUFFER, readback);
            glFramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_TEXTURE_2D, destination, 0);
            require(glCheckFramebufferStatus(GL_FRAMEBUFFER) == GL_FRAMEBUFFER_COMPLETE,
                QStringLiteral("Readback framebuffer is incomplete"));
            std::array<float, 4> pixel {};
            glReadPixels(32, 16, 1, 1, GL_RGBA, GL_FLOAT, pixel.data());
            require(glGetError() == GL_NO_ERROR, QStringLiteral("OpenGL rendering/readback failed"));
            for (size_t channel = 0; channel < 3; ++channel) {
                if (!std::isfinite(pixel[channel]) || std::abs(pixel[channel] - expected[channel]) >= 0.003f) {
                    throw std::runtime_error(QStringLiteral("Reload %1 output %2 frame %3 channel %4: got %5, expected %6")
                            .arg(cycle)
                            .arg(output)
                            .arg(number)
                            .arg(channel)
                            .arg(pixel[channel])
                            .arg(expected[channel])
                            .toStdString());
                }
            }
        };
        frame(11, 0, true, { 0.12549f, 0.25f, 0.125f });
        frame(11, 1, false, { 0.12549f, 0.75f, 0.25f });
        frame(11, 2, false, { 0.12549f, 0.75f, 0.375f });
        frame(22, 0, true, { 0.12549f, 0.25f, 0.125f });
        frame(11, 3, true, { 0.12549f, 0.25f, 0.125f });
        require(!runtime->setParameter(QStringLiteral("MISSING"), 1, error), QStringLiteral("Unknown parameter accepted"));
        require(!runtime->setParameter(QStringLiteral("GAIN"), 3, error), QStringLiteral("Out-of-range parameter accepted"));
        require(runtime->setParameter(QStringLiteral("GAIN"), 0.5, error), error);
        frame(11, 4, false, { 0.062745f, 0.375f, 0.125f });
        frame(22, 1, false, { 0.062745f, 0.375f, 0.125f });
        require(runtime->setParameter(QStringLiteral("GAIN"), 0.1, error), error);
        frame(11, 5, true, { 0.012549f, 0.025f, 0.0125f });
    }
    // Without mipmap_input, a high requested LOD must sample the live base
    // level, not allocated but uninitialized mip storage (VHSPro banding).
    const GLuint fresh = makeTexture(true);
    {
        QString error;
        auto runtime = std::async(std::launch::async, [&] {
            return ShaderRuntime::load(display, context, baseLevelPreset, { 11 }, {}, error);
        }).get();
        require(bool(runtime), error);
        require(runtime->render(11, { fresh, destination, GL_RGBA16F, QSize(64, 32), 0, 60.0f, 17, true }, error), error);
        glBindFramebuffer(GL_FRAMEBUFFER, readback);
        glFramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_TEXTURE_2D, destination, 0);
        std::array<float, 4> pixel {};
        glReadPixels(32, 16, 1, 1, GL_RGBA, GL_FLOAT, pixel.data());
        require(glGetError() == GL_NO_ERROR && std::abs(pixel[0] - 0.25f) < 0.003f
                && std::abs(pixel[1] - 0.5f) < 0.003f && std::abs(pixel[2] - 0.75f) < 0.003f,
            QStringLiteral("High-LOD sample read uninitialized mip storage: %1 %2 %3").arg(pixel[0]).arg(pixel[1]).arg(pixel[2]));
    }
    glDeleteTextures(1, &fresh);
    glDeleteFramebuffers(1, &readback);
    glDeleteTextures(1, &source);
    glDeleteTextures(1, &destination);
    eglMakeCurrent(display, EGL_NO_SURFACE, EGL_NO_SURFACE, EGL_NO_CONTEXT);
    eglDestroyContext(display, context);
    eglDestroySurface(display, surface);
}

int main(int argc, char** argv)
{
    QCoreApplication application(argc, argv);
    try {
        require(argc == 2, QStringLiteral("Pass the shader fixture directory"));
        if (!epoxy_has_egl_extension(EGL_NO_DISPLAY, "EGL_EXT_platform_base")
            || !epoxy_has_egl_extension(EGL_NO_DISPLAY, "EGL_MESA_platform_surfaceless")) {
            std::cerr << "These real-GL regressions require Mesa surfaceless EGL.\n";
            return 77;
        }
        QTemporaryDir directory;
        require(directory.isValid(), QStringLiteral("Cannot create the isolated fixture directory"));
        for (const char* file : { "temporal.slangp", "temporal.slang", "finish.slang" }) {
            require(QFile::copy(QString::fromLocal8Bit(argv[1]) + QLatin1Char('/') + QLatin1String(file),
                        directory.filePath(QLatin1String(file))),
                QStringLiteral("Cannot copy shader fixture"));
        }
        QFile basePreset(directory.filePath(QStringLiteral("base-level.slangp")));
        require(basePreset.open(QIODevice::WriteOnly), QStringLiteral("Cannot create base-level preset"));
        basePreset.write("shaders = 1\nshader0 = base-level.slang\nfilter_linear0 = true\nmipmap_input0 = false\n");
        basePreset.close();
        QFile baseShader(directory.filePath(QStringLiteral("base-level.slang")));
        require(baseShader.open(QIODevice::WriteOnly), QStringLiteral("Cannot create base-level shader"));
        baseShader.write(R"(#version 450
layout(std140, set = 0, binding = 0) uniform UBO { mat4 MVP; } global;
#pragma stage vertex
layout(location = 0) in vec4 Position;
layout(location = 1) in vec2 TexCoord;
layout(location = 0) out vec2 uv;
void main() { gl_Position = global.MVP * Position; uv = TexCoord; }
#pragma stage fragment
layout(location = 0) in vec2 uv;
layout(location = 0) out vec4 FragColor;
layout(set = 0, binding = 2) uniform sampler2D Source;
void main() { FragColor = textureLod(Source, uv, 3.0); }
)");
        baseShader.close();
        QImage lut(2, 2, QImage::Format_RGBA8888);
        lut.fill(QColor(128, 255, 255));
        require(lut.save(directory.filePath(QStringLiteral("lookup.png"))), QStringLiteral("Cannot create LUT fixture"));
        const EGLDisplay display = eglGetPlatformDisplayEXT(EGL_PLATFORM_SURFACELESS_MESA, EGL_DEFAULT_DISPLAY, nullptr);
        require(eglInitialize(display, nullptr, nullptr), QStringLiteral("EGL initialization failed"));
        require(eglBindAPI(EGL_OPENGL_API), QStringLiteral("Desktop OpenGL is unavailable"));
        const EGLint configAttributes[] = { EGL_SURFACE_TYPE, EGL_PBUFFER_BIT, EGL_RENDERABLE_TYPE, EGL_OPENGL_BIT, EGL_NONE };
        EGLConfig config = nullptr;
        EGLint count = 0;
        require(eglChooseConfig(display, configAttributes, &config, 1, &count) && count,
            QStringLiteral("No host OpenGL configuration"));
        for (bool robust : { false, true }) {
            exerciseContext(display, config, robust, directory.filePath(QStringLiteral("temporal.slangp")),
                directory.filePath(QStringLiteral("base-level.slangp")));
        }
        eglTerminate(display);
        std::cout << "Temporal isolation, resets, reloads, parameters, base-level sampling, and context sharing passed.\n";
        return 0;
    } catch (const std::exception& error) {
        std::cerr << error.what() << '\n';
        return 1;
    }
}
