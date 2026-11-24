import 'dart:async';
import 'dart:io';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../app_theme.dart';
import '../models/media_item.dart';
import '../services/app_logger.dart';
import '../services/app_settings.dart';
import '../services/ffmpeg_service.dart';
import '../services/ai_service.dart';
import '../services/resize_dimensions.dart';
import 'preview_dialog.dart';
import 'update_button.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({
    super.key,
    required this.settings,
    this.checkToolsOnStart = true,
    this.initialItems = const [],
  });
  final AppSettings settings;
  final bool checkToolsOnStart;
  final List<MediaItem> initialItems;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _items = <MediaItem>[];
  final _ffmpeg = FfmpegService();
  final _ai = AiService();
  bool _cancelRequested = false;
  String _stage = '';
  String _modelStatus = 'モデルを確認中…';
  final _widthController = TextEditingController();
  final _heightController = TextEditingController();
  bool _dragging = false;
  bool _processing = false;
  MediaItem? _selected;

  AppSettings get settings => widget.settings;

  @override
  void initState() {
    super.initState();
    _items.addAll(widget.initialItems);
    _selected = _items.firstOrNull;
    _widthController.text = '${settings.customWidth}';
    _heightController.text = '${settings.customHeight}';
    if (widget.checkToolsOnStart) {
      unawaited(_checkFfmpeg());
      _ai.modelStatus().then((value) {
        if (mounted) setState(() => _modelStatus = value);
      });
    }
  }

  @override
  void dispose() {
    _widthController.dispose();
    _heightController.dispose();
    super.dispose();
  }

  Future<void> _checkFfmpeg() async {
    try {
      await _ffmpeg.initialize();
    } on FfmpegMissingException catch (error) {
      if (mounted) _message(error.toString(), error: true);
    }
  }

  void _message(String text, {bool error = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          text,
          style: error
              ? TextStyle(color: Theme.of(context).colorScheme.onError)
              : null,
        ),
        backgroundColor: error ? Theme.of(context).colorScheme.error : null,
      ),
    );
  }

  Future<void> _pickFiles() async {
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: const [
        'jpg',
        'jpeg',
        'png',
        'webp',
        'mp4',
        'mov',
        'mkv',
        'avi',
        'webm',
      ],
    );
    if (result.isEmpty) return;
    await _addPaths(result.map((file) => file.path).whereType<String>());
  }

  Future<void> _addPaths(Iterable<String> paths) async {
    if (_processing) return;
    var unsupported = 0;
    final existing = _items.map((item) => p.canonicalize(item.path)).toSet();
    final additions = <MediaItem>[];
    for (final path in paths) {
      final kind = kindFromPath(path);
      if (kind == null || !File(path).existsSync()) {
        unsupported++;
        continue;
      }
      if (existing.add(p.canonicalize(path))) {
        additions.add(MediaItem(path, kind)..analyzing = true);
      }
    }
    if (additions.isEmpty) {
      if (unsupported > 0) _message('対応していないファイル形式です。', error: true);
      return;
    }
    setState(() {
      _items.addAll(additions);
      _selected ??= additions.first;
    });
    for (final item in additions) {
      if (!mounted) return;
      try {
        item.info = await _ffmpeg.probe(item.path);
      } catch (error) {
        item.analysisError = error.toString();
      } finally {
        item.analyzing = false;
      }
      if (mounted) setState(() {});
    }
    if (mounted && unsupported > 0) {
      _message('$unsupported 件の未対応ファイルを除外しました。');
    }
  }

  Future<void> _chooseOutputFolder() async {
    final path = await FilePicker.getDirectoryPath(
      initialDirectory: settings.outputDirectory.isEmpty
          ? null
          : settings.outputDirectory,
    );
    if (path == null || !mounted || _processing) return;
    settings.outputDirectory = path;
    settings.sameFolder = false;
    await settings.save();
    if (mounted) setState(() {});
  }

  void _removeItem(MediaItem item) {
    if (_processing) return;
    final path = p.canonicalize(item.path);
    final index = _items.indexWhere(
      (candidate) => p.canonicalize(candidate.path) == path,
    );
    if (index < 0) return;
    setState(() {
      final wasSelected = identical(_selected, _items[index]);
      _items.removeAt(index);
      if (wasSelected) {
        _selected = _items.isEmpty
            ? null
            : _items[index.clamp(0, _items.length - 1)];
      }
    });
  }

  void _clearItems() {
    if (_processing || _items.isEmpty) return;
    setState(() {
      _items.clear();
      _selected = null;
    });
  }

  bool _readCustomSize() {
    final width = int.tryParse(_widthController.text);
    final height = int.tryParse(_heightController.text);
    if (width == null || height == null || !validCustomSize(width, height)) {
      return false;
    }
    settings.customWidth = width;
    settings.customHeight = height;
    return true;
  }

  void _customSizeChanged(String _) {
    final valid = _readCustomSize();
    setState(() {});
    if (valid) unawaited(settings.save());
  }

  Future<void> _startAll() async {
    if (_processing || _items.isEmpty) return;
    if (_items.any((item) => item.analyzing)) {
      _message('ファイルの解析が終わってから変換を開始してください。');
      return;
    }
    if (settings.sizeType == SizeType.custom && !_readCustomSize()) {
      _message('幅・高さは2以上の有効な整数で入力してください。', error: true);
      return;
    }
    if (!settings.sameFolder && settings.outputDirectory.isEmpty) {
      _message('保存先フォルダを選択してください。', error: true);
      return;
    }
    final job = settings.conversion;
    setState(() {
      _processing = true;
      _cancelRequested = false;
      _stage = '';
      for (final item in _items) {
        item.state = JobState.waiting;
        item.progress = 0;
        item.errorMessage = null;
        item.outputPath = null;
        final source = item.info?.pixels;
        item.plannedOutput = job.scaleMode == ScaleMode.resize && source != null
            ? resizeDimensions(source, job, kind: item.kind)
            : null;
      }
    });
    for (final item in _items) {
      if (!mounted || _cancelRequested) break;
      setState(() {
        item.state = JobState.processing;
        _selected = item;
      });
      try {
        if (item.info == null) {
          item.info = await _ffmpeg.probe(item.path);
          item.analysisError = null;
        }
        if (_cancelRequested) throw const ConversionException('キャンセルしました。');
        void progressUpdate(
          double progress,
          Duration elapsed,
          Duration? remaining,
        ) {
          if (!mounted) return;
          setState(() {
            item.progress = progress;
            item.elapsed = elapsed;
            item.remaining = remaining;
          });
        }

        if (job.scaleMode == ScaleMode.resize) {
          final source = item.info?.pixels;
          item.plannedOutput ??= source == null
              ? null
              : resizeDimensions(source, job, kind: item.kind);
          if (item.plannedOutput == null) {
            throw const ConversionException(
              '仕上がりサイズを作れません。倍率を上げるか、より大きいサイズを指定してください。',
            );
          }
        }
        final output = job.scaleMode == ScaleMode.ai
            ? await _ai.convert(
                item: item,
                settings: job,
                ffmpeg: _ffmpeg,
                onProgress: progressUpdate,
                onStage: (value) {
                  if (mounted && _stage != value) {
                    setState(() => _stage = value);
                  }
                },
              )
            : await _ffmpeg.convert(
                item: item,
                settings: job,
                outputSize: item.plannedOutput!,
                onProgress: progressUpdate,
              );
        if (!mounted) return;
        setState(() {
          item.outputPath = output;
          item.progress = 1;
          item.state = JobState.completed;
        });
      } catch (error) {
        if (!mounted) return;
        final cancelled =
            _cancelRequested || error.toString().contains('キャンセル');
        setState(() {
          item.state = cancelled ? JobState.cancelled : JobState.error;
          item.errorMessage = error.toString();
        });
        if (!cancelled && error is FfmpegMissingException) {
          _message(error.toString(), error: true);
          break;
        }
      }
    }
    if (!mounted) return;
    setState(() => _processing = false);
  }

  Future<void> _cancel() async {
    setState(() {
      _cancelRequested = true;
      _stage = '停止しています…';
      for (final item in _items.where(
        (item) => item.state == JobState.waiting,
      )) {
        item.state = JobState.cancelled;
      }
    });
    await _ai.cancel();
    await _ffmpeg.cancel();
  }

  Future<void> _openLog() async {
    final log = await AppLogger.file;
    try {
      await Process.start(Platform.isWindows ? 'explorer.exe' : 'open', [
        log.path,
      ], mode: ProcessStartMode.detached);
    } catch (_) {
      if (mounted) _message('ログ: ${log.path}');
    }
  }

  Future<void> _preview() async {
    final item = _selected;
    if (_processing || item == null || item.kind != MediaKind.image) return;
    if (settings.sizeType == SizeType.custom && !_readCustomSize()) {
      _message('幅・高さは2以上の有効な整数で入力してください。', error: true);
      return;
    }
    final job = settings.conversion;
    setState(() {
      _processing = true;
      _cancelRequested = false;
      _stage = '比較プレビューを作成中…';
    });
    Directory? directory;
    try {
      directory = await AiService.previewFolder();
      final previewPath = directory.path;
      final output = await _ai.convert(
        item: item,
        settings: job,
        ffmpeg: _ffmpeg,
        preview: true,
        previewDirectory: previewPath,
        onProgress: (_, _, _) {},
        onStage: (stage) {
          if (mounted && _stage != stage) setState(() => _stage = stage);
        },
      );
      if (mounted && !_cancelRequested) {
        await showDialog<void>(
          context: context,
          // On Windows, expose the comparison route without overlapping the
          // outgoing and incoming accessibility trees during a transition.
          animationStyle: Platform.isWindows
              ? AnimationStyle.noAnimation
              : null,
          requestFocus: true,
          builder: (_) => PreviewDialog(
            original: p.join(previewPath, 'original.png'),
            result: output,
          ),
        );
      }
    } catch (error) {
      if (mounted) _message(error.toString(), error: true);
    } finally {
      if (directory != null && await directory.exists()) {
        try {
          await directory.delete(recursive: true);
        } catch (_) {}
      }
      if (mounted) {
        setState(() {
          _processing = false;
          _stage = '';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 56 * MediaQuery.textScalerOf(context).scale(1),
        titleSpacing: 20,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Media Scaler',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.titleLarge,
            ),
            Text(
              '画像・動画のサイズ変換・高画質化',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall,
            ),
          ],
        ),
        actions: [
          UpdateButton(checkOnStart: widget.checkToolsOnStart),
          PopupMenuButton<ThemeMode>(
            tooltip: '表示テーマ',
            icon: const Icon(Icons.brightness_6_outlined),
            initialValue: settings.themeMode,
            onSelected: (value) {
              settings.themeMode = value;
              unawaited(settings.save());
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: ThemeMode.system, child: Text('OSの設定に合わせる')),
              PopupMenuItem(value: ThemeMode.light, child: Text('ライトモード')),
              PopupMenuItem(value: ThemeMode.dark, child: Text('ダークモード')),
            ],
          ),
          IconButton(
            onPressed: _openLog,
            tooltip: 'ログを開く',
            icon: const Icon(Icons.article_outlined),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: DecoratedBox(
        decoration: BoxDecoration(
          gradient: theme.brightness == Brightness.dark
              ? AppTheme.darkBackground
              : null,
        ),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final list = _fileArea();
            final panel = _settingsPanel();
            return Padding(
              padding: const EdgeInsets.all(16),
              child: constraints.maxWidth >= 900
                  ? Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(flex: 3, child: list),
                        const SizedBox(width: 16),
                        SizedBox(width: 360, child: panel),
                      ],
                    )
                  : SingleChildScrollView(
                      child: Column(
                        children: [
                          SizedBox(
                            height: (constraints.maxHeight * .5).clamp(
                              300.0,
                              440.0,
                            ),
                            child: list,
                          ),
                          const SizedBox(height: 12),
                          panel,
                        ],
                      ),
                    ),
            );
          },
        ),
      ),
      bottomNavigationBar: DecoratedBox(
        decoration: BoxDecoration(
          color: colors.surfaceContainerLow,
          border: Border(top: BorderSide(color: colors.outlineVariant)),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: LayoutBuilder(
              builder: (context, box) {
                final count = Semantics(
                  liveRegion: true,
                  child: Text(
                    '${_items.length} ファイル　完了 ${_items.where((e) => e.state == JobState.completed).length} 件',
                    style: theme.textTheme.bodyMedium,
                  ),
                );
                final buttons = [
                  OutlinedButton.icon(
                    onPressed: _processing && !_cancelRequested
                        ? _cancel
                        : null,
                    icon: const Icon(Icons.stop_circle_outlined),
                    label: const Text('キャンセル'),
                  ),
                  FilledButton.icon(
                    onPressed: !_processing && _items.isNotEmpty
                        ? _startAll
                        : null,
                    icon: const Icon(Icons.play_arrow),
                    label: const Text('すべて変換開始'),
                  ),
                ];
                if (box.maxWidth <
                    420 * MediaQuery.textScalerOf(context).scale(1)) {
                  return Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      count,
                      Wrap(spacing: 8, children: buttons),
                    ],
                  );
                }
                return Row(
                  children: [
                    Expanded(child: count),
                    buttons.first,
                    const SizedBox(width: 8),
                    buttons.last,
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  Widget _fileArea() {
    return DropTarget(
      onDragEntered: (_) => setState(() => _dragging = true),
      onDragExited: (_) => setState(() => _dragging = false),
      onDragDone: (detail) {
        setState(() => _dragging = false);
        unawaited(_addPaths(detail.files.map((file) => file.path)));
      },
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: Column(
          children: [
            Container(
              color: _dragging
                  ? Theme.of(context).colorScheme.primaryContainer
                  : Theme.of(context).colorScheme.surfaceContainerLow,
              padding: const EdgeInsets.all(16),
              child: OverflowBar(
                alignment: MainAxisAlignment.spaceBetween,
                overflowAlignment: OverflowBarAlignment.start,
                overflowSpacing: 2,
                children: [
                  Text(
                    _dragging ? 'ここにドロップしてください' : 'ファイル一覧',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  Wrap(
                    spacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      if (_items.isNotEmpty) ...[
                        TextButton.icon(
                          onPressed: _processing ? null : _clearItems,
                          icon: const Icon(Icons.delete_sweep_outlined),
                          label: const Text('一覧を空にする'),
                        ),
                      ],
                      OutlinedButton.icon(
                        onPressed: _processing ? null : _pickFiles,
                        icon: const Icon(Icons.add_photo_alternate_outlined),
                        label: const Text('画像・動画を追加'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            Expanded(
              child: _items.isEmpty
                  ? _emptyDropArea()
                  : ListView.separated(
                      itemCount: _items.length,
                      separatorBuilder: (_, _) => const Divider(height: 1),
                      itemBuilder: (_, index) => _itemTile(_items[index]),
                    ),
            ),
            if (_selected != null) _infoBar(_selected!),
          ],
        ),
      ),
    );
  }

  Widget _emptyDropArea() {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Material(
        color: _dragging
            ? colors.secondaryContainer
            : colors.surfaceContainerLow,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: BorderSide(
            color: _dragging ? colors.primary : colors.outlineVariant,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: _pickFiles,
          child: Center(
            child: SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.file_upload_outlined,
                      size: 36,
                      color: colors.onSurfaceVariant,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      '画像・動画をここへドラッグ＆ドロップ',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.titleMedium,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'または上の「画像・動画を追加」を押します',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  String? _sizeSummary(MediaItem item) {
    final useCurrentSettings = !_processing && item.state == JobState.waiting;
    if (useCurrentSettings && settings.scaleMode != ScaleMode.resize)
      return null;
    if (item.analyzing) return '寸法を解析中…';
    if (item.analysisError != null) return '寸法を取得できませんでした';
    final source = item.info?.pixels;
    if (source == null) return null;
    final input = '${source.width}×${source.height}';
    if (useCurrentSettings &&
        settings.sizeType == SizeType.custom &&
        !validCustomSize(
          int.tryParse(_widthController.text) ?? 0,
          int.tryParse(_heightController.text) ?? 0,
        )) {
      return '$input　幅・高さを有効な整数で入力';
    }
    final output = useCurrentSettings
        ? resizeDimensions(source, settings.conversion, kind: item.kind)
        : item.plannedOutput;
    if (output == null) {
      return useCurrentSettings ? '$input　倍率か仕上がりサイズを変更' : null;
    }
    final dw = output.width - source.width;
    final dh = output.height - source.height;
    final direction = switch ((dw, dh)) {
      (0, 0) => '同じサイズ',
      (var w, var h) when w.abs() <= 1 && h.abs() <= 1 => 'サイズ調整',
      (>= 0, >= 0) => '拡大',
      (<= 0, <= 0) => '縮小',
      _ => 'サイズ調整',
    };
    return '$input → ${output.width}×${output.height}　$direction';
  }

  Widget _itemTile(MediaItem item) {
    final colors = Theme.of(context).colorScheme;
    final dark = colors.brightness == Brightness.dark;
    final details =
        '${item.kind == MediaKind.image ? '画像' : '動画'} ・ ${formatBytes(item.sizeBytes)}';
    final size = _sizeSummary(item);
    final status = switch (item.state) {
      JobState.waiting => ('待機中', Icons.schedule, colors.onSurfaceVariant),
      JobState.processing => ('処理中', Icons.sync, colors.primary),
      JobState.completed => (
        '完了',
        Icons.check_circle,
        dark ? const Color(0xFF9CC4AC) : const Color(0xFF286444),
      ),
      JobState.error => ('エラー', Icons.error, colors.error),
      JobState.cancelled => (
        'キャンセル',
        Icons.cancel,
        dark ? const Color(0xFFD8BC8E) : const Color(0xFF715124),
      ),
    };
    return ListTile(
      key: ValueKey(item.path),
      selected: identical(item, _selected),
      onTap: () => setState(() => _selected = item),
      leading: item.kind == MediaKind.image
          ? ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: Image.file(
                File(item.path),
                width: 52,
                height: 44,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => const Icon(Icons.image_outlined),
              ),
            )
          : const SizedBox(
              width: 52,
              child: Icon(Icons.movie_outlined, size: 34),
            ),
      title: Text(item.fileName, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Semantics(
        container: true,
        excludeSemantics: true,
        label: size == null ? details : '$details　$size',
        value: item.state == JobState.processing
            ? '${(item.progress * 100).round()}% ・ 経過 ${formatDuration(item.elapsed)}${item.remaining == null ? '' : ' ・ 残り約 ${formatDuration(item.remaining!)}'}'
            : item.errorMessage ?? status.$1,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(details),
            if (size != null)
              Text(size, style: Theme.of(context).textTheme.bodySmall),
            if (item.state == JobState.processing) ...[
              const SizedBox(height: 4),
              LinearProgressIndicator(value: item.progress),
              Text(
                '${(item.progress * 100).toStringAsFixed(0)}% ・ 経過 ${formatDuration(item.elapsed)}${item.remaining == null ? '' : ' ・ 残り約 ${formatDuration(item.remaining!)}'}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
            if (item.errorMessage != null && item.state == JobState.error)
              Text(
                item.errorMessage!,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
          ],
        ),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(status.$2, color: status.$3, size: 18),
          const SizedBox(width: 5),
          Text(status.$1),
          IconButton(
            key: ValueKey('remove-${item.path}'),
            tooltip: '一覧から削除',
            onPressed: _processing ? null : () => _removeItem(item),
            icon: const Icon(Icons.delete_outline),
          ),
        ],
      ),
    );
  }

  Widget _infoBar(MediaItem item) {
    final info = item.info;
    final values = <String>[
      if (info?.width != null) '${info!.width} × ${info.height}',
      if (info?.sampleAspectRatio case final String ratio
          when ratio != '1/1' && ratio != '0/1')
        '画素比 ${ratio.replaceAll('/', ':')}',
      if (item.kind == MediaKind.video && info?.frameRate != null)
        '${info!.frameRate!.toStringAsFixed(2)} fps',
      if (item.kind == MediaKind.video && info?.durationSeconds != null)
        formatDuration(
          Duration(milliseconds: (info!.durationSeconds! * 1000).round()),
        ),
      if (info?.codec != null) info!.codec!.toUpperCase(),
      if (info?.format != null) info!.format!,
    ];
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Text(
        item.analysisError ??
            (values.isEmpty ? 'ファイル情報を取得中…' : values.join('　・　')),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }

  Widget _settingsPanel() {
    return Card(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('処理設定', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 14),
            SegmentedButton<ScaleMode>(
              segments: const [
                ButtonSegment(value: ScaleMode.resize, label: Text('サイズ変換')),
                ButtonSegment(value: ScaleMode.ai, label: Text('AI高画質化')),
              ],
              selected: {settings.scaleMode},
              onSelectionChanged: _processing
                  ? null
                  : (value) {
                      setState(() => settings.scaleMode = value.first);
                      unawaited(settings.save());
                    },
            ),
            const SizedBox(height: 14),
            if (settings.scaleMode == ScaleMode.resize) ...[
              Text(
                '共通設定に合わせて、ファイルごとに拡大・縮小します。同じサイズでも再保存します。',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 12),
            ],
            if (settings.scaleMode == ScaleMode.ai) ...[
              Text(_modelStatus, style: Theme.of(context).textTheme.bodySmall),
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                initialValue: settings.aiModel,
                isExpanded: true,
                decoration: const InputDecoration(labelText: '素材の種類'),
                items: const [
                  DropdownMenuItem(value: 'photo', child: Text('写真・実写（細部を復元）')),
                  DropdownMenuItem(
                    value: 'anime',
                    child: Text('イラスト・アニメ（輪郭を改善）'),
                  ),
                ],
                onChanged: _processing
                    ? null
                    : (value) {
                        setState(() => settings.aiModel = value!);
                        unawaited(settings.save());
                      },
              ),
              const SizedBox(height: 10),
              DropdownButtonFormField<NormalQuality>(
                initialValue: settings.aiQuality,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'AIの品質'),
                items: const [
                  DropdownMenuItem(
                    value: NormalQuality.fast,
                    child: Text('高速（軽量・アニメ向けモデル）'),
                  ),
                  DropdownMenuItem(
                    value: NormalQuality.standard,
                    child: Text('標準（選んだ素材に最適化）'),
                  ),
                  DropdownMenuItem(
                    value: NormalQuality.high,
                    child: Text('高画質（画像は複数回処理）'),
                  ),
                ],
                onChanged: _processing
                    ? null
                    : (value) {
                        setState(() => settings.aiQuality = value!);
                        unawaited(settings.save());
                      },
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('AIでGPUを優先'),
                subtitle: const Text('利用できない場合はCPUで続行します'),
                value: settings.aiUseGpu,
                onChanged: _processing
                    ? null
                    : (value) {
                        setState(() => settings.aiUseGpu = value);
                        unawaited(settings.save());
                      },
              ),
              DropdownButtonFormField<int>(
                initialValue: settings.aiVideoFps,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'AI動画のフレームレート'),
                items: const [
                  DropdownMenuItem(value: 30, child: Text('最大30 fps（おすすめ）')),
                  DropdownMenuItem(value: 24, child: Text('最大24 fps（より高速）')),
                  DropdownMenuItem(value: 0, child: Text('元動画を維持（非常に低速）')),
                ],
                onChanged: _processing
                    ? null
                    : (value) {
                        setState(() => settings.aiVideoFps = value!);
                        unawaited(settings.save());
                      },
              ),
              const SizedBox(height: 8),
              const Text(
                '複数フレームをまとめてGPU処理します。長い動画は「高速」と最大24/30 fpsがおすすめです。音声は保持します。HDRは対象外です。',
                style: TextStyle(fontSize: 12),
              ),
              OutlinedButton.icon(
                onPressed: !_processing && _selected?.kind == MediaKind.image
                    ? _preview
                    : null,
                icon: const Icon(Icons.compare),
                label: const Text('画像のAI比較プレビュー'),
              ),
              Text(_processing ? _stage : '待機中'),
              const SizedBox(height: 14),
            ],
            DropdownButtonFormField<SizeType>(
              key: ValueKey(settings.sizeType),
              initialValue: settings.sizeType,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'サイズの決め方'),
              items: const [
                DropdownMenuItem(
                  value: SizeType.multiplier,
                  child: Text('倍率で指定'),
                ),
                DropdownMenuItem(
                  value: SizeType.preset,
                  child: Text('プリセットから選ぶ'),
                ),
                DropdownMenuItem(
                  value: SizeType.custom,
                  child: Text('幅・高さで指定'),
                ),
              ],
              onChanged: _processing
                  ? null
                  : (value) {
                      if (value == null) return;
                      setState(() => settings.sizeType = value);
                      unawaited(settings.save());
                    },
            ),
            const SizedBox(height: 12),
            _sizeControls(),
            const SizedBox(height: 12),
            DropdownButtonFormField<NormalQuality>(
              initialValue: settings.normalQuality,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: '変換のきれいさ',
                helperText: '高品質ほど処理に時間がかかります',
              ),
              items: const [
                DropdownMenuItem(value: NormalQuality.fast, child: Text('高速')),
                DropdownMenuItem(
                  value: NormalQuality.standard,
                  child: Text('標準（おすすめ）'),
                ),
                DropdownMenuItem(value: NormalQuality.high, child: Text('高品質')),
              ],
              onChanged: _processing
                  ? null
                  : (value) {
                      if (value == null) return;
                      setState(() => settings.normalQuality = value);
                      unawaited(settings.save());
                    },
            ),
            const SizedBox(height: 16),
            Text('動画の設定', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                DropdownButtonFormField<VideoQuality>(
                  initialValue: settings.videoQuality,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: '動画品質'),
                  items: const [
                    DropdownMenuItem(
                      value: VideoQuality.compact,
                      child: Text('軽量'),
                    ),
                    DropdownMenuItem(
                      value: VideoQuality.standard,
                      child: Text('標準'),
                    ),
                    DropdownMenuItem(
                      value: VideoQuality.high,
                      child: Text('高画質'),
                    ),
                    DropdownMenuItem(
                      value: VideoQuality.maximum,
                      child: Text('最高画質'),
                    ),
                  ],
                  onChanged: _processing
                      ? null
                      : (value) {
                          if (value == null) return;
                          setState(() => settings.videoQuality = value);
                          unawaited(settings.save());
                        },
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<VideoCodec>(
                  initialValue: settings.videoCodec,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: '動画形式'),
                  items: const [
                    DropdownMenuItem(
                      value: VideoCodec.h264,
                      child: Text('互換性優先 (H.264)'),
                    ),
                    DropdownMenuItem(
                      value: VideoCodec.h265,
                      child: Text('容量優先 (H.265)'),
                    ),
                  ],
                  onChanged: _processing
                      ? null
                      : (value) {
                          if (value == null) return;
                          setState(() => settings.videoCodec = value);
                          unawaited(settings.save());
                        },
                ),
              ],
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('GPUで高速化'),
              subtitle: const Text('通常動画の書き出しを高速化。使えない場合はCPUへ切替'),
              value: settings.useGpu,
              onChanged: _processing
                  ? null
                  : (value) {
                      setState(() => settings.useGpu = value);
                      unawaited(settings.save());
                    },
            ),
            Text('JPEG画像の品質：${settings.jpegQuality}'),
            Slider(
              // On Windows, replace the slider and its value-indicator overlay
              // together when disabling it. The AX bridge removes the old
              // parent's subtree before attaching the new one.
              key: Theme.of(context).platform == TargetPlatform.windows
                  ? ValueKey(_processing)
                  : null,
              value: settings.jpegQuality.toDouble(),
              min: 1,
              max: 100,
              divisions: 99,
              label: '${settings.jpegQuality}',
              onChanged: _processing
                  ? null
                  : (value) =>
                        setState(() => settings.jpegQuality = value.round()),
              onChangeEnd: (_) => unawaited(settings.save()),
            ),
            const Divider(height: 28),
            Text('保存先', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            DropdownButtonFormField<bool>(
              initialValue: settings.renameOutput,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'タイトル（ファイル名）の変更'),
              items: const [
                DropdownMenuItem(value: true, child: Text('変更OK（サイズを付ける）')),
                DropdownMenuItem(value: false, child: Text('変更NG（サイズを付けない）')),
              ],
              onChanged: _processing
                  ? null
                  : (value) {
                      if (value == null) return;
                      setState(() => settings.renameOutput = value);
                      unawaited(settings.save());
                    },
            ),
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: Text(
                '同名ファイルがある場合は、上書きせず連番を付けます。動画の拡張子は.mp4になります。',
                style: TextStyle(fontSize: 12),
              ),
            ),
            RadioGroup<bool>(
              groupValue: settings.sameFolder,
              onChanged: (value) {
                if (_processing || value == null) return;
                setState(() => settings.sameFolder = value);
                unawaited(settings.save());
              },
              child: Column(
                children: [
                  const RadioListTile(
                    value: true,
                    contentPadding: EdgeInsets.zero,
                    title: Text('元ファイルと同じフォルダ'),
                  ),
                  RadioListTile(
                    value: false,
                    contentPadding: EdgeInsets.zero,
                    title: const Text('指定したフォルダ'),
                    subtitle: Text(
                      settings.outputDirectory.isEmpty
                          ? '未選択'
                          : settings.outputDirectory,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
            OutlinedButton.icon(
              onPressed: _processing ? null : _chooseOutputFolder,
              icon: const Icon(Icons.folder_open),
              label: const Text('保存先フォルダを選ぶ'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sizeControls() {
    if (settings.sizeType == SizeType.multiplier) {
      final ai = settings.scaleMode == ScaleMode.ai;
      return DropdownButtonFormField<num>(
        key: ValueKey(settings.scaleMode),
        initialValue: ai ? settings.aiMultiplier : settings.resizeMultiplier,
        isExpanded: true,
        decoration: InputDecoration(labelText: ai ? 'AIの倍率' : '倍率'),
        items: [
          for (final value in ai ? aiMultipliers : resizeMultipliers)
            DropdownMenuItem(
              value: value,
              child: Text('${formatMultiplier(value.toDouble())}倍'),
            ),
        ],
        onChanged: _processing
            ? null
            : (value) {
                if (value == null) return;
                setState(() {
                  if (ai) {
                    settings.aiMultiplier = value.toInt();
                  } else {
                    settings.resizeMultiplier = value.toDouble();
                  }
                });
                unawaited(settings.save());
              },
      );
    }
    if (settings.sizeType == SizeType.preset) {
      return DropdownButtonFormField<int>(
        initialValue: settings.presetHeight,
        isExpanded: true,
        decoration: const InputDecoration(
          labelText: '仕上がり解像度',
          helperText: '短辺を基準に、縦横比を保って調整します',
          helperMaxLines: 3,
        ),
        items: [
          for (final value in sizePresets)
            DropdownMenuItem(value: value, child: Text('${value}p')),
        ],
        onChanged: _processing
            ? null
            : (value) {
                if (value == null) return;
                setState(() => settings.presetHeight = value);
                unawaited(settings.save());
              },
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '縦横比を保って、指定した幅・高さの枠に収めます。',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _widthController,
                enabled: !_processing,
                onChanged: _customSizeChanged,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: '横幅 (px)'),
              ),
            ),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 8),
              child: Text('×'),
            ),
            Expanded(
              child: TextField(
                controller: _heightController,
                enabled: !_processing,
                onChanged: _customSizeChanged,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: '高さ (px)'),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
