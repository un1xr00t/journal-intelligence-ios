// lib/screens/onboarding_screen.dart
//
// 14-step registration + AI memory building flow.
// Mirrors Onboarding.jsx step-for-step.
// After Account step: registers + loginGetToken (no HomeShell transition yet).
// Done step: calls auth.completeAuthentication() → app routes to HomeShell.

import 'package:adaptive_platform_ui/adaptive_platform_ui.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/auth_provider.dart';
import '../services/api_service.dart';
import '../theme/app_theme.dart';
import '../widgets/glass_card.dart';

Color _withAlpha(Color color, double alpha) => color.withValues(alpha: alpha);

// ── Constants ─────────────────────────────────────────────────────────────────

const _kStepLabels = [
  'Welcome',
  'Features',
  'About You',
  'Situation',
  'People',
  'Topics',
  'Goals',
  'Account',
  'Recovery',
  'AI Setup',
  'Memory',
  'Import',
  'Text Journal',
  'All Set',
];

const _kSituationOpts = [
  (
    'relationship',
    '⚡',
    'Relationship',
    'Difficult relationship or planning to leave'
  ),
  (
    'custody',
    '◎',
    'Custody/Parenting',
    'Co-parenting conflict or custody dispute'
  ),
  ('workplace', '⊞', 'Workplace', 'Hostile work environment or HR matter'),
  ('housing', '⬡', 'Housing', 'Instability, eviction, or unsafe living'),
  ('legal', '⊕', 'Legal Matter', 'Ongoing legal case needing documentation'),
  (
    'mental_health',
    '〜',
    'Mental Health',
    'Tracking mood, anxiety, or wellbeing'
  ),
  (
    'growth',
    '◈',
    'Personal Growth',
    'Self-reflection and building self-knowledge'
  ),
  ('other', '✦', 'Something Else', "My situation doesn't fit a category"),
];

const _kTopicOpts = [
  'Anxiety',
  'Sleep',
  'Health',
  'Work',
  'Relationships',
  'Family',
  'Money',
  'Safety',
  'Legal',
  'Housing',
  'Trauma',
  'Boundaries',
  'Self-worth',
  'Healing',
  'Documentation',
  'Growth',
  'Addiction',
  'Children',
  'Isolation',
  'Identity',
];

const _kGoalOpts = [
  (
    'document',
    '◷',
    'Document my experience',
    'Build an accurate, timestamped record'
  ),
  (
    'patterns',
    '⬡',
    "Find patterns I'm missing",
    "Let AI surface what I can't see myself"
  ),
  (
    'case_file',
    '⊕',
    'Build a case file',
    'Exportable evidence for legal/medical use'
  ),
  (
    'mental',
    '〜',
    'Track my mental health',
    'Mood, severity, and stability over time'
  ),
  (
    'exit',
    '⚡',
    'Plan a major life change',
    'Structured roadmap with AI support'
  ),
  (
    'process',
    '◎',
    'Process my feelings',
    "Understand what I'm actually experiencing"
  ),
  (
    'evidence',
    '◈',
    'Gather legal evidence',
    'For custody, restraining orders, or court'
  ),
  ('heal', '✦', 'Grow and heal', 'Long-term self-knowledge and recovery'),
];

const _kPronounOpts = ['she/her', 'he/him', 'they/them', 'prefer not to say'];

const _kSecurityQuestionsBank = [
  'What was the name of your first pet?',
  'What city were you born in?',
  "What is your mother's maiden name?",
  'What was the name of your first school?',
  'What was the make and model of your first car?',
  'What is the middle name of your oldest sibling?',
  'What street did you grow up on?',
  'What was the name of your childhood best friend?',
  'What is the name of the town where your nearest relative lives?',
  'What was your childhood nickname?',
  'What is the name of the hospital where you were born?',
  'What was the first concert you attended?',
];

// ── Root Screen ───────────────────────────────────────────────────────────────

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  int _step = 0;

  // Form data — mirrors Onboarding.jsx form state
  String _preferredName = '';
  String _pronouns = '';
  String _situationType = '';
  String _situationStory = '';
  final List<Map<String, String>> _people = [];
  final List<String> _topics = [];
  final List<String> _goals = [];
  // Auth tokens held mid-onboarding (don't transition yet)
  Map<String, dynamic>? _midUser;

  void _next() {
    if (mounted) setState(() => _step++);
  }

  void _back() {
    if (_step > 0 && mounted) setState(() => _step--);
  }

  Map<String, dynamic> _memoryPayload({String aiSummary = ''}) => {
        'preferred_name': _preferredName,
        'pronouns': _pronouns,
        'situation_type': _situationType,
        'situation_story': _situationStory,
        'people': _people,
        'topics': _topics,
        'goals': _goals,
        if (aiSummary.isNotEmpty) 'ai_summary': aiSummary,
      };

  void _finishOnboarding() {
    if (!mounted) return;
    if (_midUser != null) {
      context.read<AuthProvider>().completeAuthentication(_midUser!);
    }
    // Consumer at root has now swapped LoginScreen → HomeShell.
    // Pop everything off the navigator stack so HomeShell is visible.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        Navigator.of(context).popUntil((route) => route.isFirst);
      }
    });
  }

  Widget _buildCurrentStep() {
    switch (_step) {
      case 0:
        return _WelcomeStep(onNext: _next);
      case 1:
        return _FeatureTourStep(onNext: _next, onBack: _back);
      case 2:
        return _AboutStep(
          preferredName: _preferredName,
          pronouns: _pronouns,
          onChanged: (name, pronouns) => setState(() {
            _preferredName = name;
            _pronouns = pronouns;
          }),
          onNext: _next,
          onBack: _back,
        );
      case 3:
        return _SituationStep(
          situationType: _situationType,
          situationStory: _situationStory,
          onChanged: (type, story) => setState(() {
            _situationType = type;
            _situationStory = story;
          }),
          onNext: _next,
          onBack: _back,
        );
      case 4:
        return _PeopleStep(
          people: _people,
          onChanged: (p) => setState(() {
            _people.clear();
            _people.addAll(p);
          }),
          onNext: _next,
          onBack: _back,
        );
      case 5:
        return _TopicsStep(
          topics: _topics,
          onChanged: (t) => setState(() {
            _topics.clear();
            _topics.addAll(t);
          }),
          onNext: _next,
          onBack: _back,
        );
      case 6:
        return _GoalsStep(
          goals: _goals,
          onChanged: (g) => setState(() {
            _goals.clear();
            _goals.addAll(g);
          }),
          onNext: _next,
          onBack: _back,
        );
      case 7:
        return _AccountStep(
          onSuccess: (_, __, ___, user, ____) {
            setState(() {
              _midUser = user;
            });
            _next();
          },
          onBack: _back,
        );
      case 8:
        return _SecurityQuestionsStep(onNext: _next, onBack: _back);
      case 9:
        return _AiProviderStep(onNext: _next, onBack: _back);
      case 10:
        return _MemoryStep(
          payload: _memoryPayload(),
          onNext: _next,
          onBack: _back,
        );
      case 11:
        return _DayOneStep(onNext: _next, onBack: _back);
      case 12:
        return _SmsStep(onNext: _next, onBack: _back);
      case 13:
        return _DoneStep(
          preferredName: _preferredName,
          onDone: _finishOnboarding,
        );
      default:
        _finishOnboarding();
        return const SizedBox.shrink();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: JournalColors.bgBase,
      body: Stack(
        children: [
          const Positioned.fill(child: _OnboardingBackdrop()),
          SafeArea(
            child: Column(
              children: [
                _ProgressDots(current: _step, total: _kStepLabels.length),
                Expanded(
                  child: SingleChildScrollView(
                    keyboardDismissBehavior:
                        ScrollViewKeyboardDismissBehavior.onDrag,
                    padding: const EdgeInsets.fromLTRB(20, 2, 20, 32),
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 560),
                        child: AnimatedSwitcher(
                          duration: const Duration(milliseconds: 280),
                          transitionBuilder: (child, anim) => FadeTransition(
                            opacity: anim,
                            child: SlideTransition(
                              position: Tween<Offset>(
                                begin: const Offset(0, 0.035),
                                end: Offset.zero,
                              ).animate(
                                CurvedAnimation(
                                  parent: anim,
                                  curve: Curves.easeOutCubic,
                                ),
                              ),
                              child: child,
                            ),
                          ),
                          child: KeyedSubtree(
                            key: ValueKey(_step),
                            child: _buildCurrentStep(),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _OnboardingBackdrop extends StatelessWidget {
  const _OnboardingBackdrop();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: RadialGradient(
          center: const Alignment(0.25, -0.65),
          radius: 1.25,
          colors: [
            _withAlpha(JournalColors.bgCardAlt, 0.82),
            JournalColors.bgBase,
          ],
        ),
      ),
      child: Stack(
        children: [
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    _withAlpha(JournalColors.accent, 0.10),
                    _withAlpha(JournalColors.bgBase, 0.0),
                    _withAlpha(JournalColors.info, 0.05),
                  ],
                  stops: const [0, 0.42, 1],
                ),
              ),
            ),
          ),
          Positioned.fill(
            child: CustomPaint(painter: _OnboardingGridPainter()),
          ),
        ],
      ),
    );
  }
}

class _OnboardingGridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = _withAlpha(JournalColors.borderBright, 0.14)
      ..strokeWidth = 0.7;
    const gap = 44.0;
    for (double y = 0; y < size.height; y += gap) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// ── Progress Dots ─────────────────────────────────────────────────────────────

class _ProgressDots extends StatelessWidget {
  const _ProgressDots({required this.current, required this.total});
  final int current;
  final int total;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 12),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
                decoration: BoxDecoration(
                  color: _withAlpha(JournalColors.bgCardAlt, 0.72),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: JournalColors.border),
                ),
                child: Text(
                  _kStepLabels[current].toUpperCase(),
                  style: const TextStyle(
                    color: JournalColors.textPrimary,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.1,
                  ),
                ),
              ),
              Text(
                '${current + 1}/$total',
                style: const TextStyle(
                  color: JournalColors.textMuted,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: (current + 1) / total,
              backgroundColor: _withAlpha(JournalColors.bgSurface, 0.84),
              valueColor:
                  const AlwaysStoppedAnimation<Color>(JournalColors.accent),
              minHeight: 4,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Shared helpers ────────────────────────────────────────────────────────────

class _NavRow extends StatelessWidget {
  const _NavRow({
    required this.onNext,
    this.onBack,
    this.nextLabel = 'Continue',
    this.loading = false,
  });
  final VoidCallback onNext;
  final VoidCallback? onBack;
  final String nextLabel;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 24),
      child: Row(
        children: [
          if (onBack != null) ...[
            GestureDetector(
              onTap: onBack,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                decoration: BoxDecoration(
                  color: _withAlpha(JournalColors.bgSurface, 0.78),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: JournalColors.border),
                ),
                child: const Text('Back',
                    style: TextStyle(
                        color: JournalColors.textSecondary, fontSize: 14)),
              ),
            ),
            const SizedBox(width: 10),
          ],
          Expanded(
            child: AdaptiveButton(
              style: AdaptiveButtonStyle.prominentGlass,
              onPressed: loading ? null : onNext,
              label: loading ? 'Working...' : nextLabel,
            ),
          ),
        ],
      ),
    );
  }
}

Widget _fieldLabel(String text) => Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(
        text.toUpperCase(),
        style: const TextStyle(
          color: JournalColors.textMuted,
          fontSize: 10,
          letterSpacing: 1.2,
          fontWeight: FontWeight.w600,
        ),
      ),
    );

BoxDecoration _fieldDeco({bool focused = false}) => BoxDecoration(
      color: _withAlpha(JournalColors.bgSurface, 0.82),
      borderRadius: BorderRadius.circular(14),
      border: Border.all(
        color: focused ? JournalColors.borderBright : JournalColors.border,
      ),
    );

Widget _errorBanner(String? msg) {
  if (msg == null || msg.isEmpty) return const SizedBox.shrink();
  return Container(
    margin: const EdgeInsets.only(bottom: 14),
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: _withAlpha(JournalColors.danger, 0.10),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: _withAlpha(JournalColors.danger, 0.30)),
    ),
    child: Text(
      msg,
      style: const TextStyle(color: JournalColors.danger, fontSize: 13),
    ),
  );
}

String _parseErr(dynamic e) {
  final str = e.toString();
  final m = RegExp(r'"detail"\s*:\s*"([^"]+)"').firstMatch(str);
  return m?.group(1) ?? 'Something went wrong.';
}

// ── Step 0 — Welcome ──────────────────────────────────────────────────────────

class _WelcomeStep extends StatelessWidget {
  const _WelcomeStep({required this.onNext});
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 18),
        Center(
          child: Container(
            width: 58,
            height: 58,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                colors: [
                  _withAlpha(JournalColors.accent, 0.30),
                  _withAlpha(JournalColors.info, 0.16),
                ],
              ),
              border: Border.all(color: JournalColors.borderBright),
              boxShadow: const [
                BoxShadow(
                  color: JournalColors.accentGlow,
                  blurRadius: 22,
                  offset: Offset(0, 12),
                ),
              ],
            ),
            child: const Icon(
              CupertinoIcons.lock_shield,
              color: JournalColors.textPrimary,
              size: 25,
            ),
          ),
        ),
        const SizedBox(height: 20),
        const Text(
          'Set up your private journal.',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: JournalColors.textPrimary,
            fontSize: 27,
            fontWeight: FontWeight.w800,
            height: 1.2,
          ),
        ),
        const SizedBox(height: 12),
        const Text(
          'A few short steps create your account, recovery options, and the context used for summaries and reflections.',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: JournalColors.textSecondary,
            fontSize: 14,
            height: 1.6,
          ),
        ),
        const SizedBox(height: 24),
        LayoutBuilder(
          builder: (context, constraints) {
            final compact = constraints.maxWidth < 430;
            final items = [
              (
                CupertinoIcons.time,
                'Timestamped record',
                'Entries stay searchable and dated.'
              ),
              (
                CupertinoIcons.waveform_path_ecg,
                'Pattern signals',
                'Summaries can highlight repeats.'
              ),
              (
                CupertinoIcons.folder,
                'Organized context',
                'People, topics, and goals are saved.'
              ),
              (
                CupertinoIcons.lock,
                'Private setup',
                'You control what gets added.'
              ),
            ];
            if (compact) {
              return Column(
                children: [
                  for (final item in items) ...[
                    _FeatureRow(
                      icon: item.$1,
                      text: item.$2,
                      detail: item.$3,
                    ),
                    const SizedBox(height: 10),
                  ],
                ],
              );
            }
            return Wrap(
              spacing: 10,
              runSpacing: 10,
              children: items
                  .map(
                    (item) => SizedBox(
                      width: (constraints.maxWidth - 10) / 2,
                      child: _FeatureRow(
                        icon: item.$1,
                        text: item.$2,
                        detail: item.$3,
                      ),
                    ),
                  )
                  .toList(),
            );
          },
        ),
        _NavRow(onNext: onNext, nextLabel: 'Begin Setup', onBack: null),
        const SizedBox(height: 12),
      ],
    );
  }
}

class _FeatureRow extends StatelessWidget {
  const _FeatureRow({
    required this.icon,
    required this.text,
    required this.detail,
  });
  final IconData icon;
  final String text;
  final String detail;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _withAlpha(JournalColors.bgSurface, 0.72),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: JournalColors.border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: _withAlpha(JournalColors.accent, 0.13),
              shape: BoxShape.circle,
              border: Border.all(color: JournalColors.borderBright),
            ),
            child: Icon(icon, color: JournalColors.accent, size: 17),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  text,
                  style: const TextStyle(
                    color: JournalColors.textPrimary,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  detail,
                  style: const TextStyle(
                    color: JournalColors.textMuted,
                    fontSize: 11,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Step 1 — Feature Tour (8 slides) ─────────────────────────────────────────

class _FSlide {
  const _FSlide({
    required this.icon,
    required this.accent,
    required this.title,
    required this.tagline,
    required this.desc,
    this.bullets = const [],
    this.tones = const [],
    this.who = const [],
  });
  final String icon;
  final Color accent;
  final String title;
  final String tagline;
  final String desc;
  final List<String> bullets;
  final List<_Tone> tones;
  final List<_Who> who;
}

class _Tone {
  const _Tone(
      {required this.emoji,
      required this.label,
      required this.color,
      required this.desc,
      this.nsfw = false});
  final String emoji, label, desc;
  final Color color;
  final bool nsfw;
}

class _Who {
  const _Who({required this.icon, required this.label, required this.desc});
  final String icon, label, desc;
}

const _kFeatureSlides = [
  _FSlide(
    icon: '⬡',
    accent: JournalColors.accent,
    title: 'Pattern Detection',
    tagline: 'Repeated themes and timing',
    desc:
        'Entries can be summarized for recurring emotional, behavioral, and situational patterns.',
    bullets: [
      'Escalation windows',
      'Weekly summaries',
      'Early-warning signals'
    ],
  ),
  _FSlide(
    icon: '⊕',
    accent: JournalColors.accent2,
    title: 'Evidence Vault',
    tagline: 'Records and attachments',
    desc:
        'Keep entries, files, and incident context together so they can be reviewed or exported later.',
    bullets: [
      'PDF exports',
      'Photo and document attachments',
      'Chronological records'
    ],
  ),
  _FSlide(
    icon: '⚡',
    accent: JournalColors.severity,
    title: 'Exit Plan',
    tagline: 'Step-by-step planning',
    desc:
        'If you need a structured plan, the app can organize safety, finances, housing, support, and next steps.',
    bullets: [
      'Personalized checklist',
      'Progress tracking',
      'Secure sharing option'
    ],
  ),
  _FSlide(
    icon: '〜',
    accent: JournalColors.success,
    title: 'Nervous System',
    tagline: 'Mood and severity trends',
    desc:
        'Mood and severity scores help show baselines, spikes, and recovery windows over time.',
    bullets: ['Trend charts', 'Stability scoring', 'Recovery patterns'],
  ),
  _FSlide(
    icon: '◈',
    accent: JournalColors.orange,
    title: 'People',
    tagline: 'Names and relationship context',
    desc:
        'People you identify during setup can be tracked across entries for impact and sentiment trends.',
    bullets: [
      'Per-person summaries',
      'Activity history',
      'Severity trend by person'
    ],
  ),
  _FSlide(
    icon: '◗',
    accent: JournalColors.info,
    title: 'Ask My Journal',
    tagline: 'Natural-language search',
    desc:
        'Ask questions about your entries and get answers grounded in matching journal history.',
    bullets: ['Semantic search', 'Synthesized answers', 'Entry references'],
  ),
  _FSlide(
    icon: '✦',
    accent: JournalColors.accent2,
    title: 'AI Reflections',
    tagline: 'Tone options for entries',
    desc:
        'Each entry can be reflected back in a tone you choose. You can change these preferences later.',
    tones: [
      _Tone(
          emoji: 'T',
          label: 'Therapist',
          color: JournalColors.accent2,
          desc: 'Warm, clinical insight with emotional themes'),
      _Tone(
          emoji: 'F',
          label: 'Best Friend',
          color: JournalColors.info,
          desc: 'Plainspoken support and perspective'),
      _Tone(
          emoji: 'C',
          label: 'Coach',
          color: JournalColors.success,
          desc: 'Action-oriented next steps'),
      _Tone(
          emoji: 'M',
          label: 'Mentor',
          color: JournalColors.severity,
          desc: 'Big-picture meaning and guidance'),
      _Tone(
          emoji: 'I',
          label: 'Inner Critic',
          color: JournalColors.danger,
          desc: 'Direct questions about avoidance and ownership'),
      _Tone(
          emoji: 'X',
          label: 'Chaos Agent',
          color: JournalColors.orange,
          desc: 'Unfiltered language and stronger opinions',
          nsfw: true),
    ],
  ),
  _FSlide(
    icon: '◬',
    accent: JournalColors.success,
    title: 'Detective Mode',
    tagline: 'Structured documentation',
    desc:
        'A focused workspace for situations where incident logs, files, timelines, and reports need to stay organized.',
    bullets: [
      'Investigation log with severity tags: Critical, High, Medium, Low',
      'Photo & document upload with AI vision analysis on every file',
      'Case workspace uses relevant journal and case-file context',
      'Briefings summarize patterns, contradictions, and next steps',
      'Case brief can be refreshed as the record changes',
      'Briefing history keeps prior sessions available',
      'Gallery view with lightbox and per-photo AI analysis panel',
      'Exportable case report',
    ],
    who: [
      _Who(
          icon: 'L',
          label: 'Legal disputes',
          desc: 'Records for review with counsel or court support'),
      _Who(
          icon: 'C',
          label: 'Custody',
          desc: 'Incidents, patterns, and supporting context'),
      _Who(
          icon: 'W',
          label: 'Workplace',
          desc: 'HR complaints, events, and timelines'),
      _Who(
          icon: 'S',
          label: 'Safety',
          desc: 'Private records for serious situations'),
    ],
  ),
];

class _FeatureTourStep extends StatefulWidget {
  const _FeatureTourStep({required this.onNext, required this.onBack});
  final VoidCallback onNext;
  final VoidCallback onBack;

  @override
  State<_FeatureTourStep> createState() => _FeatureTourStepState();
}

class _FeatureTourStepState extends State<_FeatureTourStep> {
  int _idx = 0;

  @override
  Widget build(BuildContext context) {
    final f = _kFeatureSlides[_idx];
    final total = _kFeatureSlides.length;
    final isLast = _idx == total - 1;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 16),

        // Header
        Text(
          'FEATURE ${_idx + 1} OF $total',
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: JournalColors.textMuted,
            fontSize: 10,
            letterSpacing: 1.4,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 6),
        const Text(
          'What the app can organize',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: JournalColors.textPrimary,
            fontSize: 18,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 16),

        // Slide card
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 220),
          child: KeyedSubtree(
            key: ValueKey(_idx),
            child: GlassCard(
              accentBorder: true,
              padding: EdgeInsets.zero,
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(20),
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      _withAlpha(JournalColors.bgCard, 0.96),
                      _withAlpha(JournalColors.bgCardAlt, 0.90),
                    ],
                  ),
                ),
                padding: const EdgeInsets.all(18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Icon + title row
                    Row(
                      children: [
                        Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            color: _withAlpha(f.accent, 0.12),
                            borderRadius: BorderRadius.circular(12),
                            border:
                                Border.all(color: _withAlpha(f.accent, 0.3)),
                          ),
                          child: Center(
                            child: Text(f.icon,
                                style:
                                    TextStyle(color: f.accent, fontSize: 20)),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(f.title,
                                  style: const TextStyle(
                                    color: JournalColors.textPrimary,
                                    fontSize: 15,
                                    fontWeight: FontWeight.w800,
                                    height: 1.2,
                                  )),
                              const SizedBox(height: 2),
                              Text(f.tagline,
                                  style:
                                      TextStyle(color: f.accent, fontSize: 11)),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),

                    // Description
                    Text(f.desc,
                        style: const TextStyle(
                            color: JournalColors.textSecondary,
                            fontSize: 12,
                            height: 1.65)),

                    // Bullets
                    if (f.bullets.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      for (final b in f.bullets) ...[
                        const SizedBox(height: 5),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              width: 5,
                              height: 5,
                              margin: const EdgeInsets.only(top: 5),
                              decoration: BoxDecoration(
                                  color: f.accent, shape: BoxShape.circle),
                            ),
                            const SizedBox(width: 9),
                            Expanded(
                              child: Text(b,
                                  style: const TextStyle(
                                      color: JournalColors.textSecondary,
                                      fontSize: 11,
                                      height: 1.5)),
                            ),
                          ],
                        ),
                      ],
                    ],

                    // "Who this is for" grid (Detective Mode)
                    if (f.who.isNotEmpty) ...[
                      const SizedBox(height: 14),
                      const Text('WHO THIS IS FOR',
                          style: TextStyle(
                            color: JournalColors.textMuted,
                            fontSize: 9,
                            letterSpacing: 1.2,
                            fontWeight: FontWeight.w700,
                          )),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                              child: _WhoCard(w: f.who[0], accent: f.accent)),
                          const SizedBox(width: 7),
                          Expanded(
                              child: _WhoCard(w: f.who[1], accent: f.accent)),
                        ],
                      ),
                      const SizedBox(height: 7),
                      Row(
                        children: [
                          Expanded(
                              child: _WhoCard(w: f.who[2], accent: f.accent)),
                          const SizedBox(width: 7),
                          Expanded(
                              child: _WhoCard(w: f.who[3], accent: f.accent)),
                        ],
                      ),
                    ],

                    // Tones (AI Reflections)
                    if (f.tones.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      for (final t in f.tones) ...[
                        const SizedBox(height: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 8),
                          decoration: BoxDecoration(
                            color: JournalColors.bgBase,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: JournalColors.border),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(t.emoji,
                                  style: const TextStyle(fontSize: 14)),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Text(t.label,
                                            style: TextStyle(
                                                color: t.color,
                                                fontSize: 12,
                                                fontWeight: FontWeight.w700)),
                                        if (t.nsfw) ...[
                                          const SizedBox(width: 6),
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                                horizontal: 5, vertical: 1),
                                            decoration: BoxDecoration(
                                              border: Border.all(
                                                  color: _withAlpha(
                                                      JournalColors.orange,
                                                      0.4)),
                                              borderRadius:
                                                  BorderRadius.circular(4),
                                            ),
                                            child: const Text('18+',
                                                style: TextStyle(
                                                    color: JournalColors.orange,
                                                    fontSize: 9,
                                                    letterSpacing: 0.8)),
                                          ),
                                        ],
                                      ],
                                    ),
                                    const SizedBox(height: 2),
                                    Text(t.desc,
                                        style: const TextStyle(
                                            color: JournalColors.textSecondary,
                                            fontSize: 11,
                                            height: 1.45)),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                      // Chaos Agent warning
                      const SizedBox(height: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 8),
                        decoration: BoxDecoration(
                          color: _withAlpha(JournalColors.orange, 0.06),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                              color: _withAlpha(JournalColors.orange, 0.24)),
                        ),
                        child: const Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(
                              CupertinoIcons.exclamationmark_triangle,
                              color: JournalColors.orange,
                              size: 14,
                            ),
                            SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Chaos Agent uses stronger language. Opt in from Settings when you want it.',
                                style: TextStyle(
                                    color: JournalColors.textSecondary,
                                    fontSize: 11,
                                    height: 1.5),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),

        const SizedBox(height: 16),

        // Dot indicators
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(total, (i) {
            final active = i == _idx;
            return GestureDetector(
              onTap: () => setState(() => _idx = i),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 220),
                width: active ? 18 : 6,
                height: 6,
                margin: const EdgeInsets.symmetric(horizontal: 3),
                decoration: BoxDecoration(
                  color: active ? f.accent : JournalColors.border,
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
            );
          }),
        ),

        const SizedBox(height: 16),

        // Nav row
        Row(
          children: [
            GestureDetector(
              onTap: _idx > 0 ? () => setState(() => _idx--) : widget.onBack,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                decoration: BoxDecoration(
                  color: JournalColors.bgSurface,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: JournalColors.border),
                ),
                child: Text(
                  _idx > 0 ? '← Prev' : '← Back',
                  style: const TextStyle(
                      color: JournalColors.textSecondary, fontSize: 13),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: GestureDetector(
                onTap: isLast ? widget.onNext : () => setState(() => _idx++),
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: isLast
                          ? [JournalColors.accent, JournalColors.accent2]
                          : [f.accent, _withAlpha(f.accent, 0.75)],
                      begin: Alignment.centerLeft,
                      end: Alignment.centerRight,
                    ),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Text(
                    isLast ? 'Continue Setup' : 'Next Feature',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        color: JournalColors.textPrimary,
                        fontSize: 13,
                        fontWeight: FontWeight.w700),
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
      ],
    );
  }
}

class _WhoCard extends StatelessWidget {
  const _WhoCard({required this.w, required this.accent});
  final _Who w;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(9),
      decoration: BoxDecoration(
        color: accent.withOpacity(0.04),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: accent.withOpacity(0.15)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(w.icon, style: const TextStyle(fontSize: 13)),
          const SizedBox(width: 7),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(w.label,
                    style: const TextStyle(
                        color: JournalColors.textPrimary,
                        fontSize: 10,
                        fontWeight: FontWeight.w700)),
                const SizedBox(height: 2),
                Text(w.desc,
                    style: const TextStyle(
                        color: JournalColors.textMuted,
                        fontSize: 9,
                        height: 1.4)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Step 2 — About You ────────────────────────────────────────────────────────

class _AboutStep extends StatefulWidget {
  const _AboutStep({
    required this.preferredName,
    required this.pronouns,
    required this.onChanged,
    required this.onNext,
    required this.onBack,
  });
  final String preferredName;
  final String pronouns;
  final void Function(String name, String pronouns) onChanged;
  final VoidCallback onNext;
  final VoidCallback onBack;

  @override
  State<_AboutStep> createState() => _AboutStepState();
}

class _AboutStepState extends State<_AboutStep> {
  late final TextEditingController _nameCtrl;
  String _pronouns = '';

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(text: widget.preferredName);
    _pronouns = widget.pronouns;
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 24),
        const Text('About you',
            style: TextStyle(
                color: JournalColors.textPrimary,
                fontSize: 22,
                fontWeight: FontWeight.w800)),
        const SizedBox(height: 6),
        const Text(
            'Used only to address you correctly in reflections. Both fields are optional.',
            style: TextStyle(
                color: JournalColors.textSecondary, fontSize: 13, height: 1.5)),
        const SizedBox(height: 24),
        _fieldLabel('Preferred Name'),
        CupertinoTextField(
          controller: _nameCtrl,
          placeholder: 'What should we call you?',
          placeholderStyle: const TextStyle(color: JournalColors.textMuted),
          style: const TextStyle(color: JournalColors.textPrimary),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: _fieldDeco(),
          textInputAction: TextInputAction.done,
          onChanged: (_) => widget.onChanged(_nameCtrl.text, _pronouns),
        ),
        const SizedBox(height: 20),
        _fieldLabel('Pronouns'),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: _kPronounOpts.map((p) {
            final on = _pronouns == p;
            return GestureDetector(
              onTap: () {
                setState(() => _pronouns = on ? '' : p);
                widget.onChanged(_nameCtrl.text, _pronouns);
              },
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: on
                      ? JournalColors.accent.withOpacity(0.15)
                      : JournalColors.bgSurface,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: on ? JournalColors.accent : JournalColors.border,
                  ),
                ),
                child: Text(p,
                    style: TextStyle(
                      color: on
                          ? JournalColors.accent
                          : JournalColors.textSecondary,
                      fontSize: 13,
                      fontWeight: on ? FontWeight.w600 : FontWeight.w400,
                    )),
              ),
            );
          }).toList(),
        ),
        _NavRow(onNext: onNext, onBack: onBack),
      ],
    );
  }

  VoidCallback get onNext => () {
        widget.onChanged(_nameCtrl.text, _pronouns);
        widget.onNext();
      };

  VoidCallback get onBack => widget.onBack;
}

// ── Step 3 — Situation ────────────────────────────────────────────────────────

class _SituationStep extends StatefulWidget {
  const _SituationStep({
    required this.situationType,
    required this.situationStory,
    required this.onChanged,
    required this.onNext,
    required this.onBack,
  });
  final String situationType;
  final String situationStory;
  final void Function(String type, String story) onChanged;
  final VoidCallback onNext;
  final VoidCallback onBack;

  @override
  State<_SituationStep> createState() => _SituationStepState();
}

class _SituationStepState extends State<_SituationStep> {
  late String _type;
  late final TextEditingController _storyCtrl;

  @override
  void initState() {
    super.initState();
    _type = widget.situationType;
    _storyCtrl = TextEditingController(text: widget.situationStory);
  }

  @override
  void dispose() {
    _storyCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 24),
        const Text("What brings you here?",
            style: TextStyle(
                color: JournalColors.textPrimary,
                fontSize: 22,
                fontWeight: FontWeight.w800)),
        const SizedBox(height: 6),
        const Text('Pick the closest match. You can update this later.',
            style: TextStyle(
                color: JournalColors.textSecondary, fontSize: 13, height: 1.5)),
        const SizedBox(height: 20),

        // Situation grid
        ...List.generate(_kSituationOpts.length ~/ 2, (row) {
          final a = _kSituationOpts[row * 2];
          final b = _kSituationOpts[row * 2 + 1];
          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              children: [
                Expanded(
                    child: _SituationCard(
                        opt: a,
                        selected: _type == a.$1,
                        onTap: () =>
                            setState(() => _type = _type == a.$1 ? '' : a.$1))),
                const SizedBox(width: 8),
                Expanded(
                    child: _SituationCard(
                        opt: b,
                        selected: _type == b.$1,
                        onTap: () =>
                            setState(() => _type = _type == b.$1 ? '' : b.$1))),
              ],
            ),
          );
        }),

        const SizedBox(height: 20),
        _fieldLabel('Your situation in your own words (optional)'),
        CupertinoTextField(
          controller: _storyCtrl,
          placeholder: 'Briefly describe the situation in your own words.',
          placeholderStyle:
              const TextStyle(color: JournalColors.textMuted, fontSize: 13),
          style:
              const TextStyle(color: JournalColors.textPrimary, fontSize: 14),
          padding: const EdgeInsets.all(14),
          decoration: _fieldDeco(),
          maxLines: 4,
          minLines: 3,
          keyboardType: TextInputType.multiline,
          textInputAction: TextInputAction.newline,
        ),
        _NavRow(
          onNext: () {
            widget.onChanged(_type, _storyCtrl.text);
            widget.onNext();
          },
          onBack: widget.onBack,
        ),
      ],
    );
  }
}

class _SituationCard extends StatelessWidget {
  const _SituationCard(
      {required this.opt, required this.selected, required this.onTap});
  final (String, String, String, String) opt;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: selected
              ? JournalColors.accent.withOpacity(0.12)
              : JournalColors.bgSurface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected ? JournalColors.accent : JournalColors.border,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(opt.$2,
                style: TextStyle(
                  color:
                      selected ? JournalColors.accent : JournalColors.textMuted,
                  fontSize: 16,
                )),
            const SizedBox(height: 4),
            Text(opt.$3,
                style: TextStyle(
                  color: selected
                      ? JournalColors.accent
                      : JournalColors.textPrimary,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                )),
            const SizedBox(height: 2),
            Text(opt.$4,
                style: const TextStyle(
                  color: JournalColors.textMuted,
                  fontSize: 10,
                  height: 1.4,
                )),
          ],
        ),
      ),
    );
  }
}

// ── Step 4 — People ───────────────────────────────────────────────────────────

class _PeopleStep extends StatefulWidget {
  const _PeopleStep({
    required this.people,
    required this.onChanged,
    required this.onNext,
    required this.onBack,
  });
  final List<Map<String, String>> people;
  final void Function(List<Map<String, String>>) onChanged;
  final VoidCallback onNext;
  final VoidCallback onBack;

  @override
  State<_PeopleStep> createState() => _PeopleStepState();
}

class _PeopleStepState extends State<_PeopleStep> {
  late List<Map<String, String>> _people;
  final _nameCtrl = TextEditingController();
  final _roleCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _people = List.from(widget.people);
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _roleCtrl.dispose();
    super.dispose();
  }

  void _add() {
    final name = _nameCtrl.text.trim();
    final role = _roleCtrl.text.trim();
    if (name.isEmpty) return;
    setState(() {
      _people.add({'name': name, 'role': role.isNotEmpty ? role : 'person'});
      _nameCtrl.clear();
      _roleCtrl.clear();
    });
    widget.onChanged(_people);
  }

  void _remove(int i) {
    setState(() => _people.removeAt(i));
    widget.onChanged(_people);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 24),
        const Text('Key people',
            style: TextStyle(
                color: JournalColors.textPrimary,
                fontSize: 22,
                fontWeight: FontWeight.w800)),
        const SizedBox(height: 6),
        const Text(
            'Add names or aliases you want grouped across entries. You can add more later.',
            style: TextStyle(
                color: JournalColors.textSecondary, fontSize: 13, height: 1.5)),
        const SizedBox(height: 20),
        Row(
          children: [
            Expanded(
              flex: 2,
              child: CupertinoTextField(
                controller: _nameCtrl,
                placeholder: 'Name',
                placeholderStyle:
                    const TextStyle(color: JournalColors.textMuted),
                style: const TextStyle(color: JournalColors.textPrimary),
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: _fieldDeco(),
                textInputAction: TextInputAction.next,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              flex: 2,
              child: CupertinoTextField(
                controller: _roleCtrl,
                placeholder: 'Role (e.g. partner)',
                placeholderStyle: const TextStyle(
                    color: JournalColors.textMuted, fontSize: 12),
                style: const TextStyle(color: JournalColors.textPrimary),
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: _fieldDeco(),
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => _add(),
              ),
            ),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: _add,
              child: Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: JournalColors.accent.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(12),
                  border:
                      Border.all(color: JournalColors.accent.withOpacity(0.4)),
                ),
                child: const Icon(CupertinoIcons.add,
                    color: JournalColors.accent, size: 20),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        for (int i = 0; i < _people.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: JournalColors.bgSurface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: JournalColors.border),
              ),
              child: Row(
                children: [
                  const Text('◈',
                      style:
                          TextStyle(color: JournalColors.accent, fontSize: 14)),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text('${_people[i]['name']} · ${_people[i]['role']}',
                        style: const TextStyle(
                            color: JournalColors.textPrimary, fontSize: 13)),
                  ),
                  GestureDetector(
                    onTap: () => _remove(i),
                    child: const Icon(CupertinoIcons.xmark,
                        color: JournalColors.textMuted, size: 16),
                  ),
                ],
              ),
            ),
          ),
        _NavRow(
          onNext: widget.onNext,
          onBack: widget.onBack,
          nextLabel: _people.isEmpty ? 'Skip' : 'Continue',
        ),
      ],
    );
  }
}

// ── Step 5 — Topics ───────────────────────────────────────────────────────────

class _TopicsStep extends StatefulWidget {
  const _TopicsStep({
    required this.topics,
    required this.onChanged,
    required this.onNext,
    required this.onBack,
  });
  final List<String> topics;
  final void Function(List<String>) onChanged;
  final VoidCallback onNext;
  final VoidCallback onBack;

  @override
  State<_TopicsStep> createState() => _TopicsStepState();
}

class _TopicsStepState extends State<_TopicsStep> {
  late List<String> _topics;

  @override
  void initState() {
    super.initState();
    _topics = List.from(widget.topics);
  }

  void _toggle(String t) {
    setState(() {
      if (_topics.contains(t))
        _topics.remove(t);
      else
        _topics.add(t);
    });
    widget.onChanged(_topics);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 24),
        const Text('Topics',
            style: TextStyle(
                color: JournalColors.textPrimary,
                fontSize: 22,
                fontWeight: FontWeight.w800)),
        const SizedBox(height: 6),
        const Text('Choose themes you want reflected in summaries and search.',
            style: TextStyle(
                color: JournalColors.textSecondary, fontSize: 13, height: 1.5)),
        const SizedBox(height: 20),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: _kTopicOpts.map((t) {
            final on = _topics.contains(t);
            return GestureDetector(
              onTap: () => _toggle(t),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                decoration: BoxDecoration(
                  color: on
                      ? JournalColors.accent.withOpacity(0.15)
                      : JournalColors.bgSurface,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: on ? JournalColors.accent : JournalColors.border,
                  ),
                ),
                child: Text(t,
                    style: TextStyle(
                      color: on
                          ? JournalColors.accent
                          : JournalColors.textSecondary,
                      fontSize: 13,
                      fontWeight: on ? FontWeight.w600 : FontWeight.w400,
                    )),
              ),
            );
          }).toList(),
        ),
        _NavRow(
          onNext: widget.onNext,
          onBack: widget.onBack,
          nextLabel: _topics.isEmpty ? 'Skip' : 'Continue',
        ),
      ],
    );
  }
}

// ── Step 6 — Goals ────────────────────────────────────────────────────────────

class _GoalsStep extends StatefulWidget {
  const _GoalsStep({
    required this.goals,
    required this.onChanged,
    required this.onNext,
    required this.onBack,
  });
  final List<String> goals;
  final void Function(List<String>) onChanged;
  final VoidCallback onNext;
  final VoidCallback onBack;

  @override
  State<_GoalsStep> createState() => _GoalsStepState();
}

class _GoalsStepState extends State<_GoalsStep> {
  late List<String> _goals;

  @override
  void initState() {
    super.initState();
    _goals = List.from(widget.goals);
  }

  void _toggle(String id) {
    setState(() {
      if (_goals.contains(id))
        _goals.remove(id);
      else
        _goals.add(id);
    });
    widget.onChanged(_goals);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 24),
        const Text('Goals',
            style: TextStyle(
                color: JournalColors.textPrimary,
                fontSize: 22,
                fontWeight: FontWeight.w800)),
        const SizedBox(height: 6),
        const Text('Select anything useful. These can be changed later.',
            style: TextStyle(
                color: JournalColors.textSecondary, fontSize: 13, height: 1.5)),
        const SizedBox(height: 20),
        for (final g in _kGoalOpts) ...[
          GestureDetector(
            onTap: () => _toggle(g.$1),
            child: Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: _goals.contains(g.$1)
                    ? JournalColors.accent.withOpacity(0.12)
                    : JournalColors.bgSurface,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: _goals.contains(g.$1)
                      ? JournalColors.accent
                      : JournalColors.border,
                ),
              ),
              child: Row(
                children: [
                  Text(g.$2,
                      style: TextStyle(
                        color: _goals.contains(g.$1)
                            ? JournalColors.accent
                            : JournalColors.textMuted,
                        fontSize: 18,
                      )),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(g.$3,
                            style: TextStyle(
                              color: _goals.contains(g.$1)
                                  ? JournalColors.accent
                                  : JournalColors.textPrimary,
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                            )),
                        const SizedBox(height: 2),
                        Text(g.$4,
                            style: const TextStyle(
                              color: JournalColors.textMuted,
                              fontSize: 11,
                              height: 1.4,
                            )),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
        _NavRow(
          onNext: widget.onNext,
          onBack: widget.onBack,
          nextLabel: _goals.isEmpty ? 'Skip' : 'Continue',
        ),
      ],
    );
  }
}

// ── Step 7 — Account ──────────────────────────────────────────────────────────

class _AccountStep extends StatefulWidget {
  const _AccountStep({required this.onSuccess, required this.onBack});
  final void Function(String username, String email, String password,
      Map<String, dynamic> user, String? apiKey) onSuccess;
  final VoidCallback onBack;

  @override
  State<_AccountStep> createState() => _AccountStepState();
}

class _AccountStepState extends State<_AccountStep> {
  final _api = ApiService();
  final _userCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();

  bool _obscure = true;
  bool _loading = false;
  String? _err;
  String? _apiKey; // shown once after registration
  Map<String, dynamic> _user = {};

  int _passwordStrength(String pw) {
    int score = 0;
    if (pw.length >= 12) score++;
    if (pw.contains(RegExp(r'[A-Z]'))) score++;
    if (pw.contains(RegExp(r'[0-9]'))) score++;
    if (pw.contains(RegExp(r'[^a-zA-Z0-9]'))) score++;
    if (pw.length >= 20) score++;
    return score;
  }

  String _strengthLabel(int s) =>
      ['', 'Weak', 'Fair', 'Good', 'Strong', 'Very Strong'][s.clamp(0, 5)];
  Color _strengthColor(int s) => [
        Colors.transparent,
        Colors.red,
        Colors.orange,
        Colors.yellow,
        const Color(0xFF10b981),
        JournalColors.accent,
      ][s.clamp(0, 5)];

  String? _validate() {
    if (_userCtrl.text.trim().length < 3)
      return 'Username must be at least 3 characters';
    if (!_emailCtrl.text.contains('@')) return 'Valid email required';
    final pw = _passCtrl.text;
    if (pw.length < 12) return 'Password must be at least 12 characters';
    if (!pw.contains(RegExp(r'[A-Z]')))
      return 'Password needs an uppercase letter';
    if (!pw.contains(RegExp(r'[0-9]'))) return 'Password needs a number';
    if (!pw.contains(RegExp(r'[^a-zA-Z0-9]'))) return 'Password needs a symbol';
    if (pw != _confirmCtrl.text) return 'Passwords do not match';
    return null;
  }

  Future<void> _submit() async {
    final err = _validate();
    if (err != null) {
      setState(() => _err = err);
      return;
    }

    setState(() {
      _loading = true;
      _err = null;
    });

    try {
      final regData = await _api.register(
        _userCtrl.text.trim(),
        _emailCtrl.text.trim(),
        _passCtrl.text,
      );
      final apiKey = regData['api_key'] as String?;

      // Now login to get token (without transitioning to HomeShell)
      final loginData = await _api.login(_userCtrl.text.trim(), _passCtrl.text);
      _api.setAccessToken(loginData['access_token'] as String);
      final user = await _api.getMe();
      await _api.clearInviteAccessToken();

      if (!mounted) return;
      setState(() {
        _loading = false;
        _apiKey = apiKey;
        _user = user;
      });

      if (apiKey == null) {
        // No API key to show → continue immediately
        widget.onSuccess(_userCtrl.text.trim(), _emailCtrl.text.trim(),
            _passCtrl.text, user, null);
      }
      // else: show API key first, user taps "Continue" which calls onSuccess
    } catch (e) {
      if (!mounted) return;
      final detail = _parseErr(e);
      // If user already exists, try logging in (graceful fallback)
      final alreadyExists = detail.toLowerCase().contains('already') ||
          detail.toLowerCase().contains('taken') ||
          detail.toLowerCase().contains('exists');
      if (alreadyExists) {
        try {
          final loginData =
              await _api.login(_userCtrl.text.trim(), _passCtrl.text);
          _api.setAccessToken(loginData['access_token'] as String);
          final user = await _api.getMe();
          await _api.clearInviteAccessToken();
          if (!mounted) return;
          setState(() {
            _loading = false;
            _user = user;
          });
          widget.onSuccess(_userCtrl.text.trim(), _emailCtrl.text.trim(),
              _passCtrl.text, user, null);
          return;
        } catch (_) {}
      }
      setState(() {
        _loading = false;
        _err = detail;
      });
    }
  }

  @override
  void dispose() {
    _userCtrl.dispose();
    _emailCtrl.dispose();
    _passCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // API key "show once" state
    if (_apiKey != null) {
      return _ApiKeyReveal(
        apiKey: _apiKey!,
        user: _user,
        onContinue: () {
          widget.onSuccess(
            _userCtrl.text.trim(),
            _emailCtrl.text.trim(),
            _passCtrl.text,
            _user,
            _apiKey,
          );
        },
      );
    }

    final pw = _passCtrl.text;
    final strength = _passwordStrength(pw);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 24),
        const Text('Secure your account',
            style: TextStyle(
                color: JournalColors.textPrimary,
                fontSize: 22,
                fontWeight: FontWeight.w800)),
        const SizedBox(height: 6),
        const Text(
            'Passwords stored as bcrypt hashes. Plain text is never kept or logged.',
            style: TextStyle(
                color: JournalColors.textSecondary, fontSize: 13, height: 1.5)),
        const SizedBox(height: 20),
        _errorBanner(_err),
        _fieldLabel('Username'),
        CupertinoTextField(
          controller: _userCtrl,
          placeholder: 'yourname',
          placeholderStyle: const TextStyle(color: JournalColors.textMuted),
          style: const TextStyle(color: JournalColors.textPrimary),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: _fieldDeco(),
          autocorrect: false,
          textInputAction: TextInputAction.next,
        ),
        const SizedBox(height: 14),
        _fieldLabel('Email'),
        CupertinoTextField(
          controller: _emailCtrl,
          placeholder: 'you@email.com',
          placeholderStyle: const TextStyle(color: JournalColors.textMuted),
          style: const TextStyle(color: JournalColors.textPrimary),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: _fieldDeco(),
          keyboardType: TextInputType.emailAddress,
          autocorrect: false,
          textInputAction: TextInputAction.next,
        ),
        const SizedBox(height: 14),
        _fieldLabel('Password'),
        CupertinoTextField(
          controller: _passCtrl,
          placeholder: 'Min 12 chars, upper, number, symbol',
          placeholderStyle:
              const TextStyle(color: JournalColors.textMuted, fontSize: 12),
          style: const TextStyle(color: JournalColors.textPrimary),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: _fieldDeco(),
          obscureText: _obscure,
          textInputAction: TextInputAction.next,
          suffix: GestureDetector(
            onTap: () => setState(() => _obscure = !_obscure),
            child: Padding(
              padding: const EdgeInsets.only(right: 14),
              child: Icon(
                _obscure ? CupertinoIcons.eye : CupertinoIcons.eye_slash,
                color: JournalColors.textMuted,
                size: 18,
              ),
            ),
          ),
          onChanged: (_) => setState(() {}),
        ),
        if (pw.isNotEmpty) ...[
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(2),
                  child: LinearProgressIndicator(
                    value: strength / 5,
                    backgroundColor: JournalColors.border,
                    valueColor:
                        AlwaysStoppedAnimation<Color>(_strengthColor(strength)),
                    minHeight: 3,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Text(_strengthLabel(strength),
                  style:
                      TextStyle(color: _strengthColor(strength), fontSize: 11)),
            ],
          ),
        ],
        const SizedBox(height: 14),
        _fieldLabel('Confirm Password'),
        CupertinoTextField(
          controller: _confirmCtrl,
          placeholder: 'Repeat your password',
          placeholderStyle: const TextStyle(color: JournalColors.textMuted),
          style: const TextStyle(color: JournalColors.textPrimary),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: _fieldDeco(),
          obscureText: true,
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => _submit(),
        ),
        _NavRow(
          onNext: _submit,
          onBack: widget.onBack,
          nextLabel: 'Create Account',
          loading: _loading,
        ),
      ],
    );
  }
}

class _ApiKeyReveal extends StatefulWidget {
  const _ApiKeyReveal(
      {required this.apiKey, required this.user, required this.onContinue});
  final String apiKey;
  final Map<String, dynamic> user;
  final VoidCallback onContinue;

  @override
  State<_ApiKeyReveal> createState() => _ApiKeyRevealState();
}

class _ApiKeyRevealState extends State<_ApiKeyReveal> {
  bool _copied = false;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 24),
        const Text('⊞',
            textAlign: TextAlign.center,
            style: TextStyle(color: JournalColors.accent, fontSize: 36)),
        const SizedBox(height: 16),
        const Text('Account created!',
            textAlign: TextAlign.center,
            style: TextStyle(
                color: JournalColors.textPrimary,
                fontSize: 22,
                fontWeight: FontWeight.w800)),
        const SizedBox(height: 10),
        const Text(
          'Your API key is shown once — copy it now and paste it into your iPhone Shortcut. You can regenerate it later in Settings.',
          textAlign: TextAlign.center,
          style: TextStyle(
              color: JournalColors.textSecondary, fontSize: 13, height: 1.6),
        ),
        const SizedBox(height: 20),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: JournalColors.bgSurface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: JournalColors.accent.withOpacity(0.3)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('⚠ COPY NOW — WON\'T BE SHOWN AGAIN',
                  style: TextStyle(
                    color: Color(0xFFf59e0b),
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.2,
                  )),
              const SizedBox(height: 10),
              SelectableText(
                widget.apiKey,
                style: const TextStyle(
                  color: Color(0xFFa5b4fc),
                  fontSize: 12,
                  fontFamily: 'monospace',
                  height: 1.6,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        GestureDetector(
          onTap: () async {
            // Copy to clipboard
            setState(() => _copied = true);
            Future.delayed(const Duration(seconds: 3), () {
              if (mounted) setState(() => _copied = false);
            });
          },
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 12),
            decoration: BoxDecoration(
              color: _copied
                  ? const Color(0xFF10b981).withOpacity(0.1)
                  : JournalColors.accent.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: _copied
                    ? const Color(0xFF10b981).withOpacity(0.4)
                    : JournalColors.accent.withOpacity(0.3),
              ),
            ),
            child: Text(
              _copied ? '✓ Copied!' : '⊕ Copy API Key',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: _copied
                    ? const Color(0xFF10b981)
                    : JournalColors.textPrimary,
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
        const SizedBox(height: 14),
        AdaptiveButton(
          style: AdaptiveButtonStyle.prominentGlass,
          onPressed: widget.onContinue,
          label: 'Continue',
        ),
      ],
    );
  }
}

// ── Step 8 — Security Questions ───────────────────────────────────────────────

class _SecurityQuestionsStep extends StatefulWidget {
  const _SecurityQuestionsStep({required this.onNext, required this.onBack});
  final VoidCallback onNext;
  final VoidCallback onBack;

  @override
  State<_SecurityQuestionsStep> createState() => _SecurityQuestionsStepState();
}

class _SecurityQuestionsStepState extends State<_SecurityQuestionsStep> {
  final _api = ApiService();

  String _q1 = _kSecurityQuestionsBank[0];
  String _q2 = _kSecurityQuestionsBank[1];
  String _q3 = _kSecurityQuestionsBank[2];
  final _a1 = TextEditingController();
  final _a2 = TextEditingController();
  final _a3 = TextEditingController();

  bool _saving = false;
  String? _err;

  @override
  void dispose() {
    _a1.dispose();
    _a2.dispose();
    _a3.dispose();
    super.dispose();
  }

  void _pickQuestion(int idx, String current) {
    final others = idx == 0
        ? [_q2, _q3]
        : idx == 1
            ? [_q1, _q3]
            : [_q1, _q2];
    final opts = _kSecurityQuestionsBank
        .where((q) => q == current || !others.contains(q))
        .toList();

    showCupertinoModalPopup<String>(
      context: context,
      builder: (_) => Container(
        color: JournalColors.bgCard,
        height: 300,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: const Text('Cancel',
                        style: TextStyle(
                            color: JournalColors.textSecondary, fontSize: 15)),
                  ),
                  const Text('Pick a question',
                      style: TextStyle(
                          color: JournalColors.textPrimary,
                          fontSize: 15,
                          fontWeight: FontWeight.w600)),
                  GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: const Text('Done',
                        style: TextStyle(
                            color: JournalColors.accent,
                            fontSize: 15,
                            fontWeight: FontWeight.w600)),
                  ),
                ],
              ),
            ),
            Expanded(
              child: CupertinoPicker(
                itemExtent: 44,
                scrollController: FixedExtentScrollController(
                  initialItem: opts.indexOf(current).clamp(0, opts.length - 1),
                ),
                onSelectedItemChanged: (i) {
                  setState(() {
                    if (idx == 0)
                      _q1 = opts[i];
                    else if (idx == 1)
                      _q2 = opts[i];
                    else
                      _q3 = opts[i];
                  });
                },
                children: opts
                    .map((q) => Center(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            child: Text(q,
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                    color: JournalColors.textPrimary,
                                    fontSize: 13)),
                          ),
                        ))
                    .toList(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _save() async {
    if (_a1.text.trim().isEmpty ||
        _a2.text.trim().isEmpty ||
        _a3.text.trim().isEmpty) {
      setState(() => _err = 'Please answer all three questions.');
      return;
    }
    if ({_q1, _q2, _q3}.length < 3) {
      setState(() => _err = 'Please choose three different questions.');
      return;
    }
    setState(() {
      _saving = true;
      _err = null;
    });
    try {
      await _api.setupSecurityQuestions(
        q1: _q1,
        a1: _a1.text.trim(),
        q2: _q2,
        a2: _a2.text.trim(),
        q3: _q3,
        a3: _a3.text.trim(),
      );
      if (mounted) widget.onNext();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _err = _parseErr(e);
      });
    }
  }

  Widget _questionBlock(int idx, String q, TextEditingController ctrl) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        GestureDetector(
          onTap: () => _pickQuestion(idx, q),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: JournalColors.bgSurface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: JournalColors.border),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(q,
                      style: const TextStyle(
                          color: JournalColors.textSecondary,
                          fontSize: 12,
                          height: 1.4)),
                ),
                const Icon(CupertinoIcons.chevron_down,
                    color: JournalColors.textMuted, size: 14),
              ],
            ),
          ),
        ),
        const SizedBox(height: 6),
        CupertinoTextField(
          controller: ctrl,
          placeholder: 'Your answer',
          placeholderStyle: const TextStyle(color: JournalColors.textMuted),
          style: const TextStyle(color: JournalColors.textPrimary),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
          decoration: _fieldDeco(),
          autocorrect: false,
          textInputAction: TextInputAction.next,
        ),
        const SizedBox(height: 16),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 24),
        const Text('Recovery questions',
            style: TextStyle(
                color: JournalColors.textPrimary,
                fontSize: 22,
                fontWeight: FontWeight.w800)),
        const SizedBox(height: 6),
        const Text(
          'If you ever lose email access, these let you reset your password offline. Answers are hashed — never stored in plain text.',
          style: TextStyle(
              color: JournalColors.textSecondary, fontSize: 13, height: 1.5),
        ),
        const SizedBox(height: 20),
        _errorBanner(_err),
        _questionBlock(0, _q1, _a1),
        _questionBlock(1, _q2, _a2),
        _questionBlock(2, _q3, _a3),
        Row(
          children: [
            Expanded(
              child: GestureDetector(
                onTap: widget.onNext,
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  decoration: BoxDecoration(
                    color: JournalColors.bgSurface,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: JournalColors.border),
                  ),
                  child: const Text('Skip for now',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          color: JournalColors.textSecondary, fontSize: 13)),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: AdaptiveButton(
                style: AdaptiveButtonStyle.prominentGlass,
                onPressed: _saving ? null : _save,
                label: _saving ? 'Saving...' : 'Save and Continue',
              ),
            ),
          ],
        ),
      ],
    );
  }
}

// ── Step 9 — AI Provider ──────────────────────────────────────────────────────

class _AiProviderStep extends StatefulWidget {
  const _AiProviderStep({required this.onNext, required this.onBack});
  final VoidCallback onNext;
  final VoidCallback onBack;

  @override
  State<_AiProviderStep> createState() => _AiProviderStepState();
}

class _AiProviderStepState extends State<_AiProviderStep> {
  final _api = ApiService();
  final _keyCtrl = TextEditingController();

  String _provider = 'anthropic';
  bool _saving = false;
  String? _err;

  final _providers = const [
    ('anthropic', '⊕', 'Anthropic Claude', 'claude-sonnet-4-6'),
    ('openai', '◈', 'OpenAI GPT', 'gpt-4o'),
    ('gemini', '⬡', 'Google Gemini', 'gemini-1.5-pro'),
  ];

  Future<void> _save() async {
    final key = _keyCtrl.text.trim();
    if (key.isEmpty) {
      widget.onNext();
      return;
    }

    setState(() {
      _saving = true;
      _err = null;
    });
    try {
      await _api.updateAiProvider({
        'provider': _provider,
        'api_key': key,
      });
      if (mounted) widget.onNext();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _err = _parseErr(e);
      });
    }
  }

  @override
  void dispose() {
    _keyCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 24),
        const Text('AI provider setup',
            style: TextStyle(
                color: JournalColors.textPrimary,
                fontSize: 22,
                fontWeight: FontWeight.w800)),
        const SizedBox(height: 6),
        const Text(
          'Connect an AI API key for reflections, pattern analysis, and memory summaries. You can skip this and add it later in Settings.',
          style: TextStyle(
              color: JournalColors.textSecondary, fontSize: 13, height: 1.5),
        ),
        const SizedBox(height: 20),

        _errorBanner(_err),

        // Provider picker
        for (final p in _providers) ...[
          GestureDetector(
            onTap: () => setState(() => _provider = p.$1),
            child: Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: _provider == p.$1
                    ? JournalColors.accent.withOpacity(0.12)
                    : JournalColors.bgSurface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: _provider == p.$1
                      ? JournalColors.accent
                      : JournalColors.border,
                ),
              ),
              child: Row(
                children: [
                  Text(p.$2,
                      style: TextStyle(
                        color: _provider == p.$1
                            ? JournalColors.accent
                            : JournalColors.textMuted,
                        fontSize: 16,
                      )),
                  const SizedBox(width: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(p.$3,
                          style: TextStyle(
                            color: _provider == p.$1
                                ? JournalColors.accent
                                : JournalColors.textPrimary,
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                          )),
                      Text(p.$4,
                          style: const TextStyle(
                            color: JournalColors.textMuted,
                            fontSize: 11,
                          )),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],

        const SizedBox(height: 8),
        _fieldLabel('API Key (optional)'),
        CupertinoTextField(
          controller: _keyCtrl,
          placeholder: 'sk-... or similar',
          placeholderStyle: const TextStyle(color: JournalColors.textMuted),
          style: const TextStyle(color: JournalColors.textPrimary),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: _fieldDeco(),
          autocorrect: false,
          obscureText: true,
          textInputAction: TextInputAction.done,
        ),
        const SizedBox(height: 8),
        const Text(
          'Your key is stored encrypted on the server and never logged.',
          style: TextStyle(
              color: JournalColors.textMuted, fontSize: 11, height: 1.5),
        ),

        Padding(
          padding: const EdgeInsets.only(top: 24),
          child: Row(
            children: [
              Expanded(
                child: GestureDetector(
                  onTap: widget.onNext,
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    decoration: BoxDecoration(
                      color: JournalColors.bgSurface,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: JournalColors.border),
                    ),
                    child: const Text('Skip for now',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            color: JournalColors.textSecondary, fontSize: 13)),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: AdaptiveButton(
                  style: AdaptiveButtonStyle.prominentGlass,
                  onPressed: _saving ? null : _save,
                  label: _saving ? 'Saving...' : 'Save and Continue',
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ── Step 10 — Memory ──────────────────────────────────────────────────────────

class _MemoryStep extends StatefulWidget {
  const _MemoryStep({
    required this.payload,
    required this.onNext,
    required this.onBack,
  });
  final Map<String, dynamic> payload;
  final VoidCallback onNext;
  final VoidCallback onBack;

  @override
  State<_MemoryStep> createState() => _MemoryStepState();
}

class _MemoryStepState extends State<_MemoryStep> {
  final _api = ApiService();
  String? _aiSummary;
  bool _loadingPreview = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _loadPreview();
  }

  Future<void> _loadPreview() async {
    try {
      final res = await _api.onboardingMemoryPreview(widget.payload);
      if (mounted)
        setState(() {
          _aiSummary = res['ai_summary'] as String?;
          _loadingPreview = false;
        });
    } catch (_) {
      if (mounted) setState(() => _loadingPreview = false);
    }
  }

  Future<void> _saveAndContinue() async {
    setState(() => _saving = true);
    try {
      await _api.onboardingMemorySave({
        ...widget.payload,
        if (_aiSummary != null && _aiSummary!.isNotEmpty)
          'ai_summary': _aiSummary,
      });
    } catch (_) {}
    if (mounted) widget.onNext();
  }

  Widget _memRow(String icon, String label, String value) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(icon,
                style:
                    const TextStyle(color: JournalColors.accent, fontSize: 13)),
            const SizedBox(width: 10),
            Text('$label: ',
                style: const TextStyle(
                    color: JournalColors.textMuted,
                    fontSize: 12,
                    fontWeight: FontWeight.w600)),
            Expanded(
              child: Text(value,
                  style: const TextStyle(
                      color: JournalColors.textSecondary,
                      fontSize: 12,
                      height: 1.4)),
            ),
          ],
        ),
      );

  @override
  Widget build(BuildContext context) {
    final p = widget.payload;
    final name = p['preferred_name'] as String? ?? '';
    final sit = p['situation_type'] as String? ?? '';
    final people = (p['people'] as List?)?.cast<Map>() ?? [];
    final topics = (p['topics'] as List?)?.cast<String>() ?? [];
    final goals = (p['goals'] as List?)?.cast<String>() ?? [];

    final sitLabel = _kSituationOpts
        .firstWhere((s) => s.$1 == sit, orElse: () => ('', '', sit, ''))
        .$3;
    final goalLabels = goals.map((id) {
      final g = _kGoalOpts.firstWhere((g) => g.$1 == id,
          orElse: () => (id, '', id, ''));
      return g.$3;
    }).join(', ');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 24),
        const Text('Your AI memory',
            style: TextStyle(
                color: JournalColors.textPrimary,
                fontSize: 22,
                fontWeight: FontWeight.w800)),
        const SizedBox(height: 6),
        const Text(
          'This context is saved for reflections, pattern analysis, and summaries.',
          style: TextStyle(
              color: JournalColors.textSecondary, fontSize: 13, height: 1.5),
        ),
        const SizedBox(height: 20),
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: JournalColors.accent.withOpacity(0.05),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: JournalColors.accent.withOpacity(0.2)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Text('✦',
                      style:
                          TextStyle(color: JournalColors.accent, fontSize: 18)),
                  const SizedBox(width: 10),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: const [
                      Text('AI Memory — Active',
                          style: TextStyle(
                              color: JournalColors.accent,
                              fontSize: 12,
                              fontWeight: FontWeight.w700)),
                      Text('updates with every new journal entry',
                          style: TextStyle(
                              color: JournalColors.textMuted, fontSize: 10)),
                    ],
                  ),
                ],
              ),
              const Divider(color: Color(0x22818cf8), height: 24),
              if (name.isNotEmpty) _memRow('◎', 'Name', name),
              if (sitLabel.isNotEmpty) _memRow('〜', 'Situation', sitLabel),
              if (people.isNotEmpty)
                _memRow(
                    '◈',
                    'Key People',
                    people
                        .map((p) => '${p['name']} (${p['role']})')
                        .join(', ')),
              if (topics.isNotEmpty) _memRow('⬡', 'Topics', topics.join(', ')),
              if (goalLabels.isNotEmpty) _memRow('⊕', 'Goals', goalLabels),
              const Divider(color: Color(0x22818cf8), height: 20),
              const Text('AI CONTEXT SUMMARY',
                  style: TextStyle(
                    color: JournalColors.textMuted,
                    fontSize: 9,
                    letterSpacing: 1.2,
                    fontWeight: FontWeight.w700,
                  )),
              const SizedBox(height: 8),
              if (_loadingPreview)
                const Row(
                  children: [
                    CupertinoActivityIndicator(radius: 8),
                    SizedBox(width: 10),
                    Text('Generating your context…',
                        style: TextStyle(
                            color: JournalColors.textMuted, fontSize: 12)),
                  ],
                )
              else if (_aiSummary != null && _aiSummary!.isNotEmpty)
                Text(_aiSummary!,
                    style: const TextStyle(
                        color: JournalColors.textSecondary,
                        fontSize: 12,
                        height: 1.65))
              else
                const Text(
                  'Your memory context will grow as you add journal entries.',
                  style: TextStyle(
                      color: JournalColors.textMuted,
                      fontSize: 12,
                      fontStyle: FontStyle.italic,
                      height: 1.6),
                ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        const Text(
            'Update your memory profile anytime from Settings → Memory Profile.',
            style: TextStyle(color: JournalColors.textMuted, fontSize: 11)),
        _NavRow(
          onNext: _saveAndContinue,
          onBack: widget.onBack,
          nextLabel: 'Save Memory and Continue',
          loading: _saving,
        ),
      ],
    );
  }
}

// ── Step 11 — Day One Import ──────────────────────────────────────────────────

class _DayOneStep extends StatefulWidget {
  const _DayOneStep({required this.onNext, required this.onBack});
  final VoidCallback onNext;
  final VoidCallback onBack;

  @override
  State<_DayOneStep> createState() => _DayOneStepState();
}

class _DayOneStepState extends State<_DayOneStep> {
  final _api = ApiService();

  // intro | uploading | processing | done | error
  String _phase = 'intro';
  String? _jobId;
  String? _errMsg;

  int _processed = 0;
  int _total = 0;
  int _inserted = 0;
  int _skipped = 0;
  int _errors = 0;

  static const _steps = [
    ('1', 'Open Day One', 'Open the Day One app on your iPhone, iPad, or Mac.'),
    ('2', 'Go to Settings', 'Tap the menu icon and open Settings.'),
    ('3', 'Tap Journals', 'Select the journal you want to export.'),
    (
      '4',
      'Choose "Export Journal"',
      'Tap Export Journal → choose JSON format when prompted.'
    ),
    (
      '5',
      'Share the file here',
      'Day One creates a .json or .zip file — use the share sheet or Files app to pick it below.'
    ),
  ];

  Future<void> _pickAndUpload() async {
    // Let user pick .zip or .json from Files
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['zip', 'json'],
      allowMultiple: false,
    );
    if (result == null || result.files.isEmpty) return;

    final file = result.files.first;
    if (file.path == null) return;

    setState(() {
      _phase = 'uploading';
      _errMsg = null;
    });

    try {
      final res = await _api.importDayOne(file.path!, file.name);
      final jobId = res['job_id'] as String?;
      if (jobId == null) throw Exception('No job_id returned');
      setState(() {
        _jobId = jobId;
        _total = (res['total'] as num?)?.toInt() ?? 0;
        _phase = 'processing';
      });
      _startPolling();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errMsg = _parseErr(e).isNotEmpty
            ? _parseErr(e)
            : 'Upload failed — check the file is a valid Day One export.';
        _phase = 'error';
      });
    }
  }

  void _startPolling() {
    Future.doWhile(() async {
      await Future.delayed(const Duration(milliseconds: 1200));
      if (!mounted || _phase != 'processing') return false;
      try {
        final res = await _api.getDayOneImportStatus(_jobId!);
        if (!mounted) return false;
        setState(() {
          _processed = (res['processed'] as num?)?.toInt() ?? _processed;
          _total = (res['total'] as num?)?.toInt() ?? _total;
          _inserted = (res['inserted'] as num?)?.toInt() ?? _inserted;
          _skipped = (res['skipped'] as num?)?.toInt() ?? _skipped;
          _errors = (res['errors'] as num?)?.toInt() ?? _errors;
          final status = res['status'] as String? ?? '';
          if (status == 'done') _phase = 'done';
          if (status == 'error') _phase = 'error';
        });
        return _phase == 'processing';
      } catch (_) {
        return _phase == 'processing'; // keep retrying on network blip
      }
    });
  }

  int get _pct => _total > 0 ? ((_processed / _total) * 100).round() : 0;

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 250),
      child: KeyedSubtree(
        key: ValueKey(_phase),
        child: _buildPhase(),
      ),
    );
  }

  Widget _buildPhase() {
    switch (_phase) {
      case 'uploading':
        return _buildUploading();
      case 'processing':
        return _buildProcessing();
      case 'done':
        return _buildDone();
      case 'error':
        return _buildError();
      default:
        return _buildIntro();
    }
  }

  // ── Intro ─────────────────────────────────────────────────────

  Widget _buildIntro() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 24),
        Row(
          children: const [
            Text('⬆',
                style: TextStyle(color: JournalColors.accent, fontSize: 22)),
            SizedBox(width: 10),
            Expanded(
              child: Text('Have a Day One account?',
                  style: TextStyle(
                      color: JournalColors.textPrimary,
                      fontSize: 22,
                      fontWeight: FontWeight.w800)),
            ),
          ],
        ),
        const SizedBox(height: 8),
        const Text(
          'Import earlier Day One entries so they are available in timeline, search, and summaries.',
          style: TextStyle(
              color: JournalColors.textSecondary, fontSize: 13, height: 1.6),
        ),
        const SizedBox(height: 18),

        // Step-by-step instructions
        for (int i = 0; i < _steps.length; i++) ...[
          Padding(
            padding: EdgeInsets.only(
                top: 10, bottom: i < _steps.length - 1 ? 0 : 10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 22,
                  height: 22,
                  decoration: BoxDecoration(
                    color: JournalColors.accent.withOpacity(0.12),
                    shape: BoxShape.circle,
                    border: Border.all(
                        color: JournalColors.accent.withOpacity(0.3)),
                  ),
                  child: Center(
                    child: Text(_steps[i].$1,
                        style: const TextStyle(
                          color: JournalColors.accent,
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                        )),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(_steps[i].$2,
                          style: const TextStyle(
                              color: JournalColors.textPrimary,
                              fontSize: 12,
                              fontWeight: FontWeight.w700)),
                      const SizedBox(height: 2),
                      Text(_steps[i].$3,
                          style: const TextStyle(
                              color: JournalColors.textSecondary,
                              fontSize: 11,
                              height: 1.5)),
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (i < _steps.length - 1)
            const Divider(color: Color(0x0DFFFFFF), height: 1),
        ],

        const SizedBox(height: 14),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 9),
          decoration: BoxDecoration(
            color: JournalColors.bgSurface,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: JournalColors.border),
          ),
          child: const Text(
            'ⓘ  Text entries are fully imported. Photo-only entries are skipped.',
            style: TextStyle(
                color: JournalColors.textMuted,
                fontSize: 11,
                height: 1.55,
                fontFamily: 'monospace'),
          ),
        ),
        const SizedBox(height: 18),

        AdaptiveButton(
          style: AdaptiveButtonStyle.prominentGlass,
          onPressed: _pickAndUpload,
          label: 'Upload .json or .zip',
        ),
        const SizedBox(height: 10),
        GestureDetector(
          onTap: widget.onNext,
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 13),
            decoration: BoxDecoration(
              color: JournalColors.bgSurface,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: JournalColors.border),
            ),
            child: const Text(
              'Skip — I\'ll import later in Settings',
              textAlign: TextAlign.center,
              style:
                  TextStyle(color: JournalColors.textSecondary, fontSize: 13),
            ),
          ),
        ),
        const SizedBox(height: 8),
        GestureDetector(
          onTap: widget.onBack,
          child: const Padding(
            padding: EdgeInsets.symmetric(vertical: 6),
            child: Text('← Back',
                textAlign: TextAlign.center,
                style: TextStyle(color: JournalColors.textMuted, fontSize: 12)),
          ),
        ),
      ],
    );
  }

  // ── Uploading ─────────────────────────────────────────────────

  Widget _buildUploading() {
    return const Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(height: 48),
        Text('📤', textAlign: TextAlign.center, style: TextStyle(fontSize: 44)),
        SizedBox(height: 20),
        Text('Uploading…',
            textAlign: TextAlign.center,
            style: TextStyle(
                color: JournalColors.textPrimary,
                fontSize: 18,
                fontWeight: FontWeight.w700)),
        SizedBox(height: 8),
        Text('Hang tight',
            textAlign: TextAlign.center,
            style: TextStyle(color: JournalColors.textSecondary, fontSize: 13)),
        SizedBox(height: 24),
        Center(
            child: CupertinoActivityIndicator(
                radius: 14, color: JournalColors.accent)),
      ],
    );
  }

  // ── Processing ────────────────────────────────────────────────

  Widget _buildProcessing() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 32),
        const Text('Importing your journal…',
            textAlign: TextAlign.center,
            style: TextStyle(
                color: JournalColors.textPrimary,
                fontSize: 16,
                fontWeight: FontWeight.w700)),
        const SizedBox(height: 6),
        const Text("Don't close this screen. This may take a few minutes.",
            textAlign: TextAlign.center,
            style: TextStyle(color: JournalColors.textSecondary, fontSize: 12)),
        const SizedBox(height: 24),

        // Progress bar
        ClipRRect(
          borderRadius: BorderRadius.circular(3),
          child: LinearProgressIndicator(
            value: _total > 0 ? _pct / 100 : null,
            backgroundColor: JournalColors.border,
            valueColor:
                const AlwaysStoppedAnimation<Color>(JournalColors.accent),
            minHeight: 5,
          ),
        ),
        const SizedBox(height: 10),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              _processed < _total ? 'Processing entries…' : 'Running analysis…',
              style: const TextStyle(
                  color: JournalColors.textSecondary, fontSize: 11),
            ),
            Text('$_processed / $_total',
                style:
                    const TextStyle(color: JournalColors.accent, fontSize: 11)),
          ],
        ),
        const SizedBox(height: 20),

        // Stats grid
        Row(
          children: [
            _StatCard(
                label: 'Imported',
                value: _inserted,
                color: const Color(0xFF10b981)),
            const SizedBox(width: 8),
            _StatCard(
                label: 'Skipped',
                value: _skipped,
                color: JournalColors.textSecondary),
            const SizedBox(width: 8),
            _StatCard(
                label: 'Errors',
                value: _errors,
                color: _errors > 0 ? Colors.red : JournalColors.textSecondary),
          ],
        ),
      ],
    );
  }

  // ── Done ──────────────────────────────────────────────────────

  Widget _buildDone() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 32),
        Container(
          width: 56,
          height: 56,
          margin: const EdgeInsets.symmetric(horizontal: 140),
          decoration: BoxDecoration(
            color: const Color(0xFF10b981).withOpacity(0.15),
            shape: BoxShape.circle,
            border: Border.all(color: const Color(0xFF10b981).withOpacity(0.3)),
          ),
          child: const Center(
            child: Text('✓',
                style: TextStyle(
                    color: Color(0xFF10b981),
                    fontSize: 24,
                    fontWeight: FontWeight.w700)),
          ),
        ),
        const SizedBox(height: 18),
        const Text('Import complete',
            textAlign: TextAlign.center,
            style: TextStyle(
                color: JournalColors.textPrimary,
                fontSize: 22,
                fontWeight: FontWeight.w800)),
        const SizedBox(height: 10),
        Text(
          '$_inserted ${_inserted == 1 ? 'entry' : 'entries'} imported. '
          'Patterns, people intelligence, and mood analysis are ready on your dashboard.',
          textAlign: TextAlign.center,
          style: const TextStyle(
              color: JournalColors.textSecondary, fontSize: 13, height: 1.6),
        ),
        if (_skipped > 0 || _errors > 0) ...[
          const SizedBox(height: 6),
          Text(
            [
              if (_skipped > 0)
                '$_skipped duplicate${_skipped != 1 ? 's' : ''} skipped',
              if (_errors > 0) '$_errors error${_errors != 1 ? 's' : ''}',
            ].join(' · '),
            textAlign: TextAlign.center,
            style:
                const TextStyle(color: JournalColors.textMuted, fontSize: 11),
          ),
        ],
        const SizedBox(height: 28),
        AdaptiveButton(
          style: AdaptiveButtonStyle.prominentGlass,
          onPressed: widget.onNext,
          label: 'Continue',
        ),
      ],
    );
  }

  // ── Error ─────────────────────────────────────────────────────

  Widget _buildError() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 32),
        const Text('⚠',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.orange, fontSize: 40)),
        const SizedBox(height: 16),
        const Text('Import failed',
            textAlign: TextAlign.center,
            style: TextStyle(
                color: JournalColors.textPrimary,
                fontSize: 20,
                fontWeight: FontWeight.w800)),
        const SizedBox(height: 10),
        Text(
          _errMsg ??
              'Something went wrong. Check the file is a valid Day One export.',
          textAlign: TextAlign.center,
          style: const TextStyle(
              color: JournalColors.textSecondary, fontSize: 13, height: 1.5),
        ),
        const SizedBox(height: 24),
        AdaptiveButton(
          style: AdaptiveButtonStyle.prominentGlass,
          onPressed: () => setState(() {
            _phase = 'intro';
            _errMsg = null;
          }),
          label: 'Try Again',
        ),
        const SizedBox(height: 10),
        GestureDetector(
          onTap: widget.onNext,
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 13),
            decoration: BoxDecoration(
              color: JournalColors.bgSurface,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: JournalColors.border),
            ),
            child: const Text('Skip for now',
                textAlign: TextAlign.center,
                style: TextStyle(
                    color: JournalColors.textSecondary, fontSize: 13)),
          ),
        ),
      ],
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard(
      {required this.label, required this.value, required this.color});
  final String label;
  final int value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: JournalColors.bgSurface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: JournalColors.border),
        ),
        child: Column(
          children: [
            Text('$value',
                style: TextStyle(
                    color: color,
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    fontFamily: 'monospace')),
            const SizedBox(height: 3),
            Text(label,
                style: const TextStyle(
                    color: JournalColors.textMuted, fontSize: 10)),
          ],
        ),
      ),
    );
  }
}

// ── Step 12 — SMS / Text Journal ──────────────────────────────────────────────

class _SmsStep extends StatefulWidget {
  const _SmsStep({required this.onNext, required this.onBack});
  final VoidCallback onNext;
  final VoidCallback onBack;

  @override
  State<_SmsStep> createState() => _SmsStepState();
}

class _SmsStepState extends State<_SmsStep> {
  final _api = ApiService();
  final _phoneCtrl = TextEditingController();
  final _codeCtrl = TextEditingController();

  String _phase = 'enter'; // enter | verify | done
  bool _loading = false;
  String? _err;

  Future<void> _sendCode() async {
    final phone = _phoneCtrl.text.trim();
    if (phone.isEmpty) {
      setState(() => _err = 'Enter your phone number');
      return;
    }
    setState(() {
      _loading = true;
      _err = null;
    });
    try {
      await _api.requestSmsVerification(phone);
      if (mounted)
        setState(() {
          _loading = false;
          _phase = 'verify';
        });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _err = _parseErr(e);
      });
    }
  }

  Future<void> _verify() async {
    final code = _codeCtrl.text.trim();
    if (code.length != 6) {
      setState(() => _err = 'Enter the 6-digit code');
      return;
    }
    setState(() {
      _loading = true;
      _err = null;
    });
    try {
      await _api.verifySmsCode(_phoneCtrl.text.trim(), code);
      if (mounted)
        setState(() {
          _loading = false;
          _phase = 'done';
        });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _err = _parseErr(e);
      });
    }
  }

  @override
  void dispose() {
    _phoneCtrl.dispose();
    _codeCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 24),
        const Text('Text journal',
            style: TextStyle(
                color: JournalColors.textPrimary,
                fontSize: 22,
                fontWeight: FontWeight.w800)),
        const SizedBox(height: 6),
        const Text(
          'Text any message to your journal number and it\'s saved as an entry. You\'ll get an AI summary back. Optional — skip if you prefer the app.',
          style: TextStyle(
              color: JournalColors.textSecondary, fontSize: 13, height: 1.5),
        ),
        const SizedBox(height: 20),
        if (_phase == 'enter') ...[
          _errorBanner(_err),
          _fieldLabel('Your Phone Number'),
          CupertinoTextField(
            controller: _phoneCtrl,
            placeholder: '+1 555 000 0000',
            placeholderStyle: const TextStyle(color: JournalColors.textMuted),
            style: const TextStyle(color: JournalColors.textPrimary),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: _fieldDeco(),
            keyboardType: TextInputType.phone,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _sendCode(),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 24),
            child: Row(
              children: [
                Expanded(
                  child: GestureDetector(
                    onTap: widget.onNext,
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      decoration: BoxDecoration(
                        color: JournalColors.bgSurface,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: JournalColors.border),
                      ),
                      child: const Text('Skip',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                              color: JournalColors.textSecondary,
                              fontSize: 13)),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: AdaptiveButton(
                    style: AdaptiveButtonStyle.prominentGlass,
                    onPressed: _loading ? null : _sendCode,
                    label: _loading ? 'Sending...' : 'Send Code',
                  ),
                ),
              ],
            ),
          ),
        ],
        if (_phase == 'verify') ...[
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: JournalColors.accent.withOpacity(0.08),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: JournalColors.accent.withOpacity(0.2)),
            ),
            child: Text(
              'Code sent to ${_phoneCtrl.text} — expires in 10 minutes',
              style: const TextStyle(
                  color: JournalColors.textSecondary,
                  fontSize: 12,
                  height: 1.5),
            ),
          ),
          const SizedBox(height: 16),
          _errorBanner(_err),
          _fieldLabel('6-Digit Code'),
          CupertinoTextField(
            controller: _codeCtrl,
            placeholder: '000000',
            placeholderStyle: const TextStyle(
                color: JournalColors.textMuted, fontSize: 24, letterSpacing: 8),
            style: const TextStyle(
                color: JournalColors.textPrimary,
                fontSize: 28,
                fontWeight: FontWeight.w700,
                letterSpacing: 10),
            textAlign: TextAlign.center,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
            decoration: _fieldDeco(),
            keyboardType: TextInputType.number,
            maxLength: 6,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _verify(),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 24),
            child: Row(
              children: [
                Expanded(
                  child: GestureDetector(
                    onTap: () => setState(() {
                      _phase = 'enter';
                      _err = null;
                      _codeCtrl.clear();
                    }),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      decoration: BoxDecoration(
                        color: JournalColors.bgSurface,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: JournalColors.border),
                      ),
                      child: const Text('Resend',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                              color: JournalColors.textSecondary,
                              fontSize: 13)),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: AdaptiveButton(
                    style: AdaptiveButtonStyle.prominentGlass,
                    onPressed: _loading ? null : _verify,
                    label: _loading ? 'Verifying...' : 'Verify',
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          GestureDetector(
            onTap: widget.onNext,
            child: const Text('Skip for now',
                textAlign: TextAlign.center,
                style: TextStyle(color: JournalColors.textMuted, fontSize: 12)),
          ),
        ],
        if (_phase == 'done') ...[
          const SizedBox(height: 12),
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: const Color(0xFF10b981).withOpacity(0.15),
              shape: BoxShape.circle,
              border:
                  Border.all(color: const Color(0xFF10b981).withOpacity(0.3)),
            ),
            child: const Center(
              child: Text('✓',
                  style: TextStyle(
                      color: Color(0xFF10b981),
                      fontSize: 24,
                      fontWeight: FontWeight.w700)),
            ),
          ),
          const SizedBox(height: 16),
          const Text('Phone verified!',
              textAlign: TextAlign.center,
              style: TextStyle(
                  color: JournalColors.textPrimary,
                  fontSize: 20,
                  fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          const Text(
            'Text any message to your journal number to save it as an entry. You\'ll receive an AI-generated summary back.',
            textAlign: TextAlign.center,
            style: TextStyle(
                color: JournalColors.textSecondary, fontSize: 13, height: 1.6),
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: JournalColors.bgSurface,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: JournalColors.border),
            ),
            child: Text(
              _phoneCtrl.text,
              textAlign: TextAlign.center,
              style: const TextStyle(
                  color: JournalColors.textSecondary,
                  fontSize: 12,
                  fontFamily: 'monospace'),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 20),
            child: AdaptiveButton(
              style: AdaptiveButtonStyle.prominentGlass,
              onPressed: widget.onNext,
              label: 'Continue Setup',
            ),
          ),
        ],
      ],
    );
  }
}

// ── Step 13 — Done ────────────────────────────────────────────────────────────

class _DoneStep extends StatefulWidget {
  const _DoneStep({required this.preferredName, required this.onDone});
  final String preferredName;
  final VoidCallback onDone;

  @override
  State<_DoneStep> createState() => _DoneStepState();
}

class _DoneStepState extends State<_DoneStep> {
  int _countdown = 5;

  @override
  void initState() {
    super.initState();
    _tick();
  }

  void _tick() async {
    while (_countdown > 0 && mounted) {
      await Future.delayed(const Duration(seconds: 1));
      if (!mounted) return;
      setState(() => _countdown--);
    }
    if (mounted) widget.onDone();
  }

  @override
  Widget build(BuildContext context) {
    final name = widget.preferredName.isNotEmpty
        ? "You're set, ${widget.preferredName}!"
        : "You're all set!";

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 32),
        Container(
          width: 64,
          height: 64,
          margin: const EdgeInsets.symmetric(horizontal: 148),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [JournalColors.accent, Color(0xFF8b5cf6)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: JournalColors.accent.withOpacity(0.4),
                blurRadius: 24,
                spreadRadius: 4,
              ),
            ],
          ),
          child: const Center(
            child:
                Text('✦', style: TextStyle(color: Colors.white, fontSize: 28)),
          ),
        ),
        const SizedBox(height: 24),
        Text(name,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: JournalColors.textPrimary,
              fontSize: 26,
              fontWeight: FontWeight.w800,
              height: 1.2,
            )),
        const SizedBox(height: 12),
        const Text(
          'Your setup is saved. You can write, import, or adjust settings next.',
          textAlign: TextAlign.center,
          style: TextStyle(
              color: JournalColors.textSecondary, fontSize: 13, height: 1.65),
        ),
        const SizedBox(height: 28),

        // 2x2 feature grid
        Row(
          children: [
            Expanded(
                child: _DoneFeatureCard(
                    icon: '◈',
                    title: 'Upload first entry',
                    hint: 'via iPhone Shortcut')),
            const SizedBox(width: 8),
            Expanded(
                child: _DoneFeatureCard(
                    icon: '〜',
                    title: 'Nervous System',
                    hint: 'mood tracking over time')),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
                child: _DoneFeatureCard(
                    icon: '⬡',
                    title: 'Pattern Detection',
                    hint: 'AI runs automatically')),
            const SizedBox(width: 8),
            Expanded(
                child: _DoneFeatureCard(
                    icon: '✦', title: 'Exit Plan', hint: "when you're ready")),
          ],
        ),

        const SizedBox(height: 28),
        AdaptiveButton(
          style: AdaptiveButtonStyle.prominentGlass,
          onPressed: widget.onDone,
          label: 'Enter Dashboard',
        ),
        const SizedBox(height: 10),
        Text(
          'Redirecting in ${_countdown}s',
          textAlign: TextAlign.center,
          style: const TextStyle(color: JournalColors.textMuted, fontSize: 11),
        ),
      ],
    );
  }
}

class _DoneFeatureCard extends StatelessWidget {
  const _DoneFeatureCard(
      {required this.icon, required this.title, required this.hint});
  final String icon;
  final String title;
  final String hint;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: JournalColors.bgSurface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: JournalColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(icon,
              style:
                  const TextStyle(color: JournalColors.accent, fontSize: 14)),
          const SizedBox(height: 4),
          Text(title,
              style: const TextStyle(
                  color: JournalColors.textPrimary,
                  fontSize: 11,
                  fontWeight: FontWeight.w700)),
          const SizedBox(height: 2),
          Text(hint,
              style: const TextStyle(
                  color: JournalColors.textMuted, fontSize: 10)),
        ],
      ),
    );
  }
}
