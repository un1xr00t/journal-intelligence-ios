import 'dart:async';
import 'dart:typed_data';

import 'package:adaptive_platform_ui/adaptive_platform_ui.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/cupertino.dart';
import 'package:provider/provider.dart';

import '../providers/launch_intent_provider.dart';
import '../services/ai_response_limits.dart';
import '../services/api_service.dart';
import '../services/sage_profile_service.dart';
import '../services/voice_entry_service.dart';
import '../theme/app_theme.dart';
import '../widgets/glass_card.dart';
import '../widgets/section_header.dart';

Color _withAlpha(Color color, double alpha) => color.withValues(alpha: alpha);

class CarPlayCompanionScreen extends StatefulWidget {
  const CarPlayCompanionScreen({
    super.key,
    this.initialFocus = 'hub',
  });

  final String initialFocus;

  @override
  State<CarPlayCompanionScreen> createState() => _CarPlayCompanionScreenState();
}

class _CarPlayCompanionScreenState extends State<CarPlayCompanionScreen> {
  final _api = ApiService();
  final _sageProfile = SageProfileService();
  final _voiceEntryService = VoiceEntryService();
  final _audioPlayer = AudioPlayer();
  final _transcriptCtrl = TextEditingController();
  final _transcriptFocus = FocusNode();

  StreamSubscription<VoiceEntryEvent>? _voiceEventsSub;

  Map<String, dynamic>? _todayBrief;
  bool _todayLoading = true;
  String? _todayError;

  bool _listening = false;
  bool _savingEntry = false;
  String? _voiceError;
  String? _entrySavedMessage;

  bool _briefingLoading = false;
  bool _briefingSpeaking = false;
  int _briefingRequestCounter = 0;
  String? _briefingError;
  bool _initialFocusHandled = false;

  @override
  void initState() {
    super.initState();
    _loadTodayBrief();
    _voiceEventsSub = _voiceEntryService.events.listen(_handleVoiceEvent);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _handleInitialFocus();
    });
  }

  @override
  void dispose() {
    _voiceEventsSub?.cancel();
    _audioPlayer.dispose();
    _transcriptCtrl.dispose();
    _transcriptFocus.dispose();
    super.dispose();
  }

  Future<void> _loadTodayBrief() async {
    setState(() {
      _todayLoading = true;
      _todayError = null;
    });
    try {
      final data = await _api.getTodayBrief();
      if (!mounted) return;
      setState(() {
        _todayBrief = data;
        _todayLoading = false;
      });
      _handleInitialFocus();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _todayError = _parseError(e);
        _todayLoading = false;
      });
    }
  }

  void _handleInitialFocus() {
    if (!mounted || _initialFocusHandled) return;
    final focus = widget.initialFocus.trim().toLowerCase();
    if (focus == 'voice') {
      _initialFocusHandled = true;
      unawaited(_startListening());
      return;
    }
    if (focus == 'briefing' && !_todayLoading && _todayBrief != null) {
      _initialFocusHandled = true;
      unawaited(_playTodayBriefing());
      return;
    }
    if (focus != 'briefing') {
      _initialFocusHandled = true;
    }
  }

  void _handleVoiceEvent(VoiceEntryEvent event) {
    if (!mounted) return;
    setState(() {
      _listening = event.isListening;
      if (event.error != null && event.error!.trim().isNotEmpty) {
        _voiceError = event.error;
      }
      final transcript = event.transcript?.trim();
      if (transcript != null && transcript.isNotEmpty) {
        _transcriptCtrl.value = TextEditingValue(
          text: transcript,
          selection: TextSelection.collapsed(offset: transcript.length),
        );
      }
    });
  }

  Future<void> _startListening() async {
    setState(() {
      _voiceError = null;
      _entrySavedMessage = null;
    });
    try {
      await _voiceEntryService.startListening();
      if (!mounted) return;
      setState(() {
        _listening = true;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _listening = false;
        _voiceError = _parseVoiceError(e);
      });
    }
  }

  Future<void> _stopListening() async {
    try {
      await _voiceEntryService.stopListening();
      if (!mounted) return;
      setState(() => _listening = false);
    } catch (e) {
      if (!mounted) return;
      setState(() => _voiceError = _parseVoiceError(e));
    }
  }

  Future<void> _clearTranscript() async {
    await _voiceEntryService.cancelListening();
    if (!mounted) return;
    setState(() {
      _listening = false;
      _voiceError = null;
      _entrySavedMessage = null;
      _transcriptCtrl.clear();
    });
  }

  Future<void> _saveVoiceEntry() async {
    final text = _transcriptCtrl.text.trim();
    if (text.isEmpty) return;

    setState(() {
      _savingEntry = true;
      _voiceError = null;
      _entrySavedMessage = null;
    });
    try {
      await _api.createEntry(text: text);
      if (!mounted) return;
      setState(() {
        _savingEntry = false;
        _transcriptCtrl.clear();
        _entrySavedMessage = 'Voice entry saved to your journal.';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _savingEntry = false;
        _voiceError = _parseError(e);
      });
    }
  }

  Future<void> _toggleBriefingPlayback() async {
    if (_briefingSpeaking || _briefingLoading) {
      await _stopBriefingPlayback();
      return;
    }
    await _playTodayBriefing();
  }

  Future<void> _stopBriefingPlayback() async {
    _briefingRequestCounter += 1;
    await _audioPlayer.stop();
    if (!mounted) return;
    setState(() {
      _briefingSpeaking = false;
      _briefingLoading = false;
    });
  }

  Future<void> _playTodayBriefing() async {
    if (_todayBrief == null) {
      if (!_todayLoading) {
        setState(() {
          _briefingError = 'Today briefing is not available yet.';
        });
      }
      return;
    }

    final speech = _buildTodaySpeech(_todayBrief!);
    if (speech.isEmpty) {
      setState(() {
        _briefingError = 'Today briefing is not ready to play yet.';
      });
      return;
    }

    final requestId = ++_briefingRequestCounter;
    setState(() {
      _briefingLoading = true;
      _briefingSpeaking = false;
      _briefingError = null;
    });

    try {
      await _audioPlayer.stop();
      final voiceSettings = await _api.getVoiceSettings();
      final hasVoiceKey = voiceSettings['has_voice_key'] == true;
      final usingOpenAi = voiceSettings['using_openai'] == true;
      if (!hasVoiceKey && !usingOpenAi) {
        throw Exception(
          'Voice requires an OpenAI API key. Add one in Settings → Voice, or switch AI provider to OpenAI.',
        );
      }

      final chunks = buildSpeechChunks(speech);
      if (chunks.isEmpty) throw Exception('No text to speak.');
      final sageSettings = await _sageProfile.loadSettings();

      if (!mounted || requestId != _briefingRequestCounter) return;
      setState(() {
        _briefingLoading = false;
        _briefingSpeaking = true;
      });
      for (final chunk in chunks) {
        if (requestId != _briefingRequestCounter) return;
        if (!mounted) return;
        setState(() => _briefingLoading = true);
        final bytes = await _api.voiceSpeak(
          text: chunk,
          voiceId: sageSettings.voiceId,
        );
        if (bytes.isEmpty) throw Exception('No audio returned.');
        if (requestId != _briefingRequestCounter) return;
        if (!mounted) return;
        setState(() => _briefingLoading = false);
        await _audioPlayer.play(
          BytesSource(Uint8List.fromList(bytes), mimeType: 'audio/mpeg'),
        );
        await _waitForAudioToFinish();
      }

      if (requestId != _briefingRequestCounter || !mounted) return;
      setState(() {
        _briefingSpeaking = false;
        _briefingLoading = false;
      });
    } catch (e) {
      if (requestId != _briefingRequestCounter || !mounted) return;
      setState(() {
        _briefingLoading = false;
        _briefingSpeaking = false;
        _briefingError = _parseTtsError(e);
      });
    }
  }

  Future<void> _waitForAudioToFinish() {
    final completer = Completer<void>();
    StreamSubscription<void>? completeSub;
    StreamSubscription<PlayerState>? stateSub;

    void finish() {
      if (completer.isCompleted) return;
      completeSub?.cancel();
      stateSub?.cancel();
      completer.complete();
    }

    completeSub = _audioPlayer.onPlayerComplete.listen((_) => finish());
    stateSub = _audioPlayer.onPlayerStateChanged.listen((state) {
      if (state == PlayerState.stopped || state == PlayerState.disposed) {
        finish();
      }
    });

    return completer.future.timeout(
      const Duration(minutes: 3),
      onTimeout: () => finish(),
    );
  }

  void _openRoute(String route) {
    final launchIntent = context.read<LaunchIntentProvider>();
    launchIntent.registerRoute(route);
    Navigator.of(context).pop();
  }

  String _buildTodaySpeech(Map<String, dynamic> data) {
    final brief = _readMap(data['brief']);
    final trajectory = _readMap(brief['trajectory']);
    final horizons = _readMap(brief['time_horizons']);

    final lines = <String>[
      'Journal Intelligence today briefing.',
      if (_readText(brief, 'emotional_state') case final value?)
        'Emotional state: $value.',
      if (_readText(brief, 'do_today') case final value?) 'Do today: $value.',
      if (_readText(brief, 'biggest_risk') case final value?)
        'Biggest risk: $value.',
      if (_readText(brief, 'most_important_decision') case final value?)
        'Most important decision: $value.',
      if (_readText(brief, 'avoiding') case final value?)
        'You may be avoiding: $value.',
      if (_readText(trajectory, 'summary') case final value?)
        'Trajectory summary: $value.',
      if (_readText(horizons, 'today') case final value?)
        'Today horizon: $value.',
    ];

    return lines.join(' ').trim();
  }

  Map<String, dynamic> _readMap(dynamic value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) {
      return value.map(
        (key, entryValue) => MapEntry(key.toString(), entryValue),
      );
    }
    return <String, dynamic>{};
  }

  String? _readText(Map<String, dynamic> map, String key) {
    final value = map[key];
    if (value is String) {
      final trimmed = value.trim();
      return trimmed.isEmpty ? null : trimmed;
    }
    final text = value?.toString().trim();
    return text == null || text.isEmpty ? null : text;
  }

  String _parseError(dynamic e) {
    final str = e.toString();
    final match = RegExp(r'"detail"\s*:\s*"([^"]+)"').firstMatch(str);
    return match?.group(1) ?? 'Something went wrong.';
  }

  String _parseVoiceError(dynamic e) {
    final raw = e.toString();
    if (raw.contains('permission')) {
      return 'Voice capture needs microphone and speech access in iOS Settings.';
    }
    return 'Couldn’t start voice capture. $raw';
  }

  String _parseTtsError(dynamic e) {
    final raw = e.toString();
    final match = RegExp(r'"detail"\s*:\s*"([^"]+)"').firstMatch(raw);
    return match?.group(1) ??
        'Couldn’t generate audio. Check Settings → Voice and try again.';
  }

  String _focusLabel() {
    return switch (widget.initialFocus.trim().toLowerCase()) {
      'voice' => 'Voice entry ready',
      'briefing' => 'Today briefing ready',
      'sage' => 'Sage shortcut ready',
      'detective' => 'Detective shortcut ready',
      _ => 'Companion hub',
    };
  }

  @override
  Widget build(BuildContext context) {
    final today = _todayBrief == null ? null : _readMap(_todayBrief!['brief']);
    final trajectory = today == null
        ? const <String, dynamic>{}
        : _readMap(today['trajectory']);
    final noData = _todayBrief?['no_data'] == true;
    final emotionalState =
        today == null ? null : _readText(today, 'emotional_state');
    final doToday = today == null ? null : _readText(today, 'do_today');
    final risk = today == null ? null : _readText(today, 'biggest_risk');
    final summary =
        trajectory.isEmpty ? null : _readText(trajectory, 'summary');

    return CupertinoPageScaffold(
      backgroundColor: JournalColors.bgBase,
      child: Stack(
        children: [
          const Positioned.fill(child: _CarPlayBackdrop()),
          CustomScrollView(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            slivers: [
              CupertinoSliverNavigationBar(
                largeTitle: const Text('CarPlay'),
                backgroundColor: _withAlpha(JournalColors.bgBase, 0.9),
                border: const Border(
                  bottom: BorderSide(color: JournalColors.border, width: 0.5),
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
                sliver: SliverList(
                  delegate: SliverChildListDelegate([
                    GlassCard(
                      accentBorder: true,
                      padding: const EdgeInsets.all(22),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                width: 48,
                                height: 48,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  gradient: LinearGradient(
                                    colors: [
                                      _withAlpha(JournalColors.accent, 0.95),
                                      _withAlpha(JournalColors.accent2, 0.92),
                                    ],
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                  ),
                                ),
                                child: const Icon(
                                  CupertinoIcons.waveform_path_ecg,
                                  color: JournalColors.textPrimary,
                                ),
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      _focusLabel().toUpperCase(),
                                      style: const TextStyle(
                                        color: JournalColors.textMuted,
                                        fontSize: 11,
                                        fontWeight: FontWeight.w700,
                                        letterSpacing: 1.2,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    const Text(
                                      'Journal Intelligence Companion',
                                      style: TextStyle(
                                        color: JournalColors.textPrimary,
                                        fontSize: 24,
                                        fontWeight: FontWeight.w800,
                                        height: 1.1,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          const Text(
                            'Use the same dark, premium app language while CarPlay hands you into faster capture, audio briefings, and one-tap pivots into the deeper parts of the app.',
                            style: TextStyle(
                              color: JournalColors.textSecondary,
                              fontSize: 14,
                              height: 1.6,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),
                    const SectionHeader(title: 'Voice Entry'),
                    const SizedBox(height: 10),
                    GlassCard(
                      accentBorder:
                          widget.initialFocus.trim().toLowerCase() == 'voice',
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  _listening
                                      ? 'Listening for your quick entry...'
                                      : 'Tap the mic to capture a thought, then save it as a journal entry.',
                                  style: const TextStyle(
                                    color: JournalColors.textPrimary,
                                    fontSize: 17,
                                    fontWeight: FontWeight.w700,
                                    height: 1.25,
                                  ),
                                ),
                              ),
                              if (_listening)
                                const CupertinoActivityIndicator(
                                  color: JournalColors.accent,
                                ),
                            ],
                          ),
                          const SizedBox(height: 14),
                          CupertinoTextField(
                            controller: _transcriptCtrl,
                            focusNode: _transcriptFocus,
                            minLines: 6,
                            maxLines: null,
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: JournalColors.bgSurface,
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: _listening
                                    ? JournalColors.borderBright
                                    : JournalColors.border,
                              ),
                            ),
                            style: const TextStyle(
                              color: JournalColors.textPrimary,
                              fontSize: 15,
                              height: 1.55,
                            ),
                            placeholder:
                                'Your voice transcript will appear here. You can edit it before saving.',
                            placeholderStyle: const TextStyle(
                              color: JournalColors.textMuted,
                              fontSize: 14,
                            ),
                          ),
                          if (_voiceError != null) ...[
                            const SizedBox(height: 12),
                            Text(
                              _voiceError!,
                              style: const TextStyle(
                                color: JournalColors.danger,
                                fontSize: 13,
                                height: 1.45,
                              ),
                            ),
                          ],
                          if (_entrySavedMessage != null) ...[
                            const SizedBox(height: 12),
                            Text(
                              _entrySavedMessage!,
                              style: const TextStyle(
                                color: JournalColors.success,
                                fontSize: 13,
                                height: 1.45,
                              ),
                            ),
                          ],
                          const SizedBox(height: 14),
                          Wrap(
                            spacing: 10,
                            runSpacing: 10,
                            children: [
                              AdaptiveButton(
                                style: AdaptiveButtonStyle.prominentGlass,
                                onPressed: _listening
                                    ? _stopListening
                                    : _startListening,
                                label: _listening
                                    ? 'Stop Listening'
                                    : 'Start Voice Entry',
                              ),
                              AdaptiveButton(
                                onPressed:
                                    _transcriptCtrl.text.trim().isEmpty ||
                                            _savingEntry
                                        ? null
                                        : _saveVoiceEntry,
                                label: _savingEntry ? 'Saving…' : 'Save Entry',
                              ),
                              AdaptiveButton(
                                onPressed:
                                    _transcriptCtrl.text.isEmpty && !_listening
                                        ? null
                                        : _clearTranscript,
                                label: 'Clear',
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),
                    const SectionHeader(title: 'Today Briefing'),
                    const SizedBox(height: 10),
                    GlassCard(
                      accentBorder: widget.initialFocus.trim().toLowerCase() ==
                          'briefing',
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  noData
                                      ? 'Today needs more journal history before it can generate a briefing.'
                                      : emotionalState ??
                                          'Today is ready when you are.',
                                  style: const TextStyle(
                                    color: JournalColors.textPrimary,
                                    fontSize: 17,
                                    fontWeight: FontWeight.w700,
                                    height: 1.25,
                                  ),
                                ),
                              ),
                              if (_briefingLoading)
                                const CupertinoActivityIndicator(
                                  color: JournalColors.accent,
                                ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          if (_todayLoading)
                            const Text(
                              'Loading today briefing...',
                              style: TextStyle(
                                color: JournalColors.textSecondary,
                                fontSize: 14,
                              ),
                            )
                          else if (_todayError != null)
                            Text(
                              _todayError!,
                              style: const TextStyle(
                                color: JournalColors.danger,
                                fontSize: 14,
                                height: 1.5,
                              ),
                            )
                          else
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                if (doToday != null)
                                  _BriefLine(
                                    label: 'Do today',
                                    value: doToday,
                                  ),
                                if (risk != null)
                                  _BriefLine(
                                    label: 'Biggest risk',
                                    value: risk,
                                  ),
                                if (summary != null)
                                  _BriefLine(
                                    label: 'Trajectory',
                                    value: summary,
                                  ),
                              ],
                            ),
                          if (_briefingError != null) ...[
                            const SizedBox(height: 12),
                            Text(
                              _briefingError!,
                              style: const TextStyle(
                                color: JournalColors.danger,
                                fontSize: 13,
                                height: 1.45,
                              ),
                            ),
                          ],
                          const SizedBox(height: 14),
                          Wrap(
                            spacing: 10,
                            runSpacing: 10,
                            children: [
                              AdaptiveButton(
                                style: AdaptiveButtonStyle.prominentGlass,
                                onPressed: (_todayLoading ||
                                        _todayError != null ||
                                        noData)
                                    ? null
                                    : _toggleBriefingPlayback,
                                label: _briefingSpeaking || _briefingLoading
                                    ? 'Stop Briefing'
                                    : 'Listen to Briefing',
                              ),
                              AdaptiveButton(
                                onPressed:
                                    _todayLoading ? null : _loadTodayBrief,
                                label: 'Refresh Briefing',
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),
                    const SectionHeader(title: 'Fast Pivots'),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      children: [
                        _QuickRouteCard(
                          title: 'Open Write',
                          body:
                              'Jump into the full writing surface with photos and more room.',
                          icon: CupertinoIcons.pencil,
                          accent: JournalColors.accent,
                          onTap: () => _openRoute('/write'),
                        ),
                        _QuickRouteCard(
                          title: 'Open Today',
                          body:
                              'Review the full Today screen after the spoken briefing finishes.',
                          icon: CupertinoIcons.sparkles,
                          accent: JournalColors.info,
                          onTap: () => _openRoute('/today'),
                        ),
                        _QuickRouteCard(
                          title: 'Ask Sage',
                          body:
                              'Turn the current moment into a question for Sage with full context.',
                          icon: CupertinoIcons.chat_bubble_2,
                          accent: JournalColors.accent2,
                          onTap: () => _openRoute('/sage'),
                        ),
                        _QuickRouteCard(
                          title: 'Open Detective',
                          body:
                              'Escalate a clue, contradiction, or incident into detective mode.',
                          icon: CupertinoIcons.search,
                          accent: JournalColors.severity,
                          onTap: () => _openRoute('/detective'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                    const SectionHeader(title: 'Ideas'),
                    const SizedBox(height: 10),
                    const GlassCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _IdeaLine(
                            title: 'Commute recap mode',
                            body:
                                'One tap starts voice capture with a prompt like “What happened today that I should not forget?”',
                          ),
                          SizedBox(height: 12),
                          _IdeaLine(
                            title: 'Detective clue handoff',
                            body:
                                'Let a saved voice entry become the opening note for a detective case workflow.',
                          ),
                          SizedBox(height: 12),
                          _IdeaLine(
                            title: 'Ask Sage from transcript',
                            body:
                                'Offer a follow-up action that turns the captured text into a Sage question without retyping.',
                          ),
                          SizedBox(height: 12),
                          _IdeaLine(
                            title: 'Priority queue',
                            body:
                                'Mark a spoken entry as urgent, reflective, or evidence-oriented before saving.',
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 40),
                  ]),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _BriefLine extends StatelessWidget {
  const _BriefLine({
    required this.label,
    required this.value,
  });

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: RichText(
        text: TextSpan(
          children: [
            TextSpan(
              text: '${label.toUpperCase()}  ',
              style: const TextStyle(
                color: JournalColors.textMuted,
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.2,
              ),
            ),
            TextSpan(
              text: value,
              style: const TextStyle(
                color: JournalColors.textSecondary,
                fontSize: 14,
                height: 1.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _QuickRouteCard extends StatelessWidget {
  const _QuickRouteCard({
    required this.title,
    required this.body,
    required this.icon,
    required this.accent,
    required this.onTap,
  });

  final String title;
  final String body;
  final IconData icon;
  final Color accent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 260,
      child: GlassCard(
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: accent.withValues(alpha: 0.16),
                shape: BoxShape.circle,
                border: Border.all(color: accent.withValues(alpha: 0.35)),
              ),
              child: Icon(icon, color: accent, size: 21),
            ),
            const SizedBox(height: 12),
            Text(
              title,
              style: const TextStyle(
                color: JournalColors.textPrimary,
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              body,
              style: const TextStyle(
                color: JournalColors.textSecondary,
                fontSize: 13,
                height: 1.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _IdeaLine extends StatelessWidget {
  const _IdeaLine({
    required this.title,
    required this.body,
  });

  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            color: JournalColors.textPrimary,
            fontSize: 15,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          body,
          style: const TextStyle(
            color: JournalColors.textSecondary,
            fontSize: 13,
            height: 1.5,
          ),
        ),
      ],
    );
  }
}

class _CarPlayBackdrop extends StatelessWidget {
  const _CarPlayBackdrop();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            JournalColors.bgBase,
            _withAlpha(JournalColors.bgCardAlt, 0.98),
            JournalColors.bgBase,
          ],
        ),
      ),
      child: Stack(
        children: [
          Positioned(
            top: -80,
            right: -20,
            child: Container(
              width: 220,
              height: 220,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    _withAlpha(JournalColors.accent, 0.28),
                    _withAlpha(JournalColors.accent2, 0.0),
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            bottom: -120,
            left: -50,
            child: Container(
              width: 260,
              height: 260,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    _withAlpha(JournalColors.info, 0.18),
                    _withAlpha(JournalColors.info, 0.0),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
