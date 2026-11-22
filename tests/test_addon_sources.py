import importlib.util
from pathlib import Path
import tempfile
import unittest

spec = importlib.util.spec_from_file_location('addon_sources', Path(__file__).resolve().parents[1] / 'tools/addon_sources.py')
m = importlib.util.module_from_spec(spec);spec.loader.exec_module(m)


class SourceTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name);self.source = self.root / 'installed' / 'Example';self.source.mkdir(parents=True)
        (self.source / 'Example.toc').write_text('## Version: 1\nCore.lua\n')
        (self.source / 'Core.lua').write_text('error("must never execute")')
        (self.source / 'LICENSE').write_text('Original licence')
        self.sources = m.Sources(self.root / 'project')

    def tearDown(self):
        self.temp.cleanup()

    def test_snapshot_is_data_not_executed_and_noop(self):
        first = self.sources.refresh('Example', self.source)
        self.assertTrue(first['changed'])
        folder, manifest = self.sources.snapshot('Example', first['active'])
        self.assertIn('LICENSE', manifest['files'])
        self.assertEqual((folder / 'source/Core.lua').read_text(), 'error("must never execute")')
        self.assertFalse(self.sources.refresh('Example', self.source)['changed'])

    def test_version_update_and_rollback(self):
        first = self.sources.refresh('Example', self.source)
        (self.source / 'Example.toc').write_text('## Version: 2\nCore.lua\n')
        second = self.sources.refresh('Example', self.source)
        self.assertEqual(second['previous'], first['active'])
        self.assertEqual(self.sources.rollback('Example')['active'], first['active'])
        self.assertIn('Version: 2', (self.source / 'Example.toc').read_text())

    def test_same_version_file_update(self):
        first = self.sources.refresh('Example', self.source)
        (self.source / 'Core.lua').write_text('-- changed')
        self.assertNotEqual(self.sources.refresh('Example', self.source)['active'], first['active'])

    def test_incomplete_update_preserves_previous(self):
        first = self.sources.refresh('Example', self.source)
        (self.source / 'Core.lua').unlink()
        with self.assertRaises(ValueError):
            self.sources.refresh('Example', self.source)
        self.assertEqual(self.sources.status('Example')['active'], first['active'])

    def test_corrupted_snapshot_refused(self):
        first = self.sources.refresh('Example', self.source)
        folder, _ = self.sources.snapshot('Example', first['active'])
        (folder / 'source/Core.lua').write_text('-- local modification')
        with self.assertRaises(ValueError):
            self.sources.refresh('Example', self.source)

    def test_private_paths_excluded(self):
        for folder in ['WTF', 'SavedVariables', '.git']:
            p = self.source / folder;p.mkdir();(p / 'private.lua').write_text('secret')
        first = self.sources.refresh('Example', self.source)
        _, manifest = self.sources.snapshot('Example', first['active'])
        self.assertEqual(len(manifest['files']), 3)

    def test_path_traversal_rejected(self):
        with self.assertRaises(ValueError):
            self.sources.refresh('../Example', self.source)
        with self.assertRaises(ValueError):
            self.sources.snapshot('Example', '../other')

    def test_interrupted_capture_not_selected(self):
        first = self.sources.refresh('Example', self.source)
        (self.source / 'Core.lua').write_text('-- new')
        original = m.files_at;calls = 0
        def changed(path):
            nonlocal calls
            if path == self.source:
                calls += 1
                if calls == 2:
                    (self.source / 'Core.lua').write_text('-- changed while scanning')
            return original(path)
        m.files_at = changed
        try:
            with self.assertRaises(ValueError):
                self.sources.refresh('Example', self.source)
        finally:
            m.files_at = original
        self.assertEqual(self.sources.status('Example')['active'], first['active'])


if __name__ == '__main__':
    unittest.main()
