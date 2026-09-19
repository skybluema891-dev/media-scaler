import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:pub_semver/pub_semver.dart';

class UpdateException implements Exception {
  const UpdateException(this.message);
  final String message;
  @override
  String toString() => message;
}

class AppUpdate {
  const AppUpdate({
    required this.currentVersion,
    required this.version,
    required this.releaseUrl,
    required this.downloadUrl,
    required this.assetName,
  });
  final String currentVersion;
  final String version;
  final Uri releaseUrl;
  final Uri downloadUrl;
  final String assetName;
}

class _GitHubRateLimitException implements Exception {}

class UpdateService {
  static const timeout = Duration(seconds: 12);
  static bool validRepository(String value) =>
      RegExp(r'^[A-Za-z0-9][A-Za-z0-9-]*/[A-Za-z0-9_.-]+$').hasMatch(value) &&
      !value.endsWith('/.') &&
      !value.endsWith('/..');

  static Future<String> repository() async {
    const defined = String.fromEnvironment('UPDATE_REPOSITORY');
    if (defined.isNotEmpty) return defined;
    final config = jsonDecode(
      await rootBundle.loadString('config/update.json'),
    );
    return config['repository'] as String? ?? '';
  }

  static Future<String> target() async {
    if (Platform.isWindows) return 'windows-x64';
    if (!Platform.isMacOS) throw const UpdateException('このOSは更新確認に対応していません。');
    const defined = String.fromEnvironment('UPDATE_TARGET');
    if (defined == 'macos-arm64' || defined == 'macos-x86_64') return defined;
    // Also detects Apple Silicon when a universal app is launched under Rosetta.
    final result = await Process.run('/usr/sbin/sysctl', [
      '-n',
      'hw.optional.arm64',
    ]).timeout(timeout);
    return result.exitCode == 0 && result.stdout.toString().trim() == '1'
        ? 'macos-arm64'
        : 'macos-x86_64';
  }

  Future<AppUpdate?> check() async {
    final repo = await repository();
    if (!validRepository(repo)) {
      throw const UpdateException('更新先のGitHubリポジトリが未設定です。');
    }
    final info = await PackageInfo.fromPlatform();
    final platform = await target();
    final client = HttpClient()..connectionTimeout = timeout;
    try {
      dynamic data;
      try {
        data = await _getJson(
          client,
          Uri.https('api.github.com', '/repos/$repo/releases/latest'),
          userAgent: 'MediaScaler/${info.version}',
          signalRateLimit: true,
        ).timeout(timeout);
      } on _GitHubRateLimitException {
        // This CDN-backed release asset does not consume the unauthenticated
        // GitHub API quota, so updates keep working after HTTP 403/429.
        data = await _getJson(
          client,
          Uri.https(
            'github.com',
            '/$repo/releases/latest/download/latest.json',
          ),
          userAgent: 'MediaScaler/${info.version}',
          followRedirects: true,
        ).timeout(timeout);
      }
      if (data is! Map<String, dynamic>) throw const FormatException();
      return parseRelease(
        data,
        repository: repo,
        currentVersion: info.version,
        target: platform,
      );
    } on UpdateException {
      rethrow;
    } on TimeoutException {
      throw const UpdateException('更新確認がタイムアウトしました。ネットワークをご確認ください。');
    } on SocketException {
      throw const UpdateException('ネットワークに接続できません。変換処理は引き続き利用できます。');
    } on FormatException {
      throw const UpdateException('更新情報の形式を確認できませんでした。');
    } finally {
      client.close(force: true);
    }
  }

  static Future<dynamic> _getJson(
    HttpClient client,
    Uri uri, {
    required String userAgent,
    bool followRedirects = false,
    bool signalRateLimit = false,
  }) async {
    final request = await client.getUrl(uri);
    request.followRedirects = followRedirects;
    request.headers.set('Accept', 'application/vnd.github+json');
    request.headers.set('User-Agent', userAgent);
    final response = await request.close();
    if (signalRateLimit &&
        (response.statusCode == 403 || response.statusCode == 429)) {
      throw _GitHubRateLimitException();
    }
    if (response.statusCode == 404) {
      throw const UpdateException('公開済みReleaseがないか、更新先を閲覧できません。');
    }
    if (response.statusCode == 403 || response.statusCode == 429) {
      throw const UpdateException('GitHubのアクセス制限中です。時間をおいて再確認してください。');
    }
    if (response.statusCode != 200) {
      throw UpdateException('更新情報を取得できませんでした（HTTP ${response.statusCode}）。');
    }
    final bytes = <int>[];
    await for (final chunk in response) {
      bytes.addAll(chunk);
      if (bytes.length > 2 * 1024 * 1024) {
        throw const UpdateException('更新情報のサイズが大きすぎます。');
      }
    }
    return jsonDecode(utf8.decode(bytes));
  }

  static AppUpdate? parseRelease(
    Map<String, dynamic> data, {
    required String repository,
    required String currentVersion,
    required String target,
  }) {
    if (!validRepository(repository)) {
      throw const FormatException('Invalid repository');
    }
    if (data['draft'] != false || data['prerelease'] != false) return null;
    final tag = data['tag_name'];
    if (tag is! String || !RegExp(r'^v\d+\.\d+\.\d+$').hasMatch(tag)) {
      return null;
    }
    final version = Version.parse(tag.substring(1));
    if (version <= Version.parse(currentVersion)) return null;
    final suffix = switch (target) {
      'windows-x64' => 'windows-setup.exe',
      'macos-arm64' => 'macos-arm64.dmg',
      'macos-x86_64' => 'macos-x86_64.dmg',
      _ => throw const FormatException('Unsupported update target'),
    };
    final name = 'MediaScaler-$version-$suffix';
    final assets = data['assets'];
    if (assets is! List) throw const FormatException('Missing release assets');
    for (final asset in assets.whereType<Map>()) {
      if (asset['name'] != name ||
          asset['state'] != 'uploaded' ||
          asset['size'] is! num ||
          (asset['size'] as num) <= 0) {
        continue;
      }
      final expected = Uri.https(
        'github.com',
        '/$repository/releases/download/$tag/$name',
      );
      if (asset['browser_download_url'] != expected.toString()) {
        throw const FormatException('Unexpected download URL');
      }
      return AppUpdate(
        currentVersion: currentVersion,
        version: version.toString(),
        releaseUrl: Uri.https('github.com', '/$repository/releases/tag/$tag'),
        downloadUrl: expected,
        assetName: name,
      );
    }
    throw const UpdateException('新しいバージョンはありますが、このOS用の配布ファイルがまだありません。');
  }
}
