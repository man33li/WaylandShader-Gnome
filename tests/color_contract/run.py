#!/usr/bin/env python3
"""Local constructor-contract harness; exact app fragments + explicit doubles, NOT native color/ABI proof."""
from pathlib import Path
import hashlib
import importlib.util
import json
import os
import re
import sys
import time

APP = Path(__file__).resolve().parents[2]
TRIAL = APP.parent
HERE = Path(__file__).resolve().parent
STORE = APP / '.law/color-contract'
SUPERVISORS = {'agent_builder.py': '46ab376b6957e3ea7dc3bea65a257e76a4a53ae5c3c9ac99c8e1e70f4a123d36',
               'agent_dispatch.py': '7a75fe27515e0e1b1c694bd285a1b4e11dcbc795d37f64e041d0872c54b852d8'}
NAMES = ('snippet_failure_preserves_configuration', 'constructor_failures_are_atomic',
         'failed_configuration_is_retried', 'cache_uses_all_inputs',
         'working_color_and_transform_order', 'color_teardown_releases_refs',
         'invalid_inputs_do_not_publish')


def sha(data):
    return hashlib.sha256(data).hexdigest()


def save(path, obj):
    with path.open('x') as f:
        json.dump(obj, f, indent=2)
        f.write('\n')


def supervisor():
    for name, digest in SUPERVISORS.items():
        assert sha((TRIAL / 'scripts' / name).read_bytes()) == digest, 'supervisor changed'
    spec = importlib.util.spec_from_file_location('constructor_owner', TRIAL / 'scripts/agent_builder.py')
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def fragments():
    path = APP / 'gnome/native/paint.odin'
    text = path.read_text()
    # Copy whole top-level declarations, NEVER rewrite the constructor body for testing.
    starts = list(re.finditer(r'^([A-Za-z_]\w*) ::', text, re.M))
    sections = {m[1]: text[m.start(): starts[i+1].start() if i+1 < len(starts) else len(text)]
                for i, m in enumerate(starts)}
    wanted = ['SNIPPET_DECL', 'SNIPPET_BODY', 'Surface', 'Color_Config', 'Resources',
              'cogl_error', 'new_pipeline', 'color_destroy', 'configure_color']
    for name in ('Surface', 'Resources', 'cogl_error', 'new_pipeline', 'configure_color'):
        assert name in sections, 'source declaration missing: ' + name
    selected = {name: sections[name] for name in wanted if name in sections}
    assert 'color_destroy' in selected, 'final contract requires actual application teardown, not generated baseline fallback'
    cleanup = 'fixture_cleanup :: proc(r: ^Resources) { color_destroy(&r.color) }\n'
    body = 'package main\nimport "core:fmt"\nimport glib "../glib"\n\n' + '\n'.join(selected.values()) + cleanup
    return body.encode(), {k: sha(v.encode()) for k, v in selected.items()}


def key():
    data, parts = fragments()
    bindings = {str(p.relative_to(APP)): sha(p.read_bytes()) for p in
                [APP / 'gnome/native/paint.odin', Path(__file__), *sorted((HERE/'fixtures').glob('*.odin'))]}
    bindings['odin'] = sha(Path('/home/manea/Odin/odin').read_bytes())
    # Source packages are compiler inputs too: executable identity alone is insufficient.
    for name in ('base', 'core', 'vendor', 'shared'):
        root = Path('/home/manea/Odin')/name
        for path in sorted(root.rglob('*')):
            rel = 'odin/'+str(path.relative_to(root.parent))
            if path.is_symlink():
                bindings[rel] = 'symlink:'+os.readlink(path)
            elif path.is_file():
                bindings[rel] = sha(path.read_bytes())
    # Full native type-check dependencies, not just the extracted constructor.
    bindings.update({str(p.relative_to(APP)): sha(p.read_bytes()) for p in (APP/'gnome').rglob('*.odin')})
    return sha(json.dumps(bindings, sort_keys=True).encode()), data, parts, bindings


def sandbox(view, work, command, compile_stage):
    args = ['/usr/bin/bwrap', '--unshare-all', '--unshare-user', '--disable-userns',
            '--cap-drop', 'ALL', '--die-with-parent', '--ro-bind', '/usr', '/usr',
            '--ro-bind', '/lib', '/lib', '--ro-bind', '/lib64', '/lib64', '--symlink', 'usr/bin', '/bin',
            '--proc', '/proc', '--dev', '/dev', '--size', '67108864', '--tmpfs', '/tmp',
            '--ro-bind', str(APP), '/src', '--ro-bind', str(view), '/view', '--bind' if compile_stage else '--ro-bind', str(work), '/out',
            '--dir', '/opt/odin', '--ro-bind', '/home/manea/Odin/odin', '/opt/odin/odin']
    for name in ('base', 'core', 'vendor', 'shared'):
        args += ['--ro-bind', '/home/manea/Odin/'+name, '/opt/odin/'+name]
    args += ['--chdir', '/out', '--clearenv', '--setenv', 'PATH', '/usr/bin:/bin',
             '--setenv', 'LANG', 'C.UTF-8', '--setenv', 'HOME', '/tmp', '--',
             '/usr/bin/taskset', '-c', ','.join(map(str, sorted(os.sched_getaffinity(0))[:4])),
             '/usr/bin/prlimit', '--as=8589934592', '--data='+str(2147483648 if compile_stage else 536870912),
             '--cpu='+('120' if compile_stage else '8'), '--fsize=67108864', '--nofile=256', '--core=0',
             '--', '/usr/bin/python3', '-I', '-B', '-c',
             'import os,sys; assert sys.stdin.buffer.read()==b"\\n"; '
             'assert not any(os.path.exists(p) for p in ["/run/user","/dev/dri","/home/manea"]); '
             'assert not any(os.getenv(k) for k in ["DISPLAY","WAYLAND_DISPLAY","DBUS_SESSION_BUS_ADDRESS"]); '
             'os.execv(sys.argv[1],sys.argv[1:])', *command]
    return args


def stage(b, root, view, work, name, command, compile_stage=False):
    assert not (STORE/'QUARANTINED.json').exists() and not (STORE/'ACTIVE.json').exists(), 'prior cleanup uncertainty; no automatic recovery'
    out = root/name
    out.mkdir(mode=0o700)
    args = sandbox(view, work, command, compile_stage)
    save(out/'command.json', args)
    # Persist ownership before supervision: an exception must not enable a later cached PASS.
    active = STORE/'ACTIVE.json'
    save(active, {'stage': str(out)})
    with b.caught_signals() as pending:
        status, _ = b.launch(args, b'\n', out, time.monotonic()+(150 if compile_stage else 12), pending)
    if status['cleanup'] != b.CLEAN:
        save(STORE/'QUARANTINED.json', {'stage': str(out), 'status': status})
        raise RuntimeError('UNCERTAIN cleanup: no automatic recovery')
    active.unlink()  # Only known cleanup releases this stage's ownership.
    assert not pending[0], 'interrupted; stop this operation'
    text = (out/'stdout.jsonl').read_text()
    err = (out/'stderr.log').read_text()
    print(text, end='')
    print(err, end='', file=sys.stderr)
    return (status['leader_exit'] == 0 and status['reason'] == 'awaiting-cleanup'
            and status['stderr_bytes'] == 0)


def build(b):
    assert not (STORE/'QUARANTINED.json').exists() and not (STORE/'ACTIVE.json').exists(), 'prior cleanup uncertainty; no cache success or automatic recovery'
    digest, data, parts, bindings = key()
    STORE.mkdir(parents=True, exist_ok=True, mode=0o700)
    for path in sorted(STORE.glob('build-*'), reverse=True):
        record = path/'success.json'
        if record.exists():
            old = json.loads(record.read_bytes())
            if old['key'] == digest:
                assert sha((path/'work/contract').read_bytes()) == old['binary_sha256'], 'cached binary changed'
                return path
    number = len(list(STORE.glob('build-*')))+1
    root = STORE/f'build-{number:02d}'
    root.mkdir(mode=0o700)
    view = root/'view'
    for name in ('native', 'glib'):
        (view/name).mkdir(parents=True, mode=0o700)
    (view/'native/production.odin').write_bytes(data)
    (view/'native/support.odin').write_bytes((HERE/'fixtures/support.odin').read_bytes())
    (view/'glib/glib.odin').write_bytes((HERE/'fixtures/glib.odin').read_bytes())
    work = root/'work'
    work.mkdir(mode=0o700)
    save(root/'inputs.json', {'key': digest, 'bindings': bindings, 'fragment_sha256': parts,
                              'proof': 'exact application declarations + explicit doubles, NOT native colors/ABI'})
    flags = ['-vet', '-strict-style', '-warnings-as-errors', '-thread-count:4', '-define:GL_DEBUG=false']
    if not stage(b, root, view, work, 'native-check', ['/opt/odin/odin', 'check', '/src/gnome/native', '-no-entry-point', *flags], True):
        raise SystemExit(1)
    if not stage(b, root, view, work, 'contract-build', ['/opt/odin/odin', 'build', '/view/native', '-out:/out/contract', *flags[:-1]], True):
        raise SystemExit(1)
    assert key()[0] == digest, 'source changed during build'
    save(root/'success.json', {'key': digest, 'binary_sha256': sha((work/'contract').read_bytes())})
    return root


def main():
    os.umask(0o077)
    assert len(sys.argv) in (2,3) and sys.argv[1] in ('build','test')
    name = sys.argv[2] if len(sys.argv) == 3 else 'all'
    if sys.argv[1] == 'test' and name != 'all' and name not in NAMES:
        print('Unknown contract test:', name, file=sys.stderr)
        return 2
    b = supervisor()
    root = build(b)
    if sys.argv[1] == 'build':
        print('PASS exact-source contract build + actual native package type-check (not link/native acceptance)')
        return 0
    runs = root/'runs'
    runs.mkdir(exist_ok=True, mode=0o700)
    n = len(list(runs.iterdir()))+1
    ok = stage(b, runs, root/'view', root/'work', f'{n:03d}-{name}', ['/out/contract', name])
    assert key()[0] == json.loads((root/'success.json').read_bytes())['key'], 'source changed during test'
    return 0 if ok else 1


if __name__ == '__main__':
    raise SystemExit(main())
