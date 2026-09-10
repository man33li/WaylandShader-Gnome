import GLib from 'gi://GLib';
import GIRepository from 'gi://GIRepository?version=3.0';
import System from 'system';

const repository = GIRepository.Repository.dup_default();
repository.prepend_search_path(ARGV[0]);
repository.prepend_library_path(ARGV[0]);
const {default: WaylandShader} = await import('gi://WaylandShader?version=1.0');
const effect = WaylandShader.Effect.new();
const loop = GLib.MainLoop.new(null, false);
let observed = null;
const signal = effect.connect('status-changed', (_effect, json) => {
    observed = JSON.parse(json);
    loop.quit();
});
let expired = false;
const deadline = GLib.timeout_add(GLib.PRIORITY_DEFAULT, 5000, () => {
    expired = true;
    loop.quit();
    return GLib.SOURCE_REMOVE;
});
try {
    effect.import_settings(JSON.stringify({version: 1, enabled: true, preset: ARGV[1]}));
    effect.load_preset(ARGV[1]);
    effect.set_enabled(false);
    System.gc();
    loop.run();
    if (!observed || observed.enabled !== false || observed.loading || observed.error)
        throw Error(`The retained effect did not apply the pending-preset disable: ${JSON.stringify(observed)}`);
    print('Retained GI object delivered the completed disable after garbage collection.');
} finally {
    if (!expired)
        GLib.Source.remove(deadline);
    effect.disconnect(signal);
    effect.shutdown();
}
