import 'package:adaptive_platform_ui/adaptive_platform_ui.dart';
import 'package:flutter/cupertino.dart';
import 'package:intl/intl.dart';

import '../services/api_service.dart';
import '../theme/app_theme.dart';
import '../widgets/glass_card.dart';
import '../widgets/section_header.dart';

Color _withAlpha(Color color, double alpha) => color.withValues(alpha: alpha);

class EarlyWarningScreen extends StatefulWidget {
  const EarlyWarningScreen({super.key});

  @override
  State<EarlyWarningScreen> createState() => _EarlyWarningScreenState();
}

class _EarlyWarningScreenState extends State<EarlyWarningScreen> {
  final _api = ApiService();

  Map<String, dynamic>? _status;
  bool _loading = true;
  bool _rebuilding = false;
  bool _dismissing = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await _api.getEarlyWarningStatus();
      if (mounted) {
        setState(() {
          _status = data;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = _parseError(e);
          _loading = false;
        });
      }
    }
  }

  Future<void> _dismiss() async {
    if (_dismissing) return;
    setState(() => _dismissing = true);
    try {
      await _api.dismissEarlyWarning();
      await _load();
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = _parseError(e);
          _dismissing = false;
        });
      }
      return;
    }
    if (mounted) {
      setState(() => _dismissing = false);
    }
  }

  Future<void> _rebuild() async {
    if (_rebuilding) return;
    setState(() => _rebuilding = true);
    try {
      await _api.rebuildEarlyWarningPatterns();
      await _load();
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = _parseError(e);
          _rebuilding = false;
        });
      }
      return;
    }
    if (mounted) {
      setState(() => _rebuilding = false);
    }
  }

  String _parseError(dynamic e) {
    final str = e.toString();
    final match = RegExp(r'"detail"\s*:\s*"([^"]+)"').firstMatch(str);
    return match?.group(1) ?? 'Could not load warning status.';
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

  List<String> _readStringList(dynamic value) {
    if (value is! List) return const <String>[];
    return value
        .map((item) => item?.toString().trim())
        .whereType<String>()
        .where((item) => item.isNotEmpty)
        .toList();
  }

  String? _readText(Map<String, dynamic> map, String key) {
    final value = map[key];
    if (value is String) {
      final trimmed = value.trim();
      return trimmed.isEmpty ? null : trimmed;
    }
    final stringValue = value?.toString().trim();
    if (stringValue == null || stringValue.isEmpty) return null;
    return stringValue;
  }

  int _readInt(Map<String, dynamic> map, String key) {
    final value = map[key];
    if (value is int) return value;
    if (value is num) return value.round();
    if (value is String) return int.tryParse(value) ?? 0;
    return 0;
  }

  double? _readDouble(Map<String, dynamic> map, String key) {
    final value = map[key];
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value);
    return null;
  }

  bool _readBool(Map<String, dynamic> map, String key) {
    final value = map[key];
    if (value is bool) return value;
    if (value is String) return value.toLowerCase() == 'true';
    return false;
  }

  String _formatDate(String? raw) {
    if (raw == null || raw.isEmpty) return 'No comparable spike';
    final parsed = DateTime.tryParse(raw);
    if (parsed == null) return raw;
    return DateFormat('MMM d, y').format(parsed.toLocal());
  }

  List<Widget> _buildContent() {
    final status = _status ?? <String, dynamic>{};
    final signals = _readMap(status['current_signals']);
    final matchedSpikesRaw = status['matched_spikes'] as List? ?? const [];
    final matchedSpikes = matchedSpikesRaw
        .whereType<Map>()
        .map((item) => item.map(
              (key, value) => MapEntry(key.toString(), value),
            ))
        .toList();

    final active = _readBool(status, 'active');
    final dismissed = _readBool(status, 'dismissed');
    final totalPatterns = _readInt(status, 'total_patterns');
    final matchedCount = _readInt(status, 'matched_count');
    final confidence = _readDouble(status, 'confidence');
    final averageSeverity = _readDouble(signals, 'avg_severity');
    final lastSpikeSeverity = _readDouble(status, 'last_spike_severity');
    final lastSpikeDate = _formatDate(_readText(status, 'last_spike_date'));
    final trend = (_readText(signals, 'trend') ?? 'stable').toLowerCase();
    final severityTrendingUp = _readBool(signals, 'sev_trending_up');
    final people = _readStringList(signals['people']);
    final topics = _readStringList(signals['topics']);
    final keywords = _readStringList(signals['keywords']);
    final hasSignals =
        people.isNotEmpty || topics.isNotEmpty || keywords.isNotEmpty;

    final items = <Widget>[
      _EarlyWarningHero(
        active: active,
        dismissed: dismissed,
        totalPatterns: totalPatterns,
        matchedCount: matchedCount,
        confidence: confidence,
      ),
      const SizedBox(height: 20),
      _StatusCard(
        active: active,
        dismissed: dismissed,
        totalPatterns: totalPatterns,
        matchedCount: matchedCount,
        confidence: confidence,
        averageSeverity: averageSeverity,
        lastSpikeDate: lastSpikeDate,
        lastSpikeSeverity: lastSpikeSeverity,
        onDismiss: active ? _dismiss : null,
        dismissing: _dismissing,
      ),
      const SizedBox(height: 20),
    ];

    if (hasSignals) {
      items.addAll([
        SectionHeader(
          title: 'Current Signals',
          trailing: _TrendBadge(
            trend: trend,
            severityTrendingUp: severityTrendingUp,
          ),
        ),
        const SizedBox(height: 10),
        GlassCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Signals from the last three days.',
                style: TextStyle(
                  color: JournalColors.textSecondary,
                  fontSize: 14,
                  height: 1.5,
                ),
              ),
              if (people.isNotEmpty) ...[
                const SizedBox(height: 16),
                _SignalGroup(
                  label: 'People appearing',
                  color: JournalColors.accent2,
                  items: people,
                ),
              ],
              if (topics.isNotEmpty) ...[
                const SizedBox(height: 16),
                _SignalGroup(
                  label: 'Topics active',
                  color: JournalColors.accent,
                  items: topics,
                ),
              ],
              if (keywords.isNotEmpty) ...[
                const SizedBox(height: 16),
                _SignalGroup(
                  label: 'Stress language',
                  color: JournalColors.orange,
                  items: keywords,
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 20),
      ]);
    }

    if (matchedSpikes.isNotEmpty) {
      items.addAll([
        const SectionHeader(title: 'Historical Matches'),
        const SizedBox(height: 10),
        GlassCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Past periods that most closely resemble the recent signal set.',
                style: TextStyle(
                  color: JournalColors.textSecondary,
                  fontSize: 14,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 14),
              for (var index = 0; index < matchedSpikes.length; index++)
                Padding(
                  padding: EdgeInsets.only(
                    bottom: index == matchedSpikes.length - 1 ? 0 : 10,
                  ),
                  child: _MatchedSpikeRow(spike: matchedSpikes[index]),
                ),
            ],
          ),
        ),
        const SizedBox(height: 20),
      ]);
    }

    if (totalPatterns == 0) {
      items.addAll([
        const SectionHeader(title: 'Pattern Build'),
        const SizedBox(height: 10),
        const GlassCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  _MiniGlyph(
                    icon: CupertinoIcons.waveform_path_ecg,
                    color: JournalColors.severity,
                  ),
                  SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'No historical warning patterns are on file yet.',
                      style: TextStyle(
                        color: JournalColors.textPrimary,
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                        height: 1.3,
                      ),
                    ),
                  ),
                ],
              ),
              SizedBox(height: 14),
              Text(
                'This view becomes more useful once there are enough entries with variation in severity for the system to compare against.',
                style: TextStyle(
                  color: JournalColors.textSecondary,
                  fontSize: 14,
                  height: 1.55,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
      ]);
    }

    items.add(
      GlassCard(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            const Expanded(
              child: Text(
                'Patterns refresh automatically when this screen is checked. Use rebuild if you want a manual refresh.',
                style: TextStyle(
                  color: JournalColors.textSecondary,
                  fontSize: 13,
                  height: 1.5,
                ),
              ),
            ),
            const SizedBox(width: 16),
            SizedBox(
              width: 154,
              child: AdaptiveButton(
                style: AdaptiveButtonStyle.prominentGlass,
                onPressed: _rebuilding ? null : _rebuild,
                label: _rebuilding ? 'Rebuilding...' : 'Rebuild',
              ),
            ),
          ],
        ),
      ),
    );

    items.add(const SizedBox(height: 40));
    return items;
  }

  @override
  Widget build(BuildContext context) {
    return CupertinoPageScaffold(
      backgroundColor: JournalColors.bgBase,
      child: Stack(
        children: [
          const Positioned.fill(child: _EarlyWarningBackdrop()),
          CustomScrollView(
            slivers: [
              CupertinoSliverNavigationBar(
                largeTitle: const Text('Early Warning'),
                backgroundColor: _withAlpha(JournalColors.bgBase, 0.85),
                border: const Border(
                  bottom: BorderSide(color: JournalColors.border, width: 0.5),
                ),
                trailing: GestureDetector(
                  onTap: _loading ? null : _load,
                  child: Icon(
                    CupertinoIcons.refresh,
                    color: _loading
                        ? JournalColors.textMuted
                        : JournalColors.accent,
                  ),
                ),
              ),
              if (_loading)
                const SliverFillRemaining(
                  child: Center(
                    child: CupertinoActivityIndicator(
                      color: JournalColors.accent,
                    ),
                  ),
                )
              else if (_error != null)
                SliverFillRemaining(
                  child: _ErrorView(error: _error!, onRetry: _load),
                )
              else
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
                  sliver: SliverList(
                    delegate: SliverChildListDelegate(_buildContent()),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _EarlyWarningBackdrop extends StatelessWidget {
  const _EarlyWarningBackdrop();

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Stack(
        children: [
          const Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Color(0xFF090A15),
                    JournalColors.bgBase,
                    Color(0xFF05060D),
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            top: 110,
            left: -24,
            child: _GlowOrb(
              size: 180,
              color: _withAlpha(JournalColors.severity, 0.18),
            ),
          ),
          Positioned(
            top: 260,
            right: -34,
            child: _GlowOrb(
              size: 148,
              color: _withAlpha(JournalColors.accent, 0.14),
            ),
          ),
          Positioned(
            bottom: 140,
            left: 30,
            child: _GlowOrb(
              size: 120,
              color: _withAlpha(JournalColors.orange, 0.10),
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
          colors: [color, _withAlpha(color, 0)],
        ),
      ),
    );
  }
}

class _EarlyWarningHero extends StatelessWidget {
  const _EarlyWarningHero({
    required this.active,
    required this.dismissed,
    required this.totalPatterns,
    required this.matchedCount,
    required this.confidence,
  });

  final bool active;
  final bool dismissed;
  final int totalPatterns;
  final int matchedCount;
  final double? confidence;

  @override
  Widget build(BuildContext context) {
    final dateLabel = DateFormat('MMMM d, y').format(DateTime.now());

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: active ? JournalColors.severity : JournalColors.borderBright,
        ),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            _withAlpha(JournalColors.bgCard, 0.97),
            _withAlpha(JournalColors.bgCardAlt, 0.94),
            _withAlpha(
                active ? JournalColors.orange : JournalColors.accent, 0.08),
          ],
        ),
        boxShadow: [
          BoxShadow(
            color: _withAlpha(
              active ? JournalColors.severity : JournalColors.accentGlow,
              0.80,
            ),
            blurRadius: 28,
            offset: const Offset(0, 18),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _HeroGlyph(
                icon: active
                    ? CupertinoIcons.bell_fill
                    : dismissed
                        ? CupertinoIcons.bell_slash_fill
                        : CupertinoIcons.waveform_path_ecg,
                color: active ? JournalColors.severity : JournalColors.accent,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'PATTERN STATUS · $dateLabel',
                      style: const TextStyle(
                        color: JournalColors.textMuted,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.2,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      active
                          ? 'Recent entries resemble earlier pre-spike periods.'
                          : dismissed
                              ? 'A warning was dismissed and is being held for now.'
                              : totalPatterns == 0
                                  ? 'The system is still building enough history to compare.'
                                  : 'No current signal set is crossing the warning threshold.',
                      style: const TextStyle(
                        color: JournalColors.textPrimary,
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                        height: 1.2,
                      ),
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'This view compares the last three days against your own historical patterns.',
                      style: TextStyle(
                        color: JournalColors.textSecondary,
                        fontSize: 13,
                        height: 1.5,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: _MetricTile(
                  label: 'Patterns',
                  value: '$totalPatterns',
                  color: JournalColors.accent,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _MetricTile(
                  label: 'Matches',
                  value: '$matchedCount',
                  color: active ? JournalColors.severity : JournalColors.info,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _MetricTile(
                  label: 'Confidence',
                  value: confidence == null
                      ? '—'
                      : '${(confidence! * 100).round()}%',
                  color: JournalColors.orange,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _HeroGlyph extends StatelessWidget {
  const _HeroGlyph({required this.icon, required this.color});

  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 42,
      height: 42,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          colors: [
            _withAlpha(color, 0.24),
            _withAlpha(JournalColors.bgSurface, 0.82),
          ],
        ),
        border: Border.all(color: _withAlpha(color, 0.30)),
      ),
      child: Icon(icon, color: JournalColors.textPrimary, size: 19),
    );
  }
}

class _StatusCard extends StatelessWidget {
  const _StatusCard({
    required this.active,
    required this.dismissed,
    required this.totalPatterns,
    required this.matchedCount,
    required this.confidence,
    required this.averageSeverity,
    required this.lastSpikeDate,
    required this.lastSpikeSeverity,
    required this.onDismiss,
    required this.dismissing,
  });

  final bool active;
  final bool dismissed;
  final int totalPatterns;
  final int matchedCount;
  final double? confidence;
  final double? averageSeverity;
  final String lastSpikeDate;
  final double? lastSpikeSeverity;
  final VoidCallback? onDismiss;
  final bool dismissing;

  @override
  Widget build(BuildContext context) {
    final accentColor = active
        ? JournalColors.severity
        : dismissed
            ? JournalColors.accent
            : JournalColors.info;

    return GlassCard(
      accentBorder: active,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _MiniGlyph(
                icon: active
                    ? CupertinoIcons.exclamationmark_triangle_fill
                    : dismissed
                        ? CupertinoIcons.check_mark_circled_solid
                        : CupertinoIcons.check_mark_circled,
                color: accentColor,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _title(),
                      style: const TextStyle(
                        color: JournalColors.textPrimary,
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        height: 1.25,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      _body(),
                      style: const TextStyle(
                        color: JournalColors.textSecondary,
                        fontSize: 14,
                        height: 1.55,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (totalPatterns > 0) ...[
            const SizedBox(height: 16),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                _InlineStat(
                  label: 'Patterns on file',
                  value: '$totalPatterns',
                  color: JournalColors.accent,
                ),
                _InlineStat(
                  label: 'Current matches',
                  value: '$matchedCount',
                  color: accentColor,
                ),
                _InlineStat(
                  label: 'Confidence',
                  value: confidence == null
                      ? '—'
                      : '${(confidence! * 100).round()}%',
                  color: JournalColors.orange,
                ),
                _InlineStat(
                  label: 'Avg severity',
                  value: averageSeverity?.toStringAsFixed(1) ?? '—',
                  color: _severityColor(averageSeverity),
                ),
              ],
            ),
          ],
          if (active && onDismiss != null) ...[
            const SizedBox(height: 18),
            SizedBox(
              width: 172,
              child: AdaptiveButton(
                style: AdaptiveButtonStyle.prominentGlass,
                onPressed: dismissing ? null : onDismiss,
                label: dismissing ? 'Dismissing...' : 'Dismiss for now',
              ),
            ),
          ],
          if (lastSpikeSeverity != null || active) ...[
            const SizedBox(height: 16),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: _withAlpha(JournalColors.bgSurface, 0.72),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: JournalColors.border),
              ),
              child: Row(
                children: [
                  const Icon(
                    CupertinoIcons.clock,
                    color: JournalColors.textMuted,
                    size: 17,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Closest recent spike: $lastSpikeDate${lastSpikeSeverity == null ? '' : ' · severity ${lastSpikeSeverity!.toStringAsFixed(1)}'}',
                      style: const TextStyle(
                        color: JournalColors.textSecondary,
                        fontSize: 13,
                        height: 1.45,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  String _title() {
    if (active) return 'Warning threshold met';
    if (dismissed) return 'Warning dismissed';
    if (totalPatterns == 0) return 'Pattern history still forming';
    return 'No warning at the moment';
  }

  String _body() {
    if (active) {
      return 'The last three days align with $matchedCount earlier period${matchedCount == 1 ? '' : 's'} that preceded higher-severity entries.';
    }
    if (dismissed) {
      return 'The current warning was dismissed. If the same conditions remain, it can return after the hold period.';
    }
    if (totalPatterns == 0) {
      return 'There is not enough variation in your history yet to detect a reliable warning pattern.';
    }
    return 'Current signals are below the threshold that would surface a warning based on your prior journal patterns.';
  }
}

class _MetricTile extends StatelessWidget {
  const _MetricTile({
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
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        color: _withAlpha(color, 0.10),
        border: Border.all(color: _withAlpha(color, 0.24)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: double.infinity,
            child: FittedBox(
              alignment: Alignment.centerLeft,
              fit: BoxFit.scaleDown,
              child: Text(
                label.toUpperCase(),
                maxLines: 1,
                style: TextStyle(
                  color: _withAlpha(color, 0.96),
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.0,
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: const TextStyle(
              color: JournalColors.textPrimary,
              fontSize: 18,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _MiniGlyph extends StatelessWidget {
  const _MiniGlyph({required this.icon, required this.color});

  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 38,
      height: 38,
      decoration: BoxDecoration(
        color: _withAlpha(color, 0.12),
        shape: BoxShape.circle,
        border: Border.all(color: _withAlpha(color, 0.24)),
      ),
      child: Icon(icon, color: color, size: 18),
    );
  }
}

class _InlineStat extends StatelessWidget {
  const _InlineStat({
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
      constraints: const BoxConstraints(minWidth: 132),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        color: _withAlpha(color, 0.09),
        border: Border.all(color: _withAlpha(color, 0.22)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label.toUpperCase(),
            style: TextStyle(
              color: _withAlpha(color, 0.94),
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.0,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: const TextStyle(
              color: JournalColors.textPrimary,
              fontSize: 17,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _TrendBadge extends StatelessWidget {
  const _TrendBadge({
    required this.trend,
    required this.severityTrendingUp,
  });

  final String trend;
  final bool severityTrendingUp;

  @override
  Widget build(BuildContext context) {
    final color = switch (trend) {
      'rising' => JournalColors.success,
      'declining' => JournalColors.orange,
      _ => JournalColors.accent,
    };
    final label = switch (trend) {
      'rising' => 'Mood rising',
      'declining' => 'Mood declining',
      _ => 'Mood stable',
    };

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        _Pill(label: label, color: color),
        if (severityTrendingUp)
          const _Pill(
            label: 'Severity climbing',
            color: JournalColors.orange,
          ),
      ],
    );
  }
}

class _SignalGroup extends StatelessWidget {
  const _SignalGroup({
    required this.label,
    required this.color,
    required this.items,
  });

  final String label;
  final Color color;
  final List<String> items;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label.toUpperCase(),
          style: const TextStyle(
            color: JournalColors.textMuted,
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.15,
          ),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: items
              .map((item) => _Pill(label: item, color: color, subdued: true))
              .toList(),
        ),
      ],
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({
    required this.label,
    required this.color,
    this.subdued = false,
  });

  final String label;
  final Color color;
  final bool subdued;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        color: _withAlpha(color, subdued ? 0.10 : 0.14),
        border: Border.all(color: _withAlpha(color, subdued ? 0.24 : 0.30)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: subdued ? JournalColors.textPrimary : color,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _MatchedSpikeRow extends StatelessWidget {
  const _MatchedSpikeRow({required this.spike});

  final Map<String, dynamic> spike;

  double? _readDouble(String key) {
    final value = spike[key];
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value);
    return null;
  }

  String _readText(String key) => spike[key]?.toString() ?? 'Unknown';

  @override
  Widget build(BuildContext context) {
    final severity = _readDouble('spike_severity');
    final score = _readDouble('score');

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      decoration: BoxDecoration(
        color: _withAlpha(JournalColors.bgSurface, 0.72),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: JournalColors.border),
      ),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: _withAlpha(_severityColor(severity), 0.14),
              border: Border.all(
                color: _withAlpha(_severityColor(severity), 0.28),
              ),
            ),
            child: Center(
              child: Text(
                severity?.toStringAsFixed(0) ?? '—',
                style: TextStyle(
                  color: _severityColor(severity),
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _readText('spike_date'),
                  style: const TextStyle(
                    color: JournalColors.textPrimary,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Severity ${severity?.toStringAsFixed(1) ?? '—'}',
                  style: const TextStyle(
                    color: JournalColors.textSecondary,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(999),
              color: _withAlpha(
                (score ?? 0) >= 60
                    ? JournalColors.orange
                    : JournalColors.severity,
                0.12,
              ),
              border: Border.all(
                color: _withAlpha(
                  (score ?? 0) >= 60
                      ? JournalColors.orange
                      : JournalColors.severity,
                  0.26,
                ),
              ),
            ),
            child: Text(
              score == null ? '—' : '${score.round()}% match',
              style: TextStyle(
                color: (score ?? 0) >= 60
                    ? JournalColors.orange
                    : JournalColors.severity,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.error, required this.onRetry});

  final String error;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: GlassCard(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                CupertinoIcons.wifi_slash,
                color: JournalColors.textMuted,
                size: 28,
              ),
              const SizedBox(height: 14),
              Text(
                error,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: JournalColors.textSecondary,
                  fontSize: 14,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 16),
              AdaptiveButton(
                style: AdaptiveButtonStyle.prominentGlass,
                onPressed: onRetry,
                label: 'Retry',
              ),
            ],
          ),
        ),
      ),
    );
  }
}

Color _severityColor(double? severity) {
  if (severity == null) return JournalColors.severity;
  if (severity <= 3.0) return JournalColors.success;
  if (severity <= 6.0) return JournalColors.severity;
  return JournalColors.danger;
}
