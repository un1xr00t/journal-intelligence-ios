import 'dart:async';
import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/services.dart';

import 'local_storage_paths.dart';

const _remoteAudioMethodChannel =
    MethodChannel('journal_intelligence/remote_audio_controls');
const _remoteAudioEventChannel =
    EventChannel('journal_intelligence/remote_audio_controls/events');
const _remoteAudioSkipInterval = Duration(seconds: 15);

Future<void> configureTtsAudioPlayer(AudioPlayer player) async {
  final context = AudioContext(
    iOS: AudioContextIOS(
      category: AVAudioSessionCategory.playback,
    ),
  );
  await AudioPlayer.global.setAudioContext(context);
  await player.setAudioContext(context);
  if (Platform.isIOS) {
    _TtsRemoteAudioControls.instance.bind(player);
  }
}

Future<void> playTtsAudioFile(
  AudioPlayer player, {
  required String path,
  String title = 'Journal Intelligence',
  String subtitle = 'AI generated audio',
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
    if (Platform.isIOS) {
      await _TtsRemoteAudioControls.instance.activate(
        player,
        title: title,
        subtitle: subtitle,
      );
    }
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

Future<void> clearTtsLockScreenControls() async {
  if (!Platform.isIOS) return;
  await _TtsRemoteAudioControls.instance.clear();
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

class _TtsRemoteAudioControls {
  _TtsRemoteAudioControls._();

  static final instance = _TtsRemoteAudioControls._();

  AudioPlayer? _player;
  String _title = 'Journal Intelligence';
  String _subtitle = 'AI generated audio';
  Duration _position = Duration.zero;
  Duration? _duration;
  DateTime _lastNowPlayingUpdate = DateTime.fromMillisecondsSinceEpoch(0);
  StreamSubscription<dynamic>? _remoteSub;
  StreamSubscription<PlayerState>? _stateSub;
  StreamSubscription<Duration>? _positionSub;
  StreamSubscription<Duration>? _durationSub;

  void bind(AudioPlayer player) {
    if (_player == player) {
      _ensureRemoteSubscription();
      return;
    }

    _stateSub?.cancel();
    _positionSub?.cancel();
    _durationSub?.cancel();
    _player = player;
    _position = Duration.zero;
    _duration = null;
    _ensureRemoteSubscription();

    _stateSub = player.onPlayerStateChanged.listen((state) {
      if (state == PlayerState.stopped ||
          state == PlayerState.completed ||
          state == PlayerState.disposed) {
        unawaited(clear());
      } else {
        unawaited(_updateNowPlaying(isPlaying: state == PlayerState.playing));
      }
    });
    _positionSub = player.onPositionChanged.listen((position) {
      _position = position;
      final now = DateTime.now();
      if (now.difference(_lastNowPlayingUpdate).inMilliseconds >= 900) {
        _lastNowPlayingUpdate = now;
        unawaited(
            _updateNowPlaying(isPlaying: player.state == PlayerState.playing));
      }
    });
    _durationSub = player.onDurationChanged.listen((duration) {
      _duration = duration;
      unawaited(
          _updateNowPlaying(isPlaying: player.state == PlayerState.playing));
    });
  }

  Future<void> activate(
    AudioPlayer player, {
    required String title,
    required String subtitle,
  }) async {
    bind(player);
    _title = title;
    _subtitle = subtitle;
    _position = await player.getCurrentPosition() ?? Duration.zero;
    _duration = await player.getDuration();
    await _updateNowPlaying(isPlaying: true);
  }

  Future<void> clear() async {
    try {
      await _remoteAudioMethodChannel.invokeMethod<void>('clearNowPlaying');
    } on PlatformException {
      // Lock-screen metadata is best-effort; local audio playback should win.
    } on MissingPluginException {
      // Allows non-iOS test hosts to keep using the shared helper.
    }
  }

  void _ensureRemoteSubscription() {
    _remoteSub ??= _remoteAudioEventChannel.receiveBroadcastStream().listen(
      (event) {
        unawaited(_handleRemoteEvent(event));
      },
      onError: (_) {},
    );
  }

  Future<void> _handleRemoteEvent(dynamic event) async {
    final player = _player;
    if (player == null) return;
    final action =
        event is Map ? event['action']?.toString() : event?.toString();
    switch (action) {
      case 'play':
        await player.resume();
        await _updateNowPlaying(isPlaying: true);
      case 'pause':
        await player.pause();
        await _updateNowPlaying(isPlaying: false);
      case 'togglePlayPause':
        if (player.state == PlayerState.playing) {
          await player.pause();
          await _updateNowPlaying(isPlaying: false);
        } else {
          await player.resume();
          await _updateNowPlaying(isPlaying: true);
        }
      case 'skipBackward':
        await _seekBy(-_remoteAudioSkipInterval);
      case 'skipForward':
        await _seekBy(_remoteAudioSkipInterval);
    }
  }

  Future<void> _seekBy(Duration offset) async {
    final player = _player;
    if (player == null) return;
    final current = await player.getCurrentPosition() ?? _position;
    final duration = await player.getDuration() ?? _duration;
    var target = current + offset;
    if (target < Duration.zero) {
      target = Duration.zero;
    } else if (duration != null && target > duration) {
      target = duration;
    }
    await player.seek(target);
    _position = target;
    _duration = duration;
    await _updateNowPlaying(isPlaying: player.state == PlayerState.playing);
  }

  Future<void> _updateNowPlaying({required bool isPlaying}) async {
    try {
      await _remoteAudioMethodChannel.invokeMethod<void>('updateNowPlaying', {
        'title': _title,
        'subtitle': _subtitle,
        'elapsed': _position.inMilliseconds / 1000,
        if (_duration != null) 'duration': _duration!.inMilliseconds / 1000,
        'isPlaying': isPlaying,
      });
    } on PlatformException {
      // Lock-screen metadata is best-effort; local audio playback should win.
    } on MissingPluginException {
      // Allows non-iOS test hosts to keep using the shared helper.
    }
  }
}
