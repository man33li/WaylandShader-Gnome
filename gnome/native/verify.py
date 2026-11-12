#!/usr/bin/env python3
"""Scoped51 acceptance reads new unit receipts; it never repeats a consumed invocation."""
from pathlib import Path
import hashlib
import json
import sys
import xml.etree.ElementTree as ET

HERE=Path(__file__).resolve().parent
ROOT=HERE.parents[2]
OUT=ROOT/'evidence/baseline/native51-personal-adapter-20261112'
TESTS=('adapter_transaction_and_resources','module_and_private_introspection','isolated_receipts_and_budget')

def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def inputs():
    data=(HERE/'verification-inputs.json').read_bytes();assert data==(OUT/'inputs-4.json').read_bytes()
    m=json.loads(data)
    for row in m['files']:assert sha(Path(row['path']))==row['sha256'],row['path']
    return hashlib.sha256(data).hexdigest()
def receipt(name):
    stage=OUT/name;status=json.loads((stage/'status.json').read_bytes())
    assert status['leader_exit']==0 and status['reason']=='awaiting-cleanup' and status['stderr_bytes']==0 and status['cleanup']=='owned-group-signalled-children-reaped'
    if name.startswith(('native-','fixture-')):p=OUT/(name.split('-')[0]+'-built.json')
    elif name.startswith('elf-'):p=OUT/'elf-checked.json'
    elif name.startswith('introspection-'):p=OUT/'introspection-built.json'
    else:p=stage/'receipt.json'
    r=json.loads(p.read_bytes());current=inputs();allowed={current,json.loads((OUT/'inputs-4.json').read_bytes())['artifact_manifest_sha256']}
    assert r['manifest_sha256']in allowed and r['status_sha256']==sha(stage/'status.json') and r['known_cleanup'] and r['pending_stop']==0
    for row in r['outputs']:assert sha(Path(row['path']))==row['sha256']
    return (stage/'stdout.jsonl').read_text()
def adapter_transaction_and_resources():
    text=receipt('test-1')
    expected={'snippet_failure_preserves_configuration','constructor_failures_are_atomic','failed_configuration_is_retried','cache_uses_all_inputs','working_color_and_transform_order','color_teardown_releases_refs','invalid_inputs_do_not_publish','adapter_failures_are_atomic','adapter_sparse_resources_and_lifetime','adapter_upload_boundaries'}
    rows=[line.removeprefix('PASS native51 ')for line in text.splitlines()if line.startswith('PASS native51 ')]
    assert len(rows)==10 and set(rows)==expected
    receipt('fixture-1')
def module_and_private_introspection():
    receipt('native-2');receipt('elf-1');receipt('introspection-1')
    assert 'NEW_NATIVE_REGISTRATION_OK' in receipt('static-2') and 'NEW_STAGED_GI_OK' in receipt('gjs-1')
    tree=ET.parse(OUT/'introspection-1/WaylandShader-1.0.gir');root=tree.getroot();ns={'c':'http://www.gtk.org/introspection/core/1.0'}
    includes={(p.attrib['name'],p.attrib['version'])for p in root.findall('c:include',ns)}
    assert ('Clutter','51')in includes and ('Clutter','18')not in includes
    namespace=root.find('c:namespace',ns);assert namespace.attrib['name']=='WaylandShader' and namespace.attrib['version']=='1.0'
    assert namespace.attrib['shared-library']=='libwaylandshader-gnome.so'
    klass=namespace.find('c:class',ns);assert klass.attrib['name']=='Effect' and klass.attrib['parent']=='Clutter.Effect'
def isolated_receipts_and_budget():
    for name in ('native-2','fixture-1','elf-1','introspection-1','test-1','static-2','gjs-1'):receipt(name)
    rows=[json.loads(p.read_bytes())for p in OUT.glob('*/charge.json')]
    assert sum(r['compiler_allowance_charged']for r in rows)<=9 and sum(r['runtime_allowance_charged']for r in rows)<=4
    assert not any((OUT/p).exists()for p in('ACTIVE.json','QUARANTINED.json'))
def main():
    mode=sys.argv[1];inputs()
    if mode=='build':receipt('native-2');receipt('fixture-1')
    elif mode=='verify':module_and_private_introspection()
    elif mode=='test':
        names=TESTS if sys.argv[2]=='all' else (sys.argv[2],)
        for n in names:assert n in TESTS;globals()[n]();print('PASS',n)
    else:raise ValueError(mode)
if __name__=='__main__':main()
