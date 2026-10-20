// Missing-preset path cleanup and recent-suffix folding, compared to path-contract-baseline.json.
// Capture on the original module: gjs -m path-contract.js <dir> --capture   (check mode: omit --capture).
import GIRepository from 'gi://GIRepository?version=3.0';
import GLib from 'gi://GLib';
import Gio from 'gi://Gio';
const repository = GIRepository.Repository.dup_default();
repository.prepend_search_path(ARGV[0]);
repository.prepend_library_path(ARGV[0]);
const {default: WaylandShader} = await import('gi://WaylandShader?version=1.0');
const capture = ARGV[1] === '--capture';
const paths = ['/a/./', '/a//b//', '/a/b/', '/a/b/../', '/nx/x.slangp/',
    '/a/b/.', '/a/b/..', '/a/b', '/a/b//.', '/a/b/./.', '/a/b/../.',
    '/', '//', '///', '/.', '/./', '/..', '/../', '/../..', '/../../', '/a/..', '/a/../', '/a/..//', '/a/../../', '/a/../..//',
    '/../a/', '/../../tmp//missing.slangp', '/../../tmp//missing.slangp/', '/./a/', '///a///', '/a/b/c/../../', '/a/b/c/../../..',
    '/...', '/.../', '/a/..../', '/a/b/...', '/a/b/.../', '/a/.hidden/', '/nx/x.SlAnGp/', '/nx/x.slangp',
    '/a/b/../../', '/a/b/../..//', '/a/b/../../../', '/a/../..', '/a/../../../', '/a/../../..//', '/../x/../', '/../../x/..//',
    '///a/../', '///a/..///', '///a/../..///', '///../x/../', '///../../x/..///', '/a///b/../../..///', '/a/../../x/', '/a/../../x//', '/a/.././..//'];
const recents = ['/a.ſlangp', '/a.ſLANGP', '/b.SlAnGp', '/c.slangp', '/d.SLANGP', '/e.slang', '/f.slangpx', '/g.slangp ', '/h.glslp',
    '/K.Kslangp', '/K.\u212Aslangp', '/x.SLANGPı', '/z.ſlangpſ', '/ſlangp', '/.ſlangp', '/w.ſlangp\u0131', '/dir.ſlangp/', 'rel.ſlangp', '.ſlangp', '/a.ſlangp'];
const actual = {};
function observe(label, source) {
    const instance = WaylandShader.Effect.new();
    try {
        try {
            instance.import_settings(source);
            const status = JSON.parse(instance.get_status());
            actual[label] = {settings: instance.export_settings(), preset: status.preset, requestedPreset: status.requestedPreset, loading: status.loading, recentPresets: status.recentPresets};
        } catch (error) {
            if (!error.matches(GLib.quark_from_string('wayland-shader-error'), 1)) throw error;
            actual[label] = {error: error.message};
        }
    } finally { instance.shutdown(); }
}
for (const path of paths) observe(`path:${path}`, JSON.stringify({version: 1, preset: path}));
for (const path of recents) observe(`recent:${path}`, JSON.stringify({version: 1, recent_presets: [path]}));
observe('recent:all', JSON.stringify({version: 1, recent_presets: recents}));
if (capture) print('PATH_CAPTURE=' + JSON.stringify(actual, null, 2));
else {
    const [, bytes] = Gio.File.new_for_uri(import.meta.url).get_parent().get_child('path-contract-baseline.json').load_contents(null);
    const expected = JSON.parse(new TextDecoder().decode(bytes));
    const failures = [];
    for (const label of new Set([...Object.keys(actual), ...Object.keys(expected)])) {
        if (JSON.stringify(actual[label]) !== JSON.stringify(expected[label]))
            failures.push(`${label}: ${JSON.stringify(actual[label])} != ${JSON.stringify(expected[label])}`);
    }
    if (failures.length) throw Error(`${failures.length} path/recent mismatches:\n${failures.join('\n')}`);
    print(`Path/recents contract passed (${Object.keys(actual).length} cases).`);
}
