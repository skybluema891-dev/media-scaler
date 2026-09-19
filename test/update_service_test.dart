import 'package:flutter_test/flutter_test.dart';
import 'package:media_scaler/services/update_service.dart';

Map<String, dynamic> release(String version, String suffix) => {
  'tag_name': 'v$version',
  'draft': false,
  'prerelease': false,
  'assets': [
    {
      'name': 'MediaScaler-$version-$suffix',
      'state': 'uploaded',
      'size': 500,
      'browser_download_url':
          'https://github.com/example/scaler/releases/download/v$version/MediaScaler-$version-$suffix',
    },
  ],
};

AppUpdate? parse(
  Map<String, dynamic> data, {
  String current = '1.2.0',
  String target = 'windows-x64',
}) => UpdateService.parseRelease(
  data,
  repository: 'example/scaler',
  currentVersion: current,
  target: target,
);

void main() {
  test('numeric comparison, same version and downgrade', () {
    expect(parse(release('1.10.0', 'windows-setup.exe'))?.version, '1.10.0');
    expect(parse(release('1.2.0', 'windows-setup.exe')), isNull);
    expect(parse(release('1.1.9', 'windows-setup.exe')), isNull);
  });
  test('drafts and prereleases never notify', () {
    expect(
      parse(release('1.3.0', 'windows-setup.exe')..['draft'] = true),
      isNull,
    );
    expect(
      parse(release('1.3.0', 'windows-setup.exe')..['prerelease'] = true),
      isNull,
    );
    expect(parse(release('1.3.0-rc.1', 'windows-setup.exe')), isNull);
  });
  test('selects Windows, Apple Silicon and Intel files', () {
    for (final entry in {
      'windows-x64': 'windows-setup.exe',
      'macos-arm64': 'macos-arm64.dmg',
      'macos-x86_64': 'macos-x86_64.dmg',
    }.entries) {
      final update = parse(release('1.3.0', entry.value), target: entry.key)!;
      expect(update.assetName, 'MediaScaler-1.3.0-${entry.value}');
      expect(
        update.releaseUrl.toString(),
        'https://github.com/example/scaler/releases/tag/v1.3.0',
      );
    }
  });
  test('wrong architecture and incomplete uploads are not offered', () {
    expect(
      () => parse(release('1.3.0', 'macos-x86_64.dmg'), target: 'macos-arm64'),
      throwsA(isA<UpdateException>()),
    );
    final data = release('1.3.0', 'windows-setup.exe');
    (data['assets'] as List).first['state'] = 'new';
    expect(() => parse(data), throwsA(isA<UpdateException>()));
  });
  test('rejects external or insecure asset URLs', () {
    for (final url in [
      'https://evil.example/app.exe',
      'file:///tmp/app.exe',
      'http://github.com/example/scaler/releases/download/v1.3.0/MediaScaler-1.3.0-windows-setup.exe',
    ]) {
      final data = release('1.3.0', 'windows-setup.exe');
      (data['assets'] as List).first['browser_download_url'] = url;
      expect(() => parse(data), throwsFormatException);
    }
  });
  test('repository config validation', () {
    expect(UpdateService.validRepository('owner/repo-name'), isTrue);
    for (final value in [
      '',
      'https://github.com/owner/repo',
      'owner/../repo',
      'owner/..',
    ]) {
      expect(UpdateService.validRepository(value), isFalse);
    }
  });
}
