#!/usr/bin/python3
"""Count actual SDK/scanner C frontend/link-driver invocations in the private namespace."""
import fcntl
import json
import os
import sys

path = os.environ['CC_LEDGER']
with open(path,'a+') as f:
    fcntl.flock(f,fcntl.LOCK_EX)
    f.seek(0)
    records = [json.loads(line) for line in f if line.strip()]
    assert len(records) < int(os.environ['CC_CAP']), 'C invocation cap exhausted'
    f.seek(0,2)
    f.write(json.dumps(sys.argv[1:])+'\n'); f.flush()
os.execv('/usr/bin/x86_64-linux-gnu-gcc-16',['gcc',*sys.argv[1:]])
