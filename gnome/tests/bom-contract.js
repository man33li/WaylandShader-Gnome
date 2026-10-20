// U+FEFF (BOM) contract: JSON string/key extraction and C-string arguments, compared to bom-contract-baseline.json.
// Capture on the ORIGINAL module only: gjs -m bom-contract.js <native-dir> --capture > bom-contract-baseline.json
// Check mode (omit --capture) accumulates every mismatch. Fresh unattached object per case;
// no stage/EGL exists to start a compile worker, and no bus is touched. Private fixtures normalize to <DIR>.
// Notation: B = one real U+FEFF character (raw bytes EF BB BF inside the JSON text); E = the six ASCII
// characters \ufeff (a JSON escape). Capture output escapes B as \ufeff and E as \\ufeff; the loaded oracle preserves both.
import GIRepository from 'gi://GIRepository?version=3.0';
import GLib from 'gi://GLib';
import Gio from 'gi://Gio';
const repository = GIRepository.Repository.dup_default();
repository.prepend_search_path(ARGV[0]);
repository.prepend_library_path(ARGV[0]);
const {default: W} = await import('gi://WaylandShader?version=1.0');
const capture = ARGV[1] === '--capture';
const B = '\ufeff', E = '\\ufeff';
const hex = c => '\\u' + c.charCodeAt(0).toString(16).padStart(4, '0');

// JSON-string bodies (text between the quotes) for one base word.
function variants(base) {
    const first = base[0], rest = base.slice(1), a = base.slice(0, 2), b = base.slice(2);
    return {
        plain: base, rawLead: B + base, escLead: E + base, rawDouble: B + B + base, escDouble: E + E + base,
        rawEsc: B + E + base, escRaw: E + B + base, rawMid: a + B + b, escMid: a + E + b,
        rawTrail: base + B, escTrail: base + E, rawLeadUEsc: B + hex(first) + rest, escLeadUEsc: E + hex(first) + rest,
        rawLeadEscLater: B + first + E + rest, escLeadRawLater: E + first + B + rest,
        rawOnly: B, escOnly: E, rawDoubleOnly: B + B, escDoubleOnly: E + E,
    };
}

const REDUCED = ['rawLead', 'escLead', 'rawDouble', 'rawMid', 'rawEsc', 'escRaw', 'rawLeadEscLater'];
const CHAIN = ['plain', 'rawLead', 'escLead', 'rawDouble', 'rawEsc', 'escRaw', 'rawLeadUEsc'];
const obj = pairs => '{' + pairs.map(([k, v]) => `"${k}":${v}`).join(',') + '}';
const MISSING = '/tmp/ws-bom-missing-dir/x.slangp';

const cases = [];
function add(id, steps, status) { cases.push({id, steps, status: status ?? steps.some(s => /^(set_outputs|load_preset|set_output_)/.test(s[0]))}); }
const imp = (id, source) => add(id, [['import_settings', source]]);

// ---- 1. Values and iterated keys, every encoding variant.
for (const [label, body] of Object.entries(variants('GAIN'))) {
    imp(`param-name:${label}`, `{"version":1,"parameters":{"/p":${obj([[body, '0.5']])}}}`);
    imp(`param-preset-key:${label}`, `{"version":1,"parameters":${obj([[label === 'plain' ? 'GAIN' : body, '{"GAIN":0.5}']])}}`);
    imp(`saved-output-key:${label}`, `{"version":1,"outputs":${obj([[body, '{"gamma":2}']])}}`);
}
for (const [label, body] of Object.entries(variants(MISSING))) {
    imp(`saved-preset:${label}`, `{"version":1,"preset":"${body}"}`);
    imp(`recent-one:${label}`, `{"version":1,"recent_presets":["${body}"]}`);
    imp(`recent-mid-list:${label}`, `{"version":1,"recent_presets":["/ws/a.slangp","${body}","/ws/b.slangp"]}`);
}
const recentBase = variants('/ws/dup.slangp');
for (const first of CHAIN) for (const second of CHAIN)
    imp(`recent-dup:${first}+${second}`, `{"version":1,"recent_presets":["${recentBase[first]}","${recentBase[second]}"]}`);
for (const [label, body] of Object.entries(variants('A'))) {
    const out = (idBody, nameBody) => obj([['id', `"${idBody}"`], ['name', `"${nameBody}"`], ['x', '0'], ['y', '0'], ['width', '640'], ['height', '480'], ['scale', '1']]);
    add(`output-id:${label}`, [['set_outputs', `[${out(body, 'N')}]`]]);
    add(`output-name:${label}`, [['set_outputs', `[${out('A', body)}]`]]);
    add(`output-both:${label}`, [['set_outputs', `[${out(body, body)}]`]]);
}

// ---- 2. Static lookup names: replace the name, and put it beside the ordinary key in both orders.
const top = [['version', '1'], ['enabled', 'false'], ['preset', `"${MISSING}"`], ['outputs', '{"o":{"gamma":2}}'],
    ['parameters', '{"/p":{"GAIN":0.5}}'], ['recent_presets', '["/ws/r.slangp"]']];
for (const [name, value] of top) {
    for (const [label, body] of Object.entries(variants(name))) {
        if (label === 'plain') continue;
        imp(`static-top:${name}:replace:${label}`, obj(name === 'version' ? [[body, '1']] : [['version', '1'], [body, value]]));
        // Same key with a distinct value: reveals which of the colliding keys the lookup reads.
        if (name !== 'version') imp(`static-top:${name}:only:${label}`, obj([[body, value]]));
    }
    for (const label of REDUCED) {
        const body = variants(name)[label], other = name === 'version' ? '2' : value;
        imp(`static-top:${name}:ordinary-first:${label}`, obj(name === 'version' ? [['version', '1'], [body, other]] : [['version', '1'], [name, value], [body, value]]));
        imp(`static-top:${name}:variant-first:${label}`, obj(name === 'version' ? [[body, '2'], ['version', '1']] : [['version', '1'], [body, value], [name, value]]));
    }
}
const entry = [['shaderEnabled', 'false'], ['colorEnabled', 'true'], ['gamma', '2'], ['saturation', '0.5']];
for (const [name, value] of entry) {
    for (const [label, body] of Object.entries(variants(name))) {
        if (label === 'plain') continue;
        imp(`static-output:${name}:replace:${label}`, `{"version":1,"outputs":{"o":${obj([[body, value]])}}}`);
    }
    for (const label of REDUCED) {
        const body = variants(name)[label], other = name === 'gamma' ? '3' : name === 'saturation' ? '1.5' : name === 'shaderEnabled' ? 'true' : 'false';
        imp(`static-output:${name}:ordinary-first:${label}`, `{"version":1,"outputs":{"o":${obj([[name, value], [body, other]])}}}`);
        imp(`static-output:${name}:variant-first:${label}`, `{"version":1,"outputs":{"o":${obj([[body, other], [name, value]])}}}`);
    }
}
const geometry = [['id', '"A"'], ['name', '"N"'], ['x', '0'], ['y', '0'], ['width', '640'], ['height', '480'], ['scale', '1']];
const outputWith = pairs => `[${obj(pairs)}]`;
for (const [name, value] of geometry) {
    for (const [label, body] of Object.entries(variants(name))) {
        if (label === 'plain') continue;
        add(`static-set-outputs:${name}:replace:${label}`, [['set_outputs', outputWith(geometry.map(([k, v]) => k === name ? [body, v] : [k, v]))]]);
    }
    for (const label of REDUCED) {
        const body = variants(name)[label], alt = name === 'id' ? '"B"' : name === 'name' ? '"M"' : value === '1' ? '2' : String(Number(value) + 7);
        add(`static-set-outputs:${name}:ordinary-first:${label}`, [['set_outputs', outputWith([...geometry, [body, alt]])]]);
        add(`static-set-outputs:${name}:variant-first:${label}`, [['set_outputs', outputWith([[body, alt], ...geometry])]]);
    }
}

// ---- 3. Collisions between two keys that may decode to the same key, both orders (values 1/2 identify the survivor).
for (const first of CHAIN) for (const second of CHAIN) {
    const k1 = variants('GAIN')[first], k2 = variants('GAIN')[second], tag = `${first}+${second}`;
    imp(`collide-param-name:${tag}`, `{"version":1,"parameters":{"/p":${obj([[k1, '1'], [k2, '2']])}}}`);
    imp(`collide-param-preset-key:${tag}`, `{"version":1,"parameters":${obj([[k1, '{"GAIN":1}'], [k2, '{"GAIN":2}']])}}`);
    imp(`collide-saved-output-key:${tag}`, `{"version":1,"outputs":${obj([[k1, '{"gamma":2}'], [k2, '{"gamma":3}']])}}`);
    imp(`collide-static-enabled:${tag}`, obj([['version', '1'], [variants('enabled')[first], 'false'], [variants('enabled')[second], 'true']]));
    const id1 = variants('A')[first], id2 = variants('A')[second];
    const row = id => obj([['id', `"${id}"`], ['name', '"N"'], ['x', '0'], ['y', '0'], ['width', '1'], ['height', '1'], ['scale', '1']]);
    add(`collide-output-ids:${tag}`, [['set_outputs', `[${row(id1)},${row(id2)}]`]]);
}

// ---- 4. Storage provenance: saved output key (raw/escaped) later matched by an output id (raw/escaped).
for (const saved of CHAIN) for (const id of CHAIN) {
    const row = obj([['id', `"${variants('A')[id]}"`], ['name', '"N"'], ['x', '0'], ['y', '0'], ['width', '640'], ['height', '480'], ['scale', '1']]);
    add(`provenance:saved-${saved}:output-${id}`, [['import_settings', `{"version":1,"outputs":${obj([[variants('A')[saved], '{"gamma":2}']])}}`], ['set_outputs', `[${row}]`]]);
}

// ---- 5. C-string arguments on fresh real objects.
const argSet = base => [base, B + base, B + B + base, base + B, base.slice(0, 1) + B + base.slice(1), E + base, B + E + base, B];
const argLabel = ['plain', 'lead', 'double', 'trail', 'mid', 'escaped', 'leadEscaped', 'only'];
const idSetups = Object.entries(variants('AB')).filter(([k]) => ['plain', 'rawLead', 'rawDouble', 'rawMid', 'escLead', 'rawTrail'].includes(k));
const setup = body => ['set_outputs', `[${obj([['id', `"${body}"`], ['name', '"N"'], ['x', '0'], ['y', '0'], ['width', '640'], ['height', '480'], ['scale', '1']])}]`];
for (const [setupLabel, body] of idSetups)
    argSet('AB').forEach((arg, i) => {
        add(`arg-gamma:setup-${setupLabel}:arg-${argLabel[i]}`, [setup(body), ['set_output_gamma', arg, 2]]);
        if (['plain', 'rawLead'].includes(setupLabel)) {
            add(`arg-shader:setup-${setupLabel}:arg-${argLabel[i]}`, [setup(body), ['set_output_shader_enabled', arg, false]]);
            add(`arg-color:setup-${setupLabel}:arg-${argLabel[i]}`, [setup(body), ['set_output_color_enabled', arg, true]]);
            add(`arg-saturation:setup-${setupLabel}:arg-${argLabel[i]}`, [setup(body), ['set_output_saturation', arg, 0.5]]);
        }
    });
// Without a loaded preset (compiling one is out of scope) set_parameter fails before text(name) is reached; kept as a control.
for (const [i, arg] of argSet('GAIN').entries()) add(`arg-parameter:${argLabel[i]}`, [['set_parameter', arg, 0.5]]);
// Whole-document arguments (leading, double, middle, raw/escaped) for both JSON entry points.
for (const [i, arg] of argSet('{}').entries()) {
    imp(`arg-import-document:${argLabel[i]}`, arg);
    add(`arg-set-outputs-document:${argLabel[i]}`, [['set_outputs', argSet('[]')[i]]]);
}
// load_preset: real, exclusive, readable temporary files (@DIR@ is substituted); no shader is compiled.
const loadArgs = {
    plain: '@DIR@/p.slangp', lead: B + '@DIR@/p.slangp', double: B + B + '@DIR@/p.slangp', trail: '@DIR@/p.slangp' + B,
    leadEscaped: E + '@DIR@/p.slangp', leadRelative: B + 'p.slangp', only: B, empty: '', directory: '@DIR@', leadDirectory: B + '@DIR@',
    midFile: '@DIR@/m' + B + 'id.slangp', leadMidFile: B + '@DIR@/m' + B + 'id.slangp', midDir: '@DIR@' + B + '/p.slangp',
    leadMissing: B + '@DIR@/missing.slangp', plainMissing: '@DIR@/missing.slangp', leadSymlink: B + '@DIR@/link.slangp', plainSymlink: '@DIR@/link.slangp',
};
for (const [label, arg] of Object.entries(loadArgs)) add(`load-preset:${label}`, [['load_preset', arg]]);

if (new Set(cases.map(c => c.id)).size !== cases.length) throw Error('duplicate case id');

// ---- Run.
const dir = GLib.dir_make_tmp('ws-bom-contract-XXXXXX');
const created = [];
const actual = [];
try {
    for (const name of ['p.slangp', 'm' + B + 'id.slangp']) {
        GLib.file_set_contents(`${dir}/${name}`, new Uint8Array(0));
        created.push(`${dir}/${name}`);
    }
    Gio.File.new_for_path(`${dir}/link.slangp`).make_symbolic_link('p.slangp', null);
    created.push(`${dir}/link.slangp`);
    for (const c of cases) {
        const record = {id: c.id, steps: c.steps, results: []};
        const effect = W.Effect.new();
        try {
            for (const [method, ...args] of c.steps) {
                try {
                    effect[method](...args.map(a => typeof a === 'string' ? a.replaceAll('@DIR@', dir) : a));
                    record.results.push({ok: true});
                } catch (error) {
                    const expected = typeof error.matches === 'function' && error.matches(GLib.quark_from_string('wayland-shader-error'), 1);
                    record.results.push(expected ? {error: error.message} : {unexpectedError: String(error)});
                }
            }
            record.settings = effect.export_settings();
            if (c.status) record.status = JSON.parse(effect.get_status());
        } finally { effect.shutdown(); }
        actual.push(JSON.parse(JSON.stringify(record).split(dir).join('<DIR>')));
    }
} finally {
    for (const path of created) GLib.unlink(path);
    GLib.rmdir(dir);
}
// Real U+FEFF is written as \ufeff and ASCII "\ufeff" as \\ufeff, so records show the distinction.
const render = value => JSON.stringify(value, null, 2).replaceAll(B, '\\ufeff');
if (capture) print(render(actual));
else {
    const [, bytes] = Gio.File.new_for_uri(import.meta.url).get_parent().get_child('bom-contract-baseline.json').load_contents(null);
    const expected = JSON.parse(new TextDecoder().decode(bytes));
    const failures = [];
    const byId = new Map(expected.map(r => [r.id, r]));
    for (const r of actual) {
        const want = byId.get(r.id);
        byId.delete(r.id);
        if (JSON.stringify(want) !== JSON.stringify(r)) failures.push(`${r.id}:\n  got  ${render(r).replace(/\s+/g, ' ')}\n  want ${want === undefined ? 'missing' : render(want).replace(/\s+/g, ' ')}`);
    }
    for (const id of byId.keys()) failures.push(`${id}: baseline record has no case`);
    if (failures.length) throw Error(`${failures.length} BOM contract mismatches:\n${failures.join('\n')}`);
    print(`BOM contract passed (${actual.length} cases).`);
}
