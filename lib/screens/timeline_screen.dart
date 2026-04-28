import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:math' as math;

import 'package:audioplayers/audioplayers.dart';
import 'package:dio/dio.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../services/ai_response_limits.dart';
import '../services/api_service.dart';
import '../services/sage_profile_service.dart';
import '../services/tts_audio_file_helper.dart';
import '../theme/app_theme.dart';
import '../widgets/glass_card.dart';
import 'sage_screen.dart';

class TimelineScreen extends StatefulWidget {
  const TimelineScreen({super.key});

  @override
  State<TimelineScreen> createState() => _TimelineScreenState();
}

class _TimelineScreenState extends State<TimelineScreen> {
  static const int _pageSize = 20;
  static const List<String> _summaryTones = [
    'therapist',
    'best_friend',
    'coach',
    'mentor',
    'inner_critic',
    'chaos_agent',
  ];

  final _api = ApiService();
  final _sageProfile = SageProfileService();
  final _scroll = ScrollController();
  final _summaryAudioPlayer = AudioPlayer();

  List<Map<String, dynamic>> _entries = [];
  bool _loading = true;
  bool _loadMore = false;
  bool _hasMore = true;
  int _page = 1;
  String? _error;

  Map<String, dynamic>? _masterSummary;
  bool _summaryLoading = true;
  String? _summaryTone;
  bool _checkingSummaryTone = false;
  bool _summarySpeaking = false;
  bool _summaryTtsLoading = false;
  bool _summaryTtsSequenceActive = false;
  int _summaryTtsRequestCounter = 0;
  String? _summaryTtsError;
  String? _summaryTtsTempAudioPath;

  @override
  void initState() {
    super.initState();
    unawaited(configureTtsAudioPlayer(_summaryAudioPlayer));
    _summaryAudioPlayer.onPlayerComplete.listen((_) {
      if (mounted && !_summaryTtsSequenceActive) {
        setState(() {
          _summarySpeaking = false;
          _summaryTtsLoading = false;
        });
      }
    });
    _load();
    _loadSummary();
    _scroll.addListener(_onScroll);
  }

  @override
  void dispose() {
    _summaryAudioPlayer.dispose();
    unawaited(deleteTtsAudioTempFile(_summaryTtsTempAudioPath));
    _scroll.dispose();
    super.dispose();
  }

  Future<String> _getPreferredTone() async {
    try {
      final data = await _api.getMemory();
      final memory = (data['memory'] ?? data) as Map<String, dynamic>;
      return memory['preferred_tone'] as String? ?? 'therapist';
    } catch (_) {
      return 'therapist';
    }
  }

  Map<String, dynamic>? _normalizeInsightPayload(Map<String, dynamic> data) {
    final payload = data['data'];
    final normalized = payload is Map
        ? Map<String, dynamic>.from(payload)
        : Map<String, dynamic>.from(data);
    final insight = normalized['insight']?.toString().trim();
    return insight?.isNotEmpty == true ? normalized : null;
  }

  Future<(String, Map<String, dynamic>?)> _loadCachedSummaryForTone(
    String tone,
  ) async {
    final data = await _api.getTherapistInsightStatus(tone: tone);
    return (tone, _normalizeInsightPayload(data));
  }

  Future<(String, Map<String, dynamic>?)> _loadBestCachedSummary(
    String preferredTone,
  ) async {
    final preferred = await _loadCachedSummaryForTone(preferredTone);
    if (preferred.$2 != null) return preferred;

    for (final tone in _summaryTones) {
      if (tone == preferredTone) continue;
      try {
        final fallback = await _loadCachedSummaryForTone(tone);
        if (fallback.$2 != null) return fallback;
      } catch (_) {}
    }

    return preferred;
  }

  Future<void> _loadSummary({bool force = false, String? toneOverride}) async {
    if (!force && _masterSummary != null) return;
    if (mounted) setState(() => _summaryLoading = true);
    try {
      final tone = toneOverride ?? await _getPreferredTone();
      final result = await _loadBestCachedSummary(tone);
      if (mounted) {
        setState(() {
          _summaryTone = result.$1;
          _masterSummary = result.$2;
          _summaryLoading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _masterSummary = null;
          _summaryLoading = false;
        });
      }
    }
  }

  Future<void> _regenerateSummary() async {
    if (mounted) {
      setState(() {
        _masterSummary = null;
        _summaryLoading = true;
      });
    }
    try {
      final tone = await _getPreferredTone();
      await _api.generateTherapistInsight(tone: tone, force: true);
      final result = await _loadBestCachedSummary(tone);
      if (mounted) {
        setState(() {
          _summaryTone = result.$1;
          _masterSummary = result.$2;
          _summaryLoading = false;
        });
      }
    } catch (_) {
      Map<String, dynamic>? cached;
      try {
        final tone = await _getPreferredTone();
        final result = await _loadBestCachedSummary(tone);
        cached = result.$2;
        if (cached != null) _summaryTone = result.$1;
      } catch (_) {}
      if (mounted) {
        setState(() {
          _masterSummary = cached;
          _summaryLoading = false;
        });
      }
    }
  }

  Future<void> _refreshTimeline() async {
    await Future.wait([
      _load(),
      _reloadSummary(),
    ]);
  }

  Future<void> _reloadSummary() async {
    if (mounted) {
      setState(() {
        _masterSummary = null;
      });
    }
    await _loadSummary(force: true);
  }

  Future<void> _openSummaryInSage() async {
    final insight = _prepareSummaryForSage();
    if (insight.isEmpty) return;
    final sessionTone =
        (_summaryTone ?? _masterSummary?['tone']?.toString())?.trim();

    if (_summarySpeaking || _summaryTtsLoading) {
      _summaryTtsRequestCounter += 1;
      await _summaryAudioPlayer.stop();
      if (mounted) {
        setState(() {
          _summarySpeaking = false;
          _summaryTtsLoading = false;
          _summaryTtsSequenceActive = false;
        });
      }
    }

    if (!mounted) return;
    await pushSageScreen(
      context,
      handoff: SageHandoff.livingSummary(
        insight,
        sessionToneOverride: sessionTone?.isEmpty == true ? null : sessionTone,
      ),
    );
  }

  Future<void> _toggleSummarySpeak() async {
    final insight = _prepareSummaryForSpeech();
    if (insight.isEmpty || _summaryLoading || _summaryTtsLoading) return;

    if (_summarySpeaking) {
      _summaryTtsRequestCounter += 1;
      await _summaryAudioPlayer.stop();
      if (!mounted) return;
      setState(() {
        _summarySpeaking = false;
        _summaryTtsLoading = false;
        _summaryTtsSequenceActive = false;
      });
      return;
    }

    final requestId = ++_summaryTtsRequestCounter;
    setState(() {
      _summaryTtsLoading = true;
      _summarySpeaking = false;
      _summaryTtsError = null;
    });

    try {
      await configureTtsAudioPlayer(_summaryAudioPlayer);
      await _summaryAudioPlayer.stop();
      final voiceSettings = await _api.getVoiceSettings();
      final hasVoiceKey = voiceSettings['has_voice_key'] == true;
      final usingOpenAi = voiceSettings['using_openai'] == true;
      if (!hasVoiceKey && !usingOpenAi) {
        throw Exception(
          'Voice requires an OpenAI API key. Add one in Settings → Voice, or switch AI provider to OpenAI.',
        );
      }

      final chunks = buildSpeechChunks(insight);
      if (chunks.isEmpty) throw Exception('No text to speak.');
      final sageSettings = await _sageProfile.loadSettings();

      if (!mounted) return;
      setState(() {
        _summaryTtsLoading = false;
        _summarySpeaking = true;
      });
      _summaryTtsSequenceActive = true;

      for (final chunk in chunks) {
        if (requestId != _summaryTtsRequestCounter) return;
        if (!mounted) return;
        setState(() => _summaryTtsLoading = true);
        final bytes = await _api.voiceSpeak(
          text: chunk,
          voiceId: sageSettings.voiceId,
        );
        if (bytes.isEmpty) throw Exception('No audio returned.');
        if (requestId != _summaryTtsRequestCounter) return;
        if (!mounted) return;
        setState(() => _summaryTtsLoading = false);
        await deleteTtsAudioTempFile(_summaryTtsTempAudioPath);
        _summaryTtsTempAudioPath = await writeTtsAudioTempFile(
          prefix: 'timeline-summary-tts',
          bytes: bytes,
        );
        await playTtsAudioFile(
          _summaryAudioPlayer,
          path: _summaryTtsTempAudioPath!,
        );
        await _waitForSummaryAudioToFinish();
      }

      if (requestId != _summaryTtsRequestCounter) return;
      _summaryTtsSequenceActive = false;
      if (!mounted) return;
      setState(() {
        _summarySpeaking = false;
        _summaryTtsLoading = false;
      });
    } catch (e) {
      if (requestId != _summaryTtsRequestCounter) return;
      _summaryTtsSequenceActive = false;
      if (!mounted) return;
      setState(() {
        _summaryTtsLoading = false;
        _summarySpeaking = false;
        _summaryTtsError = _parseTtsError(e);
      });
    }
  }

  Future<void> _waitForSummaryAudioToFinish() {
    final completer = Completer<void>();
    StreamSubscription<void>? completeSub;
    StreamSubscription<PlayerState>? stateSub;

    void finish() {
      if (completer.isCompleted) return;
      completeSub?.cancel();
      stateSub?.cancel();
      completer.complete();
    }

    completeSub = _summaryAudioPlayer.onPlayerComplete.listen((_) => finish());
    stateSub = _summaryAudioPlayer.onPlayerStateChanged.listen((state) {
      if (state == PlayerState.stopped || state == PlayerState.disposed) {
        finish();
      }
    });

    return completer.future.timeout(
      const Duration(minutes: 3),
      onTimeout: () {
        finish();
      },
    );
  }

  String _prepareSummaryForSpeech() {
    return _prepareSummaryText(
      maxChars: AiResponseLimits.livingSummarySpeechMaxChars,
      maxBytes: AiResponseLimits.livingSummarySpeechMaxBytes,
      truncatedSuffix:
          '\n\n[Audio preview trimmed. Open Continue in Sage for the full insight.]',
    );
  }

  String _prepareSummaryForSage() {
    return _prepareSummaryText(
      maxChars: AiResponseLimits.livingSummarySageHandoffMaxChars,
      maxBytes: AiResponseLimits.livingSummarySageHandoffMaxBytes,
      truncatedSuffix:
          '\n\n[Timeline note: this insight was trimmed slightly before handoff so the Sage follow-up can continue reliably.]',
    );
  }

  String _prepareSummaryText({
    required int maxChars,
    required int maxBytes,
    required String truncatedSuffix,
  }) {
    final rawInsight = _masterSummary?['insight']?.toString() ?? '';
    final cleaned =
        rawInsight.split('---ACTIONS---').first.replaceAll('\u0000', '').trim();
    if (cleaned.isEmpty) return '';
    return truncateUtf8Text(
      cleaned,
      maxChars: maxChars,
      maxBytes: maxBytes,
      truncatedSuffix: truncatedSuffix,
    );
  }

  String _parseTtsError(dynamic e) {
    if (e is DioException) {
      final data = e.response?.data;
      final decoded = _decodeTtsErrorData(data);
      if (decoded != null && decoded.isNotEmpty) {
        return 'Couldn’t generate audio: $decoded';
      }
      final status = e.response?.statusCode;
      if (status == 400) {
        return 'Couldn’t generate audio. Check Settings → Voice.';
      }
      if (status == 502 || status == 504) {
        return 'Couldn’t generate audio. The voice service timed out or failed upstream.';
      }
      if (status != null) {
        return 'Couldn’t generate audio. Server returned $status.';
      }
    }
    if (e is Exception) {
      final message = e.toString().replaceFirst('Exception: ', '').trim();
      if (message.isNotEmpty) {
        return 'Couldn’t generate audio: $message';
      }
    }
    final raw = e.toString().trim();
    if (raw.isNotEmpty && raw != 'null') {
      return 'Couldn’t generate audio: $raw';
    }
    return 'Couldn’t generate audio. Try again, or shorten the summary.';
  }

  String? _decodeTtsErrorData(dynamic data) {
    dynamic decoded = data;
    if (data is List<int>) {
      try {
        decoded = utf8.decode(data);
      } catch (_) {
        return null;
      }
    }
    if (decoded is Map) {
      final detail = decoded['detail']?.toString().trim();
      if (detail?.isNotEmpty == true) return detail;
    }
    if (decoded is String) {
      final detailMatch =
          RegExp(r'"detail"\s*:\s*"([^"]+)"').firstMatch(decoded);
      return detailMatch?.group(1) ?? decoded.trim();
    }
    return null;
  }

  void _checkSummaryToneAfterBuild() {
    if (_checkingSummaryTone) return;
    _checkingSummaryTone = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      try {
        final preferredTone = await _getPreferredTone();
        if (!mounted) return;
        if (_summaryTone != null && preferredTone != _summaryTone) {
          setState(() {
            _masterSummary = null;
          });
          await _loadSummary(force: true, toneOverride: preferredTone);
        }
      } finally {
        _checkingSummaryTone = false;
      }
    });
  }

  void _onScroll() {
    if (_scroll.position.pixels >= _scroll.position.maxScrollExtent - 200 &&
        !_loadMore &&
        _hasMore) {
      _loadNext();
    }
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _page = 1;
      _hasMore = true;
      _loadMore = false;
      _error = null;
    });
    try {
      final data = await _api.getTimelinePage(page: 1, limit: _pageSize);
      if (mounted) {
        setState(() {
          _entries = data.entries;
          _page = data.page;
          _loading = false;
          _hasMore = data.hasMore;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _loading = false;
        });
      }
    }
  }

  Future<void> _loadNext() async {
    if (_loadMore || !_hasMore) return;
    final nextPage = _page + 1;
    setState(() => _loadMore = true);
    try {
      final data = await _api.getTimelinePage(page: nextPage, limit: _pageSize);
      if (mounted) {
        setState(() {
          final existingIds = _entries.map((entry) => entry['id']).toSet();
          final newEntries = data.entries
              .where((entry) => !existingIds.contains(entry['id']))
              .toList();
          _entries.addAll(newEntries);
          _page = data.page > _page ? data.page : nextPage;
          _loadMore = false;
          _hasMore = data.hasMore && newEntries.isNotEmpty;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loadMore = false);
    }
  }

  Future<void> _deleteEntry(int index, int entryId) async {
    final confirm = await showCupertinoDialog<bool>(
      context: context,
      builder: (_) => CupertinoAlertDialog(
        title: const Text('Delete Entry'),
        content: const Text('This cannot be undone.'),
        actions: [
          CupertinoDialogAction(
            isDestructiveAction: true,
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
          CupertinoDialogAction(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
    if (confirm == true) {
      try {
        await _api.deleteEntry(entryId);
        if (mounted) setState(() => _entries.removeAt(index));
      } catch (_) {}
    }
  }

  Future<void> _editEntry(int index, Map<String, dynamic> entry) async {
    final updated = await Navigator.push<Map<String, dynamic>>(
      context,
      CupertinoPageRoute(
        builder: (_) => DefaultTextStyle.merge(
          style: const TextStyle(decoration: TextDecoration.none),
          child: _EditEntryScreen(entry: entry, api: _api),
        ),
      ),
    );
    if (updated != null && mounted) {
      setState(() => _entries[index] = updated);
    }
  }

  List<DateTime> _entryDates() {
    return _entries
        .map((entry) => _tryParseDate(
              (entry['entry_date'] ?? entry['ingested_at'] ?? '') as String,
            ))
        .whereType<DateTime>()
        .toList();
  }

  DateTime? _tryParseDate(String raw) {
    if (raw.isEmpty) return null;
    try {
      return DateTime.parse(raw).toLocal();
    } catch (_) {
      return null;
    }
  }

  int _activeWeekCount() {
    final dates = _entryDates();
    final uniqueDays = dates
        .map((date) => DateTime(date.year, date.month, date.day))
        .toSet()
        .length;
    return math.min(uniqueDays, 7);
  }

  String _dateRangeLabel() {
    final dates = _entryDates();
    if (dates.isEmpty) return 'No saved moments yet';
    dates.sort();
    final first = dates.first;
    final last = dates.last;
    final formatter = DateFormat('MMM d');
    return '${formatter.format(first)} - ${formatter.format(last)}';
  }

  String _cadenceLabel() {
    final dates = _entryDates();
    if (dates.length < 2) return 'Building your rhythm';
    dates.sort();
    final span = dates.last.difference(dates.first).inDays.abs() + 1;
    final perWeek = (dates.length / math.max(span, 1)) * 7;
    if (perWeek >= 5) return 'Daily rhythm';
    if (perWeek >= 2.5) return 'Steady check-ins';
    return 'Occasional pulses';
  }

  Widget _buildBody() {
    if (_loading) {
      return const SliverFillRemaining(
        child: Center(
          child: CupertinoActivityIndicator(color: JournalColors.accent),
        ),
      );
    }

    if (_error != null) {
      return SliverFillRemaining(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 28),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 88,
                  height: 88,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: JournalColors.bgCard,
                    border: Border.all(color: JournalColors.borderBright),
                  ),
                  child: const Icon(
                    CupertinoIcons.wifi_slash,
                    color: JournalColors.textMuted,
                    size: 34,
                  ),
                ),
                const SizedBox(height: 20),
                const Text(
                  'Timeline offline',
                  style: TextStyle(
                    color: JournalColors.textPrimary,
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  _error!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: JournalColors.textSecondary,
                    fontSize: 14,
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 20),
                CupertinoButton(
                  color: JournalColors.accent,
                  borderRadius: BorderRadius.circular(14),
                  onPressed: _load,
                  child: const Text('Retry'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    if (_entries.isEmpty) {
      return const SliverFillRemaining(
        child: Center(
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: 28),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _HeroGlyph(icon: CupertinoIcons.book, size: 30),
                SizedBox(height: 20),
                Text(
                  'No entries yet',
                  style: TextStyle(
                    color: JournalColors.textPrimary,
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                SizedBox(height: 10),
                Text(
                  'Once you write a few entries, they will show up here in order.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: JournalColors.textSecondary,
                    fontSize: 15,
                    height: 1.55,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return SliverPadding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
      sliver: SliverList(
        delegate: SliverChildBuilderDelegate(
          (context, index) {
            if (index == 0) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 18),
                child: _TimelineHero(
                  entryCount: _entries.length,
                  dateRange: _dateRangeLabel(),
                  cadence: _cadenceLabel(),
                  activeDays: _activeWeekCount(),
                ),
              );
            }

            if (index == 1) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 22),
                child: _MasterSummaryCard(
                  summary: _masterSummary,
                  loading: _summaryLoading,
                  onRefresh: _regenerateSummary,
                  onToggleSpeak: _toggleSummarySpeak,
                  onContinueInSage: _openSummaryInSage,
                  speaking: _summarySpeaking,
                  ttsLoading: _summaryTtsLoading,
                  ttsError: _summaryTtsError,
                ),
              );
            }

            final entryIndex = index - 2;
            if (entryIndex == _entries.length) {
              return _loadMore
                  ? const Padding(
                      padding: EdgeInsets.symmetric(vertical: 28),
                      child: Center(
                        child: CupertinoActivityIndicator(
                          color: JournalColors.accent,
                        ),
                      ),
                    )
                  : const SizedBox(height: 36);
            }

            final entry = _entries[entryIndex];
            return Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: _EntryTile(
                entry: entry,
                index: entryIndex,
                onDelete: () => _deleteEntry(entryIndex, entry['id'] as int),
                onEdit: () => _editEntry(entryIndex, entry),
              ),
            );
          },
          childCount: _entries.length + 3,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    _checkSummaryToneAfterBuild();
    return CupertinoPageScaffold(
      backgroundColor: JournalColors.bgBase,
      child: Stack(
        children: [
          const Positioned.fill(child: _TimelineBackdrop()),
          CustomScrollView(
            controller: _scroll,
            slivers: [
              CupertinoSliverNavigationBar(
                largeTitle: const Text('Timeline'),
                backgroundColor: JournalColors.bgBase.withOpacity(0.85),
                border: const Border(
                  bottom: BorderSide(color: JournalColors.border, width: 0.5),
                ),
                trailing: GestureDetector(
                  onTap: _refreshTimeline,
                  child: const Icon(
                    CupertinoIcons.refresh,
                    color: JournalColors.accent,
                  ),
                ),
              ),
              _buildBody(),
            ],
          ),
        ],
      ),
    );
  }
}

class _TimelineBackdrop extends StatelessWidget {
  const _TimelineBackdrop();

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Stack(
        children: [
          Positioned.fill(
            child: DecoratedBox(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Color(0xFF080914),
                    JournalColors.bgBase,
                    Color(0xFF05060D),
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            top: 90,
            left: -40,
            child: _GlowOrb(
              size: 180,
              color: JournalColors.accent.withOpacity(0.18),
            ),
          ),
          Positioned(
            top: 240,
            right: -36,
            child: _GlowOrb(
              size: 140,
              color: JournalColors.info.withOpacity(0.14),
            ),
          ),
          Positioned(
            bottom: 120,
            left: 30,
            child: _GlowOrb(
              size: 120,
              color: JournalColors.orange.withOpacity(0.10),
            ),
          ),
        ],
      ),
    );
  }
}

class _GlowOrb extends StatelessWidget {
  const _GlowOrb({required this.size, required this.color});

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          colors: [color, color.withOpacity(0)],
        ),
      ),
    );
  }
}

class _TimelineHero extends StatelessWidget {
  const _TimelineHero({
    required this.entryCount,
    required this.dateRange,
    required this.cadence,
    required this.activeDays,
  });

  final int entryCount;
  final String dateRange;
  final String cadence;
  final int activeDays;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: JournalColors.borderBright),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            JournalColors.bgCard.withOpacity(0.95),
            const Color(0xFF11142A).withOpacity(0.92),
            const Color(0xFF191122).withOpacity(0.90),
          ],
        ),
        boxShadow: const [
          BoxShadow(
            color: Color(0x246366F1),
            blurRadius: 30,
            offset: Offset(0, 18),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const _HeroGlyph(icon: CupertinoIcons.sparkles, size: 24),
              const SizedBox(width: 14),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'RECENT ACTIVITY',
                      style: TextStyle(
                        color: JournalColors.textMuted,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.3,
                      ),
                    ),
                    SizedBox(height: 8),
                    Text(
                      'A summary of your recent journal activity.',
                      style: TextStyle(
                        color: JournalColors.textPrimary,
                        fontSize: 21,
                        fontWeight: FontWeight.w700,
                        height: 1.2,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Text(
            dateRange,
            style: const TextStyle(
              color: JournalColors.textSecondary,
              fontSize: 14,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: _HeroStat(
                  label: 'Entries',
                  value: '$entryCount',
                  color: JournalColors.accent,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _HeroStat(
                  label: 'Active Days',
                  value: '$activeDays/7',
                  color: JournalColors.info,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _CadencePill(text: cadence),
        ],
      ),
    );
  }
}

class _HeroGlyph extends StatelessWidget {
  const _HeroGlyph({required this.icon, required this.size});

  final IconData icon;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size * 2.1,
      height: size * 2.1,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          colors: [
            JournalColors.accent.withOpacity(0.26),
            JournalColors.info.withOpacity(0.16),
          ],
        ),
        border: Border.all(color: JournalColors.borderBright),
      ),
      child: Icon(icon, color: JournalColors.textPrimary, size: size),
    );
  }
}

class _HeroStat extends StatelessWidget {
  const _HeroStat({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        color: color.withOpacity(0.08),
        border: Border.all(color: color.withOpacity(0.22)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label.toUpperCase(),
            style: TextStyle(
              color: color.withOpacity(0.9),
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.1,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: const TextStyle(
              color: JournalColors.textPrimary,
              fontSize: 20,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _CadencePill extends StatelessWidget {
  const _CadencePill({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        color: Colors.white.withOpacity(0.04),
        border: Border.all(color: Colors.white.withOpacity(0.10)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            CupertinoIcons.waveform_path_ecg,
            color: JournalColors.orange,
            size: 16,
          ),
          const SizedBox(width: 8),
          Text(
            text,
            style: const TextStyle(
              color: JournalColors.textPrimary,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _MasterSummaryCard extends StatefulWidget {
  const _MasterSummaryCard({
    required this.summary,
    required this.loading,
    required this.onRefresh,
    required this.onToggleSpeak,
    required this.onContinueInSage,
    required this.speaking,
    required this.ttsLoading,
    required this.ttsError,
  });

  final Map<String, dynamic>? summary;
  final bool loading;
  final Future<void> Function() onRefresh;
  final Future<void> Function() onToggleSpeak;
  final Future<void> Function() onContinueInSage;
  final bool speaking;
  final bool ttsLoading;
  final String? ttsError;

  @override
  State<_MasterSummaryCard> createState() => _MasterSummaryCardState();
}

class _MasterSummaryCardState extends State<_MasterSummaryCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    if (widget.loading) {
      return GlassCard(
        accentBorder: true,
        child: Row(
          children: const [
            CupertinoActivityIndicator(color: JournalColors.accent, radius: 8),
            SizedBox(width: 12),
            Text(
              'Distilling your recent patterns...',
              style: TextStyle(color: JournalColors.textMuted, fontSize: 14),
            ),
          ],
        ),
      );
    }

    final insight = widget.summary?['insight'] as String?;
    if (insight == null || insight.isEmpty) {
      return Dismissible(
        key: const ValueKey('summary-empty'),
        direction: DismissDirection.startToEnd,
        confirmDismiss: (_) async {
          await widget.onRefresh();
          return false;
        },
        background: _summarySwipeBackground(
          label: 'Generate',
          icon: CupertinoIcons.sparkles,
        ),
        child: GlassCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: const [
              Text(
                'LIVING SUMMARY',
                style: TextStyle(
                  color: JournalColors.textMuted,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.2,
                ),
              ),
              SizedBox(height: 10),
              Text(
                'There is no insight card yet. Swipe right to generate a fresh read on the themes, tension, and emotional weather in your entries.',
                style: TextStyle(
                  color: JournalColors.textSecondary,
                  fontSize: 15,
                  height: 1.55,
                ),
              ),
            ],
          ),
        ),
      );
    }

    final entryDate = widget.summary?['entry_date'] as String?;
    final entryCount = (widget.summary?['entry_count'] as num?)?.toInt();
    final cached = widget.summary?['cached'] as bool? ?? false;
    final toneName = (widget.summary?['tone_name'] as String?) ?? 'Therapist';

    return Dismissible(
      key: const ValueKey('summary-populated'),
      direction: DismissDirection.startToEnd,
      confirmDismiss: (_) async {
        await widget.onRefresh();
        return false;
      },
      background: _summarySwipeBackground(
        label: 'Refresh',
        icon: CupertinoIcons.refresh,
      ),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(26),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              JournalColors.accent.withOpacity(0.15),
              JournalColors.bgCard.withOpacity(0.96),
              const Color(0xFF14192F).withOpacity(0.94),
            ],
          ),
          border: Border.all(color: JournalColors.borderBright),
          boxShadow: const [
            BoxShadow(
              color: Color(0x1F6366F1),
              blurRadius: 22,
              offset: Offset(0, 14),
            ),
          ],
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(26),
            onTap: () => setState(() => _expanded = !_expanded),
            child: Padding(
              padding: const EdgeInsets.all(22),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const _HeroGlyph(
                        icon: CupertinoIcons.sparkles,
                        size: 18,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${toneName.toUpperCase()} INSIGHT',
                              style: const TextStyle(
                                color: JournalColors.textMuted,
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 1.2,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              [
                                if (entryDate != null) entryDate,
                                if (entryCount != null) '$entryCount entries',
                              ].join('  •  '),
                              style: const TextStyle(
                                color: JournalColors.textSecondary,
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      if (cached)
                        const _SummaryMetaPill(
                          icon: CupertinoIcons.check_mark_circled,
                          label: 'cached',
                          accent: JournalColors.textMuted,
                        ),
                      _SummaryActionPill(
                        icon: widget.ttsLoading
                            ? null
                            : widget.speaking
                                ? CupertinoIcons.stop_fill
                                : CupertinoIcons.speaker_2_fill,
                        label: widget.ttsLoading
                            ? 'Generating…'
                            : widget.speaking
                                ? 'Stop'
                                : 'Listen',
                        accent: JournalColors.accent,
                        loading: widget.ttsLoading,
                        onTap: widget.onToggleSpeak,
                      ),
                      _SummaryActionPill(
                        icon: CupertinoIcons.chat_bubble_2_fill,
                        label: 'Continue in Sage',
                        accent: JournalColors.info,
                        onTap: widget.onContinueInSage,
                      ),
                    ],
                  ),
                  if (widget.ttsError != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      widget.ttsError!,
                      style: const TextStyle(
                        color: JournalColors.danger,
                        fontSize: 12,
                        height: 1.45,
                      ),
                    ),
                  ],
                  const SizedBox(height: 16),
                  Text(
                    insight,
                    style: const TextStyle(
                      color: JournalColors.textPrimary,
                      fontSize: 15,
                      height: 1.62,
                    ),
                    maxLines: _expanded ? null : 5,
                    overflow: _expanded
                        ? TextOverflow.visible
                        : TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Text(
                        _expanded ? 'Collapse insight' : 'Open full insight',
                        style: const TextStyle(
                          color: JournalColors.accent,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const Spacer(),
                      Icon(
                        _expanded
                            ? CupertinoIcons.chevron_up
                            : CupertinoIcons.chevron_down,
                        color: JournalColors.textMuted,
                        size: 14,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _summarySwipeBackground({
    required String label,
    required IconData icon,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: JournalColors.accent.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(26),
      ),
      padding: const EdgeInsets.only(left: 20),
      alignment: Alignment.centerLeft,
      child: Row(
        children: [
          Icon(icon, color: JournalColors.accent, size: 18),
          const SizedBox(width: 8),
          Text(
            label,
            style: const TextStyle(
              color: JournalColors.accent,
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _SummaryActionPill extends StatelessWidget {
  const _SummaryActionPill({
    required this.label,
    required this.accent,
    required this.onTap,
    this.icon,
    this.loading = false,
  });

  final IconData? icon;
  final String label;
  final Color accent;
  final Future<void> Function() onTap;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: loading ? null : () => onTap(),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(999),
          color: accent.withValues(alpha: 0.08),
          border: Border.all(color: accent.withValues(alpha: 0.22)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (loading)
              CupertinoActivityIndicator(color: accent, radius: 6)
            else if (icon != null)
              Icon(icon, color: accent, size: 13),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                color: accent,
                fontSize: 10,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SummaryMetaPill extends StatelessWidget {
  const _SummaryMetaPill({
    required this.icon,
    required this.label,
    required this.accent,
  });

  final IconData icon;
  final String label;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        color: accent.withValues(alpha: 0.08),
        border: Border.all(color: accent.withValues(alpha: 0.20)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: accent, size: 13),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              color: accent,
              fontSize: 10,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _EntryTile extends StatefulWidget {
  const _EntryTile({
    required this.entry,
    required this.index,
    required this.onDelete,
    required this.onEdit,
  });

  final Map<String, dynamic> entry;
  final int index;
  final VoidCallback onDelete;
  final VoidCallback onEdit;

  @override
  State<_EntryTile> createState() => _EntryTileState();
}

class _EntryTileState extends State<_EntryTile> {
  final _api = ApiService();
  bool _expanded = false;
  bool _attachmentsLoading = false;
  List<Map<String, dynamic>> _attachments = [];

  List<String> _parseTags(dynamic raw) {
    if (raw == null) return [];
    if (raw is List) return raw.map((e) => e.toString()).toList();
    final value = raw.toString().trim();
    if (value.isEmpty || value == '[]' || value == 'null') return [];
    try {
      final inner = value.replaceAll(RegExp(r'^\[|\]$'), '');
      return inner
          .split(RegExp(r',\s*'))
          .map((tag) => tag.replaceAll('"', '').trim())
          .where((tag) => tag.isNotEmpty)
          .toList();
    } catch (_) {
      return [];
    }
  }

  Color _fallbackMoodColor(dynamic score) {
    final value = (score as num?)?.toDouble() ?? 0.5;
    if (value >= 0.7) return JournalColors.success;
    if (value >= 0.4) return JournalColors.severity;
    return JournalColors.danger;
  }

  Color _moodAccent(String? label, dynamic score) {
    final normalized = label?.trim().toLowerCase();
    switch (normalized) {
      case 'angry':
      case 'rage':
      case 'furious':
      case 'resentful':
        return JournalColors.danger;
      case 'sad':
      case 'grief':
      case 'depressed':
      case 'lonely':
        return JournalColors.info;
      case 'anxious':
      case 'stressed':
      case 'overwhelmed':
      case 'worried':
        return JournalColors.orange;
      case 'happy':
      case 'calm':
      case 'hopeful':
      case 'content':
      case 'grateful':
        return JournalColors.success;
      case 'confused':
      case 'uncertain':
      case 'mixed':
        return JournalColors.severity;
      default:
        return _fallbackMoodColor(score);
    }
  }

  DateTime? _parseDate(String raw) {
    try {
      return DateTime.parse(raw).toLocal();
    } catch (_) {
      return null;
    }
  }

  Future<void> _ensureAttachmentsLoaded() async {
    if (_attachmentsLoading || _attachments.isNotEmpty) return;
    final entryId = widget.entry['id'];
    if (entryId is! int) return;
    setState(() => _attachmentsLoading = true);
    try {
      final result = await _api.getEntryAttachments(entryId);
      final imageAttachments = result
          .map((item) => Map<String, dynamic>.from(item as Map))
          .where(
            (item) => (item['media_type'] as String? ?? '')
                .toLowerCase()
                .startsWith('image/'),
          )
          .toList();
      if (mounted) {
        setState(() {
          _attachments = imageAttachments;
          _attachmentsLoading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _attachmentsLoading = false);
    }
  }

  void _toggleExpanded() {
    final nextExpanded = !_expanded;
    setState(() => _expanded = nextExpanded);
    if (nextExpanded) _ensureAttachmentsLoaded();
  }

  String _attachmentImagePath(String attachmentId) {
    return '/api/entry-attachments/$attachmentId/file';
  }

  Future<void> _openImageLightbox(String path) async {
    await Navigator.of(context).push(
      PageRouteBuilder<void>(
        opaque: false,
        barrierColor: Colors.black.withValues(alpha: 0.9),
        pageBuilder: (context, animation, secondaryAnimation) =>
            _TimelineImageLightbox(path: path),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return FadeTransition(opacity: animation, child: child);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final entry = widget.entry;
    final rawDate =
        (entry['entry_date'] ?? entry['ingested_at'] ?? '') as String;
    final date = _parseDate(rawDate);
    final displayDate =
        date != null ? DateFormat('EEE, MMM d').format(date) : rawDate;
    final dayNumber = date != null ? DateFormat('d').format(date) : '--';
    final monthLabel = date != null ? DateFormat('MMM').format(date) : 'ENTRY';
    final text = (entry['text'] as String? ?? '').trim();
    final displayText = ((entry['summary_text'] ??
                entry['normalized_text'] ??
                entry['text']) as String? ??
            '')
        .trim();
    final wordCount = (entry['word_count'] as num?)?.toInt() ??
        text.split(RegExp(r'\s+')).where((word) => word.isNotEmpty).length;
    final moodLabel = entry['mood_label'] as String?;
    final moodScore = entry['mood_score'];
    final tags = _parseTags(entry['tags']);
    final visibleTags = _expanded ? tags : tags.take(3).toList();
    final hiddenTagCount = _expanded ? 0 : tags.length - visibleTags.length;
    final isLong = displayText.length > 280;
    final railColor = _moodAccent(moodLabel, moodScore);

    return Dismissible(
      key: ValueKey('entry-${entry['id']}'),
      direction: DismissDirection.horizontal,
      confirmDismiss: (direction) async {
        if (direction == DismissDirection.startToEnd) {
          widget.onDelete();
        } else {
          widget.onEdit();
        }
        return false;
      },
      background: _entrySwipeBackground(
        alignment: Alignment.centerLeft,
        color: JournalColors.danger,
        icon: CupertinoIcons.trash,
        label: 'Delete',
      ),
      secondaryBackground: _entrySwipeBackground(
        alignment: Alignment.centerRight,
        color: JournalColors.accent,
        icon: CupertinoIcons.pencil,
        label: 'Edit',
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 10, right: 14),
            child: Column(
              children: [
                Container(
                  width: 46,
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(18),
                    color: Colors.white.withOpacity(0.04),
                    border: Border.all(color: Colors.white.withOpacity(0.08)),
                  ),
                  child: Column(
                    children: [
                      Text(
                        monthLabel,
                        style: const TextStyle(
                          color: JournalColors.textMuted,
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1.0,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        dayNumber,
                        style: const TextStyle(
                          color: JournalColors.textPrimary,
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  width: 2,
                  height: 88,
                  margin: const EdgeInsets.symmetric(vertical: 8),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(999),
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        railColor.withOpacity(0.85),
                        railColor.withOpacity(0.12),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _toggleExpanded,
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(26),
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      JournalColors.bgCard.withOpacity(0.96),
                      const Color(0xFF121625).withOpacity(0.94),
                    ],
                  ),
                  border: Border.all(color: Colors.white.withOpacity(0.08)),
                  boxShadow: [
                    BoxShadow(
                      color: railColor.withOpacity(0.10),
                      blurRadius: 18,
                      offset: const Offset(0, 10),
                    ),
                  ],
                ),
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  displayDate,
                                  style: const TextStyle(
                                    color: JournalColors.textPrimary,
                                    fontSize: 18,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          if (moodLabel != null && moodLabel.isNotEmpty)
                            _MetaBadge(
                              label: moodLabel,
                              color: railColor,
                            ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          _SubtleMetaChip(
                            icon: CupertinoIcons.text_alignleft,
                            label: '$wordCount words',
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      Text(
                        displayText,
                        style: const TextStyle(
                          color: JournalColors.textSecondary,
                          fontSize: 15,
                          height: 1.62,
                        ),
                        maxLines: _expanded ? null : 5,
                        overflow: _expanded
                            ? TextOverflow.visible
                            : TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 10),
                      GestureDetector(
                        onTap: _toggleExpanded,
                        child: Text(
                          _expanded
                              ? 'Show less'
                              : (isLong ? 'Read more' : 'Open entry'),
                          style: TextStyle(
                            color: railColor,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      if (_expanded) ...[
                        if (_attachmentsLoading) ...[
                          const SizedBox(height: 16),
                          const Center(
                            child: CupertinoActivityIndicator(
                              color: JournalColors.accent,
                            ),
                          ),
                        ] else if (_attachments.isNotEmpty) ...[
                          const SizedBox(height: 16),
                          SizedBox(
                            height: 72,
                            child: ListView.separated(
                              scrollDirection: Axis.horizontal,
                              itemCount: _attachments.length,
                              separatorBuilder: (_, __) =>
                                  const SizedBox(width: 10),
                              itemBuilder: (context, index) {
                                final attachment = _attachments[index];
                                final path = _attachmentImagePath(
                                    attachment['id'].toString());
                                return GestureDetector(
                                  onTap: () => _openImageLightbox(path),
                                  child: Container(
                                    width: 72,
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(16),
                                      border: Border.all(
                                        color: Colors.white
                                            .withValues(alpha: 0.10),
                                      ),
                                    ),
                                    child: ClipRRect(
                                      borderRadius: BorderRadius.circular(15),
                                      child: _AuthImage(path: path),
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                        ],
                      ],
                      if (tags.isNotEmpty) ...[
                        const SizedBox(height: 16),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            ...visibleTags.map(
                              (tag) => Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 7,
                                ),
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(999),
                                  color: railColor.withOpacity(0.08),
                                  border: Border.all(
                                    color: railColor.withOpacity(0.16),
                                  ),
                                ),
                                child: Text(
                                  tag,
                                  style: TextStyle(
                                    color: railColor.withOpacity(0.92),
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ),
                            if (hiddenTagCount > 0)
                              _SubtleMetaChip(
                                icon: CupertinoIcons.ellipsis,
                                label: '+$hiddenTagCount more',
                              ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _entrySwipeBackground({
    required Alignment alignment,
    required Color color,
    required IconData icon,
    required String label,
  }) {
    final isRight = alignment == Alignment.centerRight;
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(26),
        color: color.withOpacity(0.14),
      ),
      padding: EdgeInsets.only(left: isRight ? 0 : 20, right: isRight ? 20 : 0),
      alignment: alignment,
      child: Row(
        mainAxisAlignment:
            isRight ? MainAxisAlignment.end : MainAxisAlignment.start,
        children: [
          if (!isRight) Icon(icon, color: color, size: 18),
          if (!isRight) const SizedBox(width: 8),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
          if (isRight) const SizedBox(width: 8),
          if (isRight) Icon(icon, color: color, size: 18),
        ],
      ),
    );
  }
}

class _MetaBadge extends StatelessWidget {
  const _MetaBadge({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        color: color.withOpacity(0.12),
        border: Border.all(color: color.withOpacity(0.28)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _SubtleMetaChip extends StatelessWidget {
  const _SubtleMetaChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        color: Colors.white.withOpacity(0.04),
        border: Border.all(color: Colors.white.withOpacity(0.08)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: JournalColors.textMuted, size: 14),
          const SizedBox(width: 7),
          Text(
            label,
            style: const TextStyle(
              color: JournalColors.textSecondary,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _AuthImage extends StatefulWidget {
  const _AuthImage({required this.path});

  final String path;

  @override
  State<_AuthImage> createState() => _AuthImageState();
}

class _AuthImageState extends State<_AuthImage> {
  final _api = ApiService();
  _ImgState _state = _ImgState.loading;
  List<int>? _bytes;

  @override
  void initState() {
    super.initState();
    _fetch();
  }

  @override
  void didUpdateWidget(covariant _AuthImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.path != widget.path) {
      setState(() {
        _state = _ImgState.loading;
        _bytes = null;
      });
      _fetch();
    }
  }

  Future<void> _fetch() async {
    if (widget.path.isEmpty) {
      if (mounted) setState(() => _state = _ImgState.error);
      return;
    }
    try {
      final bytes = await _api.fetchImageBytes(widget.path);
      if (mounted) {
        setState(() {
          _bytes = bytes;
          _state = _ImgState.done;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _state = _ImgState.error);
    }
  }

  @override
  Widget build(BuildContext context) {
    switch (_state) {
      case _ImgState.loading:
        return const Center(
          child: CupertinoActivityIndicator(color: JournalColors.accent),
        );
      case _ImgState.error:
        return const Center(
          child: Icon(
            CupertinoIcons.photo,
            color: JournalColors.textMuted,
            size: 20,
          ),
        );
      case _ImgState.done:
        return Image.memory(
          Uint8List.fromList(_bytes!),
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => const Center(
            child: Icon(
              CupertinoIcons.photo,
              color: JournalColors.textMuted,
              size: 20,
            ),
          ),
        );
    }
  }
}

enum _ImgState { loading, done, error }

class _TimelineImageLightbox extends StatelessWidget {
  const _TimelineImageLightbox({required this.path});

  final String path;

  @override
  Widget build(BuildContext context) {
    return CupertinoPageScaffold(
      backgroundColor: Colors.black.withValues(alpha: 0.92),
      child: SafeArea(
        child: Stack(
          children: [
            Positioned.fill(
              child: GestureDetector(
                onTap: () => Navigator.of(context).pop(),
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 64, 20, 20),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(24),
                      child: _AuthImage(path: path),
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              top: 12,
              right: 20,
              child: GestureDetector(
                onTap: () => Navigator.of(context).pop(),
                child: Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.35),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.14),
                    ),
                  ),
                  child: const Icon(
                    CupertinoIcons.xmark,
                    color: JournalColors.textPrimary,
                    size: 18,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EditEntryScreen extends StatefulWidget {
  const _EditEntryScreen({required this.entry, required this.api});

  final Map<String, dynamic> entry;
  final ApiService api;

  @override
  State<_EditEntryScreen> createState() => _EditEntryScreenState();
}

class _EditEntryScreenState extends State<_EditEntryScreen> {
  TextEditingController? _ctrl;
  bool _loading = true;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadRaw();
  }

  Future<void> _loadRaw() async {
    try {
      final data = await widget.api.getEntry(widget.entry['id'] as int);
      final raw = (data['normalized_text'] as String? ?? '').trim();
      if (mounted) {
        setState(() {
          _ctrl = TextEditingController(text: raw);
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = 'Failed to load entry.';
        });
      }
    }
  }

  @override
  void dispose() {
    _ctrl?.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final newText = _ctrl?.text.trim() ?? '';
    if (newText.isEmpty) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final updated =
          await widget.api.updateEntry(widget.entry['id'] as int, newText);
      if (mounted) Navigator.pop(context, updated);
    } catch (_) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = 'Failed to save.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return CupertinoPageScaffold(
      backgroundColor: JournalColors.bgBase,
      navigationBar: CupertinoNavigationBar(
        backgroundColor: JournalColors.bgBase.withOpacity(0.9),
        border: const Border(
          bottom: BorderSide(color: JournalColors.border, width: 0.5),
        ),
        middle: const Text(
          'Edit Entry',
          style: TextStyle(color: JournalColors.textPrimary),
        ),
        leading: GestureDetector(
          onTap: () => Navigator.pop(context),
          child: const Text(
            'Cancel',
            style: TextStyle(color: JournalColors.textMuted),
          ),
        ),
        trailing: _saving
            ? const CupertinoActivityIndicator(
                color: JournalColors.accent,
                radius: 9,
              )
            : GestureDetector(
                onTap: _save,
                child: const Text(
                  'Save',
                  style: TextStyle(
                    color: JournalColors.accent,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
      ),
      child: _loading
          ? const Center(
              child: CupertinoActivityIndicator(
                color: JournalColors.accent,
                radius: 12,
              ),
            )
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (_error != null) ...[
                      Text(
                        _error!,
                        style: const TextStyle(
                          color: JournalColors.danger,
                          fontSize: 13,
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],
                    Expanded(
                      child: CupertinoTextField(
                        controller: _ctrl,
                        maxLines: null,
                        minLines: 10,
                        autofocus: true,
                        style: const TextStyle(
                          color: JournalColors.textPrimary,
                          fontSize: 16,
                          height: 1.6,
                        ),
                        placeholder: 'Write your entry...',
                        placeholderStyle: const TextStyle(
                          color: JournalColors.textMuted,
                          fontSize: 16,
                        ),
                        decoration:
                            const BoxDecoration(color: Colors.transparent),
                        keyboardAppearance: Brightness.dark,
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}
