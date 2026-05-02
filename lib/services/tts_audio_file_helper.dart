import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/services.dart';

import 'local_storage_paths.dart';

Future<void> configureTtsAudioPlayer(AudioPlayer player) async {
  final context = AudioContext(
    iOS: AudioContextIOS(
      category: AVAudioSessionCategory.playback,
    ),
  );
  await AudioPlayer.global.setAudioContext(context);
  await player.setAudioContext(context);
}

Future<void> playTtsAudioFile(
  AudioPlayer player, {
  required String path,
}) async {
  final file = File(path);
  final exists = await file.exists();
  final size = exists ? await file.length() : 0;
  if (!exists || size <= 0) {
    throw Exception(
      'TTS audio file was not written correctly. exists=$exists size=$size path=$path',
    );
  }

  try {
    await player.release();
    await player.setSourceDeviceFile(path, mimeType: 'audio/mpeg');
    await player.resume();
  } on PlatformException catch (e) {
    final detail = [
      if (e.code.isNotEmpty) 'code=${e.code}',
      if ((e.message ?? '').trim().isNotEmpty) 'message=${e.message}',
      if ((e.details?.toString() ?? '').trim().isNotEmpty)
        'details=${e.details}',
      'exists=$exists',
      'size=$size',
      'path=$path',
    ].join(' | ');
    throw Exception('iOS audio playback failed: $detail');
  }
}

Future<String> writeTtsAudioTempFile({
  required String prefix,
  required List<int> bytes,
}) async {
  final dir = await resolveTemporaryDirectory();
  final safePrefix = prefix.replaceAll(RegExp(r'[^a-zA-Z0-9_-]+'), '_');
  final file = File(
    '${dir.path}/$safePrefix-${DateTime.now().microsecondsSinceEpoch}.mp3',
  );
  await file.writeAsBytes(Uint8List.fromList(bytes), flush: true);
  return file.path;
}

Future<void> deleteTtsAudioTempFile(String? path) async {
  if (path == null || path.isEmpty) return;
  final file = File(path);
  if (await file.exists()) {
    await file.delete();
  }
}
