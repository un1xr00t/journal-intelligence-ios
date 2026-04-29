import 'package:flutter/cupertino.dart';
import 'package:intl/intl.dart';

import '../services/api_service.dart';
import '../theme/app_theme.dart';
import '../widgets/glass_card.dart';

Color _withAlpha(Color color, double alpha) => color.withValues(alpha: alpha);

const _kTrackCategories = <({String id, String label})>[
  (id: 'breakup_recovery', label: 'Breakup'),
  (id: 'custody_battle', label: 'Custody'),
  (id: 'burnout', label: 'Burnout'),
  (id: 'finances', label: 'Finances'),
  (id: 'sobriety', label: 'Sobriety'),
  (id: 'leaving_relationship', label: 'Leaving'),
  (id: 'general', label: 'General'),
];

const _kTrackCadences = <({String id, String label})>[
  (id: 'daily', label: 'Daily'),
  (id: 'weekly', label: 'Weekly'),
  (id: 'when_i_open_sage', label: 'When I Open Sage'),
];

class SageTracksScreen extends StatefulWidget {
  const SageTracksScreen({
    super.key,
    this.allowSelection = false,
    this.initialSelectedTrackId,
  });

  final bool allowSelection;
  final String? initialSelectedTrackId;

  @override
  State<SageTracksScreen> createState() => _SageTracksScreenState();
}

class _SageTracksScreenState extends State<SageTracksScreen> {
  final _api = ApiService();

  List<SageFocusTrack> _tracks = const [];
  bool _loading = true;
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
      final tracks = await _api.listSageTracks();
      if (!mounted) return;
      setState(() {
        _tracks = tracks;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = _parseError(e);
      });
    }
  }

  String _parseError(dynamic e) {
    final str = e.toString();
    final match = RegExp(r'"detail"\s*:\s*"([^"]+)"').firstMatch(str);
    return match?.group(1) ?? 'Could not load focus tracks.';
  }

  Future<void> _createTrack() async {
    final created = await Navigator.push<bool>(
      context,
      CupertinoPageRoute(
        builder: (_) => const _EditTrackScreen(),
      ),
    );
    if (created == true) {
      await _load();
    }
  }

  Future<void> _openTrack(SageFocusTrack track) async {
    final changed = await Navigator.push<bool>(
      context,
      CupertinoPageRoute(
        builder: (_) => _TrackDetailScreen(trackId: track.id),
      ),
    );
    if (changed == true) {
      await _load();
    }
  }

  List<SageFocusTrack> _sectionTracks(String status) {
    return _tracks.where((item) => item.status == status).toList();
  }

  @override
  Widget build(BuildContext context) {
    return CupertinoPageScaffold(
      backgroundColor: JournalColors.bgBase,
      child: CustomScrollView(
        slivers: [
          CupertinoSliverNavigationBar(
            largeTitle: const Text('Focus Tracks'),
            trailing: CupertinoButton(
              padding: EdgeInsets.zero,
              minimumSize: const Size(0, 32),
              onPressed: _createTrack,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: _withAlpha(JournalColors.accent, 0.16),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: JournalColors.borderBright),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      CupertinoIcons.plus,
                      color: JournalColors.textPrimary,
                      size: 13,
                    ),
                    SizedBox(width: 6),
                    Text(
                      'New',
                      style: TextStyle(
                        color: JournalColors.textPrimary,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            backgroundColor: JournalColors.bgBase.withValues(alpha: 0.92),
            border: const Border(
              bottom: BorderSide(color: JournalColors.border, width: 0.5),
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
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: GlassCard(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          CupertinoIcons.exclamationmark_triangle,
                          color: JournalColors.danger,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          _error!,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: JournalColors.textSecondary,
                            fontSize: 14,
                            height: 1.45,
                          ),
                        ),
                        const SizedBox(height: 14),
                        CupertinoButton(
                          color: JournalColors.accent,
                          onPressed: _load,
                          child: const Text(
                            'Retry',
                            style: TextStyle(color: JournalColors.textPrimary),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
              sliver: SliverList(
                delegate: SliverChildListDelegate([
                  const GlassCard(
                    accentBorder: true,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Ongoing Coach',
                          style: TextStyle(
                            color: JournalColors.textPrimary,
                            fontSize: 20,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        SizedBox(height: 8),
                        Text(
                          'Focus tracks help Sage remember the goal, the hard parts, and what you are trying to do next across sessions.',
                          style: TextStyle(
                            color: JournalColors.textSecondary,
                            fontSize: 14,
                            height: 1.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 18),
                  if (_tracks.isEmpty)
                    GlassCard(
                      child: Column(
                        children: [
                          const Text(
                            'No focus tracks yet',
                            style: TextStyle(
                              color: JournalColors.textPrimary,
                              fontSize: 17,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            'Create one for breakup recovery, burnout, finances, sobriety, custody, or any other long-running thread you want Sage to stay with.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: JournalColors.textSecondary,
                              fontSize: 13,
                              height: 1.45,
                            ),
                          ),
                          const SizedBox(height: 14),
                          CupertinoButton(
                            color: JournalColors.accent,
                            onPressed: _createTrack,
                            child: const Text(
                              'Start a Focus Track',
                              style: TextStyle(color: JournalColors.textPrimary),
                            ),
                          ),
                        ],
                      ),
                    ),
                  if (_sectionTracks('active').isNotEmpty)
                    _TrackSection(
                      title: 'Active',
                      tracks: _sectionTracks('active'),
                      allowSelection: widget.allowSelection,
                      initialSelectedTrackId: widget.initialSelectedTrackId,
                      onTap: _openTrack,
                    ),
                  if (_sectionTracks('paused').isNotEmpty)
                    _TrackSection(
                      title: 'Paused',
                      tracks: _sectionTracks('paused'),
                      allowSelection: widget.allowSelection,
                      initialSelectedTrackId: widget.initialSelectedTrackId,
                      onTap: _openTrack,
                    ),
                  if (_sectionTracks('archived').isNotEmpty)
                    _TrackSection(
                      title: 'Archived',
                      tracks: _sectionTracks('archived'),
                      allowSelection: widget.allowSelection,
                      initialSelectedTrackId: widget.initialSelectedTrackId,
                      onTap: _openTrack,
                    ),
                ]),
              ),
            ),
        ],
      ),
    );
  }
}

class _TrackSection extends StatelessWidget {
  const _TrackSection({
    required this.title,
    required this.tracks,
    required this.allowSelection,
    required this.initialSelectedTrackId,
    required this.onTap,
  });

  final String title;
  final List<SageFocusTrack> tracks;
  final bool allowSelection;
  final String? initialSelectedTrackId;
  final ValueChanged<SageFocusTrack> onTap;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 18),
        Text(
          title.toUpperCase(),
          style: const TextStyle(
            color: JournalColors.textMuted,
            fontSize: 12,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.1,
          ),
        ),
        const SizedBox(height: 10),
        ...tracks.map(
          (track) => Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: GestureDetector(
              onTap: () => allowSelection
                  ? Navigator.pop(context, track)
                  : onTap(track),
              child: GlassCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            track.title,
                            style: const TextStyle(
                              color: JournalColors.textPrimary,
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        if (track.isPrimary)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: _withAlpha(JournalColors.accent, 0.16),
                              borderRadius: BorderRadius.circular(999),
                              border:
                                  Border.all(color: JournalColors.borderBright),
                            ),
                            child: const Text(
                              'Primary',
                              style: TextStyle(
                                color: JournalColors.accent,
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          )
                        else if (allowSelection &&
                            initialSelectedTrackId == track.id)
                          const Icon(
                            CupertinoIcons.check_mark_circled_solid,
                            color: JournalColors.accent,
                          ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _labelForCategory(track.category),
                      style: const TextStyle(
                        color: JournalColors.info,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (track.currentGoal.trim().isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text(
                        track.currentGoal,
                        style: const TextStyle(
                          color: JournalColors.textPrimary,
                          fontSize: 14,
                          height: 1.45,
                        ),
                      ),
                    ],
                    if (track.nextCommitment.trim().isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text(
                        'Next: ${track.nextCommitment}',
                        style: const TextStyle(
                          color: JournalColors.textSecondary,
                          fontSize: 13,
                          height: 1.45,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _TrackDetailScreen extends StatefulWidget {
  const _TrackDetailScreen({required this.trackId});

  final String trackId;

  @override
  State<_TrackDetailScreen> createState() => _TrackDetailScreenState();
}

class _TrackDetailScreenState extends State<_TrackDetailScreen> {
  final _api = ApiService();
  final _dateFormat = DateFormat('MMM d, yyyy');

  SageFocusTrack? _track;
  bool _loading = true;
  bool _working = false;
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
      final track = await _api.getSageTrack(widget.trackId);
      if (!mounted) return;
      setState(() {
        _track = track;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  Future<void> _edit() async {
    final track = _track;
    if (track == null) return;
    final changed = await Navigator.push<bool>(
      context,
      CupertinoPageRoute(
        builder: (_) => _EditTrackScreen(track: track),
      ),
    );
    if (changed == true) {
      await _load();
      if (mounted) Navigator.pop(context, true);
    }
  }

  Future<void> _newCheckIn() async {
    final track = _track;
    if (track == null) return;
    final saved = await Navigator.push<bool>(
      context,
      CupertinoPageRoute(
        builder: (_) => _CheckInScreen(track: track),
      ),
    );
    if (saved == true) {
      await _load();
      if (mounted) Navigator.pop(context, true);
    }
  }

  Future<void> _setPrimary() async {
    final track = _track;
    if (track == null || _working) return;
    setState(() => _working = true);
    try {
      final updated = await _api.setPrimarySageTrack(track.id);
      if (!mounted) return;
      setState(() {
        _track = updated;
        _working = false;
      });
      Navigator.pop(context, true);
    } catch (_) {
      if (!mounted) return;
      setState(() => _working = false);
    }
  }

  Future<void> _changeStatus(String action) async {
    final track = _track;
    if (track == null || _working) return;
    setState(() => _working = true);
    try {
      SageFocusTrack updated;
      switch (action) {
        case 'pause':
          updated = await _api.pauseSageTrack(track.id);
          break;
        case 'resume':
          updated = await _api.resumeSageTrack(track.id);
          break;
        case 'archive':
          updated = await _api.archiveSageTrack(track.id);
          break;
        default:
          updated = track;
      }
      if (!mounted) return;
      setState(() {
        _track = updated;
        _working = false;
      });
      Navigator.pop(context, true);
    } catch (_) {
      if (!mounted) return;
      setState(() => _working = false);
    }
  }

  Future<void> _delete() async {
    final track = _track;
    if (track == null) return;
    final confirm = await showCupertinoDialog<bool>(
      context: context,
      builder: (_) => CupertinoAlertDialog(
        title: const Text('Delete focus track'),
        content: Text('Forget "${track.title}" completely?'),
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
    if (confirm != true) return;
    await _api.deleteSageTrack(track.id);
    if (!mounted) return;
    Navigator.pop(context, true);
  }

  String _formatDate(String? value) {
    if (value == null || value.trim().isEmpty) return 'No check-in yet';
    final parsed = DateTime.tryParse(value);
    if (parsed == null) return value;
    return _dateFormat.format(parsed.toLocal());
  }

  @override
  Widget build(BuildContext context) {
    final track = _track;
    return CupertinoPageScaffold(
      backgroundColor: JournalColors.bgBase,
      child: CustomScrollView(
        slivers: [
          CupertinoSliverNavigationBar(
            largeTitle: Text(track?.title ?? 'Track'),
            previousPageTitle: 'Tracks',
            trailing: CupertinoButton(
              padding: EdgeInsets.zero,
              minimumSize: const Size(0, 32),
              onPressed: _loading ? null : _edit,
              child: const Text(
                'Edit',
                style: TextStyle(
                  color: JournalColors.accent,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            backgroundColor: JournalColors.bgBase.withValues(alpha: 0.92),
            border: const Border(
              bottom: BorderSide(color: JournalColors.border, width: 0.5),
            ),
          ),
          if (_loading)
            const SliverFillRemaining(
              child: Center(
                child: CupertinoActivityIndicator(color: JournalColors.accent),
              ),
            )
          else if (track == null)
            SliverFillRemaining(
              child: Center(
                child: Text(
                  _error ?? 'Track not found.',
                  style: const TextStyle(color: JournalColors.textSecondary),
                ),
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
              sliver: SliverList(
                delegate: SliverChildListDelegate([
                  GlassCard(
                    accentBorder: true,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                _labelForCategory(track.category),
                                style: const TextStyle(
                                  color: JournalColors.info,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                            Text(
                              _formatDate(track.lastCheckInAt),
                              style: const TextStyle(
                                color: JournalColors.textMuted,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        if (track.currentGoal.trim().isNotEmpty)
                          _DetailBlock(
                            title: 'Current Goal',
                            text: track.currentGoal,
                          ),
                        if (track.whyThisMatters.trim().isNotEmpty)
                          _DetailBlock(
                            title: 'Why This Matters',
                            text: track.whyThisMatters,
                          ),
                        if (track.nextCommitment.trim().isNotEmpty)
                          _DetailBlock(
                            title: 'Next Commitment',
                            text: track.nextCommitment,
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 18),
                  Row(
                    children: [
                      Expanded(
                        child: CupertinoButton(
                          color: JournalColors.accent,
                          onPressed: _working ? null : _newCheckIn,
                          child: const Text(
                            'Check In Now',
                            style: TextStyle(color: JournalColors.textPrimary),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  if (track.recentWins.isNotEmpty)
                    _StringListCard(title: 'Recent Wins', items: track.recentWins),
                  if (track.stuckPoints.isNotEmpty)
                    _StringListCard(title: 'Stuck Points', items: track.stuckPoints),
                  if (track.openLoops.isNotEmpty)
                    _StringListCard(title: 'Open Loops', items: track.openLoops),
                  if (track.checkIns.isNotEmpty)
                    _CheckInListCard(checkIns: track.checkIns),
                  const SizedBox(height: 18),
                  GlassCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Manage',
                          style: TextStyle(
                            color: JournalColors.textPrimary,
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 12),
                        if (!track.isPrimary && track.status == 'active')
                          _ManageRow(
                            label: 'Set as primary track',
                            onTap: _setPrimary,
                          ),
                        if (track.status == 'active')
                          _ManageRow(
                            label: 'Pause track',
                            onTap: () => _changeStatus('pause'),
                          ),
                        if (track.status == 'paused')
                          _ManageRow(
                            label: 'Resume track',
                            onTap: () => _changeStatus('resume'),
                          ),
                        if (track.status != 'archived')
                          _ManageRow(
                            label: 'Archive track',
                            onTap: () => _changeStatus('archive'),
                          ),
                        _ManageRow(
                          label: 'Delete track',
                          destructive: true,
                          onTap: _delete,
                        ),
                      ],
                    ),
                  ),
                ]),
              ),
            ),
        ],
      ),
    );
  }
}

class _EditTrackScreen extends StatefulWidget {
  const _EditTrackScreen({this.track});

  final SageFocusTrack? track;

  @override
  State<_EditTrackScreen> createState() => _EditTrackScreenState();
}

class _EditTrackScreenState extends State<_EditTrackScreen> {
  final _api = ApiService();
  final _titleCtrl = TextEditingController();
  final _goalCtrl = TextEditingController();
  final _whyCtrl = TextEditingController();
  final _stuckCtrl = TextEditingController();
  final _winsCtrl = TextEditingController();
  final _loopsCtrl = TextEditingController();
  final _nextCtrl = TextEditingController();
  final _markersCtrl = TextEditingController();

  late String _category;
  late String _cadence;
  bool _isPrimary = false;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final track = widget.track;
    _category = track?.category ?? 'general';
    _cadence = track?.checkInCadence ?? 'weekly';
    _isPrimary = track?.isPrimary ?? false;
    _titleCtrl.text = track?.title ?? '';
    _goalCtrl.text = track?.currentGoal ?? '';
    _whyCtrl.text = track?.whyThisMatters ?? '';
    _stuckCtrl.text = track?.stuckPoints.join('\n') ?? '';
    _winsCtrl.text = track?.recentWins.join('\n') ?? '';
    _loopsCtrl.text = track?.openLoops.join('\n') ?? '';
    _nextCtrl.text = track?.nextCommitment ?? '';
    _markersCtrl.text = track?.successMarkers.join('\n') ?? '';
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _goalCtrl.dispose();
    _whyCtrl.dispose();
    _stuckCtrl.dispose();
    _winsCtrl.dispose();
    _loopsCtrl.dispose();
    _nextCtrl.dispose();
    _markersCtrl.dispose();
    super.dispose();
  }

  List<String> _lines(TextEditingController controller) {
    return controller.text
        .split('\n')
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .toList();
  }

  Future<void> _save() async {
    if (_saving) return;
    if (_titleCtrl.text.trim().isEmpty || _goalCtrl.text.trim().isEmpty) {
      setState(() => _error = 'Title and current goal are required.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    final body = <String, dynamic>{
      'title': _titleCtrl.text.trim(),
      'category': _category,
      'check_in_cadence': _cadence,
      'current_goal': _goalCtrl.text.trim(),
      'why_this_matters': _whyCtrl.text.trim(),
      'stuck_points': _lines(_stuckCtrl),
      'recent_wins': _lines(_winsCtrl),
      'open_loops': _lines(_loopsCtrl),
      'next_commitment': _nextCtrl.text.trim(),
      'success_markers': _lines(_markersCtrl),
      'is_primary': _isPrimary,
    };

    try {
      if (widget.track == null) {
        await _api.createSageTrack(body);
      } else {
        await _api.updateSageTrack(widget.track!.id, body);
      }
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = e.toString();
      });
    }
  }

  Widget _field(
    String label,
    TextEditingController controller, {
    int minLines = 1,
    int maxLines = 3,
    String? placeholder,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label.toUpperCase(),
            style: const TextStyle(
              color: JournalColors.textMuted,
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.0,
            ),
          ),
          const SizedBox(height: 8),
          CupertinoTextField(
            controller: controller,
            placeholder: placeholder,
            minLines: minLines,
            maxLines: maxLines,
            padding: const EdgeInsets.all(14),
            style: const TextStyle(
              color: JournalColors.textPrimary,
              fontSize: 15,
            ),
            placeholderStyle: const TextStyle(
              color: JournalColors.textMuted,
              fontSize: 15,
            ),
            decoration: BoxDecoration(
              color: JournalColors.bgSurface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: JournalColors.border),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isEditing = widget.track != null;
    return CupertinoPageScaffold(
      backgroundColor: JournalColors.bgBase,
      child: CustomScrollView(
        slivers: [
          CupertinoSliverNavigationBar(
            largeTitle: Text(isEditing ? 'Edit Track' : 'New Track'),
            previousPageTitle: 'Tracks',
            trailing: CupertinoButton(
              padding: EdgeInsets.zero,
              minimumSize: const Size(0, 32),
              onPressed: _saving ? null : _save,
              child: Text(
                _saving ? 'Saving…' : 'Save',
                style: const TextStyle(
                  color: JournalColors.accent,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            backgroundColor: JournalColors.bgBase.withValues(alpha: 0.92),
            border: const Border(
              bottom: BorderSide(color: JournalColors.border, width: 0.5),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                GlassCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'You control this memory. Edit, pause, or delete it anytime.',
                        style: TextStyle(
                          color: JournalColors.textSecondary,
                          fontSize: 13,
                          height: 1.45,
                        ),
                      ),
                      if (_error != null) ...[
                        const SizedBox(height: 12),
                        Text(
                          _error!,
                          style: const TextStyle(
                            color: JournalColors.danger,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 18),
                _field('Title', _titleCtrl, placeholder: 'Breakup recovery'),
                _field('Current Goal', _goalCtrl,
                    minLines: 2,
                    maxLines: 4,
                    placeholder: 'What are you trying to do right now?'),
                _field('Why This Matters', _whyCtrl, minLines: 2, maxLines: 4),
                _field('Stuck Points', _stuckCtrl,
                    minLines: 3,
                    maxLines: 5,
                    placeholder: 'One per line'),
                _field('Recent Wins', _winsCtrl,
                    minLines: 3,
                    maxLines: 5,
                    placeholder: 'One per line'),
                _field('Open Loops', _loopsCtrl,
                    minLines: 3,
                    maxLines: 5,
                    placeholder: 'One per line'),
                _field('Next Commitment', _nextCtrl,
                    minLines: 2, maxLines: 4),
                _field('Success Markers', _markersCtrl,
                    minLines: 3,
                    maxLines: 5,
                    placeholder: 'One per line'),
                GlassCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Category',
                        style: TextStyle(
                          color: JournalColors.textPrimary,
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: _kTrackCategories
                            .map(
                              (item) => _ChoiceChip(
                                label: item.label,
                                active: _category == item.id,
                                onTap: () => setState(() => _category = item.id),
                              ),
                            )
                            .toList(),
                      ),
                      const SizedBox(height: 18),
                      const Text(
                        'Check-in cadence',
                        style: TextStyle(
                          color: JournalColors.textPrimary,
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: _kTrackCadences
                            .map(
                              (item) => _ChoiceChip(
                                label: item.label,
                                active: _cadence == item.id,
                                onTap: () => setState(() => _cadence = item.id),
                              ),
                            )
                            .toList(),
                      ),
                      const SizedBox(height: 18),
                      Row(
                        children: [
                          const Expanded(
                            child: Text(
                              'Set as primary track',
                              style: TextStyle(
                                color: JournalColors.textPrimary,
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          CupertinoSwitch(
                            value: _isPrimary,
                            onChanged: (value) =>
                                setState(() => _isPrimary = value),
                            activeTrackColor: JournalColors.accent,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ]),
            ),
          ),
        ],
      ),
    );
  }
}

class _CheckInScreen extends StatefulWidget {
  const _CheckInScreen({required this.track});

  final SageFocusTrack track;

  @override
  State<_CheckInScreen> createState() => _CheckInScreenState();
}

class _CheckInScreenState extends State<_CheckInScreen> {
  final _api = ApiService();
  final _moodCtrl = TextEditingController();
  final _whatCtrl = TextEditingController();
  final _winCtrl = TextEditingController();
  final _hardCtrl = TextEditingController();
  final _nextCtrl = TextEditingController();

  String _progress = 'mixed';
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _moodCtrl.dispose();
    _whatCtrl.dispose();
    _winCtrl.dispose();
    _hardCtrl.dispose();
    _nextCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving) return;
    if (_whatCtrl.text.trim().isEmpty) {
      setState(() => _error = 'Say what happened in this check-in.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await _api.createSageTrackCheckIn(widget.track.id, {
        'source': 'manual',
        'mood_label': _moodCtrl.text.trim(),
        'progress_status': _progress,
        'what_happened': _whatCtrl.text.trim(),
        'win': _winCtrl.text.trim(),
        'hard_part': _hardCtrl.text.trim(),
        'next_step': _nextCtrl.text.trim(),
        'user_confirmed': true,
      });
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = e.toString();
      });
    }
  }

  Widget _field(
    String label,
    TextEditingController controller, {
    int minLines = 2,
    int maxLines = 4,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label.toUpperCase(),
            style: const TextStyle(
              color: JournalColors.textMuted,
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.0,
            ),
          ),
          const SizedBox(height: 8),
          CupertinoTextField(
            controller: controller,
            minLines: minLines,
            maxLines: maxLines,
            padding: const EdgeInsets.all(14),
            style: const TextStyle(
              color: JournalColors.textPrimary,
              fontSize: 15,
            ),
            placeholderStyle: const TextStyle(
              color: JournalColors.textMuted,
              fontSize: 15,
            ),
            decoration: BoxDecoration(
              color: JournalColors.bgSurface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: JournalColors.border),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return CupertinoPageScaffold(
      backgroundColor: JournalColors.bgBase,
      child: CustomScrollView(
        slivers: [
          CupertinoSliverNavigationBar(
            largeTitle: const Text('Track Check-In'),
            previousPageTitle: 'Track',
            trailing: CupertinoButton(
              padding: EdgeInsets.zero,
              minimumSize: const Size(0, 32),
              onPressed: _saving ? null : _save,
              child: Text(
                _saving ? 'Saving…' : 'Save',
                style: const TextStyle(
                  color: JournalColors.accent,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            backgroundColor: JournalColors.bgBase.withValues(alpha: 0.92),
            border: const Border(
              bottom: BorderSide(color: JournalColors.border, width: 0.5),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                GlassCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.track.title,
                        style: const TextStyle(
                          color: JournalColors.textPrimary,
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        widget.track.currentGoal,
                        style: const TextStyle(
                          color: JournalColors.textSecondary,
                          fontSize: 13,
                          height: 1.45,
                        ),
                      ),
                      if (_error != null) ...[
                        const SizedBox(height: 12),
                        Text(
                          _error!,
                          style: const TextStyle(
                            color: JournalColors.danger,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 18),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: const [
                    ('improving', 'Improving'),
                    ('mixed', 'Mixed'),
                    ('stuck', 'Stuck'),
                  ]
                      .map(
                        (item) => const SizedBox(),
                      )
                      .toList(),
                ),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _ChoiceChip(
                      label: 'Improving',
                      active: _progress == 'improving',
                      onTap: () => setState(() => _progress = 'improving'),
                    ),
                    _ChoiceChip(
                      label: 'Mixed',
                      active: _progress == 'mixed',
                      onTap: () => setState(() => _progress = 'mixed'),
                    ),
                    _ChoiceChip(
                      label: 'Stuck',
                      active: _progress == 'stuck',
                      onTap: () => setState(() => _progress = 'stuck'),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                _field('How are you doing?', _moodCtrl, minLines: 1, maxLines: 2),
                _field('What happened?', _whatCtrl),
                _field('Win', _winCtrl, minLines: 1, maxLines: 3),
                _field('Hard part', _hardCtrl, minLines: 1, maxLines: 3),
                _field('Next step', _nextCtrl, minLines: 1, maxLines: 3),
              ]),
            ),
          ),
        ],
      ),
    );
  }
}

class _DetailBlock extends StatelessWidget {
  const _DetailBlock({
    required this.title,
    required this.text,
  });

  final String title;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title.toUpperCase(),
            style: const TextStyle(
              color: JournalColors.textMuted,
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.0,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            text,
            style: const TextStyle(
              color: JournalColors.textPrimary,
              fontSize: 14,
              height: 1.45,
            ),
          ),
        ],
      ),
    );
  }
}

class _StringListCard extends StatelessWidget {
  const _StringListCard({
    required this.title,
    required this.items,
  });

  final String title;
  final List<String> items;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: GlassCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(
                color: JournalColors.textPrimary,
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 10),
            ...items.take(6).map(
                  (item) => Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(
                      '• $item',
                      style: const TextStyle(
                        color: JournalColors.textSecondary,
                        fontSize: 14,
                        height: 1.45,
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

class _CheckInListCard extends StatelessWidget {
  const _CheckInListCard({required this.checkIns});

  final List<SageTrackCheckIn> checkIns;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: GlassCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Recent Check-Ins',
              style: TextStyle(
                color: JournalColors.textPrimary,
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 10),
            ...checkIns.take(5).map(
                  (item) => Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: JournalColors.bgSurface,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: JournalColors.border),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            item.whatHappened,
                            style: const TextStyle(
                              color: JournalColors.textPrimary,
                              fontSize: 14,
                              height: 1.45,
                            ),
                          ),
                          if (item.win.trim().isNotEmpty) ...[
                            const SizedBox(height: 6),
                            Text(
                              'Win: ${item.win}',
                              style: const TextStyle(
                                color: JournalColors.textSecondary,
                                fontSize: 13,
                              ),
                            ),
                          ],
                          if (item.nextStep.trim().isNotEmpty) ...[
                            const SizedBox(height: 4),
                            Text(
                              'Next: ${item.nextStep}',
                              style: const TextStyle(
                                color: JournalColors.info,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ],
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

class _ManageRow extends StatelessWidget {
  const _ManageRow({
    required this.label,
    required this.onTap,
    this.destructive = false,
  });

  final String label;
  final VoidCallback onTap;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          decoration: BoxDecoration(
            color: JournalColors.bgSurface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: JournalColors.border),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    color: destructive
                        ? JournalColors.danger
                        : JournalColors.textPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Icon(
                CupertinoIcons.chevron_right,
                color: destructive
                    ? JournalColors.danger
                    : JournalColors.textMuted,
                size: 16,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ChoiceChip extends StatelessWidget {
  const _ChoiceChip({
    required this.label,
    required this.active,
    required this.onTap,
  });

  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        decoration: BoxDecoration(
          color: active
              ? _withAlpha(JournalColors.accent, 0.16)
              : JournalColors.bgSurface,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: active ? JournalColors.borderBright : JournalColors.border,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: active
                ? JournalColors.textPrimary
                : JournalColors.textSecondary,
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

String _labelForCategory(String id) {
  for (final item in _kTrackCategories) {
    if (item.id == id) return item.label;
  }
  return id.replaceAll('_', ' ');
}
