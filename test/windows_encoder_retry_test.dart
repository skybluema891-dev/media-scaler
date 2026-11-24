import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_scaler/models/media_item.dart';
import 'package:media_scaler/screens/home_screen.dart';
import 'package:media_scaler/services/app_settings.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _TestPaths extends PathProviderPlatform {
  _TestPaths(this.root);
  final String root;

  @override
  Future<String> getApplicationSupportPath() async => root;
}

Future<ProcessResult> _run(String executable, List<String> args) async {
  final result = await Process.run(executable, args);
  expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
  return result;
}

Future<void> _waitFor(bool Function() condition) async {
  final elapsed = Stopwatch()..start();
  while (!condition()) {
    if (elapsed.elapsed > const Duration(seconds: 20)) {
      fail('Timed out waiting for the conversion or fixture');
    }
    await Future<void>.delayed(const Duration(milliseconds: 30));
  }
}

void main() {
  // Opt in on Windows using the directory containing the packaged FFmpeg pair.
  // The substitute encoder, progress trace, input and outputs stay in test temp.
  final shipped = Platform.environment['MEDIA_SCALER_TEST_FFMPEG_DIR'];
  group(
    'Windows encoder failure through HomeScreen',
    () {
      late Directory scratch;
      late Directory tools;
      late String actual;
      late String probe;
      late File source;
      late List<int> original;
      late File marker;
      late File trace;
      final working = Directory.current;
      final paths = PathProviderPlatform.instance;

      setUpAll(() async {
        scratch = await Directory.systemTemp.createTemp('encoder-retry-');
        tools = await Directory(
          p.join(scratch.path, 'tools', 'ffmpeg', 'windows'),
        ).create(recursive: true);
        actual = p.join(tools.path, 'actual-ffmpeg.exe');
        probe = p.join(tools.path, 'ffprobe.exe');
        await File(p.join(shipped!, 'ffmpeg.exe')).copy(actual);
        await File(p.join(shipped, 'ffprobe.exe')).copy(probe);
        final compiler = p.join(
          Platform.environment['SystemRoot']!,
          'Microsoft.NET',
          'Framework64',
          'v4.0.30319',
          'csc.exe',
        );
        await _run(compiler, [
          '/nologo',
          '/out:${p.join(tools.path, 'ffmpeg.exe')}',
          p.join(working.path, 'test', 'fixtures', 'EncoderFixture.cs'),
        ]);
        marker = File(p.join(tools.path, 'fixture-mode.txt'));
        trace = File(p.join(tools.path, 'fixture-events.txt'));
        source = File(p.join(scratch.path, 'source.mp4'));
        await _run(actual, [
          '-v',
          'error',
          '-f',
          'lavfi',
          '-i',
          'testsrc2=s=64x48:r=2:d=1',
          '-f',
          'lavfi',
          '-i',
          'sine=frequency=440:duration=1',
          '-c:v',
          'libx264',
          '-threads',
          '1',
          '-c:a',
          'aac',
          source.path,
        ]);
        original = await source.readAsBytes();
        PathProviderPlatform.instance = _TestPaths(scratch.path);
        Directory.current = scratch;
      });
      tearDownAll(() async {
        Directory.current = working;
        PathProviderPlatform.instance = paths;
        await scratch.delete(recursive: true);
      });

      // Each test presses the same conversion button used in the Release app.
      // Only the normal libx265 attempt is replaced by a controlled process exit.
      for (final scenario in [
        (
          mode: 'once',
          codec: VideoCodec.h265,
          state: JobState.completed,
          retry: true,
        ),
        (
          mode: 'repeat',
          codec: VideoCodec.h265,
          state: JobState.error,
          retry: true,
        ),
        (
          mode: 'other',
          codec: VideoCodec.h265,
          state: JobState.error,
          retry: false,
        ),
        (
          mode: 'once',
          codec: VideoCodec.h264,
          state: JobState.error,
          retry: false,
        ),
        (
          mode: 'cancel',
          codec: VideoCodec.h265,
          state: JobState.cancelled,
          retry: false,
        ),
      ]) {
        testWidgets(
          '${scenario.mode} ${scenario.codec.name} → ${scenario.state.name}',
          (tester) async {
            marker.writeAsStringSync(scenario.mode);
            trace.writeAsStringSync('');
            final output = Directory(
              p.join(scratch.path, '${scenario.mode}-${scenario.codec.name}'),
            )..createSync();
            SharedPreferences.setMockInitialValues({});
            final settings = await AppSettings.load()
              ..useGpu = false
              ..videoCodec = scenario.codec
              ..sameFolder = false
              ..outputDirectory = output.path;
            final item = MediaItem(source.path, MediaKind.video);
            await tester.pumpWidget(
              MaterialApp(
                home: HomeScreen(
                  settings: settings,
                  initialItems: [item],
                  checkToolsOnStart: false,
                ),
              ),
            );
            await tester.pumpAndSettle();
            final start = find.text('すべて変換開始');
            final cancel = scenario.state == JobState.cancelled;
            await tester.runAsync(() async {
              await tester.tap(start);
              await _waitFor(
                () => cancel
                    ? trace.readAsStringSync().contains('initial') &&
                          output.listSync().whereType<File>().any(
                            (f) =>
                                f.readAsStringSync() ==
                                'Synthetic incomplete output',
                          )
                    : item.state == JobState.completed ||
                          item.state == JobState.error,
              );
            });
            await tester.pump();
            if (cancel) {
              await tester.runAsync(() async {
                await tester.tap(find.text('キャンセル'));
                await _waitFor(() => item.state == JobState.cancelled);
              });
              await tester.pump();
            }
            expect(item.state, scenario.state, reason: item.errorMessage);
            final startButton = find.ancestor(
              of: start,
              matching: find.byWidgetPredicate((w) => w is FilledButton),
            );
            expect(
              tester.widget<FilledButton>(startButton).onPressed,
              isNotNull,
            );
            expect(trace.readAsLinesSync(), [
              '${scenario.mode} initial existed=False',
              if (scenario.retry) '${scenario.mode} retry existed=False',
            ]);
            expect(source.readAsBytesSync(), original);
            if (item.state == JobState.completed) {
              final result = item.outputPath!;
              expect(output.listSync().map((f) => f.path), [result]);
              final info = (await tester.runAsync(
                () => _run(probe, [
                  '-v',
                  'error',
                  '-show_streams',
                  '-of',
                  'json',
                  result,
                ]),
              ))!;
              final streams =
                  (jsonDecode(info.stdout as String)['streams'] as List)
                      .cast<Map<String, dynamic>>();
              final video = streams.singleWhere(
                (s) => s['codec_type'] == 'video',
              );
              expect(
                [video['codec_name'], video['width'], video['height']],
                ['hevc', 128, 96],
              );
              expect(
                streams.singleWhere(
                  (s) => s['codec_type'] == 'audio',
                )['codec_name'],
                'aac',
              );
              await tester.runAsync(
                () => _run(actual, [
                  '-v',
                  'error',
                  '-xerror',
                  '-i',
                  result,
                  '-map',
                  '0',
                  '-f',
                  'null',
                  '-',
                ]),
              );
            } else {
              expect(output.listSync(), isEmpty);
            }
            expect(tester.takeException(), isNull);
          },
        );
      }
    },
    skip: !Platform.isWindows || shipped == null
        ? 'Requires Windows and MEDIA_SCALER_TEST_FFMPEG_DIR'
        : false,
  );
}
