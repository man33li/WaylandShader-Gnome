import GIRepository from 'gi://GIRepository?version=3.0';
import GLib from 'gi://GLib';
import Gio from 'gi://Gio';
const repository = GIRepository.Repository.dup_default();
repository.prepend_search_path(ARGV[0]);
repository.prepend_library_path(ARGV[0]);
const {default: W} = await import('gi://WaylandShader?version=1.0');
const cases = [];
function add(id, source, method = 'import_settings') { cases.push({id, source, method}); }
for (const source of ['', ' ', '\t\r\n', '{}', '[]', 'null', 'true', 'false', '1', '"text"', '}', ']', ',', ':', 'not json', '\v{}', '\f{}'])
    add(`root:${JSON.stringify(source)}`, source);
for (const root of ['{"version":1,"enabled":false}', '[]']) {
    for (const prefix of ['\ufeff', ' \ufeff', '\ufeff\ufeff', '\ufeff \t']) add(`bom:${JSON.stringify(prefix)}:${root}`, prefix + root);
    for (const suffix of [' ', '\t\r\n', '"', 'tru', '\\', '\ufeff', '{}', '[]', '1e', '/*x*/']) add(`tail:${root}:${JSON.stringify(suffix)}`, root + suffix);
}
add('bom-only', '\ufeff');
add('bom-output', '\ufeff[]', 'set_outputs');
add('bom-output-object', '\ufeff{}', 'set_outputs');
add('bom-inside', '{\ufeff"version":1}');
for (const n of ['.5', '-.5', '.5e1', '-.5E+1', '.', '-.', '-', '+1', '01', '-01', '00', '0.', '1.', '1.e2', '1e', '1e+', '1e-', '1e2', '0e9999', '-0e-9999', '1e4000', '1e-4000', '5e-324', '1e-324', '2.2250738585072014e-308', '1.7976931348623157e308', '1.7976931348623159e308', 'NaN', 'Infinity', '0x1']) {
    add(`number:${n}`, `{"version":1,"ignored":${n}}`);
    add(`array-number:${n}`, `[${n}]`);
}
add('version-leading-dot', '{"version":.5e1}');
for (const source of ['{', '{1:2}', "{'version':1}", '{true:1}', '{null:1}', '{[]:1}', '{"":1}', '{"version":1,"version":1}', '{"version":1,"":0}', '{"a"}', '{"a" 1}', '{"a":', '{"a":}', '{"a":]', '{"a":,}', '{"a":1', '{"a":1,', '{"a":1,}', '{"a":1 2}', '{"a":1,true:2}', '[', '[1', '[1,', '[1,]', '[}', '[1 2]', '[1 x', '[1 x]', '[1}', '[1]']) add(`structure:${source}`, source);
for (const text of ['', 'a\nb', 'a\rb', 'a\tb', '\\q', '\\u0000', '\\u+123', '\\u 123', '\\ué123', '\\ud800', '\\udfff', '\\ud83d\\ude00', '\\ud800\\u0041', '\\ud800\\ud800', 'é😀', '\\"', '\\\\', '\\b\\f\\n\\r\\t\\/'])
    add(`string:${JSON.stringify(text)}`, `{"version":1,"ignored":"${text}"}`);
for (const tail of ['', '\\', '\\u', '\\u1', '\\u12', '\\u123', '\\u1234', '\\uX', '\\q', '\\"']) add(`truncated:${JSON.stringify(tail)}`, '{"version":1,"ignored":"' + tail);
for (const text of ['\\u', '\\u1', '\\u12', '\\u123', '\\uXXXX']) add(`escape:${text}`, `{"version":1,"ignored":"${text}"}`);
for (const depth of [1, 2, 1023, 1024, 1025]) {
    add(`depth-array:${depth}`, '['.repeat(depth) + ']'.repeat(depth));
    add(`depth-object:${depth}`, '{"a":'.repeat(depth) + '0' + '}'.repeat(depth));
}
add('recent-high', '{"version":1,"recent_presets":["/x\\ud800.slangp"]}');
add('recent-low', '{"version":1,"recent_presets":["/x\\udfff.slangp"]}');
add('empty-duplicate', '{"version":1,"parameters":{"/p":{"":1,"x":1,"x":2}}}');
for (const value of ['{}', '[]', '1', '"x"', 'true', 'null']) {
    for (const tail of ['tru', '"', '\\', ':', 'x', '']) {
        add(`nested-object:${value}:${JSON.stringify(tail)}`, `{"version":1,"x":${value}${tail}}`);
        add(`nested-array:${value}:${JSON.stringify(tail)}`, `[${value}${tail}]`);
    }
}
for (const source of ['{"a":1,1:2}', '{"a":1,"b"', '{"a":1,"b" 2}', '{"a":1,"b":}', '{"a":1,"b":,}', '{"a":1,"b":"\\', '{"a":1,"b":"\\u', '[1e', '[1e+', '[1e-', '[.']) add(`context:${source}`, source);
// Whole arguments remain valid UTF-8; Qt's unknown escape consumes only the first byte.
for (const text of ['é', '€', '😀']) {
    add(`multibyte-escape-value:${text}`, `{"version":1,"ignored":"\\${text}"}`);
    add(`multibyte-escape-key:${text}`, `{"version":1,"\\${text}":0}`);
}
// Round 3 (R3-1), appended after all earlier records: raw U+FEFF (B, bytes EF BB BF) versus the ASCII escape \ufeff (E).
// Raw-versus-escaped matrices live in bom-contract.js; ids here spell the encoding out because JSON.stringify keeps B invisible.
{
    const B = '\ufeff', E = '\\ufeff';
    const forms = {plain: s => s, rawLead: s => B + s, escLead: s => E + s, rawDouble: s => B + B + s, escDouble: s => E + E + s,
        rawMid: s => s.slice(0, 2) + B + s.slice(2), escMid: s => s.slice(0, 2) + E + s.slice(2), rawOnly: () => B, escOnly: () => E,
        rawLeadEscLater: s => B + s[0] + E + s.slice(1)};
    for (const [form, f] of Object.entries(forms)) {
        add(`r3:version-key:${form}`, `{"${f('version')}":1}`);
        add(`r3:version-key-beside:${form}`, `{"version":1,"${f('version')}":2}`);
        add(`r3:param-name:${form}`, `{"version":1,"parameters":{"/p":{"${f('GAIN')}":0.5}}}`);
        add(`r3:param-preset-key:${form}`, `{"version":1,"parameters":{"${f('/p')}":{"GAIN":0.5}}}`);
        add(`r3:output-key:${form}`, `{"version":1,"outputs":{"${f('AB')}":{"gamma":2}}}`);
        add(`r3:gamma-key:${form}`, `{"version":1,"outputs":{"o":{"${f('gamma')}":2}}}`);
        add(`r3:preset-value:${form}`, `{"version":1,"preset":"${f('/tmp/ws-r3-missing-dir/x.slangp')}"}`);
        add(`r3:recent:${form}`, `{"version":1,"recent_presets":["${f('/tmp/ws-r3-missing-dir/x.slangp')}"]}`);
        add(`r3:set-outputs-id:${form}`, `[{"id":"${f('AB')}","name":"${f('N1')}","x":0,"y":0,"width":1,"height":1,"scale":1}]`, 'set_outputs');
    }
    for (const [order, pair] of [['raw-then-escaped', [B + 'GAIN', E + 'GAIN']], ['escaped-then-raw', [E + 'GAIN', B + 'GAIN']], ['raw-then-plain', [B + 'GAIN', 'GAIN']], ['plain-then-raw', ['GAIN', B + 'GAIN']]])
        add(`r3:collide-param-name:${order}`, `{"version":1,"parameters":{"/p":{"${pair[0]}":1,"${pair[1]}":2}}}`);
}
const parserErrors = new Set(['unterminated object', 'missing name separator', 'unterminated array', 'missing value separator', 'illegal value', 'illegal number', 'invalid escape sequence', 'invalid UTF8 string', 'unterminated string', 'object is missing after a comma', 'too deeply nested document', 'garbage at the end of the document']);
const actual = [];
for (const entry of cases) {
    const effect = W.Effect.new();
    const result = {...entry};
    try {
        try {
            effect[entry.method](entry.source);
            result.settings = effect.export_settings();
            result.parseError = '';
        } catch (error) {
            if (typeof error.matches !== 'function' || !error.matches(GLib.quark_from_string('wayland-shader-error'), 1))
                result.unexpectedError = String(error);
            result.error = error.message;
            // Schema failures prove successful JSON parsing; do not use them as parser errors.
            result.parseError = parserErrors.has(error.message) ? error.message : '';
        }
    } finally { effect.shutdown(); }
    actual.push(result);
}
if (ARGV[1] === '--capture') print(JSON.stringify(actual, null, 2));
else {
    const [, bytes] = Gio.File.new_for_uri(import.meta.url).get_parent().get_child('parser-corpus-baseline.json').load_contents(null);
    const expected = JSON.parse(new TextDecoder().decode(bytes));
    let mismatches = 0;
    for (let i = 0; i < Math.max(expected.length, actual.length); ++i) {
        if (JSON.stringify(expected[i]) !== JSON.stringify(actual[i])) {
            printerr(`FAIL ${actual[i]?.id ?? i}: ${JSON.stringify(actual[i])} != ${JSON.stringify(expected[i])}`);
            ++mismatches;
        }
    }
    if (mismatches) throw Error(`${mismatches} parser corpus mismatches`);
    print(`Parser corpus: ${actual.length} cases match.`);
}
