#!/usr/bin/env python3
"""Prepare new 51 test inputs only; never compile/run or invoke a closed driver."""
from pathlib import Path
import hashlib
import json
import re
import shutil
import sys

HERE = Path(__file__).resolve().parent
APP = HERE.parents[1]
WANTED = ('SNIPPET_DECL','SNIPPET_BODY','Surface','Color_Config','Resources',
          'cogl_error','new_pipeline','color_destroy','configure_color')


def extract():
    text = (APP/'gnome/native/paint.odin').read_text()
    starts = list(re.finditer(r'^([A-Za-z_]\w*) ::',text,re.M))
    names = [m[1] for m in starts]
    assert len(names) == len(set(names)), 'duplicate declaration'
    sections = {m[1]:text[m.start():starts[i+1].start() if i+1<len(starts) else len(text)] for i,m in enumerate(starts)}
    assert set(WANTED) <= sections.keys()
    color = (APP/'gnome/native/color51.odin').read_text()
    prefix = 'package waylandshader\n\nimport glib "../glib"\n\n'
    assert color.startswith(prefix)
    selected = {n:sections[n] for n in WANTED}
    # Only package/import headers change. All production declarations and bodies are verbatim.
    body = 'package main\nimport "core:fmt"\nimport glib "../glib"\n\n'+'\n'.join(selected.values())+color[len(prefix):]+'\nfixture_cleanup :: proc(r:^Resources) { color_destroy(&r.color) }\n'
    return body, {n:hashlib.sha256(v.encode()).hexdigest() for n,v in selected.items()}


def main():
    assert len(sys.argv)==2
    view = Path(sys.argv[1]); view.mkdir(mode=0o700)
    (view/'main').mkdir(); (view/'glib').mkdir()
    body,parts = extract()
    (view/'main/production.odin').write_text(body)
    for name in ('support','adapter'):shutil.copyfile(HERE/'fixtures'/f'{name}.odin',view/'main'/f'{name}.odin')
    shutil.copyfile(HERE/'fixtures/glib.odin',view/'glib/glib.odin')
    (view/'fragments.json').write_text(json.dumps({'paint_declarations':parts,'color51_full_source':hashlib.sha256((APP/'gnome/native/color51.odin').read_bytes()).hexdigest(),'limits':'source-copy and doubles only; no native ABI or pixels'},indent=2)+'\n')
    print('Prepared verbatim 51 adapter and constructor declarations; no compiler or native run.')


if __name__=='__main__':main()
