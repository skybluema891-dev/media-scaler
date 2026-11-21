import 'package:flutter_test/flutter_test.dart';
import 'package:media_scaler/services/app_settings.dart';
import 'package:media_scaler/services/ffmpeg_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test(
    'Quick Sync HEVC uses its default preset and honors video quality',
    () async {
      SharedPreferences.setMockInitialValues({});
      final settings = await AppSettings.load();
      settings.videoQuality = VideoQuality.high;
      final service = FfmpegService();

      for (final normalQuality in NormalQuality.values) {
        settings.normalQuality = normalQuality;
        expect(service.videoQualityArgs(settings, 'hevc_qsv'), [
          '-global_quality',
          '19',
        ]);
      }
      settings.normalQuality = NormalQuality.standard;
      expect(service.videoQualityArgs(settings, 'h264_qsv'), [
        '-preset',
        'faster',
        '-global_quality',
        '19',
      ]);
    },
  );
}
