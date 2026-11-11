#!/usr/bin/env python3
"""Offline controller-failure regressions; no process/model launch, only owned fake artifacts."""
import contextlib
import importlib.util
from pathlib import Path
import tempfile
import unittest

spec = importlib.util.spec_from_file_location('contract_driver', Path(__file__).with_name('run.py'))
r = importlib.util.module_from_spec(spec)
spec.loader.exec_module(r)


class FakeSupervisor:
    CLEAN = 'owned-group-signalled-children-reaped'

    def __init__(self, reason='awaiting-cleanup', cleanup=CLEAN, stderr=0, throws=False):
        self.result = {'reason': reason, 'cleanup': cleanup, 'leader_exit': 0, 'stderr_bytes': stderr}
        self.throws = throws

    @contextlib.contextmanager
    def caught_signals(self):
        yield [0]

    def launch(self, args, request, out, deadline, pending):
        if self.throws:
            raise RuntimeError('simulated supervision exception, no real process exists')
        (out/'stdout.jsonl').write_text('')
        (out/'stderr.log').write_text('x' if self.result['stderr_bytes'] else '')
        return self.result, b''


class DriverTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='fake-controller-', dir=r.APP/'.law')
        self.root = Path(self.temp.name)
        self.old = r.STORE
        r.STORE = self.root
        for name in ('view', 'work'):
            (self.root/name).mkdir()

    def tearDown(self):
        r.STORE = self.old
        # All markers here are our fake data; no child was ever launched.
        self.temp.cleanup()

    def stage(self, b):
        return r.stage(b, self.root, self.root/'view', self.root/'work', 'stage', ['/fake/not-executed'])

    def test_clean_stage_releases_ownership(self):
        self.assertTrue(self.stage(FakeSupervisor()))
        self.assertFalse((self.root/'ACTIVE.json').exists())

    def test_zero_exit_does_not_override_controller_failure(self):
        self.assertFalse(self.stage(FakeSupervisor(reason='output-cap')))
        self.assertFalse((self.root/'ACTIVE.json').exists())

    def test_zero_exit_does_not_override_stderr(self):
        self.assertFalse(self.stage(FakeSupervisor(stderr=1)))

    def test_uncertain_cleanup_quarantines_builds(self):
        with self.assertRaisesRegex(RuntimeError, 'UNCERTAIN'):
            self.stage(FakeSupervisor(cleanup='incomplete'))
        self.assertTrue((self.root/'ACTIVE.json').exists())
        self.assertTrue((self.root/'QUARANTINED.json').exists())
        with self.assertRaisesRegex(AssertionError, 'prior cleanup uncertainty'):
            r.build(FakeSupervisor())

    def test_thrown_supervision_blocks_later_cached_success(self):
        with self.assertRaisesRegex(RuntimeError, 'simulated'):
            self.stage(FakeSupervisor(throws=True))
        self.assertTrue((self.root/'ACTIVE.json').exists())
        with self.assertRaisesRegex(AssertionError, 'prior cleanup uncertainty'):
            r.build(FakeSupervisor())

    def test_missing_application_teardown_cannot_pass(self):
        old_app = r.APP
        source = self.root/'gnome/native'
        source.mkdir(parents=True)
        (source/'paint.odin').write_text('\n'.join(name+' :: proc() {}' for name in
                                                 ('Surface', 'Resources', 'cogl_error', 'new_pipeline', 'configure_color')))
        r.APP = self.root
        try:
            with self.assertRaisesRegex(AssertionError, 'requires actual application teardown'):
                r.fragments()
        finally:
            r.APP = old_app


if __name__ == '__main__':
    unittest.main(verbosity=2)
