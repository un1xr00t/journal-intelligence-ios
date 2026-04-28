import 'package:adaptive_platform_ui/adaptive_platform_ui.dart';
import 'package:flutter/cupertino.dart';

import '../services/notification_nudge_service.dart';
import '../theme/app_theme.dart';
import '../widgets/glass_card.dart';

Color _withAlpha(Color color, double alpha) => color.withValues(alpha: alpha);

class NotificationNudgesScreen extends StatefulWidget {
  const NotificationNudgesScreen({super.key});

  @override
  State<NotificationNudgesScreen> createState() =>
      _NotificationNudgesScreenState();
}

class _NotificationNudgesScreenState extends State<NotificationNudgesScreen> {
  final _service = NotificationNudgeService();

  NotificationNudgeSettings _settings = NotificationNudgeSettings.defaults();
  NotificationBridgeStatus? _status;
  bool _loading = true;
  bool _syncing = false;
  bool _capturingPlace = false;
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
      final results = await Future.wait([
        _service.loadSettings(),
        _service.getStatus(),
      ]);
      if (!mounted) return;
      setState(() {
        _settings = results[0] as NotificationNudgeSettings;
        _status = results[1] as NotificationBridgeStatus;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = _friendlyError(e);
        _loading = false;
      });
    }
  }

  Future<void> _requestNotificationPermission() async {
    try {
      final status = await _service.requestNotificationPermission();
      if (!mounted) return;
      setState(() => _status = status);
    } catch (e) {
      _showMessage('Could not request notification permission.', details: e);
    }
  }

  Future<void> _requestLocationPermission() async {
    try {
      final status = await _service.requestLocationPermission();
      if (!mounted) return;
      setState(() => _status = status);
    } catch (e) {
      _showMessage('Could not request location permission.', details: e);
    }
  }

  Future<void> _updateSettings(NotificationNudgeSettings nextSettings) async {
    setState(() {
      _syncing = true;
      _settings = nextSettings;
      _error = null;
    });

    try {
      await _service.syncSchedules(nextSettings);
      final status = await _service.getStatus();
      if (!mounted) return;
      setState(() {
        _status = status;
        _syncing = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _syncing = false);
      _showMessage('Could not update your nudges.', details: e);
      _load();
    }
  }

  Future<void> _pickTime({
    required String title,
    required int initialHour,
    required int initialMinute,
    required void Function(int hour, int minute) onSelected,
  }) async {
    var selected = DateTime(
      2024,
      1,
      1,
      initialHour,
      initialMinute,
    );

    final picked = await showCupertinoModalPopup<DateTime>(
      context: context,
      builder: (context) {
        return DefaultTextStyle.merge(
          style: const TextStyle(decoration: TextDecoration.none),
          child: Container(
            height: 320,
            color: JournalColors.bgCard,
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
                  child: Row(
                    children: [
                      CupertinoButton(
                        padding: EdgeInsets.zero,
                        onPressed: () => Navigator.of(context).pop(),
                        child: const Text(
                          'Cancel',
                          style: TextStyle(color: JournalColors.textSecondary),
                        ),
                      ),
                      Expanded(
                        child: Text(
                          title,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: JournalColors.textPrimary,
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      CupertinoButton(
                        padding: EdgeInsets.zero,
                        onPressed: () => Navigator.of(context).pop(selected),
                        child: const Text(
                          'Done',
                          style: TextStyle(color: JournalColors.accent),
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: CupertinoDatePicker(
                    mode: CupertinoDatePickerMode.time,
                    initialDateTime: selected,
                    use24hFormat: false,
                    onDateTimeChanged: (value) => selected = value,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );

    if (picked == null) return;
    onSelected(picked.hour, picked.minute);
  }

  Future<void> _addPlace() async {
    final status = _status;
    if (status == null) return;

    if (!status.notificationsAuthorized) {
      _showMessage('Turn on notifications first so iPhone can show the nudge.');
      return;
    }

    if (!status.locationAuthorized) {
      await _requestLocationPermission();
      if (!mounted || !(_status?.locationAuthorized ?? false)) return;
    }

    final nameController = TextEditingController();
    final enteredPlaceName = await showCupertinoDialog<String>(
      context: context,
      builder: (context) {
        return DefaultTextStyle.merge(
          style: const TextStyle(decoration: TextDecoration.none),
          child: CupertinoAlertDialog(
            title: const Text('Save This Place'),
            content: Column(
              children: [
                const SizedBox(height: 8),
                const Text(
                  'Stand where you want the nudge to trigger. You can name it yourself or let the app suggest a place name from your current location.',
                  style: TextStyle(fontSize: 13),
                ),
                const SizedBox(height: 12),
                CupertinoTextField(
                  controller: nameController,
                  placeholder: 'Optional: Boyce Park, Soccer Field, Home...',
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: JournalColors.bgSurface,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: JournalColors.border),
                  ),
                  style: const TextStyle(color: JournalColors.textPrimary),
                  placeholderStyle:
                      const TextStyle(color: JournalColors.textMuted),
                  autofocus: true,
                ),
              ],
            ),
            actions: [
              CupertinoDialogAction(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Cancel'),
              ),
              CupertinoDialogAction(
                onPressed: () =>
                    Navigator.of(context).pop(nameController.text.trim()),
                child: const Text('Use Current Spot'),
              ),
            ],
          ),
        );
      },
    );
    nameController.dispose();

    if (enteredPlaceName == null) return;

    setState(() => _capturingPlace = true);
    try {
      final location = await _service.getCurrentLocationDetails();
      final suggestedName = location['placeName']?.toString().trim() ?? '';
      final finalPlaceName = enteredPlaceName.trim().isNotEmpty
          ? enteredPlaceName.trim()
          : (suggestedName.isNotEmpty ? suggestedName : 'Saved Place');
      final nextPlaces = [
        ..._settings.places,
        NudgePlace(
          id: DateTime.now().microsecondsSinceEpoch.toString(),
          name: finalPlaceName,
          latitude: location['latitude'] ?? 0,
          longitude: location['longitude'] ?? 0,
        ),
      ];
      if (!mounted) return;
      setState(() => _capturingPlace = false);
      await _updateSettings(_settings.copyWith(places: nextPlaces));
    } catch (e) {
      if (!mounted) return;
      setState(() => _capturingPlace = false);
      _showMessage('Could not capture your current location.', details: e);
    }
  }

  Future<void> _removePlace(NudgePlace place) async {
    final confirmed = await showCupertinoDialog<bool>(
      context: context,
      builder: (context) {
        return DefaultTextStyle.merge(
          style: const TextStyle(decoration: TextDecoration.none),
          child: CupertinoAlertDialog(
            title: const Text('Remove Place?'),
            content: Text('Stop location nudges for ${place.name}?'),
            actions: [
              CupertinoDialogAction(
                isDestructiveAction: true,
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('Remove'),
              ),
              CupertinoDialogAction(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Cancel'),
              ),
            ],
          ),
        );
      },
    );

    if (confirmed != true) return;
    final nextPlaces =
        _settings.places.where((saved) => saved.id != place.id).toList();
    await _updateSettings(_settings.copyWith(places: nextPlaces));
  }

  void _showMessage(String message, {Object? details}) {
    final detailText = details == null ? null : _friendlyError(details);
    showCupertinoDialog<void>(
      context: context,
      builder: (context) {
        return DefaultTextStyle.merge(
          style: const TextStyle(decoration: TextDecoration.none),
          child: CupertinoAlertDialog(
            title: const Text('Notification Nudges'),
            content: Text(
              detailText == null ? message : '$message\n\n$detailText',
            ),
            actions: [
              CupertinoDialogAction(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('OK'),
              ),
            ],
          ),
        );
      },
    );
  }

  String _friendlyError(Object error) {
    final text = error.toString();
    final detailMatch =
        RegExp(r'"message":\s*"([^"]+)"').firstMatch(text)?.group(1);
    if (detailMatch != null && detailMatch.isNotEmpty) return detailMatch;
    if (text.contains('location_permission_denied')) {
      return 'Location permission is off. Enable it in Settings to save places.';
    }
    if (text.contains('notification_permission_failed')) {
      return 'Notification permission could not be requested right now.';
    }
    return text;
  }

  String _formatTime(int hour, int minute) {
    final normalizedHour = hour % 24;
    final period = normalizedHour >= 12 ? 'PM' : 'AM';
    final twelveHour = normalizedHour % 12 == 0 ? 12 : normalizedHour % 12;
    final minuteLabel = minute.toString().padLeft(2, '0');
    return '$twelveHour:$minuteLabel $period';
  }

  @override
  Widget build(BuildContext context) {
    return CupertinoPageScaffold(
      backgroundColor: JournalColors.bgBase,
      child: Stack(
        children: [
          const Positioned.fill(child: _NudgesBackdrop()),
          CustomScrollView(
            slivers: [
              CupertinoSliverNavigationBar(
                largeTitle: const Text('Notification Nudges'),
                backgroundColor: _withAlpha(JournalColors.bgBase, 0.9),
                border: const Border(
                  bottom: BorderSide(color: JournalColors.border, width: 0.5),
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
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            CupertinoIcons.exclamationmark_triangle,
                            color: JournalColors.textMuted,
                            size: 26,
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
                          const SizedBox(height: 18),
                          CupertinoButton(
                            onPressed: _load,
                            child: const Text(
                              'Try Again',
                              style: TextStyle(color: JournalColors.accent),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                )
              else
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(20, 10, 20, 28),
                  sliver: SliverList(
                    delegate: SliverChildListDelegate([
                      _HeroCard(
                        syncing: _syncing,
                        capturingPlace: _capturingPlace,
                      ),
                      const SizedBox(height: 20),
                      _PermissionCard(
                        status: _status!,
                        onRequestNotifications: _requestNotificationPermission,
                        onRequestLocation: _requestLocationPermission,
                      ),
                      const SizedBox(height: 20),
                      const _SectionTitle(
                        title: 'Time Nudges',
                        subtitle:
                            'Recurring reminders that work fully on-device.',
                      ),
                      const SizedBox(height: 10),
                      GlassCard(
                        child: Column(
                          children: [
                            _ToggleRow(
                              icon: CupertinoIcons.sun_max_fill,
                              iconColor: JournalColors.severity,
                              title: 'Morning Check-In',
                              subtitle:
                                  'Prompt yourself to name what feels heavy, hopeful, or unfinished.',
                              value: _settings.morningPromptEnabled,
                              onChanged: (value) => _updateSettings(
                                _settings.copyWith(morningPromptEnabled: value),
                              ),
                            ),
                            const _Divider(),
                            _ActionRow(
                              icon: CupertinoIcons.time,
                              iconColor: JournalColors.info,
                              title: 'Morning Time',
                              subtitle: _formatTime(_settings.morningHour,
                                  _settings.morningMinute),
                              trailingText: 'Edit',
                              onTap: () => _pickTime(
                                title: 'Morning Time',
                                initialHour: _settings.morningHour,
                                initialMinute: _settings.morningMinute,
                                onSelected: (hour, minute) => _updateSettings(
                                  _settings.copyWith(
                                    morningHour: hour,
                                    morningMinute: minute,
                                  ),
                                ),
                              ),
                            ),
                            const _Divider(),
                            _ToggleRow(
                              icon: CupertinoIcons.moon_stars_fill,
                              iconColor: JournalColors.accent2,
                              title: 'Evening Wrap-Up',
                              subtitle:
                                  'Catch what mattered today before it disappears.',
                              value: _settings.eveningPromptEnabled,
                              onChanged: (value) => _updateSettings(
                                _settings.copyWith(eveningPromptEnabled: value),
                              ),
                            ),
                            const _Divider(),
                            _ActionRow(
                              icon: CupertinoIcons.time,
                              iconColor: JournalColors.info,
                              title: 'Evening Time',
                              subtitle: _formatTime(_settings.eveningHour,
                                  _settings.eveningMinute),
                              trailingText: 'Edit',
                              onTap: () => _pickTime(
                                title: 'Evening Time',
                                initialHour: _settings.eveningHour,
                                initialMinute: _settings.eveningMinute,
                                onSelected: (hour, minute) => _updateSettings(
                                  _settings.copyWith(
                                    eveningHour: hour,
                                    eveningMinute: minute,
                                  ),
                                ),
                              ),
                            ),
                            const _Divider(),
                            _ToggleRow(
                              icon: CupertinoIcons.heart_fill,
                              iconColor: JournalColors.success,
                              title: 'Weekly Wyatt Nudge',
                              subtitle:
                                  'A weekly reminder to capture an activity or memory with Wyatt.',
                              value: _settings.weeklyWyattPromptEnabled,
                              onChanged: (value) => _updateSettings(
                                _settings.copyWith(
                                  weeklyWyattPromptEnabled: value,
                                ),
                              ),
                            ),
                            const _Divider(),
                            _ActionRow(
                              icon: CupertinoIcons.time,
                              iconColor: JournalColors.info,
                              title: 'Weekly Wyatt Time',
                              subtitle: _formatTime(
                                  _settings.weeklyHour, _settings.weeklyMinute),
                              trailingText: 'Edit',
                              onTap: () => _pickTime(
                                title: 'Weekly Wyatt Time',
                                initialHour: _settings.weeklyHour,
                                initialMinute: _settings.weeklyMinute,
                                onSelected: (hour, minute) => _updateSettings(
                                  _settings.copyWith(
                                    weeklyHour: hour,
                                    weeklyMinute: minute,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),
                      const _SectionTitle(
                        title: 'Location Nudges',
                        subtitle:
                            'Save parks, home, school, or other places and fire a local reminder when you arrive.',
                      ),
                      const SizedBox(height: 10),
                      GlassCard(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _ToggleRow(
                              icon: CupertinoIcons.location_solid,
                              iconColor: JournalColors.orange,
                              title: 'Location Prompts',
                              subtitle:
                                  'Show a lock-screen reminder when you arrive at saved places.',
                              value: _settings.locationPromptsEnabled,
                              onChanged: (value) => _updateSettings(
                                _settings.copyWith(
                                    locationPromptsEnabled: value),
                              ),
                            ),
                            const _Divider(),
                            Padding(
                              padding:
                                  const EdgeInsets.fromLTRB(16, 14, 16, 16),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'Saved Places',
                                    style: TextStyle(
                                      color: JournalColors.textPrimary,
                                      fontSize: 15,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  const Text(
                                    'Stand at the place first, then save it. Each place uses a local geofence, opens Write on the main tap, and includes an Ask Sage notification action for live place lookup when web search is enabled.',
                                    style: TextStyle(
                                      color: JournalColors.textSecondary,
                                      fontSize: 13,
                                      height: 1.45,
                                    ),
                                  ),
                                  const SizedBox(height: 14),
                                  if (_settings.places.isEmpty)
                                    Container(
                                      width: double.infinity,
                                      padding: const EdgeInsets.all(14),
                                      decoration: BoxDecoration(
                                        color: _withAlpha(
                                          JournalColors.bgSurface,
                                          0.72,
                                        ),
                                        borderRadius: BorderRadius.circular(16),
                                        border: Border.all(
                                          color: JournalColors.border,
                                        ),
                                      ),
                                      child: const Text(
                                        'No places saved yet. Add one while you are physically at the park, home, gym, school, or wherever you want the reminder to trigger.',
                                        style: TextStyle(
                                          color: JournalColors.textSecondary,
                                          fontSize: 13,
                                          height: 1.45,
                                        ),
                                      ),
                                    )
                                  else
                                    ..._settings.places.map(
                                      (place) => Padding(
                                        padding:
                                            const EdgeInsets.only(bottom: 10),
                                        child: _PlaceRow(
                                          place: place,
                                          onRemove: () => _removePlace(place),
                                        ),
                                      ),
                                    ),
                                  const SizedBox(height: 8),
                                  AdaptiveButton(
                                    style: AdaptiveButtonStyle.prominentGlass,
                                    onPressed:
                                        _capturingPlace ? null : _addPlace,
                                    label: _capturingPlace
                                        ? 'Saving Current Spot...'
                                        : 'Add Current Location',
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 18),
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: _withAlpha(JournalColors.info, 0.08),
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(
                            color: _withAlpha(JournalColors.info, 0.22),
                          ),
                        ),
                        child: const Text(
                          'These are local iPhone notifications, so they can appear on your lock screen like normal alerts. Timing can still vary a bit because iOS applies heuristics for location triggers and respects Focus / notification settings.',
                          style: TextStyle(
                            color: JournalColors.textSecondary,
                            fontSize: 13,
                            height: 1.5,
                          ),
                        ),
                      ),
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

class _HeroCard extends StatelessWidget {
  const _HeroCard({
    required this.syncing,
    required this.capturingPlace,
  });

  final bool syncing;
  final bool capturingPlace;

  @override
  Widget build(BuildContext context) {
    final statusText = capturingPlace
        ? 'Capturing your current spot...'
        : syncing
            ? 'Updating your nudges...'
            : 'These reminders stay on your phone and do not need APNs.';

    return GlassCard(
      accentBorder: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: _withAlpha(JournalColors.accent, 0.18),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: JournalColors.borderBright),
                ),
                child: const Icon(
                  CupertinoIcons.bell_fill,
                  color: JournalColors.textPrimary,
                ),
              ),
              const SizedBox(width: 14),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'LOCK-SCREEN NUDGES',
                      style: TextStyle(
                        color: JournalColors.textMuted,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.2,
                      ),
                    ),
                    SizedBox(height: 4),
                    Text(
                      'Location prompts, Wyatt reminders, and simple journaling nudges.',
                      style: TextStyle(
                        color: JournalColors.textPrimary,
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        height: 1.25,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            statusText,
            style: const TextStyle(
              color: JournalColors.textSecondary,
              fontSize: 14,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }
}

class _PermissionCard extends StatelessWidget {
  const _PermissionCard({
    required this.status,
    required this.onRequestNotifications,
    required this.onRequestLocation,
  });

  final NotificationBridgeStatus status;
  final VoidCallback onRequestNotifications;
  final VoidCallback onRequestLocation;

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      child: Column(
        children: [
          _PermissionRow(
            icon: CupertinoIcons.bell_circle_fill,
            iconColor: JournalColors.accent,
            title: 'Notifications',
            subtitle: status.notificationsAuthorized
                ? 'Enabled for lock-screen and banner delivery.'
                : 'Required for local reminders to show up on your phone.',
            statusLabel:
                status.notificationsAuthorized ? 'Allowed' : 'Needs Access',
            statusColor: status.notificationsAuthorized
                ? JournalColors.success
                : JournalColors.severity,
            actionLabel: status.notificationsAuthorized ? 'Refresh' : 'Enable',
            onTap: onRequestNotifications,
          ),
          const _Divider(),
          _PermissionRow(
            icon: CupertinoIcons.location_fill,
            iconColor: JournalColors.orange,
            title: 'Location',
            subtitle: status.locationAuthorized
                ? 'Ready for saved-place arrival prompts.'
                : 'Needed only for geofence nudges.',
            statusLabel: status.locationAuthorized ? 'Allowed' : 'Needs Access',
            statusColor: status.locationAuthorized
                ? JournalColors.success
                : JournalColors.severity,
            actionLabel: status.locationAuthorized ? 'Refresh' : 'Enable',
            onTap: onRequestLocation,
          ),
        ],
      ),
    );
  }
}

class _PermissionRow extends StatelessWidget {
  const _PermissionRow({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    required this.statusLabel,
    required this.statusColor,
    required this.actionLabel,
    required this.onTap,
  });

  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;
  final String statusLabel;
  final Color statusColor;
  final String actionLabel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: _withAlpha(iconColor, 0.14),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: iconColor, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: JournalColors.textPrimary,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  subtitle,
                  style: const TextStyle(
                    color: JournalColors.textSecondary,
                    fontSize: 12,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: _withAlpha(statusColor, 0.14),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  statusLabel,
                  style: TextStyle(
                    color: statusColor,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              GestureDetector(
                onTap: onTap,
                child: Text(
                  actionLabel,
                  style: const TextStyle(
                    color: JournalColors.accent,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({
    required this.title,
    required this.subtitle,
  });

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title.toUpperCase(),
          style: const TextStyle(
            color: JournalColors.textMuted,
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.2,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          subtitle,
          style: const TextStyle(
            color: JournalColors.textSecondary,
            fontSize: 13,
            height: 1.45,
          ),
        ),
      ],
    );
  }
}

class _ToggleRow extends StatelessWidget {
  const _ToggleRow({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: _withAlpha(iconColor, 0.14),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: iconColor, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: JournalColors.textPrimary,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  subtitle,
                  style: const TextStyle(
                    color: JournalColors.textSecondary,
                    fontSize: 12,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          CupertinoSwitch(
            value: value,
            onChanged: onChanged,
            activeTrackColor: JournalColors.accent,
          ),
        ],
      ),
    );
  }
}

class _ActionRow extends StatelessWidget {
  const _ActionRow({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    required this.trailingText,
    required this.onTap,
  });

  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;
  final String trailingText;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: _withAlpha(iconColor, 0.14),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: iconColor, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      color: JournalColors.textPrimary,
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      color: JournalColors.textSecondary,
                      fontSize: 12,
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Text(
              trailingText,
              style: const TextStyle(
                color: JournalColors.accent,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PlaceRow extends StatelessWidget {
  const _PlaceRow({
    required this.place,
    required this.onRemove,
  });

  final NudgePlace place;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _withAlpha(JournalColors.bgSurface, 0.72),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: JournalColors.border),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: _withAlpha(JournalColors.orange, 0.16),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(
              CupertinoIcons.location_solid,
              color: JournalColors.orange,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  place.name,
                  style: const TextStyle(
                    color: JournalColors.textPrimary,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  'Radius ${place.radiusMeters.round()}m',
                  style: const TextStyle(
                    color: JournalColors.textSecondary,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          GestureDetector(
            onTap: onRemove,
            child: const Text(
              'Remove',
              style: TextStyle(
                color: JournalColors.danger,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Divider extends StatelessWidget {
  const _Divider();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 1,
      margin: const EdgeInsets.symmetric(horizontal: 14),
      color: JournalColors.border,
    );
  }
}

class _NudgesBackdrop extends StatelessWidget {
  const _NudgesBackdrop();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            JournalColors.bgBase,
            _withAlpha(JournalColors.bgCardAlt, 0.94),
            JournalColors.bgBase,
          ],
        ),
      ),
    );
  }
}
