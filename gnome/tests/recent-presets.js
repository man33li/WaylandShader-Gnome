// Saved history is advisory: malformed entries are dropped, valid ones keep
// their order, duplicates collapse, and at most ten survive a round trip.
import GIRepository from 'gi://GIRepository?version=3.0';

const repository = GIRepository.Repository.dup_default();
repository.prepend_search_path(ARGV[0]);
repository.prepend_library_path(ARGV[0]);
const {default: WaylandShader} = await import('gi://WaylandShader?version=1.0');
const effect = WaylandShader.Effect.new();
try {
    const valid = Array.from({length: 12}, (_, index) => `/presets/p${index}.slangp`);
    effect.import_settings(JSON.stringify({
        version: 1,
        enabled: false,
        recent_presets: [valid[0], 'relative.slangp', 7, '/presets/x.glslp', valid[0], '/presets/UPPER.SLANGP', ...valid.slice(1)],
    }));
    const expected = [valid[0], '/presets/UPPER.SLANGP', ...valid.slice(1, 9)];
    const exported = JSON.parse(effect.export_settings()).recent_presets;
    const reported = JSON.parse(effect.get_status()).recentPresets;
    for (const [name, value] of [['export', exported], ['status', reported]]) {
        if (JSON.stringify(value) !== JSON.stringify(expected))
            throw Error(`${name} history ${JSON.stringify(value)} != ${JSON.stringify(expected)}`);
    }
    effect.import_settings(JSON.stringify({version: 1, enabled: false, recent_presets: 'not-a-list'}));
    if (JSON.parse(effect.export_settings()).recent_presets.length !== 0)
        throw Error('Malformed history must import as empty, not fail or keep stale entries.');
    print('Recent preset history import/export filtering passed.');
} finally {
    effect.shutdown();
}
