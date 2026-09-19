"""Retry publication from verified, immutable CI artifacts without rebuilding."""
import argparse
import os
import re
import subprocess

from release_automation import ROOT, api, publish, version_from


def validate_run(run, jobs, repository):
    if (run['repository']['full_name'] != repository
            or run['head_repository']['full_name'] != repository
            or run['path'] != '.github/workflows/release.yml'
            or run['event'] not in ('push', 'workflow_dispatch')
            or run['status'] != 'completed'
            or not re.fullmatch(r'[0-9a-f]{40}', run['head_sha'])):
        raise ValueError('Only completed release builds from this repository are accepted')
    required = {'windows', 'macos (macos-15)', 'macos (macos-15-intel)'}
    for name in required:
        matches = [job for job in jobs if job['name'] == name]
        if len(matches) != 1 or matches[0]['conclusion'] != 'success':
            raise ValueError('All three platform builds must have succeeded: ' + name)
    return run['head_sha']


def recover(run_id):
    if not re.fullmatch(r'[0-9]+', run_id):
        raise ValueError('Run ID must be numeric')
    repository = os.environ['GITHUB_REPOSITORY']
    run = api('/actions/runs/' + run_id)
    jobs = api('/actions/runs/' + run_id + '/jobs?per_page=100')['jobs']
    sha = validate_run(run, jobs, repository)
    # checkout fetch-depth:0 retains the exact original source. Never move its tag.
    spec = subprocess.check_output(['git', 'show', sha + ':pubspec.yaml'], text=True)
    version, _ = version_from(spec)
    folder = ROOT / 'artifacts'
    if folder.exists() and any(folder.iterdir()):
        raise ValueError('Artifact directory must be empty before recovery')
    # gh nests multiple artifacts by name; selecting each one separately merges
    # its files directly into the same directory, as download-artifact does.
    for name in ('windows-installer', 'macos-15', 'macos-15-intel'):
        subprocess.run(['gh', 'run', 'download', run_id, '--repo', repository,
                        '--name', name, '--dir', str(folder)], check=True)
    publish(version=version, sha=sha)


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('run_id')
    recover(parser.parse_args().run_id)
