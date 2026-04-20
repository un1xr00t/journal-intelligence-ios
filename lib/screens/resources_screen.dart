// lib/screens/resources_screen.dart
//
// Personalized support resources — ranked by AI from journal patterns.
// Pushed from Settings → SUPPORT → Resources.
// Routes: GET /api/resources · POST /api/resources/generate

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/api_service.dart';
import '../theme/app_theme.dart';
import '../widgets/glass_card.dart';

// ── Static resource library ───────────────────────────────────────────────────
// AI ranks + contextualises these. Phone numbers / URLs are curated here only.

class _ResourceItem {
  final String name;
  final String description;
  final String type; // technique | app | hotline | service | directory | organization | community | resource | tool
  final String? url;
  final String? phone;
  const _ResourceItem({
    required this.name,
    required this.description,
    required this.type,
    this.url,
    this.phone,
  });
}

class _ResourceCategory {
  final String id;
  final String title;
  final String emoji;
  final Color color;
  final String defaultContext;
  final List<_ResourceItem> resources;
  const _ResourceCategory({
    required this.id,
    required this.title,
    required this.emoji,
    required this.color,
    required this.defaultContext,
    required this.resources,
  });
}

const _kResourceLibrary = <String, _ResourceCategory>{
  'grounding': _ResourceCategory(
    id: 'grounding',
    title: 'Grounding & Calming',
    emoji: '🌿',
    color: Color(0xFF10b981),
    defaultContext: 'Simple, accessible tools for when you need to slow down and feel steady.',
    resources: [
      _ResourceItem(name: 'Box Breathing', description: '4-count inhale, hold, exhale, hold — repeat 4 times to calm the nervous system', type: 'technique'),
      _ResourceItem(name: '5-4-3-2-1 Grounding', description: 'Name 5 things you see, 4 you hear, 3 you can touch, 2 you smell, 1 you taste', type: 'technique'),
      _ResourceItem(name: 'Physiological Sigh', description: 'Double inhale through nose, then long slow exhale — fastest known way to lower stress', type: 'technique'),
      _ResourceItem(name: 'Progressive Muscle Relaxation', description: 'Tense and release each muscle group from toes to head — 15 to 20 minutes', type: 'technique'),
      _ResourceItem(name: 'Headspace', description: 'Guided meditation, breathing, and sleep tools — free trial available', type: 'app', url: 'https://headspace.com'),
      _ResourceItem(name: 'Calm', description: 'Sleep stories, meditations, and breathing exercises for daily stress', type: 'app', url: 'https://calm.com'),
      _ResourceItem(name: 'Insight Timer', description: 'Free library of 150,000+ guided meditations', type: 'app', url: 'https://insighttimer.com'),
      _ResourceItem(name: 'PTSD Coach', description: 'VA-developed grounding and coping tools — free, no account needed', type: 'app', url: 'https://www.ptsd.va.gov/appvid/mobile/ptsdcoach_app.asp'),
    ],
  ),
  'emotional_support': _ResourceCategory(
    id: 'emotional_support',
    title: 'Emotional Support & Therapy',
    emoji: '💬',
    color: Color(0xFF8b5cf6),
    defaultContext: "Talking to someone trained to listen can help you process what you're carrying.",
    resources: [
      _ResourceItem(name: 'SAMHSA Helpline', description: 'Free, confidential mental health and substance use referrals, 24/7', type: 'hotline', phone: '1-800-662-4357'),
      _ResourceItem(name: 'NAMI Helpline', description: 'Support, info, and referrals — Mon–Fri, 10am–10pm ET', type: 'hotline', phone: '1-800-950-6264'),
      _ResourceItem(name: '7 Cups', description: 'Free anonymous chat with trained volunteer listeners — 24/7', type: 'service', url: 'https://7cups.com'),
      _ResourceItem(name: 'BetterHelp', description: 'Online therapy — text, video, or phone sessions with licensed therapists', type: 'service', url: 'https://betterhelp.com'),
      _ResourceItem(name: 'Open Path Collective', description: 'Affordable in-person and online therapy, \$30–\$80 per session', type: 'service', url: 'https://openpathcollective.org'),
      _ResourceItem(name: 'Psychology Today', description: 'Find local therapists filterable by specialty, insurance, and identity', type: 'directory', url: 'https://www.psychologytoday.com/us/therapists'),
      _ResourceItem(name: 'Warmline Directory', description: 'Find your state warmline — someone to talk to before crisis hits', type: 'hotline', url: 'https://warmline.org'),
    ],
  ),
  'mental_health': _ResourceCategory(
    id: 'mental_health',
    title: 'Mental Health & Wellbeing',
    emoji: '🧠',
    color: Color(0xFF6366f1),
    defaultContext: 'Resources for understanding and supporting your mental wellbeing over time.',
    resources: [
      _ResourceItem(name: 'NAMI', description: 'National Alliance on Mental Illness — education, helpline, and local support groups', type: 'organization', url: 'https://nami.org'),
      _ResourceItem(name: 'Mental Health America', description: 'Free screening tools, resources, and local affiliate support', type: 'organization', url: 'https://mhanational.org'),
      _ResourceItem(name: 'NIMH', description: 'National Institute of Mental Health — research-backed info on every condition', type: 'resource', url: 'https://www.nimh.nih.gov'),
      _ResourceItem(name: 'Sanvello', description: 'CBT-based app for anxiety, depression, and stress — free tier available', type: 'app', url: 'https://sanvello.com'),
      _ResourceItem(name: 'Woebot', description: 'AI-powered CBT mental health support', type: 'app', url: 'https://woebothealth.com'),
      _ResourceItem(name: 'Daylio', description: 'Micro mood journal and habit tracker — identify emotional patterns', type: 'app', url: 'https://daylio.net'),
      _ResourceItem(name: 'DBSA', description: 'Depression and Bipolar Support Alliance — free online and in-person peer groups', type: 'community', url: 'https://www.dbsalliance.org'),
    ],
  ),
  'relationship': _ResourceCategory(
    id: 'relationship',
    title: 'Relationship & Family Support',
    emoji: '🤝',
    color: Color(0xFFec4899),
    defaultContext: 'Support for navigating difficult relationships, conflict, and family dynamics.',
    resources: [
      _ResourceItem(name: 'National DV Hotline', description: '24/7 domestic violence support — call or text START to 88788', type: 'hotline', phone: '1-800-799-7233', url: 'https://thehotline.org'),
      _ResourceItem(name: 'Love Is Respect', description: 'Relationship abuse resources — call or text LOVEIS to 22522', type: 'hotline', phone: '1-866-331-9474', url: 'https://loveisrespect.org'),
      _ResourceItem(name: 'WomensLaw.org', description: 'State-by-state legal information for abuse survivors — confidential live chat', type: 'resource', url: 'https://womenslaw.org'),
      _ResourceItem(name: 'Safe Horizon', description: 'Crisis support for victims of violence and abuse', type: 'service', phone: '1-800-621-4673', url: 'https://safehorizon.org'),
      _ResourceItem(name: 'DomesticShelters.org', description: 'Find local domestic violence shelters by zip code', type: 'directory', url: 'https://www.domesticshelters.org'),
      _ResourceItem(name: 'Codependents Anonymous', description: 'Free 12-step support groups for unhealthy relationship patterns', type: 'community', url: 'https://coda.org'),
    ],
  ),
  'parenting': _ResourceCategory(
    id: 'parenting',
    title: 'Parenting & Co-Parenting',
    emoji: '🌻',
    color: Color(0xFFf59e0b),
    defaultContext: 'Support for parents navigating stress, single parenting, or co-parenting challenges.',
    resources: [
      _ResourceItem(name: 'Childhelp Hotline', description: 'Support for parents under stress and children in need', type: 'hotline', phone: '1-800-422-4453'),
      _ResourceItem(name: 'Boys Town National Hotline', description: '24/7 crisis and parenting support for parents and teens', type: 'hotline', phone: '1-800-448-3000'),
      _ResourceItem(name: 'Our Family Wizard', description: 'Co-parenting communication and scheduling — court-accepted documentation', type: 'tool', url: 'https://ourfamilywizard.com'),
      _ResourceItem(name: 'TalkingParents', description: 'Documented co-parenting messaging — timestamped records for legal use', type: 'tool', url: 'https://talkingparents.com'),
      _ResourceItem(name: 'Child Mind Institute', description: 'Expert guidance on child and teen mental health — free articles by age', type: 'resource', url: 'https://childmind.org'),
      _ResourceItem(name: 'Postpartum Support International', description: 'Postpartum depression and anxiety support', type: 'hotline', phone: '1-800-944-4773', url: 'https://postpartum.net'),
    ],
  ),
  'financial': _ResourceCategory(
    id: 'financial',
    title: 'Financial Support',
    emoji: '💵',
    color: Color(0xFF059669),
    defaultContext: 'Help managing financial stress, debt, and planning for stability.',
    resources: [
      _ResourceItem(name: 'NFCC', description: 'National Foundation for Credit Counseling — free and low-cost financial counseling', type: 'organization', url: 'https://nfcc.org'),
      _ResourceItem(name: 'Benefits.gov', description: 'Federal benefits eligibility screener — find what you qualify for', type: 'resource', url: 'https://benefits.gov'),
      _ResourceItem(name: '211', description: 'Call or text 211 — local social services, food, housing, financial help', type: 'hotline', phone: '211'),
      _ResourceItem(name: 'Consumer Financial Protection Bureau', description: 'Tools, guides, and complaint filing for financial issues', type: 'resource', url: 'https://consumerfinance.gov'),
      _ResourceItem(name: 'GreenPath', description: 'Nonprofit financial counseling and debt management', type: 'service', url: 'https://greenpath.com'),
    ],
  ),
  'legal': _ResourceCategory(
    id: 'legal',
    title: 'Legal Resources',
    emoji: '⚖️',
    color: Color(0xFF64748b),
    defaultContext: 'Navigating legal situations — free help and trusted directories.',
    resources: [
      _ResourceItem(name: 'LawHelp.org', description: 'Find free legal aid in your state', type: 'directory', url: 'https://lawhelp.org'),
      _ResourceItem(name: 'Legal Services Corporation', description: 'Federally funded civil legal help for low-income Americans', type: 'organization', url: 'https://lsc.gov'),
      _ResourceItem(name: 'American Bar Association', description: 'Find a lawyer — directory and referral service', type: 'directory', url: 'https://www.americanbar.org/groups/legal_services/flh-home'),
      _ResourceItem(name: 'Courthouse Libraries', description: 'Free legal research resources — most counties have public access', type: 'resource'),
      _ResourceItem(name: 'Avvo', description: 'Free Q&A with lawyers and attorney directory', type: 'directory', url: 'https://avvo.com'),
    ],
  ),
  'safety': _ResourceCategory(
    id: 'safety',
    title: 'Safety Planning',
    emoji: '🛡️',
    color: Color(0xFFef4444),
    defaultContext: 'If your safety is at risk, these resources can help you plan and act.',
    resources: [
      _ResourceItem(name: 'National DV Hotline', description: '24/7 safety planning, local shelter referrals, and crisis support', type: 'hotline', phone: '1-800-799-7233', url: 'https://thehotline.org'),
      _ResourceItem(name: 'Safe Horizon', description: 'NYC-based but national referrals — victims of violence and abuse', type: 'service', phone: '1-800-621-4673', url: 'https://safehorizon.org'),
      _ResourceItem(name: 'DomesticShelters.org', description: 'Find emergency shelter in your area by zip code', type: 'directory', url: 'https://www.domesticshelters.org'),
      _ResourceItem(name: 'Futures Without Violence', description: 'Safety resources for survivors and those supporting them', type: 'organization', url: 'https://www.futureswithoutviolence.org'),
      _ResourceItem(name: 'National Center for Victims of Crime', description: 'Helpline and resources for all crime victims', type: 'service', phone: '1-855-484-2846', url: 'https://victimsofcrime.org'),
    ],
  ),
  'practical_tools': _ResourceCategory(
    id: 'practical_tools',
    title: 'Practical Tools',
    emoji: '🧰',
    color: Color(0xFF0ea5e9),
    defaultContext: 'Everyday tools that help you stay organized, documented, and in control.',
    resources: [
      _ResourceItem(name: 'Notion', description: 'Free workspace for notes, documents, and tracking — great for case files', type: 'tool', url: 'https://notion.so'),
      _ResourceItem(name: 'Google Drive', description: 'Free cloud storage — back up screenshots, documents, and evidence securely', type: 'tool', url: 'https://drive.google.com'),
      _ResourceItem(name: 'Signal', description: 'End-to-end encrypted messaging — private conversations and document sharing', type: 'app', url: 'https://signal.org'),
      _ResourceItem(name: 'TalkingParents', description: 'Court-admissible co-parenting communication logs', type: 'tool', url: 'https://talkingparents.com'),
      _ResourceItem(name: 'Reclaim the Records', description: 'Access to vital records and public documents', type: 'resource', url: 'https://reclaimtherecords.org'),
    ],
  ),
  'crisis': _ResourceCategory(
    id: 'crisis',
    title: 'Crisis Support',
    emoji: '🆘',
    color: Color(0xFFef4444),
    defaultContext: 'If you need support right now, these services are available immediately.',
    resources: [
      _ResourceItem(name: '988 Suicide & Crisis Lifeline', description: 'Call or text 988 — free, confidential crisis support 24/7', type: 'hotline', phone: '988'),
      _ResourceItem(name: 'Crisis Text Line', description: 'Text HOME to 741741 — free crisis counseling by text, 24/7', type: 'hotline'),
      _ResourceItem(name: 'International Association for Suicide Prevention', description: 'Crisis center directory by country', type: 'directory', url: 'https://www.iasp.info/resources/Crisis_Centres'),
      _ResourceItem(name: 'SAMHSA Helpline', description: 'Mental health and substance use crisis support, 24/7', type: 'hotline', phone: '1-800-662-4357'),
      _ResourceItem(name: 'Emergency Services', description: 'Call 911 for immediate danger to yourself or others', type: 'hotline', phone: '911'),
    ],
  ),
};

// ── Screen ────────────────────────────────────────────────────────────────────

class ResourcesScreen extends StatefulWidget {
  const ResourcesScreen({super.key});

  @override
  State<ResourcesScreen> createState() => _ResourcesScreenState();
}

class _ResourcesScreenState extends State<ResourcesScreen> {
  final _api = ApiService();

  bool _loading     = true;
  bool _generating  = false;
  String? _error;

  Map<String, dynamic>? _profile;
  String? _generatedAt;

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    setState(() { _loading = true; _error = null; });
    try {
      final data = await _api.getResources();
      if (mounted) setState(() {
        _profile     = data?['profile'] as Map<String, dynamic>?;
        _generatedAt = data?['generated_at'] as String?;
        _loading     = false;
      });
    } catch (e) {
      if (mounted) setState(() {
        _error   = 'Could not load resources — check your connection.';
        _loading = false;
      });
    }
  }

  Future<void> _generate({bool force = false}) async {
    if (_generating) return;
    setState(() { _generating = true; _error = null; });
    try {
      final data = await _api.generateResources(force: force);
      if (mounted) setState(() {
        _profile     = data['profile'] as Map<String, dynamic>?;
        _generatedAt = data['generated_at'] as String?;
        _generating  = false;
      });
    } catch (e) {
      if (mounted) setState(() {
        _error      = 'Could not generate recommendations — try again.';
        _generating = false;
      });
    }
  }

  bool get _isStale {
    if (_generatedAt == null) return false;
    final generated = DateTime.tryParse(_generatedAt!);
    if (generated == null) return false;
    return DateTime.now().difference(generated).inDays > 7;
  }

  String _fmtDate(String? iso) {
    if (iso == null) return '';
    final dt = DateTime.tryParse(iso);
    if (dt == null) return '';
    const months = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
    return '${months[dt.month - 1]} ${dt.day}, ${dt.year}';
  }

  @override
  Widget build(BuildContext context) {
    final ranked       = (_profile?['ranked_categories'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    final surfaceCrisis = _profile?['surface_crisis'] == true;
    final crisisEntry  = surfaceCrisis ? ranked.where((c) => c['id'] == 'crisis').firstOrNull : null;
    final mainEntries  = crisisEntry != null ? ranked.where((c) => c['id'] != 'crisis').toList() : ranked;

    return CupertinoPageScaffold(
      backgroundColor: JournalColors.bgBase,
      navigationBar: CupertinoNavigationBar(
        backgroundColor: JournalColors.bgBase.withOpacity(0.9),
        border: const Border(bottom: BorderSide(color: JournalColors.border, width: 0.5)),
        middle: const Text('Resources',
            style: TextStyle(color: JournalColors.textPrimary, fontWeight: FontWeight.w600)),
        trailing: _profile != null
            ? GestureDetector(
                onTap: _generating ? null : () => _generate(force: true),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: _generating
                        ? JournalColors.accent.withOpacity(0.06)
                        : JournalColors.accent.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: JournalColors.accent.withOpacity(0.30),
                    ),
                  ),
                  child: _generating
                      ? const CupertinoActivityIndicator(radius: 7)
                      : const Text('Refresh',
                          style: TextStyle(
                            color: JournalColors.accent,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          )),
                ),
              )
            : null,
      ),
      child: SafeArea(
        child: _loading
            ? const Center(child: CupertinoActivityIndicator())
            : _buildBody(ranked, crisisEntry, mainEntries),
      ),
    );
  }

  Widget _buildBody(
    List<Map<String, dynamic>> ranked,
    Map<String, dynamic>? crisisEntry,
    List<Map<String, dynamic>> mainEntries,
  ) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
      children: [
        // Error banner
        if (_error != null) ...[
          Container(
            margin: const EdgeInsets.only(bottom: 16),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.red.withOpacity(0.08),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.red.withOpacity(0.25)),
            ),
            child: Text(_error!,
                style: const TextStyle(color: Colors.redAccent, fontSize: 13)),
          ),
        ],

        // ── No profile yet ──────────────────────────────────────────
        if (_profile == null && _error == null) ...[
          const SizedBox(height: 32),
          const Text('Support Resources',
              style: TextStyle(
                  color: JournalColors.textPrimary,
                  fontSize: 22,
                  fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          const Text(
            'Based on what you\'ve shared, we\'ll surface the support resources most relevant to your situation.',
            style: TextStyle(color: JournalColors.textSecondary, fontSize: 14, height: 1.6),
          ),
          const SizedBox(height: 28),
          GestureDetector(
            onTap: _generating ? null : () => _generate(force: false),
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 14),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [JournalColors.accent, Color(0xFF7c3aed)],
                ),
                borderRadius: BorderRadius.circular(12),
              ),
              child: _generating
                  ? const CupertinoActivityIndicator(color: Colors.white, radius: 10)
                  : const Text('Show My Resources',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.w600)),
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'Uses your journal patterns and onboarding context. Nothing is shared externally.',
            textAlign: TextAlign.center,
            style: TextStyle(color: JournalColors.textMuted, fontSize: 11, height: 1.6),
          ),
          const SizedBox(height: 40),
        ],

        // ── Profile loaded ──────────────────────────────────────────
        if (_profile != null) ...[
          // Stale / date badge
          if (_generatedAt != null) ...[
            Row(children: [
              if (_isStale) ...[
                const Icon(CupertinoIcons.exclamationmark_circle,
                    color: Color(0xFFf59e0b), size: 13),
                const SizedBox(width: 4),
              ],
              Text(
                '${_isStale ? 'Outdated — ' : ''}Updated ${_fmtDate(_generatedAt)}',
                style: TextStyle(
                  color: _isStale ? const Color(0xFFf59e0b) : JournalColors.textMuted,
                  fontSize: 11,
                ),
              ),
            ]),
            const SizedBox(height: 12),
          ],

          // Personalized intro
          if ((_profile!['intro'] as String? ?? '').trim().isNotEmpty) ...[
            _IntroCard(text: (_profile!['intro'] as String).trim()),
            const SizedBox(height: 20),
          ],

          // Crisis — pinned top when signals warrant it
          if (crisisEntry != null) ...[
            _SectionLabel('IF YOU NEED SUPPORT RIGHT NOW'),
            const SizedBox(height: 8),
            _CategoryCard(
              categoryId: crisisEntry['id'] as String,
              context: crisisEntry['context'] as String? ?? '',
              isCrisis: true,
            ),
            const SizedBox(height: 20),
          ],

          // Main ranked categories
          if (mainEntries.isNotEmpty) ...[
            _SectionLabel('RESOURCES FOR YOU'),
            const SizedBox(height: 8),
            ...mainEntries.map((entry) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _CategoryCard(
                categoryId: entry['id'] as String,
                context: entry['context'] as String? ?? '',
                isCrisis: false,
              ),
            )),
          ],

          const SizedBox(height: 24),

          // Privacy footer
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.015),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                  color: JournalColors.border, style: BorderStyle.solid),
            ),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('🔒', style: TextStyle(fontSize: 14)),
              const SizedBox(width: 10),
              const Expanded(
                child: Text(
                  'These recommendations are generated from your private journal patterns. Nothing is shared externally. Refresh as your situation changes.',
                  style: TextStyle(
                      color: JournalColors.textMuted,
                      fontSize: 11,
                      height: 1.65),
                ),
              ),
            ]),
          ),
        ],
      ],
    );
  }
}

// ── Section label ─────────────────────────────────────────────────────────────

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) => Text(
    text,
    style: const TextStyle(
      color: JournalColors.textMuted,
      fontSize: 10,
      letterSpacing: 0.8,
      fontWeight: FontWeight.w600,
    ),
  );
}

// ── Intro card ────────────────────────────────────────────────────────────────

class _IntroCard extends StatelessWidget {
  final String text;
  const _IntroCard({required this.text});

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'PERSONALIZED FOR YOU',
            style: TextStyle(
              color: JournalColors.accent,
              fontSize: 9,
              letterSpacing: 1.1,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            text,
            style: TextStyle(
              color: JournalColors.textSecondary,
              fontSize: 13,
              height: 1.7,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Category card ─────────────────────────────────────────────────────────────

class _CategoryCard extends StatefulWidget {
  final String categoryId;
  final String context;
  final bool isCrisis;
  const _CategoryCard({
    required this.categoryId,
    required this.context,
    required this.isCrisis,
  });

  @override
  State<_CategoryCard> createState() => _CategoryCardState();
}

class _CategoryCardState extends State<_CategoryCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final cat = _kResourceLibrary[widget.categoryId];
    if (cat == null) return const SizedBox.shrink();

    final displayContext = widget.context.isNotEmpty ? widget.context : cat.defaultContext;

    return GlassCard(
      onTap: () => setState(() => _expanded = !_expanded),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Header row
        Row(children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: cat.color.withOpacity(0.15),
              borderRadius: BorderRadius.circular(8),
            ),
            alignment: Alignment.center,
            child: Text(cat.emoji, style: const TextStyle(fontSize: 18)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(cat.title,
                style: const TextStyle(
                    color: JournalColors.textPrimary,
                    fontSize: 15,
                    fontWeight: FontWeight.w600)),
          ),
          Icon(
            _expanded ? CupertinoIcons.chevron_up : CupertinoIcons.chevron_down,
            color: JournalColors.textMuted,
            size: 14,
          ),
        ]),

        const SizedBox(height: 10),

        // AI context blurb
        Text(
          displayContext,
          style: const TextStyle(
              color: JournalColors.textSecondary, fontSize: 12, height: 1.65),
        ),

        // Expanded resource list
        if (_expanded) ...[
          const SizedBox(height: 12),
          const Divider(color: JournalColors.border, height: 1),
          const SizedBox(height: 12),
          ...cat.resources.map((r) => _ResourceRow(item: r)),
        ],
      ]),
    );
  }
}

// ── Resource row ──────────────────────────────────────────────────────────────

class _ResourceRow extends StatelessWidget {
  final _ResourceItem item;
  const _ResourceRow({required this.item});

  Color _typeColor(String type) {
    return switch (type) {
      'hotline'      => const Color(0xFFef4444),
      'app'          => const Color(0xFF6366f1),
      'service'      => const Color(0xFF8b5cf6),
      'directory'    => const Color(0xFF0ea5e9),
      'organization' => const Color(0xFF10b981),
      'community'    => const Color(0xFFec4899),
      'technique'    => const Color(0xFF10b981),
      'tool'         => const Color(0xFF0ea5e9),
      _              => JournalColors.textMuted,
    };
  }

  void _copyToClipboard(BuildContext context, String text) {
    Clipboard.setData(ClipboardData(text: text));
    // Show a brief tooltip
    showCupertinoDialog(
      context: context,
      barrierDismissible: true,
      builder: (_) => const CupertinoAlertDialog(
        title: Text('Copied'),
        content: Text('Phone number copied to clipboard.'),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final hasLink  = item.url != null;
    final hasPhone = item.phone != null;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Type dot
        Padding(
          padding: const EdgeInsets.only(top: 5),
          child: Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              color: _typeColor(item.type),
              shape: BoxShape.circle,
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(
                child: Text(item.name,
                    style: const TextStyle(
                        color: JournalColors.textPrimary,
                        fontSize: 13,
                        fontWeight: FontWeight.w600)),
              ),
              // Type badge
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: _typeColor(item.type).withOpacity(0.10),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  item.type.replaceAll('_', ' '),
                  style: TextStyle(
                      color: _typeColor(item.type),
                      fontSize: 9,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.4),
                ),
              ),
            ]),
            const SizedBox(height: 3),
            Text(item.description,
                style: const TextStyle(
                    color: JournalColors.textSecondary, fontSize: 11, height: 1.5)),
            // CTA buttons
            if (hasPhone || hasLink) ...[
              const SizedBox(height: 8),
              Row(children: [
                if (hasPhone)
                  GestureDetector(
                    onTap: () => _copyToClipboard(context, item.phone!),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: _typeColor(item.type).withOpacity(0.12),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: _typeColor(item.type).withOpacity(0.30)),
                      ),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        Icon(CupertinoIcons.phone_fill,
                            color: _typeColor(item.type), size: 11),
                        const SizedBox(width: 5),
                        Text(item.phone!,
                            style: TextStyle(
                                color: _typeColor(item.type),
                                fontSize: 11,
                                fontWeight: FontWeight.w600)),
                      ]),
                    ),
                  ),
                if (hasPhone && hasLink) const SizedBox(width: 8),
                if (hasLink)
                  GestureDetector(
                    onTap: () {
                      // Requires url_launcher — show copy fallback until added
                      Clipboard.setData(ClipboardData(text: item.url!));
                      showCupertinoDialog(
                        context: context,
                        barrierDismissible: true,
                        builder: (_) => CupertinoAlertDialog(
                          title: const Text('Link Copied'),
                          content: Text(item.url!),
                          actions: [
                            CupertinoDialogAction(
                              onPressed: () => Navigator.pop(context),
                              child: const Text('OK'),
                            ),
                          ],
                        ),
                      );
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: JournalColors.accent.withOpacity(0.10),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: JournalColors.accent.withOpacity(0.25)),
                      ),
                      child: const Row(mainAxisSize: MainAxisSize.min, children: [
                        Icon(CupertinoIcons.arrow_up_right_square,
                            color: JournalColors.accent, size: 11),
                        SizedBox(width: 5),
                        Text('Open',
                            style: TextStyle(
                                color: JournalColors.accent,
                                fontSize: 11,
                                fontWeight: FontWeight.w600)),
                      ]),
                    ),
                  ),
              ]),
            ],
          ]),
        ),
      ]),
    );
  }
}