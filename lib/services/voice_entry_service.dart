import 'dart:async';

import 'package:flutter/services.dart';

class VoiceEntryEvent {
  const VoiceEntryEvent({
    required this.status,
    required this.isListening,
    this.transcript,
    this.error,
    this.isFinal = false,
  });

  final String status;
  final bool isListening;
  final String? transcript;
  final String? error;
  final bool isFinal;

  factory VoiceEntryEvent.fromMap(Map<dynamic, dynamic> map) {
    return VoiceEntryEvent(
      status: map['status']?.toString() ?? 'idle',
      isListening: map['isListening'] == true,
      transcript: map['transcript']?.toString(),
      error: map['error']?.toString(),
      isFinal: map['isFinal'] == true,
    );
  }
}

class VoiceEntryService {
  static const _methodChannel =
      MethodChannel('journal_intelligence/voice_entry');
  static const _eventChannel =
      EventChannel('journal_intelligence/voice_entry/events');

  Stream<VoiceEntryEvent>? _events;

  Stream<VoiceEntryEvent> get events {
    return _events ??= _eventChannel.receiveBroadcastStream().map((event) {
      final map = Map<dynamic, dynamic>.from(event as Map);
      return VoiceEntryEvent.fromMap(map);
    });
  }

  Future<void> startListening() {
    return _methodChannel.invokeMethod<void>('start');
  }

  Future<void> stopListening() {
    return _methodChannel.invokeMethod<void>('stop');
  }

  Future<void> cancelListening() {
    return _methodChannel.invokeMethod<void>('cancel');
  }
}
