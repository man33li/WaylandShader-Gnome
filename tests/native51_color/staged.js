import GIRepository from 'gi://GIRepository?version=3.0';
import System from 'system';

const repository = GIRepository.Repository.dup_default();
repository.prepend_search_path('/test/native');
repository.prepend_library_path('/test/native');
const {default: WaylandShader} = await import('gi://WaylandShader?version=1.0');
let effect = WaylandShader.Effect.new();
if (!effect)
    throw new Error('Native effect construction failed');
const status = JSON.parse(effect.get_status());
if (typeof status !== 'object' || status === null)
    throw new Error('Status is not an object');
effect.shutdown();
effect.run_dispose();
effect = null;
System.gc();
System.gc();
print('NEW_STAGED_GI_OK unattached lifecycle only; no paint/color/preset/Shell/desktop acceptance');
