#pragma once

#include <QString>

namespace WaylandShader::ControllerBackend {

inline const QString effectPath = QStringLiteral("/WaylandShader");
inline const QString effectInterface = QStringLiteral("org.waylandshader.Effect");

#ifdef WAYLANDSHADER_GNOME
inline constexpr bool watchExtensionLifecycle = true;
inline const QString service = QStringLiteral("org.gnome.Shell");
inline const QString compositor = QStringLiteral("GNOME Shell");
inline const QString desktopEnvironment = QStringLiteral("GNOME Shell / Mutter");
inline const QString effectDescription = QStringLiteral("WaylandShader GNOME extension");
inline const QString activationPath = QStringLiteral("/org/gnome/Shell");
inline const QString activationInterface = QStringLiteral("org.gnome.Shell.Extensions");
inline const QString activationMethod = QStringLiteral("EnableExtension");
inline const QString activationArgument = QStringLiteral("waylandshader@man33li.github.com");
inline const QString controllerName = QStringLiteral("waylandshader-gnome-controller");
inline const QString cliName = QStringLiteral("waylandshader-gnomectl");
inline const QString desktopFile = QStringLiteral("org.waylandshader.GnomeController");
inline const QString installationHint = QStringLiteral(
    " Install the WaylandShader GNOME extension and its native module built for this GNOME Shell version, "
    "and allow user extensions. On NixOS, a new login may be required. GNOME Shell will not be restarted.");
inline const QString activationHint = QStringLiteral(
    "Mutation commands may enable only the waylandshader@man33li.github.com GNOME extension.");
#else
inline constexpr bool watchExtensionLifecycle = false;
inline const QString service = QStringLiteral("org.kde.KWin");
inline const QString compositor = QStringLiteral("KWin");
inline const QString desktopEnvironment = QStringLiteral("KDE Plasma / KWin");
inline const QString effectDescription = QStringLiteral("WaylandShader KWin effect");
inline const QString activationPath = QStringLiteral("/Effects");
inline const QString activationInterface = QStringLiteral("org.kde.kwin.Effects");
inline const QString activationMethod = QStringLiteral("loadEffect");
inline const QString activationArgument = QStringLiteral("waylandshader");
inline const QString controllerName = QStringLiteral("waylandshader-controller");
inline const QString cliName = QStringLiteral("waylandshaderctl");
inline const QString desktopFile = QStringLiteral("org.waylandshader.Controller");
inline const QString installationHint = QStringLiteral(
    " Install the WaylandShader native plugin built for this KWin version; "
    "on NixOS, a new login may be required. KWin will not be restarted.");
inline const QString activationHint = QStringLiteral("Mutation commands may load only the waylandshader KWin effect.");
#endif

} // namespace WaylandShader::ControllerBackend
