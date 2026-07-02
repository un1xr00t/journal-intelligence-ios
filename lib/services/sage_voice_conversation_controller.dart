import 'dart:async';

import 'package:flutter/foundation.dart';

import 'voice_entry_service.dart';

/// Phases of a hands-free Sage voice conversation.
enum SageVoicePhase {
  /// Not yet started, or between sessions.
  idle,

  /// Microphone open, capturing the user's turn.
  listening,

  /// Turn captured; waiting on Sage's reply.
  thinking,

  /// Speaking Sage's reply out loud.
  speaking,

  /// Something failed; user can retry or end.
  error,

  /// Session finished (user ended it or it timed out).
  ended,
}

/// Drives the listen → send → speak → re-listen loop for Sage voice mode.
///
/// Speech capture reuses [VoiceEntryService] (native SFSpeechRecognizer).
/// Sending and speaking are delegated back to the Sage screen so the
/// conversation shares the exact same thread, context, and TTS pipeline
/// as typed chat.
class SageVoiceConversationController extends ChangeNotifier {
  SageVoiceConversationController({
    required VoiceEntryService voiceEntry,
    required this.sendTurn,
    required this.speakReply,
    required this.stopSpeaking,
    this.silenceThreshold = const Duration(milliseconds: 2200),
    this.noSpeechTimeout = const Duration(seconds: 10),
  }) : _voiceEntry = voiceEntry;

  /// Sends one user turn through the normal Sage chat pipeline and returns
  /// the assistant reply text (null on failure).
  final Future<String?> Function(String transcript) sendTurn;

  /// Speaks the most recent assistant reply via the existing TTS pipeline.
  /// Completes when playback finishes; returns false if TTS failed.
  final Future<bool> Function() speakReply;

  /// Immediately stops any TTS playback.
  final Future<void> Function() stopSpeaking;

  /// How long the transcript must stay unchanged before the turn auto-sends.
  final Duration silenceThreshold;

  /// How long to wait with an empty transcript before ending the session.
  final Duration noSpeechTimeout;

  final VoiceEntryService _voiceEntry;

  SageVoicePhase _phase = SageVoicePhase.idle;
  String _transcript = '';
  String _lastReply = '';
  String? _errorText;
  int _turnCount = 0;

  StreamSubscription<VoiceEntryEvent>? _eventsSub;
  Timer? _ticker;
  DateTime _lastTranscriptChange = DateTime.now();
  DateTime _listenStartedAt = DateTime.now();
  Completer<String>? _finalTranscriptCompleter;
  bool _stopRequested = false;
  bool _disposed = false;

  /// Bumped on every state transition so stale async continuations bail out.
  int _generation = 0;

  SageVoicePhase get phase => _phase;
  String get transcript => _transcript;
  String get lastReply => _lastReply;
  String? get errorText => _errorText;
  int get turnCount => _turnCount;
  bool get isActive =>
      _phase != SageVoicePhase.idle && _phase != SageVoicePhase.ended;

  /// Starts the session: opens the mic and begins the loop.
  Future<void> start() async {
    if (_disposed || isActive) return;
    _eventsSub ??= _voiceEntry.events.listen(
      _handleVoiceEvent,
      onError: (Object e) => _failListening(_describeError(e)),
    );
    await _beginListening();
  }

  /// Ends the whole session (user tapped end, or screen is closing).
  Future<void> endSession() async {
    if (_disposed) return;
    final generation = ++_generation;
    _ticker?.cancel();
    _stopRequested = true;
    try {
      await _voiceEntry.cancelListening();
    } catch (_) {}
    try {
      await stopSpeaking();
    } catch (_) {}
    if (_disposed || generation != _generation) return;
    _setPhase(SageVoicePhase.ended);
  }

  /// While listening: send whatever has been captured right now.
  Future<void> sendNow() async {
    if (_phase != SageVoicePhase.listening) return;
    if (_transcript.trim().isEmpty) return;
    await _completeTurn();
  }

  /// While speaking: barge in — stop the reply and reopen the mic.
  Future<void> interrupt() async {
    if (_phase != SageVoicePhase.speaking) return;
    final generation = ++_generation;
    try {
      await stopSpeaking();
    } catch (_) {}
    if (_disposed || generation != _generation) return;
    await _beginListening();
  }

  /// From the error phase: try listening again.
  Future<void> retry() async {
    if (_phase != SageVoicePhase.error) return;
    await _beginListening();
  }

  Future<void> _beginListening() async {
    if (_disposed) return;
    final generation = ++_generation;
    _transcript = '';
    _errorText = null;
    _stopRequested = false;
    _finalTranscriptCompleter = null;
    _lastTranscriptChange = DateTime.now();
    _listenStartedAt = DateTime.now();
    _setPhase(SageVoicePhase.listening);

    try {
      await _voiceEntry.startListening();
    } catch (e) {
      if (_disposed || generation != _generation) return;
      _failListening(_describeError(e));
      return;
    }
    if (_disposed || generation != _generation) return;

    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(milliseconds: 250), (_) {
      if (_phase != SageVoicePhase.listening || generation != _generation) {
        return;
      }
      final now = DateTime.now();
      final hasSpeech = _transcript.trim().isNotEmpty;
      if (hasSpeech &&
          now.difference(_lastTranscriptChange) >= silenceThreshold) {
        unawaited(_completeTurn());
      } else if (!hasSpeech &&
          now.difference(_listenStartedAt) >= noSpeechTimeout) {
        unawaited(endSession());
      }
    });
  }

  void _handleVoiceEvent(VoiceEntryEvent event) {
    if (_disposed) return;

    if (event.error != null && event.error!.trim().isNotEmpty) {
      // A "final" error after we already asked to stop is just the recognizer
      // winding down; the turn continues with what we captured.
      final completer = _finalTranscriptCompleter;
      if (completer != null && !completer.isCompleted) {
        completer.complete(_transcript);
        return;
      }
      if (_phase == SageVoicePhase.listening) {
        _failListening(event.error!);
      }
      return;
    }

    final text = event.transcript;
    if (text != null && text != _transcript) {
      _transcript = text;
      _lastTranscriptChange = DateTime.now();
      if (_phase == SageVoicePhase.listening) notifyListeners();
    }

    if (event.isFinal) {
      final completer = _finalTranscriptCompleter;
      if (completer != null && !completer.isCompleted) {
        completer.complete(_transcript);
      } else if (_phase == SageVoicePhase.listening && !_stopRequested) {
        // Native recognizer finalized on its own (e.g. its internal limit).
        if (_transcript.trim().isNotEmpty) {
          unawaited(_completeTurn());
        } else {
          unawaited(_beginListening());
        }
      }
    }
  }

  Future<void> _completeTurn() async {
    if (_phase != SageVoicePhase.listening) return;
    final generation = ++_generation;
    _ticker?.cancel();
    _stopRequested = true;
    _setPhase(SageVoicePhase.thinking);

    // Stop the recognizer and give it a moment to deliver its final,
    // punctuation-corrected transcript.
    final completer = Completer<String>();
    _finalTranscriptCompleter = completer;
    try {
      await _voiceEntry.stopListening();
    } catch (_) {}
    final finalTranscript = await completer.future
        .timeout(const Duration(milliseconds: 1500), onTimeout: () {
      return _transcript;
    });
    _finalTranscriptCompleter = null;
    if (_disposed || generation != _generation) return;

    final prompt = finalTranscript.trim();
    if (prompt.isEmpty) {
      await _beginListening();
      return;
    }
    _transcript = prompt;
    notifyListeners();

    String? reply;
    try {
      reply = await sendTurn(prompt);
    } catch (_) {
      reply = null;
    }
    if (_disposed || generation != _generation) return;

    if (reply == null || reply.trim().isEmpty) {
      _errorText = 'Sage couldn’t reply. Tap the orb to try again.';
      _setPhase(SageVoicePhase.error);
      return;
    }

    _turnCount += 1;
    _lastReply = reply.trim();
    _setPhase(SageVoicePhase.speaking);

    var spoke = false;
    try {
      spoke = await speakReply();
    } catch (_) {
      spoke = false;
    }
    if (_disposed || generation != _generation) return;

    if (!spoke) {
      _errorText =
          'Couldn’t play Sage’s reply out loud. The text is in the chat. '
          'Tap the orb to keep talking.';
      _setPhase(SageVoicePhase.error);
      return;
    }

    await _beginListening();
  }

  void _failListening(String message) {
    if (_disposed) return;
    _generation += 1;
    _ticker?.cancel();
    _errorText = _friendlyVoiceError(message);
    _setPhase(SageVoicePhase.error);
  }

  String _describeError(Object e) {
    final raw = e.toString().replaceFirst('Exception: ', '').trim();
    return raw.isEmpty ? 'Voice capture failed.' : raw;
  }

  String _friendlyVoiceError(String raw) {
    final lower = raw.toLowerCase();
    if (lower.contains('permission') || lower.contains('denied')) {
      return 'Voice mode needs microphone and speech access in iOS Settings.';
    }
    if (lower.contains('no speech')) {
      return 'Didn’t catch anything. Tap the orb to try again.';
    }
    return raw;
  }

  void _setPhase(SageVoicePhase phase) {
    _phase = phase;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _ticker?.cancel();
    _eventsSub?.cancel();
    super.dispose();
  }
}
