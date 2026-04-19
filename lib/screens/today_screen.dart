// lib/screens/today_screen.dart
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../services/api_service.dart';
import '../theme/app_theme.dart';
import '../widgets/glass_card.dart';
import '../widgets/section_header.dart';

class TodayScreen extends StatefulWidget {
  const TodayScreen({super.key});

  @override
  State<TodayScreen> createState() => _TodayScreenState();
}

class _TodayScreenState extends State<TodayScreen> {
  final _api = ApiService();

  Map<String, dynamic>? _brief;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final data = await _api.getTodayBrief();
      if (mounted) setState(() { _brief = data; _loading = false; });
    } catch (e) {
      if (mounted) setState(() { _error = e.toString(); _loading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return CupertinoPageScaffold(
      backgroundColor: JournalColors.bgBase,
      child: CustomScrollView(
        slivers: [
          CupertinoSliverNavigationBar(
            largeTitle: const Text('Today'),
            backgroundColor: JournalColors.bgBase.withOpacity(0.9),
            border: const Border(
              bottom: BorderSide(color: JournalColors.border, width: 0.5),
            ),
            trailing: GestureDetector(
              onTap: _load,
              child: const Icon(CupertinoIcons.refresh, color: JournalColors.accent),
            ),
          ),
          if (_loading)
            const SliverFillRemaining(
              child: Center(
                child: CupertinoActivityIndicator(color: JournalColors.accent),
              ),
            )
          else if (_error != null)
            SliverFillRemaining(
              child: _ErrorView(error: _error!, onRetry: _load),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              sliver: SliverList(
                delegate: SliverChildListDelegate([
                  _DateBadge(),
                  const SizedBox(height: 20),
                  if (_brief?['greeting'] != null) ...[
                    _GreetingCard(text: _brief!['greeting'] as String),
                    const SizedBox(height: 20),
                  ],
                  if (_brief?['summary'] != null) ...[
                    const SectionHeader(title: 'Daily Summary'),
                    const SizedBox(height: 12),
                    GlassCard(
                      child: Text(
                        _brief!['summary'] as String,
                        style: const TextStyle(
                          color: JournalColors.textPrimary,
                          fontSize: 15,
                          height: 1.65,
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                  ],
                  if (_brief?['mood'] != null) ...[
                    const SectionHeader(title: 'Mood'),
                    const SizedBox(height: 12),
                    _MoodCard(mood: _brief!['mood'] as Map<String, dynamic>),
                    const SizedBox(height: 24),
                  ],
                  if (_brief?['alerts'] != null &&
                      (_brief!['alerts'] as List).isNotEmpty) ...[
                    const SectionHeader(title: 'Alerts'),
                    const SizedBox(height: 12),
                    ...((_brief!['alerts'] as List)
                        .cast<Map<String, dynamic>>()
                        .map((a) => Padding(
                              padding: const EdgeInsets.only(bottom: 10),
                              child: _AlertCard(alert: a),
                            ))),
                    const SizedBox(height: 24),
                  ],
                  if (_brief?['pattern_insights'] != null &&
                      (_brief!['pattern_insights'] as List).isNotEmpty) ...[
                    const SectionHeader(title: 'Pattern Insights'),
                    const SizedBox(height: 12),
                    ...((_brief!['pattern_insights'] as List)
                        .cast<String>()
                        .map((s) => Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: _InsightRow(text: s),
                            ))),
                  ],
                  const SizedBox(height: 40),
                ]),
              ),
            ),
        ],
      ),
    );
  }
}

// ── Sub-widgets ───────────────────────────────────────────────────────────────

class _DateBadge extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final dayName  = DateFormat('EEEE').format(now);
    final dateStr  = DateFormat('MMMM d, y').format(now);
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: JournalColors.accent.withOpacity(0.12),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: JournalColors.borderBright),
          ),
          child: Row(
            children: [
              const Icon(CupertinoIcons.calendar, color: JournalColors.accent, size: 14),
              const SizedBox(width: 6),
              Text(
                '$dayName · $dateStr',
                style: const TextStyle(
                  color: JournalColors.accent,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _GreetingCard extends StatelessWidget {
  const _GreetingCard({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            JournalColors.accent.withOpacity(0.15),
            JournalColors.accent2.withOpacity(0.08),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: JournalColors.borderBright),
      ),
      child: Text(
        text,
        style: const TextStyle(
          color: JournalColors.textPrimary,
          fontSize: 17,
          fontWeight: FontWeight.w500,
          height: 1.5,
        ),
      ),
    );
  }
}

class _MoodCard extends StatelessWidget {
  const _MoodCard({required this.mood});
  final Map<String, dynamic> mood;

  @override
  Widget build(BuildContext context) {
    final label = mood['label'] ?? mood['mood'] ?? 'Unknown';
    final score = (mood['score'] as num?)?.toDouble() ?? 0.5;
    final color = _moodColor(score);

    return GlassCard(
      child: Row(
        children: [
          Container(
            width: 48, height: 48,
            decoration: BoxDecoration(
              color: color.withOpacity(0.15),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(_moodIcon(score), color: color, size: 26),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label.toString(),
                    style: const TextStyle(
                      color: JournalColors.textPrimary,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    )),
                const SizedBox(height: 6),
                LinearProgressIndicator(
                  value: score,
                  backgroundColor: JournalColors.bgSurface,
                  color: color,
                  minHeight: 6,
                  borderRadius: BorderRadius.circular(3),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Color _moodColor(double score) {
    if (score >= 0.7) return const Color(0xFF22C55E);
    if (score >= 0.4) return const Color(0xFFF59E0B);
    return const Color(0xFFEF4444);
  }

  IconData _moodIcon(double score) {
    if (score >= 0.7) return CupertinoIcons.smiley_fill;
    if (score >= 0.4) return CupertinoIcons.smiley;
    return CupertinoIcons.smiley_fill; // replace with sad if available
  }
}

class _AlertCard extends StatelessWidget {
  const _AlertCard({required this.alert});
  final Map<String, dynamic> alert;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFF59E0B).withOpacity(0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFF59E0B).withOpacity(0.25)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(CupertinoIcons.exclamationmark_triangle_fill,
              color: Color(0xFFF59E0B), size: 18),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              alert['description']?.toString() ?? alert['message']?.toString() ?? '',
              style: const TextStyle(color: JournalColors.textPrimary, fontSize: 14, height: 1.5),
            ),
          ),
        ],
      ),
    );
  }
}

class _InsightRow extends StatelessWidget {
  const _InsightRow({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.only(top: 5),
          child: Icon(CupertinoIcons.circle_fill,
              color: JournalColors.accent, size: 7),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(text,
              style: const TextStyle(
                  color: JournalColors.textSecondary, fontSize: 14, height: 1.6)),
        ),
      ],
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.error, required this.onRetry});
  final String error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(CupertinoIcons.wifi_slash, color: JournalColors.textMuted, size: 48),
          const SizedBox(height: 16),
          const Text('Could not load today\'s brief',
              style: TextStyle(color: JournalColors.textSecondary)),
          const SizedBox(height: 20),
          CupertinoButton(
            color: JournalColors.accent,
            onPressed: onRetry,
            child: const Text('Retry'),
          ),
        ],
      ),
    );
  }
}
