#!/usr/bin/env python3
"""Scoped51 acceptance over preserved observations; never replay a consumed process."""
from pathlib import Path
import importlib.util
import json
import sys

# Python -I omits the script directory; load this exact adjacent authenticated reader.
HERE=Path(__file__).resolve().parent
s=importlib.util.spec_from_file_location('native51_evidence',HERE/'evidence.py')
e=importlib.util.module_from_spec(s);s.loader.exec_module(e)
TESTS=('adapter_transaction_and_resources','module_and_private_introspection','isolated_receipts_and_budget')


def adapter_transaction_and_resources():
    text=e.receipt('test-1')
    expected={'snippet_failure_preserves_configuration','constructor_failures_are_atomic','failed_configuration_is_retried','cache_uses_all_inputs','working_color_and_transform_order','color_teardown_releases_refs','invalid_inputs_do_not_publish','adapter_failures_are_atomic','adapter_sparse_resources_and_lifetime','adapter_upload_boundaries'}
    rows=[line.removeprefix('PASS native51 ')for line in text.splitlines()if line.startswith('PASS native51 ')]
    assert len(rows)==10 and set(rows)==expected
    e.receipt('fixture-1')


def module_and_private_introspection():
    e.receipt('native-2');e.receipt('elf-1')
    assert 'NEW_NATIVE_REGISTRATION_OK'in e.receipt('static-2')
    assert 'NEW_GI_COMPILE_OK'in e.receipt('gi',True)
    text=e.receipt('gjs',True)
    assert text.startswith('NEW_STAGED_GI_OK ')
    actual=json.loads(text.removeprefix('NEW_STAGED_GI_OK '))
    assert actual['typelib']=='/test/native/WaylandShader-1.0.typelib' and actual['version']=='1.0'
    assert actual['observed']=={n:['/test/native/'+n]for n in('libwaylandshader-gnome.so','libwaylandshader-rashader.so.2')}
    spec=importlib.util.spec_from_file_location('current_gir_contract',e.ROOT/'tasks/native51-gi-continuation-20261112/steps.py')
    parser=importlib.util.module_from_spec(spec);spec.loader.exec_module(parser)
    proof=parser.validate((e.GI/'gi/WaylandShader-1.0.gir').read_bytes())
    assert proof['parent']=='Clutter.Effect' and proof['include']=='Clutter-51'
    assert(e.GI/'gi/WaylandShader-1.0.typelib').stat().st_size>0


def isolated_receipts_and_budget():
    for name in('native-2','fixture-1','elf-1','test-1','static-2'):e.receipt(name)
    for name in('gi','gjs'):e.receipt(name,True)
    old=[e.read(p)for p in e.OLD.glob('*/charge.json')]
    new=[e.read(p)for p in e.GI.glob('*/charge.json')]
    assert sum(x['compiler_allowance_charged']for x in old)==9 and sum(x['runtime_allowance_charged']for x in old)==4
    assert sum(x['compiler_charged']for x in new)==4 and sum(x['native_charged']for x in new)==2
    assert e.read(e.GI/'scope.json')['budget']=={'compiler_invocations':4,'native_processes':2,'advisors':2,'reviews':2,'attempts':1}
    assert e.read(e.OLD/'replan-1.json')['budget_after']==9
    assert len((e.GI/'gi/cc-ledger').read_text().splitlines())==3
    for name in('native-1','introspection-1','static-1'):
        status=e.read(e.OLD/name/'status.json')
        assert status['leader_exit']==1 and status['cleanup']=='owned-group-signalled-children-reaped'
    assert not any((base/p).exists()for base in(e.OLD,e.GI)for p in('ACTIVE.json','QUARANTINED.json'))


def main():
    mode=sys.argv[1];e.inputs()
    if mode=='build':e.receipt('native-2');e.receipt('fixture-1')
    elif mode=='verify':module_and_private_introspection()
    elif mode=='test':
        names=TESTS if sys.argv[2]=='all'else(sys.argv[2],)
        for name in names:assert name in TESTS;globals()[name]();print('PASS',name)
    else:raise ValueError(mode)


if __name__=='__main__':main()
