"""Validate versions and publish only complete desktop releases."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import urllib.error
import urllib.request

ROOT = Path(__file__).resolve().parents[1]


def version_from(text):
    match = re.search(r'^version:\s*(\d+\.\d+\.\d+)\+(\d+)\s*$', text, re.M)
    if not match:
        raise ValueError('pubspec.yaml must contain version: MAJOR.MINOR.PATCH+BUILD')
    version, build = match.groups()
    if any(len(part) > 1 and part.startswith('0') for part in version.split('.')):
        raise ValueError('Version components must not have leading zeros')
    return version, build


def api(path, data=None, method=None):
    request = urllib.request.Request('https://api.github.com/repos/' + os.environ['GITHUB_REPOSITORY'] + path,
        data=None if data is None else json.dumps(data).encode(), method=method,
        headers={'Authorization': 'Bearer ' + os.environ['GH_TOKEN'],
                 'Accept': 'application/vnd.github+json', 'Content-Type': 'application/json',
                 'User-Agent': 'MediaScaler-release'})
    try:
        with urllib.request.urlopen(request, timeout=60) as response:
            return json.load(response)
    except urllib.error.HTTPError as error:
        if error.code == 404 and data is None:
            return None
        raise


def should_publish(event_name, ref, default_branch, version, previous=None):
    if ref.startswith('refs/tags/'):
        if ref != 'refs/tags/v' + version:
            raise ValueError('Tag must exactly match pubspec version')
        return True
    if ref != 'refs/heads/' + default_branch:
        return False
    if event_name == 'workflow_dispatch':
        return True
    if event_name != 'push':
        return False
    if previous is None:
        return True
    old, _ = version_from(previous)
    if tuple(map(int, version.split('.'))) < tuple(map(int, old.split('.'))):
        raise ValueError('Release version must not decrease')
    return version != old


def plan():
    version, _ = version_from((ROOT / 'pubspec.yaml').read_text(encoding='utf-8-sig'))
    event = json.loads(Path(os.environ['GITHUB_EVENT_PATH']).read_text())
    before = event.get('before', '')
    previous = None
    if before and set(before) != {'0'}:
        result = subprocess.run(['git', 'show', before + ':pubspec.yaml'], capture_output=True, text=True)
        if result.returncode == 0:
            previous = result.stdout
    publish = should_publish(os.environ['GITHUB_EVENT_NAME'], os.environ['GITHUB_REF'],
                             event['repository']['default_branch'], version, previous)
    existing = api('/releases/tags/v' + version) if publish else None
    if existing and not existing['draft']:
        publish = False
    with open(os.environ['GITHUB_OUTPUT'], 'a', encoding='utf-8') as output:
        output.write(f'version={version}\npublish={str(publish).lower()}\n')
    print(f'v{version}: publish={publish}')


def expected_assets(version):
    return [f'MediaScaler-{version}-{suffix}' for suffix in (
        'windows-setup.exe', 'macos-arm64.zip', 'macos-arm64.dmg',
        'macos-x86_64.zip', 'macos-x86_64.dmg')]


def publish():
    version, _ = version_from((ROOT / 'pubspec.yaml').read_text(encoding='utf-8-sig'))
    tag = 'v' + version
    sha = subprocess.check_output(['git', 'rev-parse', 'HEAD'], text=True).strip()
    folder = ROOT / 'artifacts'
    names = expected_assets(version)
    for name in names:
        if not (folder / name).is_file() or (folder / name).stat().st_size == 0:
            raise ValueError('Missing or empty release artifact: ' + name)
    checksums = []
    for name in names:
        digest = hashlib.sha256()
        with (folder / name).open('rb') as source:
            for block in iter(lambda: source.read(1024 * 1024), b''):
                digest.update(block)
        checksums.append(f'{digest.hexdigest()}  {name}\n')
    (folder / 'SHA256SUMS.txt').write_text(''.join(checksums), encoding='utf-8')
    existing = api('/releases/tags/' + tag)
    if existing and not existing['draft']:
        print('Already published; leaving existing release unchanged.')
        return
    # Never move an existing tag to a different source commit.
    ref = api('/git/ref/tags/' + tag)
    if ref:
        obj = ref['object']
        while obj['type'] == 'tag':
            obj = api('/git/tags/' + obj['sha'])['object']
        if obj['sha'] != sha:
            raise ValueError('Existing tag points to another commit. Increment version instead.')
    else:
        api('/git/refs', {'ref': 'refs/tags/' + tag, 'sha': sha})
    env = dict(os.environ, GH_REPO=os.environ['GITHUB_REPOSITORY'])
    if not existing:
        subprocess.run(['gh', 'release', 'create', tag, '--draft', '--verify-tag',
            '--title', 'Media Scaler ' + tag, '--generate-notes'], env=env, check=True)
    subprocess.run(['gh', 'release', 'upload', tag, *[str(folder / n) for n in names],
                    str(folder / 'SHA256SUMS.txt'), '--clobber'], env=env, check=True)
    release = api('/releases/tags/' + tag)
    uploaded = {a['name'] for a in release['assets'] if a['state'] == 'uploaded' and a['size'] > 0}
    if not set(names + ['SHA256SUMS.txt']).issubset(uploaded):
        raise ValueError('Release upload is incomplete; leaving it as a draft.')
    api('/releases/' + str(release['id']), {'draft': False, 'make_latest': 'legacy'}, 'PATCH')
    print('Published: ' + release['html_url'])


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('command', choices=['plan', 'publish'])
    args = parser.parse_args()
    (plan if args.command == 'plan' else publish)()
