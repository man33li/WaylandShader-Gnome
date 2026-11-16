// CPU-only tests of the actual extension methods, with only GI/Shell boundaries replaced.
// No native module, D-Bus connection, settings file or compositor is loaded.
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import vm from 'node:vm';

const file = new URL('../extension/extension.js', import.meta.url);
const original = readFileSync(file, 'utf8');
const nativeImport = "await import('gi://WaylandShader?version=1.0')";
assert.equal(original.split(nativeImport).length, 2, 'exactly one native import boundary');
const source = original.replace(/^import .*;\n/gm, '')
    .replace('export default class', 'class').replace(nativeImport, 'mockNative') +
    '\nglobalThis.Subject = WaylandShaderExtension;';
const base = () => ({version: 1, enabled: false, preset: '/old.slangp',
    recent_presets: ['/recent.slangp'], parameters: {'/old.slangp': {Old: 1}, '/other.slangp': {Keep: 2}},
    outputs: {A: {gamma: 1}, B: {gamma: 1.2}}});
const profile = () => ({preset: '/movie.slangp', parameters: {Gain: 0.7}, outputs: {A: {gamma: 1.5}}});

function fixture({profiles = {}, preferred = '', configuration = base()} = {}) {
    const values = {configuration: JSON.stringify(configuration),
        profiles: typeof profiles === 'string' ? profiles : JSON.stringify(profiles), 'default-profile': preferred};
    const writes = [], imports = [], errors = [];
    let state = structuredClone(configuration);
    const settings = {get_string: key => values[key] ?? '', set_string(key, value) {
        values[key] = value; writes.push([key, value]);
    }};
    const effect = {connect: () => 1, disconnect() {}, set_outputs() {}, reset_history() {}, shutdown() {},
        export_settings: () => JSON.stringify(state),
        import_settings(text) {
            const candidate = JSON.parse(text);
            if (Object.values(candidate.outputs ?? {}).some(output => output.gamma > 5))
                throw Error('Invalid output gamma');
            state = candidate; imports.push(structuredClone(candidate)); return true;
        },
        get_status: () => JSON.stringify({enabled: state.enabled ?? false, active: false, loading: false,
            error: '', preset: state.preset ?? '', outputs: []})};
    const signal = {connect: () => 1, disconnect() {}};
    const context = {console: {error: (...args) => errors.push(args)},
        Extension: class {getSettings() {return settings;}},
        GLib: {build_filenamev: parts => parts.join('/'), Variant: class {
            constructor(type, value) {this.type = type; this.value = value;}
        }},
        GIRepository: {Repository: {dup_default: () => ({prepend_search_path() {}, prepend_library_path() {}})}},
        mockNative: {default: {Effect: {new: () => effect}}},
        Gio: {DBus: {session: {}}, DBusExportedObject: {wrapJSObject: () => ({export() {}, unexport() {}, emit_signal() {}})}},
        Main: {layoutManager: {...signal, monitors: []}, sessionMode: signal},
        global: {...signal, backend: {get_monitor_manager: () => ({...signal, get_monitors: () => []})},
            stage: {get_effect: () => null, add_effect_with_name() {}, remove_effect() {}, queue_redraw() {}},
            compositor: {disable_unredirect() {}, enable_unredirect() {}}}};
    vm.runInNewContext(source, context, {filename: file.pathname, timeout: 1000});
    const extension = new context.Subject();
    extension.path = '/mock-extension';
    extension._settings = settings; extension._effect = effect; extension._closing = false;
    extension._settingsLoaded = false;
    return {extension, values, writes, imports, errors, state: () => structuredClone(state)};
}
function call(fixture, method, name) {
    let result;
    const invocation = {return_value: value => {result = {type: value.type, value: [...value.value]};},
        return_dbus_error: (name, message) => {result = {error: name, message};}};
    assert.doesNotThrow(() => fixture.extension[method]([name], invocation));
    assert.ok(result, 'method must always reply'); return result;
}
let passed = 0;
async function test(name, body) {await body(); console.log(`PASS ${name}`); passed++;}
await test('overlay preserves enablement, recents, unrelated overrides and monitors', () => {
    const f = fixture({profiles: {Movie: profile()}});
    assert.deepEqual(call(f, 'loadProfileAsync', 'Movie'), {type: '(b)', value: [true]});
    const current = f.state();
    assert.equal(current.enabled, false);
    assert.deepEqual(current.recent_presets, ['/recent.slangp']);
    assert.deepEqual(current.parameters['/other.slangp'], {Keep: 2});
    assert.deepEqual(current.parameters['/movie.slangp'], {Gain: 0.7});
    assert.deepEqual(current.outputs, {A: {gamma: 1.5}, B: {gamma: 1.2}});
});
await test('save snapshots only current preset parameters and exact names', () => {
    const f = fixture();
    for (const name of [' Movie ', '__proto__', 'constructor']) {
        assert.equal(call(f, 'saveProfileAsync', name).type, '(b)');
        const saved = JSON.parse(f.values.profiles);
        assert.ok(Object.hasOwn(saved, name));
        assert.deepEqual(saved[name].parameters, {Old: 1});
        assert.equal(saved[name].preset, '/old.slangp');
    }
    assert.deepEqual(JSON.parse(f.extension.profiles()).profiles, [' Movie ', '__proto__', 'constructor']);
});
await test('invalid or unknown names reject without changing state', () => {
    const f = fixture();
    for (const name of ['', ' ', 'missing']) {
        const before = JSON.stringify(f.state());
        assert.match(call(f, 'loadProfileAsync', name).error, /Rejected$/);
        assert.equal(JSON.stringify(f.state()), before);
    }
});
await test('delete clears matching default but keeps unrelated profiles', () => {
    const f = fixture({profiles: {A: profile(), B: profile()}, preferred: 'A'});
    assert.equal(call(f, 'deleteProfileAsync', 'A').type, '(b)');
    assert.equal(f.values['default-profile'], '');
    assert.deepEqual(Object.keys(JSON.parse(f.values.profiles)), ['B']);
});
await test('default clear obeys shutdown and settings-error boundary', () => {
    const f = fixture({preferred: 'Movie'}); f.extension._closing = true;
    assert.match(call(f, 'setDefaultProfileAsync', '').error, /Unavailable$/);
    assert.equal(f.values['default-profile'], 'Movie');
    const healthy = fixture({preferred: 'Movie'});
    assert.deepEqual(call(healthy, 'setDefaultProfileAsync', ''), {type: '(b)', value: [true]});
    assert.equal(healthy.values['default-profile'], '');
});
await test('actual enable overlays login default without re-enabling master', async () => {
    const f = fixture({profiles: {Movie: profile()}, preferred: 'Movie'});
    await f.extension.enable();
    assert.equal(f.state().preset, '/movie.slangp'); assert.equal(f.state().enabled, false);
    assert.deepEqual(f.state().recent_presets, ['/recent.slangp']);
    assert.deepEqual(f.state().outputs.B, {gamma: 1.2});
    f.extension.disable();
});
await test('malformed profile containers and inherited names cannot choose a default', async () => {
    for (const profiles of ['[]', 'null', 'bad-json', '{}']) {
        const f = fixture({profiles, preferred: 'constructor'}); await f.extension.enable();
        assert.equal(f.state().preset, '/old.slangp'); f.extension.disable();
    }
});
await test('invalid stored default falls back to saved configuration', async () => {
    const broken = profile(); broken.outputs.A.gamma = 99;
    const f = fixture({profiles: {Broken: broken}, preferred: 'Broken'});
    await f.extension.enable();
    assert.equal(f.state().preset, '/old.slangp'); assert.equal(f.extension._closing, false);
    assert.ok(f.errors.length > 0); f.extension.disable();
});
await test('profile load returns its atomic target independently of later status', () => {
    const f = fixture({profiles: {Movie: profile()}});
    const result = call(f, 'loadProfileStatusAsync', 'Movie');
    assert.equal(result.type, '(s)');
    assert.equal(JSON.parse(result.value[0]).preset, '/movie.slangp');
    assert.match(call(f, 'loadProfileStatusAsync', 'missing').error, /Rejected$/);
});
console.log(`${passed} profile groups passed; mocked GI/Shell only, no native execution.`);
