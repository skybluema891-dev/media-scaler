import 'dart:async';

import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/update_service.dart';

class UpdateButton extends StatefulWidget {
  const UpdateButton({
    super.key,
    this.checkOnStart = true,
    this.checkForUpdate,
    this.openUrl,
  });
  final bool checkOnStart;
  final Future<AppUpdate?> Function()? checkForUpdate;
  final Future<bool> Function(Uri)? openUrl;
  @override
  State<UpdateButton> createState() => _UpdateButtonState();
}

class _UpdateButtonState extends State<UpdateButton> {
  bool _busy = false;
  bool _showingDialog = false;
  @override
  void initState() {
    super.initState();
    if (widget.checkOnStart) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(_check(automatic: true));
      });
    }
  }

  void _message(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));
    }
  }

  Future<void> _check({bool automatic = false}) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final prefs = await SharedPreferences.getInstance();
      final update = await (widget.checkForUpdate ?? UpdateService().check)();
      if (!mounted) return;
      if (update == null) {
        if (!automatic) {
          final info = await PackageInfo.fromPlatform();
          _message('バージョン ${info.version} は最新です。');
        }
        return;
      }
      if (automatic &&
          prefs.getString('update.skippedVersion') == update.version) {
        return;
      }
      setState(() => _showingDialog = true);
      final action = await showDialog<String>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('新しいバージョンがあります'),
          content: SizedBox(
            width: 420,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('${update.currentVersion} → ${update.version}'),
                  const SizedBox(height: 12),
                  Text(update.assetName),
                  const SizedBox(height: 12),
                  Text(
                    update.assetName.endsWith('.exe')
                        ? 'ダウンロード後、変換を終えてアプリを終了し、インストーラーを実行してください。'
                        : 'ダウンロード後、変換を終えてアプリを終了し、DMG内のアプリをApplicationsへコピーしてください。',
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, 'skip'),
              child: const Text('この版をスキップ'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('あとで'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, 'notes'),
              child: const Text('変更内容'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, 'download'),
              child: const Text('ダウンロード'),
            ),
          ],
        ),
      );
      if (action == 'skip') {
        await prefs.setString('update.skippedVersion', update.version);
      }
      if (action == 'notes' || action == 'download') {
        final url = action == 'notes' ? update.releaseUrl : update.downloadUrl;
        final opened =
            await (widget.openUrl?.call(url) ??
                launchUrl(url, mode: LaunchMode.externalApplication));
        if (!opened) _message('ブラウザーを開けませんでした。GitHubのReleaseページをご確認ください。');
      }
    } catch (error) {
      // Startup network failures must never interrupt local media processing.
      if (!automatic || _showingDialog) {
        _message(
          error is UpdateException
              ? error.message
              : '更新確認に失敗しました。しばらくして再確認してください。',
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _showingDialog = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => IconButton(
    tooltip: _busy ? '更新を確認中…' : '更新を確認',
    onPressed: _busy ? null : () => _check(),
    icon: _busy && !_showingDialog
        ? const SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2),
          )
        : const Icon(Icons.system_update_alt),
  );
}
