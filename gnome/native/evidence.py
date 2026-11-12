"""Authenticate saved native51 observations without re-executing consumed work."""
from pathlib import Path
import hashlib
import json

HERE=Path(__file__).resolve().parent
ROOT=HERE.parents[2]
OLD=ROOT/'evidence/baseline/native51-personal-adapter-20261112'
GI=ROOT/'evidence/baseline/native51-gi-continuation-20261112'


def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def read(p):return json.loads(p.read_bytes())


def inputs():
    anchor=read(HERE/'verification-inputs.json')
    path=GI/'current-proof-inputs.json'
    assert anchor['manifest']==str(path) and anchor['sha256']==sha(path)
    m=read(path)
    prior=read(OLD/'inputs-4.json')
    replacements=m['prior_metadata_snapshots']
    assert set(replacements)=={str(HERE/'verify.py')}
    for row in prior['files']:
        # Only acceptance-reader code changed; original bytes remain in an explicit snapshot.
        p=Path(replacements.get(row['path'],row['path']))
        assert sha(p)==row['sha256'],str(p)
    for row in m['files']:assert sha(Path(row['path']))==row['sha256'],row['path']
    return m


def receipt(name,continuation=False):
    m=inputs();stage=(GI if continuation else OLD)/name
    status=read(stage/'status.json')
    assert status['leader_exit']==0 and status['reason']=='awaiting-cleanup' and status['stderr_bytes']==0
    assert status['cleanup']=='owned-group-signalled-children-reaped'
    if continuation:p=stage/'receipt.json'
    elif name.startswith(('native-','fixture-')):p=OLD/(name.split('-')[0]+'-built.json')
    elif name=='elf-1':p=OLD/'elf-checked.json'
    else:p=stage/'receipt.json'
    r=read(p)
    allowed={m['continuation_manifest_sha256']}if continuation else set(m['prior_success_manifest_sha256'])
    assert r['manifest_sha256']in allowed and r['status_sha256']==sha(stage/'status.json')
    assert r['known_cleanup'] and r['pending_stop']==0
    if continuation:
        assert r['module_sha256']=='5f4159c9b5f1964767d2fc77d1f7440cfb214b7b05a22fd3d7dd2310c84ea013'
        assert r['stdout_sha256']==sha(stage/'stdout.jsonl') and r['stderr_sha256']==sha(stage/'stderr.log')
    for row in r['outputs']:assert sha(Path(row['path']))==row['sha256']
    if 'artifact'in r:assert sha(Path(r['artifact']))==r['sha256']
    return (stage/'stdout.jsonl').read_text()
