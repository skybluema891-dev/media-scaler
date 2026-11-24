import 'dart:io';

import 'package:flutter/material.dart';

class PreviewDialog extends StatefulWidget {
  const PreviewDialog({
    super.key,
    required this.original,
    required this.result,
  });
  final String original;
  final String result;
  @override
  State<PreviewDialog> createState() => _PreviewDialogState();
}

class _PreviewDialogState extends State<PreviewDialog> {
  double _split = .5;
  @override
  Widget build(BuildContext context) => AlertDialog(
    insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
    titlePadding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
    contentPadding: const EdgeInsets.symmetric(horizontal: 20),
    actionsPadding: const EdgeInsets.fromLTRB(20, 4, 12, 8),
    title: const Text('左：元画像 ／ 右：AI処理後'),
    content: SizedBox(
      width: 780,
      height: 450,
      child: Column(
        children: [
          Text(
            '比較用に短縮した画像です。保存時は元の解像度から処理します。',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 6),
          Expanded(
            child: SizedBox.expand(
              child: FittedBox(
                fit: BoxFit.contain,
                child: Stack(
                  children: [
                    Image.file(File(widget.result), excludeFromSemantics: true),
                    Positioned.fill(
                      child: ClipRect(
                        clipper: _SplitClipper(_split),
                        child: Image.file(
                          File(widget.original),
                          fit: BoxFit.contain,
                          excludeFromSemantics: true,
                        ),
                      ),
                    ),
                    Positioned.fill(
                      child: Align(
                        alignment: Alignment(_split * 2 - 1, 0),
                        child: FractionallySizedBox(
                          widthFactor: .003,
                          child: ColoredBox(
                            color: Theme.of(context).colorScheme.primary,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Slider(
            label: '比較境界',
            autofocus: true,
            value: _split,
            semanticFormatterCallback: (value) =>
                '元画像 ${(value * 100).round()}パーセント',
            onChanged: (value) => setState(() => _split = value),
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('閉じる'),
      ),
    ],
  );
}

class _SplitClipper extends CustomClipper<Rect> {
  _SplitClipper(this.split);
  final double split;
  @override
  Rect getClip(Size size) =>
      Rect.fromLTWH(0, 0, size.width * split, size.height);
  @override
  bool shouldReclip(_SplitClipper oldClipper) => split != oldClipper.split;
}
