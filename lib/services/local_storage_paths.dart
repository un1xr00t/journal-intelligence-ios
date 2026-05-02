import 'dart:io';

import 'package:path_provider/path_provider.dart';

Future<Directory> resolveAppSupportDirectory() async {
  try {
    return await getApplicationSupportDirectory();
  } catch (_) {
    final fallback = _fallbackBaseDirectory('Library/Application Support');
    await fallback.create(recursive: true);
    return fallback;
  }
}

Future<Directory> resolveTemporaryDirectory() async {
  try {
    return await getTemporaryDirectory();
  } catch (_) {
    final fallback = _fallbackBaseDirectory('tmp');
    await fallback.create(recursive: true);
    return fallback;
  }
}

Directory _fallbackBaseDirectory(String suffix) {
  final home = Platform.environment['HOME'];
  if (home != null && home.isNotEmpty) {
    return Directory('$home/$suffix');
  }
  return Directory('${Directory.systemTemp.path}/journal_intelligence/$suffix');
}
