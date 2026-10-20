// Private-bus fixture: owns org.gnome.Shell, exports /WaylandShader with the
// org.waylandshader.Effect interface of extension.js:10-22, and never answers a call.
// Run only inside dbus-run-session (tests/cli-golden.sh sets WS_CALLER_BUS):
//   WS_CALLER_BUS=$DBUS_SESSION_BUS_ADDRESS dbus-run-session -- gjs -m hang-shell.js
import Gio from 'gi://Gio';
import GLib from 'gi://GLib';
import System from 'system';

const caller = GLib.getenv('WS_CALLER_BUS');
const bus = GLib.getenv('DBUS_SESSION_BUS_ADDRESS');
if (caller === null || bus === null || bus === caller) {
    printerr('hang-shell.js refuses to run on the caller\'s session bus');
    System.exit(2);
}

const XML = `<node>
  <interface name="org.waylandshader.Effect">
    <method name="status"><arg type="s" direction="out"/></method>
    <method name="loadPreset"><arg type="s" direction="in"/><arg type="b" direction="out"/></method>
    <method name="setEnabled"><arg type="b" direction="in"/><arg type="b" direction="out"/></method>
    <method name="setParameter"><arg type="s" direction="in"/><arg type="d" direction="in"/><arg type="b" direction="out"/></method>
    <method name="setOutputShaderEnabled"><arg type="s" direction="in"/><arg type="b" direction="in"/><arg type="b" direction="out"/></method>
    <method name="setOutputColorEnabled"><arg type="s" direction="in"/><arg type="b" direction="in"/><arg type="b" direction="out"/></method>
    <method name="setOutputGamma"><arg type="s" direction="in"/><arg type="d" direction="in"/><arg type="b" direction="out"/></method>
    <method name="setOutputSaturation"><arg type="s" direction="in"/><arg type="d" direction="in"/><arg type="b" direction="out"/></method>
    <signal name="statusChanged"><arg type="s"/></signal>
  </interface>
</node>`;

// An *Async handler that never calls invocation.return_value leaves the call pending.
const never = () => {};
const exported = Gio.DBusExportedObject.wrapJSObject(XML, {
    statusAsync: never,
    loadPresetAsync: never,
    setEnabledAsync: never,
    setParameterAsync: never,
    setOutputShaderEnabledAsync: never,
    setOutputColorEnabledAsync: never,
    setOutputGammaAsync: never,
    setOutputSaturationAsync: never,
});

const loop = new GLib.MainLoop(null, false);
Gio.bus_own_name(Gio.BusType.SESSION, 'org.gnome.Shell', Gio.BusNameOwnerFlags.NONE,
    connection => exported.export(connection, '/WaylandShader'),
    null,
    () => loop.quit()); // name lost: nothing left to serve
loop.run();
