// Run only against a fresh disposable GNOME session, never the desktop bus.
// Usage: gjs -m parameter-bypass.js PRIVATE_GNOME_BUS_ADDRESS
import Gio from 'gi://Gio';
import GLib from 'gi://GLib';

if (ARGV.length !== 1)
    throw Error('Supply the D-Bus address of a fresh disposable GNOME session.');

const bus = Gio.DBusConnection.new_for_address_sync(ARGV[0],
    Gio.DBusConnectionFlags.AUTHENTICATION_CLIENT | Gio.DBusConnectionFlags.MESSAGE_BUS_CONNECTION,
    null, null);
const iface = 'org.waylandshader.Effect';
function call(method, signature = null, values = []) {
    return bus.call_sync('org.gnome.Shell', '/WaylandShader', iface, method,
        signature ? new GLib.Variant(signature, values) : null,
        null, Gio.DBusCallFlags.NONE, 10000, null).deepUnpack()[0];
}
function status() {
    return JSON.parse(call('status'));
}
function expect(condition, message) {
    if (!condition)
        throw Error(message);
}
function mutate(method, signature, values) {
    expect(call(method, signature, values) === true, `${method} rejected the operation`);
}
function settled() {
    const deadline = GLib.get_monotonic_time() + 10000000;
    do {
        const state = status();
        if (!state.loading)
            return state;
        GLib.usleep(10000);
    } while (GLib.get_monotonic_time() < deadline);
    throw Error('Preset compilation did not settle.');
}
function gain(state) {
    return state.parameters.find(parameter => parameter.name === 'GAIN')?.value;
}

const initial = status();
expect(!initial.preset && !initial.loading && !initial.active,
    'Refusing to overwrite an existing desktop preset or active effect; use a fresh disposable session.');
expect(initial.outputs.length > 0, 'The disposable compositor needs a virtual monitor.');
const directory = GLib.dir_make_tmp('waylandshader-bypass-XXXXXX');
const preset = GLib.build_filenamev([directory, 'probe.slangp']);
const shader = GLib.build_filenamev([directory, 'probe.slang']);
GLib.file_set_contents(preset, 'shaders = 1\nshader0 = probe.slang\n');
GLib.file_set_contents(shader, `#version 450
#pragma parameter GAIN "Gain" 1.0 0.25 2.0 0.05
layout(std140, set = 0, binding = 0) uniform UBO { mat4 MVP; } global;
layout(push_constant) uniform Parameters { float GAIN; } params;
#pragma stage vertex
layout(location = 0) in vec4 Position;
layout(location = 1) in vec2 TexCoord;
layout(location = 0) out vec2 uv;
void main() { gl_Position = global.MVP * Position; uv = TexCoord; }
#pragma stage fragment
layout(location = 0) in vec2 uv;
layout(location = 0) out vec4 FragColor;
layout(set = 0, binding = 2) uniform sampler2D Source;
void main() { FragColor = vec4(texture(Source, uv).rgb * params.GAIN, 1.0); }
`);
try {
    mutate('setEnabled', '(b)', [true]);
    mutate('setOutputShaderEnabled', '(sb)', [initial.outputs[0].id, true]);
    mutate('loadPreset', '(s)', [preset]);
    const loaded = settled();
    expect(!loaded.error && loaded.active && gain(loaded) === 1, 'The real probe preset did not become active.');
    mutate('setParameter', '(sd)', ['GAIN', 0.75]);
    mutate('setEnabled', '(b)', [false]);
    const bypassed = settled();
    expect(!bypassed.active && gain(bypassed) === 0.75, 'Bypass lost the last loaded parameter value.');
    mutate('setParameter', '(sd)', ['GAIN', 1.25]);
    expect(!status().active && gain(status()) === 1.25, 'A bypassed edit was lost or activated rendering.');
    for (const [name, value] of [['GAIN', 3], ['GAIN', NaN], ['UNKNOWN', 1]]) {
        let rejected = false;
        try {
            rejected = call('setParameter', '(sd)', [name, value]) !== true;
        } catch (error) {
            if (!Gio.DBusError.is_remote_error(error))
                throw error;
            expect(Gio.DBusError.get_remote_error(error).startsWith('org.waylandshader.Error.'),
                `Unexpected transport error: ${error.message}`);
            rejected = true;
        }
        expect(rejected && gain(status()) === 1.25, 'Invalid bypassed parameter edit changed the saved value.');
    }
    mutate('setEnabled', '(b)', [true]);
    const rebuilt = settled();
    expect(!rebuilt.error && rebuilt.active && gain(rebuilt) === 1.25,
        'Re-enabling did not apply the parameter edited while bypassed.');
    print('PASS: bypassed edits remain inactive, reject invalid values, and survive the real GPU-runtime rebuild.');
} finally {
    call('setEnabled', '(b)', [false]);
    GLib.unlink(preset);
    GLib.unlink(shader);
    GLib.rmdir(directory);
    bus.close_sync(null);
}
