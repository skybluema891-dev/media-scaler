import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class AppLogger {
  static File? _file;
  static Future<File> get file async {
    if (_file != null) return _file!;
    final base = await getApplicationSupportDirectory();
    final directory = Directory(p.join(base.path, 'logs'));
    await directory.create(recursive: true);
    final value = File(p.join(directory.path, 'media_scaler.log'));
    if (await value.exists() && await value.length() > 2 * 1024 * 1024) {
      final old = File('${value.path}.old');
      if (await old.exists()) await old.delete();
      await value.rename(old.path);
    }
    _file = value;
    return value;
  }

  static Future<void> write(String message) async {
    final target = await file;
    await target.writeAsString(
      '${DateTime.now().toIso8601String()} $message\n',
      mode: FileMode.append,
      flush: true,
    );
  }
}
