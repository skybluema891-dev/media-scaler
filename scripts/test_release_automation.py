import json
import unittest
import tempfile
from pathlib import Path
from unittest.mock import patch
import release_automation as automation
from release_automation import version_from, should_publish, expected_assets


class ReleaseTests(unittest.TestCase):
    def test_version(self):
        self.assertEqual(version_from('version: 1.10.0+42\r\n'), ('1.10.0', '42'))
        for invalid in ['1.0.0', 'version: 1.0.0-rc.1+1', 'version: 01.0.0+1']:
            with self.assertRaises(ValueError):
                version_from(invalid)

    def test_push(self):
        self.assertTrue(should_publish('push', 'refs/heads/main', 'main', '1.2.0', 'version: 1.1.9+1'))
        self.assertFalse(should_publish('push', 'refs/heads/main', 'main', '1.2.0', 'version: 1.2.0+1'))
        self.assertFalse(should_publish('push', 'refs/heads/work', 'main', '1.2.0'))
        with self.assertRaises(ValueError):
            should_publish('push', 'refs/heads/main', 'main', '1.1.0', 'version: 1.2.0+1')

    def test_tag_and_manual(self):
        self.assertTrue(should_publish('push', 'refs/tags/v1.2.0', 'main', '1.2.0'))
        with self.assertRaises(ValueError):
            should_publish('push', 'refs/tags/v1.3.0', 'main', '1.2.0')
        self.assertTrue(should_publish('workflow_dispatch', 'refs/heads/main', 'main', '1.2.0'))
        self.assertFalse(should_publish('pull_request', 'refs/pull/1/merge', 'main', '1.2.0'))

    def test_assets(self):
        assets = expected_assets('1.2.0')
        self.assertEqual(len(assets), 5)
        self.assertIn('MediaScaler-1.2.0-macos-x86_64.dmg', assets)
        self.assertIn('MediaScaler-1.2.0-windows-setup.exe', assets)

    def test_draft_lookup_when_tag_endpoint_returns_404(self):
        draft = {'id': 123, 'tag_name': 'v1.2.0', 'draft': True}
        with patch.object(automation, 'api', side_effect=[None, [draft]]) as api:
            self.assertEqual(automation.release_for_tag('v1.2.0'), draft)
            self.assertEqual(api.call_args_list[-1].args[0], '/releases?per_page=100&page=1')

    def test_missing_release(self):
        with patch.object(automation, 'api', side_effect=[None, []]):
            self.assertIsNone(automation.release_for_tag('v1.2.0'))

    def test_draft_is_verified_and_published_by_id(self):
        build = automation.ROOT / 'build'
        build.mkdir(exist_ok=True)
        with tempfile.TemporaryDirectory(dir=build) as temporary:
            root = Path(temporary)
            (root / 'pubspec.yaml').write_text('version: 1.2.0+5\n')
            (root / 'artifacts').mkdir()
            names = expected_assets('1.2.0')
            for name in names:
                (root / 'artifacts' / name).write_bytes(b'test artifact')
            draft = {'draft': True, 'id': 123}
            uploaded = dict(draft, html_url='https://github.com/example/app/releases/tag/v1.2.0',
                assets=[{'name': name, 'state': 'uploaded', 'size': 13}
                        for name in names + ['SHA256SUMS.txt', 'latest.json']])
            with patch.object(automation, 'ROOT', root), \
                 patch.dict(automation.os.environ, {'GITHUB_REPOSITORY': 'example/app'}), \
                 patch.object(automation.subprocess, 'check_output', return_value='abc\n'), \
                 patch.object(automation.subprocess, 'run') as run, \
                 patch.object(automation, 'release_for_tag', return_value=draft), \
                 patch.object(automation, 'api', side_effect=[
                     {'object': {'type': 'commit', 'sha': 'abc'}}, uploaded, {}]) as api:
                automation.publish()
                self.assertEqual(run.call_count, 1)
                manifest = json.loads(
                    (root / 'artifacts' / 'latest.json').read_text())
                self.assertEqual(manifest['tag_name'], 'v1.2.0')
                self.assertEqual(len(manifest['assets']), 5)
                self.assertEqual(api.call_args_list[1].args, ('/releases/123',))
                api.assert_called_with('/releases/123', {'draft': False, 'make_latest': 'legacy'}, 'PATCH')

    def test_incomplete_artifacts_never_contact_github(self):
        build = automation.ROOT / 'build'
        build.mkdir(exist_ok=True)
        with tempfile.TemporaryDirectory(dir=build) as temporary:
            root = Path(temporary)
            (root / 'pubspec.yaml').write_text('version: 1.2.0+5\n')
            with patch.object(automation, 'ROOT', root), \
                 patch.dict(automation.os.environ, {'GITHUB_REPOSITORY': 'example/app'}), \
                 patch.object(automation.subprocess, 'check_output', return_value='abc\n'), \
                 patch.object(automation, 'api') as api:
                with self.assertRaisesRegex(ValueError, 'Missing or empty'):
                    automation.publish()
                api.assert_not_called()

    def test_published_release_is_never_overwritten(self):
        build = automation.ROOT / 'build'
        build.mkdir(exist_ok=True)
        with tempfile.TemporaryDirectory(dir=build) as temporary:
            root = Path(temporary)
            (root / 'pubspec.yaml').write_text('version: 1.2.0+5\n')
            (root / 'artifacts').mkdir()
            for name in expected_assets('1.2.0'):
                (root / 'artifacts' / name).write_bytes(b'test artifact')
            with patch.object(automation, 'ROOT', root), \
                 patch.dict(automation.os.environ, {'GITHUB_REPOSITORY': 'example/app'}), \
                 patch.object(automation.subprocess, 'check_output', return_value='abc\n'), \
                 patch.object(automation.subprocess, 'run') as run, \
                 patch.object(automation, 'api', return_value={'draft': False}) as api:
                automation.publish()
                api.assert_called_once_with('/releases/tags/v1.2.0')
                run.assert_not_called()


if __name__ == '__main__':
    unittest.main()
