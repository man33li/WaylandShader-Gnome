import GIRepository from 'gi://GIRepository?version=3.0';
import GLib from 'gi://GLib';
import Gio from 'gi://Gio';
const repository = GIRepository.Repository.dup_default();
repository.prepend_search_path(ARGV[0]);
repository.prepend_library_path(ARGV[0]);
const {default: WaylandShader} = await import('gi://WaylandShader?version=1.0');
const capture = ARGV[1] === '--capture';
// Recorded by Builder from b223c1a, before checking the Odin implementation.
const expected = {
    initialStatus: '{"active":false,"enabled":true,"error":"","loading":false,"outputs":[],"parameters":[],"preset":"","recentPresets":[],"requestedPreset":""}',
    initialSettings: '{"enabled":true,"outputs":{},"parameters":{},"preset":"","recent_presets":[],"version":1}',
    missingScale: 'Output is missing its scale',
    duplicateId: 'Output IDs must be nonempty and unique',
    fractionGeometry: 'Output geometry must use integer logical coordinates',
    zeroWidth: 'width is outside its allowed range',
    'gamma0.05': 'Gamma must be finite and between 0.1 and 5',
    'gamma5.1': 'Gamma must be finite and between 0.1 and 5',
    gammaNaN: 'Gamma must be finite and between 0.1 and 5',
    'saturation-1': 'Saturation must be finite and between 0 and 2',
    'saturation2.1': 'Saturation must be finite and between 0 and 2',
    saturationNaN: 'Saturation must be finite and between 0 and 2',
    unknownOutput: 'Unknown active output: missing',
    noPreset: 'No ready preset, or compilation is in progress',
    relativeLoad: 'Preset must be an absolute readable file',
    nonObjectImport: 'Configuration must be a JSON object',
    versionImport: 'Unsupported settings version',
    relativeImport: 'Saved preset must be an absolute filename',
    jsonTrailing: 'garbage at the end of the document',
    jsonObjectEnd: 'unterminated object',
    jsonArrayEnd: 'unterminated array',
    jsonNameSeparator: 'missing name separator',
    jsonValueSeparator: 'unterminated object',
    jsonComma: 'object is missing after a comma',
    jsonStringEnd: 'unterminated string',
    jsonEscape: 'Unsupported settings version',
    jsonDepth: 'too deeply nested document',
    jsonOutputsTrailing: 'garbage at the end of the document',
    jsonOutputsDepth: 'too deeply nested document',
    jsonVTab: 'illegal number',
    jsonFormFeed: 'illegal number',
    jsonPresetEscape: 'Saved preset must be an absolute filename',
    jsonParameterDepth1024: 'Saved parameters must have finite numeric values',
    jsonParameterDepth1025: 'too deeply nested document',
    fixedSettings: '{"enabled":false,"outputs":{"A":{"colorEnabled":true,"gamma":0.1,"saturation":2,"shaderEnabled":true},"B":{"colorEnabled":false,"gamma":1,"saturation":1,"shaderEnabled":false}},"parameters":{"/presets/é😀.slangp":{"é":1e-07,"😀":0.5}},"preset":"","recent_presets":["/presets/é😀.slangp","/presets/other.SLANGP"],"version":1}',
    fixedStatus: '{"active":false,"enabled":false,"error":"","loading":false,"outputs":[{"colorActive":false,"colorEnabled":true,"gamma":0.1,"id":"A","name":"Monitor A","saturation":2,"shaderActive":false,"shaderEnabled":true},{"colorActive":false,"colorEnabled":false,"gamma":1,"id":"B","name":"Monitor B","saturation":1,"shaderActive":false,"shaderEnabled":false}],"parameters":[],"preset":"","recentPresets":["/presets/é😀.slangp","/presets/other.SLANGP"],"requestedPreset":""}',
    'stopped:set_outputs': 'The native effect has shut down',
    'stopped:import_settings': 'The native effect has shut down',
    'stopped:load_preset': 'The native effect has shut down',
    'stopped:set_enabled': 'The native effect has shut down',
    'stopped:set_parameter': 'The native effect has shut down',
    'stopped:set_output_shader_enabled': 'The native effect has shut down',
    'stopped:set_output_color_enabled': 'The native effect has shut down',
    'stopped:set_output_gamma': 'The native effect has shut down',
    'stopped:set_output_saturation': 'The native effect has shut down',
};
// Rework observations are pinned only from the original native module.
const [, baselineBytes] = Gio.File.new_for_uri(import.meta.url).get_parent().get_child('native-rework-baseline.json').load_contents(null);
const reworkExpected = JSON.parse(new TextDecoder().decode(baselineBytes));
const reworkActual = {};
const reworkCases = [
    ['trailingDecimal', '{"version":1.}'],
    ['underflow', '{"version":1,"ignored":1e-4000}'],
    ['overflow', '{"version":1,"ignored":1e4000}'],
    ['signedUnicodeEscape', '{"version":1,"ignored":"\\u+123"}'],
    ['spaceUnicodeEscape', '{"version":1,"ignored":"\\u 123"}'],
    ['nonAsciiUnicodeEscape', '{"version":1,"ignored":"\\ué123"}'],
    ['rawNewline', '{"version":1,"ignored":"a\nb"}'],
    ['missingValue', '{"version":}'],
    ['leadingZeroObject', '{"version":01}'],
    ['leadingZeroArray', '[01]'],
    ['keywordBoundary', '{"version":1,"ignored":truefalse}'],
    ['missingObjectEnd', '{"a":'],
    ['arrayTrailingComma', '[1,]'],
    ['nestedMissingValue', '{"a":[}'],
    ['loneHigh', '{"version":1,"recent_presets":["/x\\ud800.slangp"]}'],
    ['loneLow', '{"version":1,"recent_presets":["/x\\udfff.slangp"]}'],
    ['surrogateOrdering', '{"version":1,"parameters":{"/p":{"\\ud800":1,"😀":2,"\\ue000":3}}}'],
    ...['0.0005', '0.0001', '1234567.5', '12345678.25', '1e16', '9.2e18',
        '9223372036854776000', '123456789012345680000', '1.0', '-0.0', '1e-7',
        '0.5', '1e20', '1.0000001e-7', '9007199254740991', '0.10000000149011612']
        .map(n => [`number:${n}`, `{"version":1,"parameters":{"/p.slangp":{"GAIN":${n}}}}`]),
];
function observeImport(label, source, paths = false) {
    const instance = WaylandShader.Effect.new();
    try {
        try {
            instance.import_settings(source);
            reworkActual[label] = {settings: instance.export_settings()};
            if (paths) {
                const status = JSON.parse(instance.get_status());
                reworkActual[label].paths = {preset: status.preset, requestedPreset: status.requestedPreset, loading: status.loading};
            }
        } catch (error) {
            if (!error.matches(GLib.quark_from_string('wayland-shader-error'), 1)) throw error;
            reworkActual[label] = {error: error.message};
        }
    } finally { instance.shutdown(); }
}
for (const [label, source] of reworkCases) observeImport(label, source);
for (const path of ['/tmp/ws-acceptance-absent/../missing.slangp',
    '/nonexistent//a/./b/../c.slangp', '/../../tmp//missing.slangp']) {
    observeImport(`missing:${path}`, JSON.stringify({version: 1, preset: path}), true);
}
// Shell printf operates on bytes; the private directory prevents fixture collisions.
const fixture = GLib.dir_make_tmp('waylandshader-native-path-XXXXXX');
try {
    const [ok, bytes, stderr, status] = GLib.spawn_sync(null,
        ['sh', '-c', 'target=$(printf "%s/rawbad\\\\377.slangp" "$1"); : > "$target"; ln -s "$target" "$1/link.slangp"; readlink "$1/link.slangp"', 'fixture', fixture],
        null, GLib.SpawnFlags.SEARCH_PATH, null);
    if (!ok || status !== 0 || !bytes.includes(255)) throw Error('Fixture target must contain actual byte FF');
    const link = `${fixture}/link.slangp`;
    const normalize = value => value.replaceAll(fixture, '<fixture>');
    const instance = WaylandShader.Effect.new();
    try {
        instance.load_preset(link);
        reworkActual.rawFilenameLoad = normalize(instance.get_status());
    } finally { instance.shutdown(); }
    observeImport('rawFilenameRestore', JSON.stringify({version: 1, preset: link}), true);
    reworkActual.rawFilenameRestore = JSON.parse(normalize(JSON.stringify(reworkActual.rawFilenameRestore)));
} finally {
    const [, , , status] = GLib.spawn_sync(null,
        ['sh', '-c', 'rm -f -- "$1/link.slangp" "$1"/rawbad*.slangp; rmdir -- "$1"', 'cleanup', fixture],
        null, GLib.SpawnFlags.SEARCH_PATH, null);
    if (status !== 0) throw Error('Could not remove private filename fixture');
}
if (capture) print('REWORK_CAPTURE=' + JSON.stringify(reworkActual));
else {
    for (const label of Object.keys(reworkActual)) {
        if (JSON.stringify(reworkActual[label]) !== JSON.stringify(reworkExpected[label]))
            throw Error(`${label}: ${JSON.stringify(reworkActual[label])} != ${JSON.stringify(reworkExpected[label])}`);
    }
}
const actual = {};
const effect = WaylandShader.Effect.new();
if (!effect) throw Error('Effect.new returned null');
const signals = [];
effect.connect('status-changed', (_self, status) => {
    if (effect.get_status() !== status) throw Error('Reentrant status differs from emitted status');
    signals.push(status);
});
function reject(label, fn) {
    try { fn(); } catch (error) {
        if (!error.matches(GLib.quark_from_string('wayland-shader-error'), 1))
            throw Error(`${label}: wrong error domain/code: ${error}`);
        actual[label] = error.message;
        return;
    }
    throw Error(`${label}: expected GError`);
}
const output = {id: 'A', name: 'Monitor A', x: 0, y: 0, width: 640, height: 480, scale: 1};
try {
    actual.initialStatus = effect.get_status();
    actual.initialSettings = effect.export_settings();
    const missing = {...output}; delete missing.scale;
    reject('missingScale', () => effect.set_outputs(JSON.stringify([missing])));
    reject('duplicateId', () => effect.set_outputs(JSON.stringify([output, output])));
    reject('fractionGeometry', () => effect.set_outputs(JSON.stringify([{...output, x: 0.5}])));
    reject('zeroWidth', () => effect.set_outputs(JSON.stringify([{...output, width: 0}])));
    effect.set_outputs(JSON.stringify([output, {...output, id: 'B', name: 'Monitor B', x: 640}]));
    for (const value of [0.05, 5.1, NaN])
        reject(`gamma${value}`, () => effect.set_output_gamma('A', value));
    for (const value of [-1, 2.1, NaN])
        reject(`saturation${value}`, () => effect.set_output_saturation('A', value));
    reject('unknownOutput', () => effect.set_output_gamma('missing', 1));
    reject('noPreset', () => effect.set_parameter('GAIN', 1));
    reject('relativeLoad', () => effect.load_preset('relative.slangp'));
    reject('nonObjectImport', () => effect.import_settings('[]'));
    reject('versionImport', () => effect.import_settings('{"version":2}'));
    reject('relativeImport', () => effect.import_settings('{"version":1,"preset":"relative.slangp"}'));
    for (const [label, source] of [
        ['jsonTrailing', '{"version":1} x'], ['jsonObjectEnd', '{'], ['jsonArrayEnd', '['],
        ['jsonNameSeparator', '{"a" 0}'], ['jsonValueSeparator', '{"a":0 "b":1}'],
        ['jsonComma', '{"a":0,}'], ['jsonStringEnd', '{"a":"unterminated}'],
        ['jsonEscape', '{"a":"\\q"}'],
        ['jsonPresetEscape', '{"version":1,"preset":"relative\\q"}'],
        ['jsonVTab', '\v{}'], ['jsonFormFeed', '\f{}'],
        ['jsonDepth', '['.repeat(1025) + '0' + ']'.repeat(1025)],
    ]) reject(label, () => effect.import_settings(source));
    effect.import_settings('{"version":1,"enabled":false,"enabled":true,"parameters":{"":{"GAIN":1}}}');
    const duplicate = JSON.parse(effect.export_settings());
    if (duplicate.enabled !== true || duplicate.parameters['']?.GAIN !== 1)
        throw Error('JSON duplicate last-wins or empty-key preservation differs from Qt');
    const nested = depth => '['.repeat(depth) + '0' + ']'.repeat(depth);
    effect.import_settings('{"version":1,"enabled":false,"ignored":' + nested(1023) + '}');
    reject('jsonParameterDepth1024', () => effect.import_settings('{"version":1,"parameters":{"p":{"GAIN":' + nested(1021) + '}}}'));
    reject('jsonParameterDepth1025', () => effect.import_settings('{"version":1,"parameters":{"p":{"GAIN":' + nested(1022) + '}}}'));
    const inventory = JSON.stringify([output, {...output, id: 'B', name: 'Monitor B', x: 640}]);
    effect.set_outputs(inventory.replace('"id":"A"', '"id":"ignored","id":"A","":7'));
    if (JSON.parse(effect.get_status()).outputs[0].id !== 'A')
        throw Error('Output JSON duplicate key must keep its last value');
    effect.set_outputs(inventory.replace('"scale":1', '"scale":1,"ignored":' + nested(1022)));
    reject('jsonOutputsTrailing', () => effect.set_outputs('[] true'));
    reject('jsonOutputsDepth', () => effect.set_outputs(nested(1025)));
    effect.import_settings(JSON.stringify({version: 1, enabled: false, outputs: {
        A: {gamma: 0.1, saturation: 2, shaderEnabled: true, colorEnabled: true},
        B: {gamma: 1, saturation: 1, shaderEnabled: false, colorEnabled: false},
    }, parameters: {'/presets/é😀.slangp': {'é': 1e-7, '😀': 0.5}},
    recent_presets: ['/presets/é😀.slangp', '/presets/other.SLANGP']}));
    actual.fixedSettings = effect.export_settings();
    actual.fixedStatus = effect.get_status();
    if (signals.length !== 0) throw Error('Status emitted synchronously during mutation');
    const context = GLib.MainContext.default();
    while (context.pending()) context.iteration(false);
    if (signals.length !== 1 || signals[0] !== actual.fixedStatus)
        throw Error('Status changes must coalesce to one idle emission');
    effect.set_enabled(false);
    while (context.pending()) context.iteration(false);
    if (signals.length !== 1) throw Error('Unchanged status emitted again');
    effect.shutdown();
    effect.shutdown();
    for (const [name, args] of [
        ['set_outputs', ['[]']], ['import_settings', ['{}']], ['load_preset', ['/missing']],
        ['set_enabled', [true]], ['set_parameter', ['GAIN', 1]],
        ['set_output_shader_enabled', ['A', true]], ['set_output_color_enabled', ['A', true]],
        ['set_output_gamma', ['A', 1]], ['set_output_saturation', ['A', 1]],
    ]) reject(`stopped:${name}`, () => effect[name](...args));
    if (capture) print(JSON.stringify(actual, null, 4));
    else {
        for (const key of Object.keys(expected))
            if (actual[key] !== expected[key]) throw Error(`${key}: ${JSON.stringify(actual[key])} != ${JSON.stringify(expected[key])}`);
        print('Native byte/error contract passed.');
    }
} finally { effect.shutdown(); }
