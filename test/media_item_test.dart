import 'package:flutter_test/flutter_test.dart';
import 'package:media_scaler/models/media_item.dart';

void main() {
  test('対応形式を画像と動画へ正しく分類する', () {
    expect(kindFromPath(r'C:\sample\photo.JPG'), MediaKind.image);
    expect(kindFromPath('/sample/movie.mp4'), MediaKind.video);
    expect(kindFromPath('/sample/document.txt'), isNull);
  });

  test('ファイル容量を読みやすく表示する', () {
    expect(formatBytes(500), '500 B');
    expect(formatBytes(1536), '1.5 KB');
    expect(formatBytes(2 * 1024 * 1024), '2.0 MB');
  });

  test('時間を分秒で表示する', () {
    expect(formatDuration(const Duration(seconds: 65)), '01:05');
    expect(
      formatDuration(const Duration(hours: 1, minutes: 2, seconds: 3)),
      '1:02:03',
    );
  });
}
