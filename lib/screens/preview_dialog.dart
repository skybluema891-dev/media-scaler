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
    title: const Text('左：元画像 ／ 右：AI処理後'),
    content: SizedBox(
      width: 780,
      height: 450,
      child: Column(
        children: [
          const Text('比較用に短縮した画像です。保存時は元の解像度から処理します。'),
          Expanded(
            child: LayoutBuilder(
              builder: (_, box) => Stack(
                children: [
                  Positioned.fill(
                    child: Image.file(File(widget.result), fit: BoxFit.contain),
                  ),
                  Positioned.fill(
                    child: ClipRect(
                      clipper: _SplitClipper(_split),
                      child: Image.file(
                        File(widget.original),
                        fit: BoxFit.contain,
                      ),
                    ),
                  ),
                  Positioned(
                    left: box.maxWidth * _split,
                    top: 0,
                    bottom: 0,
                    child: Container(
                      width: 2,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                ],
              ),
            ),
          ),
          Slider(
            value: _split,
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
