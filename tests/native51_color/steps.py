#!/usr/bin/env python3
"""New private unit commands; called only inside the reviewed namespace by its owner."""
from pathlib import Path
import ctypes as C
import json
import os
import subprocess
import sys

HERE = Path('/src/tests/native51_color')
NATIVE = Path('/test/native')
SDK = '/usr/lib/x86_64-linux-gnu/mutter-51'


def run(args,env=None):
    print('COMMAND',json.dumps(args),flush=True)
    subprocess.run(args,env=env,check=True)


def main():
    mode = sys.argv[1]
    os.environ.update(CC='/view/cc.py',CC_LEDGER='/out/cc-ledger',CC_CAP='1')
    if mode=='native':
        run(['/usr/bin/cmake','-S','/src/gnome','-B','/out/build','-G','Ninja',
             '-DCMAKE_C_COMPILER=/view/cc.py','-DCMAKE_C_COMPILER_ID=GNU',
             '-DCMAKE_C_COMPILER_ID_RUN=TRUE','-DCMAKE_C_COMPILER_FORCED=TRUE',
             '-DCMAKE_C_ABI_COMPILED=TRUE','-DCMAKE_C_COMPILER_WORKS=TRUE',
             '-DCMAKE_C_COMPILER_VERSION=16','-DCMAKE_INSTALL_LIBDIR=lib','-DCMAKE_C_FLAGS=-include /view/signatures.h',
             '-DODIN=/opt/odin/odin','-DWAYLANDSHADER_EXPERIMENTAL_GNOME51=ON',
             '-DWAYLANDSHADER_BUILD_TESTS=OFF','-DLIBRASHADER_INCLUDE_DIR=/headers',
             '-DLIBRASHADER_LIBRARY=/private/libwaylandshader-rashader.so.2'])
        assert not Path('/out/cc-ledger').exists(), 'configuration unexpectedly invoked C compiler'
        run(['/usr/bin/cmake','--build','/out/build','--target','gnome_native','--parallel','1'])
        rows=Path('/out/cc-ledger').read_text().splitlines();assert len(rows)==1
        print('COMPILERS odin=1 c=1 (includes SDK layout + new typed public contracts)',flush=True)
    elif mode=='fixture':
        run(['/opt/odin/odin','build','/view/main','-out:/out/fixture','-o:speed','-vet','-strict-style','-thread-count:4'])
    elif mode=='elf':
        p=subprocess.run(['/usr/bin/readelf','-h','-d','--dyn-syms','--wide',str(NATIVE/'libwaylandshader-gnome.so')],capture_output=True,check=True)
        assert not p.stderr and len(p.stdout)<1024*1024
        Path('/out/elf.txt').write_bytes(p.stdout)
        text=p.stdout.decode()
        assert 'DYN (Shared object file)' in text and 'Advanced Micro Devices X86-64' in text
        assert 'libwaylandshader-rashader.so.2' in text and '$ORIGIN' in text
        assert 'libmutter-clutter-51.so' in text and 'libmutter-cogl-51.so' in text
        for bad in ('clutter_color_state_add_pipeline_transform','clutter_color_state_update_uniforms','/private','/nix/store','mutter-18','mutter-clutter-18','mutter-cogl-18'):
            assert bad not in text,bad
        for symbol in ('clutter_color_transform_new','clutter_color_transform_get_pipeline','clutter_color_pipeline_shader_add_transform','wayland_shader_effect_get_type'):
            assert symbol in text,symbol
        print('NEW_NATIVE_ELF_OK not actual color or compositor acceptance')
    elif mode=='introspection':
        os.environ.update(CC_CAP='3',LD_LIBRARY_PATH=f'{NATIVE}:/private:{SDK}:/link',GI_TYPELIB_PATH=SDK)
        helptext=subprocess.run(['/usr/bin/g-ir-scanner','--help'],capture_output=True,check=True).stdout.decode()
        extra=['--fallback-library-path='] if '--fallback-library-path' in helptext else []
        run(['/usr/bin/g-ir-scanner','--quiet','--warn-all','--no-libtool',*extra,
             '--namespace=WaylandShader','--nsversion=1.0','--identifier-prefix=WaylandShader',
             '--symbol-prefix=wayland_shader','--include=GObject-2.0','--include=Clutter-51',
             '--add-include-path='+SDK,'--pkg=libmutter-51','--library=waylandshader-gnome',
             '--library-path='+str(NATIVE),'--c-include=waylandshader-effect.h',
             '--output=/out/WaylandShader-1.0.gir','/src/gnome/native/waylandshader-effect.h'])
        run(['/usr/bin/g-ir-compiler','--includedir='+SDK,'/out/WaylandShader-1.0.gir','--output=/out/WaylandShader-1.0.typelib'])
        rows=Path('/out/cc-ledger').read_text().splitlines();assert len(rows)<=3
        print('COMPILERS scanner_c='+str(len(rows))+' typelib=1; one discovery helper native invocation')
    elif mode=='static':
        module=C.CDLL(str(NATIVE/'libwaylandshader-gnome.so'),mode=os.RTLD_NOW|os.RTLD_LOCAL)
        g=C.CDLL('libgobject-2.0.so.0')
        class Query(C.Structure):
            _fields_=[('type',C.c_size_t),('name',C.c_char_p),('klass',C.c_uint32),('instance',C.c_uint32)]
        g.g_type_query.argtypes=[C.c_size_t,C.POINTER(Query)]
        g.g_type_parent.argtypes=[C.c_size_t];g.g_type_parent.restype=C.c_size_t
        module.wayland_shader_effect_get_type.restype=C.c_size_t
        t=module.wayland_shader_effect_get_type();assert t
        for typ,size in ((g.g_type_parent(t),(200,24)),(t,(200,32))):
            q=Query();g.g_type_query(typ,C.byref(q));assert (q.klass,q.instance)==size
        module.wayland_shader_effect_new.restype=C.c_void_p
        obj=module.wayland_shader_effect_new();assert obj
        module.wayland_shader_effect_shutdown.argtypes=[C.c_void_p];module.wayland_shader_effect_shutdown.restype=None
        module.wayland_shader_effect_shutdown(obj)
        g.g_object_unref.argtypes=[C.c_void_p];g.g_object_unref.restype=None;g.g_object_unref(obj)
        maps=Path('/proc/self/maps').read_text()
        for name in ('libwaylandshader-gnome.so','libwaylandshader-rashader.so.2'):
            paths={line.split()[-1] for line in maps.splitlines() if name in line};assert paths=={str(NATIVE/name)},paths
        assert not any(s in maps for s in ('libmutter-18','libmutter-clutter-18','libmutter-cogl-18'))
        print('NEW_NATIVE_REGISTRATION_OK parent200/24 child200/32; no paint or color calls exercised')
    else:raise ValueError(mode)


if __name__=='__main__':main()
