import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_scaler/app_theme.dart';
import 'package:media_scaler/models/media_item.dart';
import 'package:media_scaler/screens/home_screen.dart';
import 'package:media_scaler/services/app_settings.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';

// The Windows AX bridge first removes a moved child from its previous parent.
// The packet attaching that child under its new parent must supply its data.
class _WindowsSemanticsBinding extends AutomatedTestWidgetsFlutterBinding {
  final tree = <int, List<int>>{};
  final missing = <int>[];
  int packets = 0;

  @override
  ui.SemanticsUpdateBuilder createSemanticsUpdateBuilder() =>
      _PacketBuilder(_record);

  void _record(Map<int, List<int>> delta) {
    packets++;
    final parents = {
      for (final entry in tree.entries)
        for (final child in entry.value) child: entry.key,
    };
    for (final entry in delta.entries) {
      for (final child in entry.value) {
        if (parents.containsKey(child) &&
            parents[child] != entry.key &&
            !delta.containsKey(child)) {
          missing.add(child);
        }
      }
    }
    tree.addAll(delta);
    final reachable = <int>{};
    final pending = [0];
    while (pending.isNotEmpty) {
      final id = pending.removeLast();
      if (reachable.add(id)) pending.addAll(tree[id] ?? const []);
    }
    tree.removeWhere((id, _) => !reachable.contains(id));
  }
}

class _PacketBuilder extends Fake implements ui.SemanticsUpdateBuilder {
  _PacketBuilder(this.record);
  final void Function(Map<int, List<int>>) record;
  final real = ui.SemanticsUpdateBuilder();
  final delta = <int, List<int>>{};

  @override
  dynamic noSuchMethod(Invocation invocation) {
    // Forward every engine field while reading just the two that form the tree.
    final args = invocation.namedArguments;
    if (invocation.memberName == #updateNode) {
      delta[args[#id] as int] = List<int>.of(
        args[#childrenInTraversalOrder] as Iterable<int>,
      );
      return Function.apply(real.updateNode, [], args);
    }
    if (invocation.memberName == #updateCustomAction) {
      return Function.apply(real.updateCustomAction, [], args);
    }
    return super.noSuchMethod(invocation);
  }

  @override
  ui.SemanticsUpdate build() {
    record(delta);
    return real.build();
  }
}

class _PreviewPaths extends PathProviderPlatform {
  final location = Completer<String?>();
  @override
  Future<String?> getApplicationSupportPath() => location.future;
}

void main() {
  final binding = _WindowsSemanticsBinding();
  testWidgets('JPEG quality keeps complete Windows semantics across a job', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1280, 720);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    final systemPaths = PathProviderPlatform.instance;
    final preview = _PreviewPaths();
    PathProviderPlatform.instance = preview;
    addTearDown(() => PathProviderPlatform.instance = systemPaths);
    SharedPreferences.setMockInitialValues({});
    final settings = await AppSettings.load()
      ..scaleMode = ScaleMode.ai;
    const path =
        'macos/Runner/Assets.xcassets/AppIcon.appiconset/app_icon_16.png';
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: HomeScreen(
          settings: settings,
          initialItems: [MediaItem(path, MediaKind.image)],
          checkToolsOnStart: false,
        ),
      ),
    );
    await tester.pumpAndSettle();
    final slider = find.byType(Slider);
    final open = find.text('画像のAI比較プレビュー');
    await tester.ensureVisible(open);
    await tester.pumpAndSettle();
    final before = binding.packets;
    await tester.tap(open);
    await tester.pumpAndSettle();
    expect(tester.widget<Slider>(slider).onChanged, isNull);
    expect(binding.packets, greaterThan(before));
    expect(binding.missing, isEmpty);
    final during = binding.packets;
    preview.location.completeError(
      StateError('End preview before starting the worker'),
    );
    await tester.pumpAndSettle();
    expect(tester.widget<Slider>(slider).onChanged, isNotNull);
    expect(binding.packets, greaterThan(during));
    expect(binding.missing, isEmpty);

    await tester.ensureVisible(slider);
    await tester.pumpAndSettle();
    final focus = tester
        .widget<FocusableActionDetector>(
          find.descendant(
            of: slider,
            matching: find.byType(FocusableActionDetector),
          ),
        )
        .focusNode!;
    focus.requestFocus();
    await tester.pump();
    final quality = settings.jpegQuality;
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    expect(settings.jpegQuality, quality + 1);
    final value = find.semantics.byLabel('${quality + 1}').evaluate().single;
    expect(value.value, '${quality + 1}%');
    expect(tester.takeException(), isNull);
  }, variant: TargetPlatformVariant.only(TargetPlatform.windows));
}
