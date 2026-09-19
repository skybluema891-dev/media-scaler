import unittest
from recover_release import validate_run


class RecoveryTests(unittest.TestCase):
    def setUp(self):
        self.run = {'repository': {'full_name': 'example/app'},
                    'head_repository': {'full_name': 'example/app'},
                    'path': '.github/workflows/release.yml', 'event': 'push',
                    'status': 'completed', 'head_sha': 'a' * 40}
        self.jobs = [{'name': name, 'conclusion': 'success'} for name in
                     ('windows', 'macos (macos-15)', 'macos (macos-15-intel)')]

    def test_successful_builds_can_be_recovered(self):
        self.assertEqual(validate_run(self.run, self.jobs, 'example/app'), 'a' * 40)

    def test_missing_or_failed_platform_rejected(self):
        with self.assertRaises(ValueError):
            validate_run(self.run, self.jobs[:-1], 'example/app')
        self.jobs[0]['conclusion'] = 'failure'
        with self.assertRaises(ValueError):
            validate_run(self.run, self.jobs, 'example/app')

    def test_fork_or_wrong_workflow_rejected(self):
        self.run['head_repository']['full_name'] = 'elsewhere/fork'
        with self.assertRaises(ValueError):
            validate_run(self.run, self.jobs, 'example/app')
        self.run['head_repository']['full_name'] = 'example/app'
        self.run['path'] = '.github/workflows/other.yml'
        with self.assertRaises(ValueError):
            validate_run(self.run, self.jobs, 'example/app')


if __name__ == '__main__':
    unittest.main()
