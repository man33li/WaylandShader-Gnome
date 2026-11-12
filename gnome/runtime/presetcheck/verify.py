#!/usr/bin/env python3
"""Scoped acceptance commands; successful GPU receipts are read, never replayed."""
from pathlib import Path
import hashlib
import importlib.util
import json
import subprocess
import sys

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[3]
OUT = ROOT/'evidence/baseline/local-shader-use-20261112'
OWNER = ROOT/'tasks/local-shader-use-v2-20261112.py'
TESTS = ('nearest_spatial_and_rejection','real_multipass_lut_cyberlab','isolation_and_cleanup')


def sha(path): return hashlib.sha256(path.read_bytes()).hexdigest()


def inputs():
    manifest = HERE/'verification-inputs-v2.json'
    assert manifest.read_bytes() == (OUT/'inputs-v2.json').read_bytes(), 'scoped inputs changed'
    m = json.loads(manifest.read_bytes())
    for row in m['files']:
        assert sha(Path(row['path'])) == row['sha256'], row['path']
    return m


def run(*args):
    subprocess.run(['/usr/bin/python3','-I','-B',str(OWNER),*args],check=True,timeout=210)


def check_receipts(ids):
    m = inputs()
    records = []
    for key in ids:
        record = json.loads((OUT/('run-'+key)/'observations.json').read_bytes())
        assert record['manifest_sha256'] == sha(OUT/'inputs-v2.json') and record['known_cleanup']
        assert record['preview_sha256'] == sha(OUT/('run-'+key)/'artifact')
        stage = OUT/('run-'+key)
        assert record['stdout_sha256'] == sha(stage/'stdout.jsonl') and record['status_sha256'] == sha(stage/'status.json')
        status = json.loads((stage/'status.json').read_bytes())
        assert status == record['status'] and status['leader_exit'] == 0 and status['reason'] == 'awaiting-cleanup' and status['stderr_bytes'] == 0
        assert status['cleanup'] == 'owned-group-signalled-children-reaped' and record['pending_stop'] == 0
        spec = importlib.util.spec_from_file_location('current_preset_protocol',ROOT/'scripts/local_shader_use.py')
        checks = importlib.util.module_from_spec(spec); spec.loader.exec_module(checks)
        parsed = checks.receipt((stage/'stdout.jsonl').read_text(),'/shaders/'+m['presets'][key]['path'],key == 'nearest')
        assert parsed == record['observations'] and len(parsed['frames']) == 8
        assert not any((OUT/marker).exists()for marker in ('ACTIVE.json','QUARANTINED.json'))
        records.append(record)
    return records


def nearest_spatial_and_rejection():
    record = check_receipts(['nearest'])[0]
    assert len(record['observations']['rejected']) == 1
    assert all(0 <= frame[3] < .003 for frame in record['observations']['frames'])


def real_multipass_lut_cyberlab():
    records = check_receipts(['ntsc','phosphorlut','guest','cyberlab'])
    assert len(records) == 4 and all(len(r['observations']['frames']) == 8 for r in records)
    assert all(int(r['observations']['LOADED'][0]) > 1 for r in records)


def isolation_and_cleanup():
    records = check_receipts(list(inputs()['presets']))
    assert len(records) == 5 and all(r['known_cleanup'] and r['pending_stop'] == 0 for r in records)
    assert all(r['status']['leader_exit'] == 0 and r['status']['cleanup'] == 'owned-group-signalled-children-reaped' for r in records)


def main():
    mode = sys.argv[1]; inputs()
    if mode == 'build':
        if not (OUT/'build-accepted.json').exists():
            attempt = len([p for p in OUT.glob('build-*')if p.is_dir()])+1
            run('build',str(attempt))
        record = json.loads((OUT/'build-accepted.json').read_bytes())
        assert record['manifest_sha256'] == sha(OUT/'inputs-v2.json') and record['sha256'] == sha(Path(record['binary']))
    elif mode == 'verify':
        subprocess.run(['/usr/bin/python3','-I','-B','-m','unittest','discover','-s',str(ROOT/'tests'),'-p','test_local_shader_use.py','-v'],cwd=ROOT,check=True,timeout=30)
    elif mode == 'test':
        name = sys.argv[2]
        if name == 'all':
            if not (OUT/'elf-accepted.json').exists(): run('elf','1')
            failed = []
            for key in json.loads((OUT/'inputs-v2.json').read_bytes())['presets']:
                if not (OUT/('run-'+key)).exists():
                    try: run('run',key)
                    except subprocess.CalledProcessError: failed.append(key)
                if any((OUT/p).exists()for p in ('ACTIVE.json','QUARANTINED.json')): raise RuntimeError('uncertain ownership')
            assert not failed, failed
            for test in TESTS: globals()[test](); print('PASS',test)
        else:
            assert name in TESTS; globals()[name](); print('PASS',name)
    else: raise ValueError(mode)


if __name__ == '__main__': main()
