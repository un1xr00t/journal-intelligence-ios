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

class _NotificationNudgesScreenState extends State<NotificationNudgesScreen>
    with WidgetsBindingObserver {
  final _service = NotificationNudgeService();

  NotificationNudgeSettings _settings = NotificationNudgeSettings.defaults();
  NotificationBridgeStatus? _status;
  JournalPatternProfile? _patternProfile;
  Map<String, dynamic>? _currentPlaceSuggestion;
  bool _loading = true;
  bool _syncing = false;
  bool _analyzingPatterns = false;
  bool _capturingPlace = false;
  bool _loadingCurrentPlace = false;
  String? _error;
  String? _patternError;

  NudgePlace? _matchingSavedPlace({
    String? name,
    double? latitude,
    double? longitude,
  }) {
    for (final place in _settings.places) {
      if (placesLikelyMatch(
        place,
        candidateName: name,
        latitude: latitude,
        longitude: longitude,
      )) {
        return place;
      }
    }
    return null;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    if (!mounted || _loading || _capturingPlace || _loadingCurrentPlace) return;
    if (_status?.locationAuthorized ?? false) {
      _refreshCurrentPlaceSuggestion(silent: true);
    }
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
      final loadedSettings = results[0] as NotificationNudgeSettings;
      final patternProfile = await _buildPatternProfileFor(loadedSettings);
      if (!mounted) return;
      setState(() {
        _settings = loadedSettings;
        _status = results[1] as NotificationBridgeStatus;
        _patternProfile = patternProfile;
        _loading = false;
      });
      await _service.syncSchedules(
        _settings,
        journalPatternProfile: patternProfile,
      );
      if (!mounted) return;
      if ((_status?.locationAuthorized ?? false)) {
        _refreshCurrentPlaceSuggestion(silent: true);
      }
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
      if (status.notificationsAuthorized) {
        await _resyncCurrentSchedules();
      }
    } catch (e) {
      _showMessage('Could not request notification permission.', details: e);
    }
  }

  Future<void> _resyncCurrentSchedules() async {
    if (!mounted) return;
    setState(() {
      _syncing = true;
      _error = null;
    });

    try {
      final patternProfile = await _buildPatternProfileFor(_settings);
      await _service.syncSchedules(
        _settings,
        journalPatternProfile: patternProfile,
      );
      if (!mounted) return;
      setState(() {
        _patternProfile = patternProfile;
        _syncing = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _syncing = false);
      _showMessage('Could not update your nudges.', details: e);
    }
  }

  Future<void> _requestLocationPermission() async {
    try {
      final status = await _service.requestLocationPermission();
      if (!mounted) return;
      setState(() => _status = status);
      if (status.locationAuthorized) {
        _refreshCurrentPlaceSuggestion(silent: true);
      }
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
      final patternProfile = await _buildPatternProfileFor(nextSettings);
      await _service.syncSchedules(
        nextSettings,
        journalPatternProfile: patternProfile,
        persistSettings: true,
      );
      final status = await _service.getStatus();
      if (!mounted) return;
      setState(() {
        _status = status;
        _patternProfile = patternProfile;
        _syncing = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _syncing = false);
      _showMessage('Could not update your nudges.', details: e);
      _load();
    }
  }

  Future<JournalPatternProfile?> _buildPatternProfileFor(
    NotificationNudgeSettings settings,
  ) async {
    if (!settings.journalPatternPromptsEnabled) {
      if (mounted) {
        setState(() {
          _analyzingPatterns = false;
          _patternError = null;
        });
      }
      return null;
    }

    if (mounted) {
      setState(() {
        _analyzingPatterns = true;
        _patternError = null;
      });
    }

    try {
      await _service.syncObservedLocationEvents();
      final patternProfile = await _service.buildJournalPatternProfile(
        settings,
      );
      if (mounted) {
        setState(() => _analyzingPatterns = false);
      }
      return patternProfile;
    } catch (e) {
      if (mounted) {
        setState(() {
          _analyzingPatterns = false;
          _patternError = _friendlyError(e);
        });
      }
      return null;
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

  Future<void> _refreshCurrentPlaceSuggestion({bool silent = false}) async {
    final status = _status;
    if (status == null) return;
    if (!status.locationAuthorized) {
      if (!silent) {
        _showMessage(
          'Location access needs to be on before the app can suggest nearby places.',
        );
      }
      return;
    }

    setState(() => _loadingCurrentPlace = true);
    try {
      final location = await _service.getCurrentLocationDetails();
      final suggestedName = location['placeName']?.toString().trim() ?? '';
      if (!mounted) return;
      setState(() {
        _currentPlaceSuggestion = {
          ...location,
          'placeName':
              suggestedName.isNotEmpty ? suggestedName : 'Current Spot',
          'addressLabel': location['addressLabel']?.toString(),
          'resolvedBy': location['resolvedBy']?.toString(),
        };
        _loadingCurrentPlace = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loadingCurrentPlace = false);
      if (!silent) {
        _showMessage('Could not detect your current place.', details: e);
      }
    }
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

    setState(() => _capturingPlace = true);
    try {
      final location = await _service.getCurrentLocationDetails();
      if (!mounted) return;
      setState(() => _capturingPlace = false);
      final suggestedName = location['placeName']?.toString().trim() ?? '';
      final place = await _showPlaceSheet(
        suggestedName: suggestedName,
        addressLabel: location['addressLabel']?.toString(),
        latitude: location['latitude'] as double? ?? 0,
        longitude: location['longitude'] as double? ?? 0,
      );
      if (place == null) return;
      await _savePlace(
        name: place.name,
        kind: place.kind,
        latitude: place.latitude!,
        longitude: place.longitude!,
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _capturingPlace = false);
      _showMessage('Could not capture your current location.', details: e);
    }
  }

  Future<_PlaceDraft?> _showPlaceSheet({
    required String suggestedName,
    String? addressLabel,
    required double latitude,
    required double longitude,
    bool allowCoordinateEditing = false,
  }) async {
    return showCupertinoModalPopup<_PlaceDraft>(
      context: context,
      builder: (context) {
        return DefaultTextStyle.merge(
          style: const TextStyle(decoration: TextDecoration.none),
          child: _AddPlaceSheet(
            suggestedName: suggestedName,
            addressLabel: addressLabel,
            initialKind: inferPlaceKind(suggestedName),
            latitude: latitude,
            longitude: longitude,
            allowCoordinateEditing: allowCoordinateEditing,
          ),
        );
      },
    );
  }

  Future<void> _savePlace({
    required String name,
    required String kind,
    required double latitude,
    required double longitude,
  }) async {
    final existingPlace = _matchingSavedPlace(
      name: name,
      latitude: latitude,
      longitude: longitude,
    );
    if (existingPlace != null) {
      _showMessage('${existingPlace.name} is already in your saved places.');
      return;
    }

    final nextPlaces = [
      ..._settings.places,
      NudgePlace(
        id: DateTime.now().microsecondsSinceEpoch.toString(),
        name: name,
        kind: kind,
        latitude: latitude,
        longitude: longitude,
      ),
    ];
    await _updateSettings(_settings.copyWith(places: nextPlaces));
    if (!mounted) return;
    setState(() {
      _currentPlaceSuggestion = {
        'latitude': latitude,
        'longitude': longitude,
        'placeName': name,
        'kind': kind,
      };
    });
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

  bool get _currentSuggestionAlreadySaved {
    final suggestion = _currentPlaceSuggestion;
    if (suggestion == null) return false;
    return _matchingSavedPlace(
          name: suggestion['placeName']?.toString(),
          latitude: suggestion['latitude'] as double?,
          longitude: suggestion['longitude'] as double?,
        ) !=
        null;
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
                        title: 'Adaptive Intelligence',
                        subtitle:
                            'Use recent journal patterns on-device to make home and work nudges more emotionally aware.',
                      ),
                      const SizedBox(height: 10),
                      GlassCard(
                        child: Column(
                          children: [
                            _ToggleRow(
                              icon: CupertinoIcons.sparkles,
                              iconColor: JournalColors.accent,
                              title: 'Use Journal Patterns',
                              subtitle:
                                  'Keep pattern learning on-device so work-to-home nudges can adapt to stress, routine, and timing.',
                              value: _settings.journalPatternPromptsEnabled,
                              onChanged: (value) => _updateSettings(
                                _settings.copyWith(
                                  journalPatternPromptsEnabled: value,
                                ),
                              ),
                            ),
                            const _Divider(),
                            _PatternInsightPanel(
                              enabled: _settings.journalPatternPromptsEnabled,
                              analyzing: _analyzingPatterns,
                              error: _patternError,
                              patternProfile: _patternProfile,
                              onRefresh: () => _updateSettings(_settings),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),
                      const _SectionTitle(
                        title: 'Location Nudges',
                        subtitle:
                            'Save parks, home, school, or other places and fire local reminders when you arrive or leave.',
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
                                  'Show lock-screen reminders that adapt to saved places and transitions.',
                              value: _settings.locationPromptsEnabled,
                              onChanged: (value) => _updateSettings(
                                _settings.copyWith(
                                    locationPromptsEnabled: value),
                              ),
                            ),
                            const _Divider(),
                            Padding(
                              padding:
                                  const EdgeInsets.fromLTRB(16, 14, 16, 12),
                              child: _currentSuggestionAlreadySaved
                                  ? _CurrentPlaceStatusRow(
                                      loading: _loadingCurrentPlace,
                                      suggestion: _currentPlaceSuggestion,
                                      hasLocationAccess:
                                          _status?.locationAuthorized ?? false,
                                      onRefresh: _refreshCurrentPlaceSuggestion,
                                    )
                                  : _SmartPlaceCard(
                                      loading: _loadingCurrentPlace,
                                      suggestion: _currentPlaceSuggestion,
                                      hasLocationAccess:
                                          _status?.locationAuthorized ?? false,
                                      savedPlaces: _settings.places,
                                      onRefresh: _refreshCurrentPlaceSuggestion,
                                      onSave: () async {
                                        final suggestion =
                                            _currentPlaceSuggestion;
                                        if (suggestion == null) return;
                                        final suggestedName =
                                            suggestion['placeName']
                                                    ?.toString() ??
                                                '';
                                        final place = await _showPlaceSheet(
                                          suggestedName: suggestedName,
                                          addressLabel:
                                              suggestion['addressLabel']
                                                  ?.toString(),
                                          latitude: suggestion['latitude']
                                                  as double? ??
                                              0,
                                          longitude: suggestion['longitude']
                                                  as double? ??
                                              0,
                                        );
                                        if (place == null) {
                                          return;
                                        }
                                        await _savePlace(
                                          name: place.name,
                                          kind: place.kind,
                                          latitude: place.latitude!,
                                          longitude: place.longitude!,
                                        );
                                      },
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
                                    'Use your current location or enter one manually. Each place uses a local geofence, opens Write on the main tap, and includes an Ask Sage notification action.',
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
                                        'No places saved yet. Add one from where you are or enter a location manually with coordinates.',
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
                                    onPressed: _capturingPlace ||
                                            _currentSuggestionAlreadySaved
                                        ? null
                                        : _addPlace,
                                    label: _capturingPlace
                                        ? 'Saving Current Spot...'
                                        : _currentSuggestionAlreadySaved
                                            ? 'Current Place Already Saved'
                                            : 'Add Current Location',
                                  ),
                                  const SizedBox(height: 10),
                                  CupertinoButton(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 14,
                                      vertical: 10,
                                    ),
                                    onPressed: () async {
                                      final place = await _showPlaceSheet(
                                        suggestedName: '',
                                        latitude: 0,
                                        longitude: 0,
                                        allowCoordinateEditing: true,
                                      );
                                      if (place == null) return;
                                      try {
                                        final resolved = await _service
                                            .resolveAddress(place.address);
                                        if (!mounted) return;
                                        await _savePlace(
                                          name: place.name,
                                          kind: place.kind,
                                          latitude:
                                              resolved['latitude'] as double? ??
                                                  0,
                                          longitude: resolved['longitude']
                                                  as double? ??
                                              0,
                                        );
                                      } catch (e) {
                                        if (!mounted) return;
                                        _showMessage(
                                          'Could not find that address.',
                                          details: e,
                                        );
                                      }
                                    },
                                    child: const Text(
                                      'Add Manually',
                                      style: TextStyle(
                                        color: JournalColors.accent,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
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

class _PatternInsightPanel extends StatelessWidget {
  const _PatternInsightPanel({
    required this.enabled,
    required this.analyzing,
    required this.error,
    required this.patternProfile,
    required this.onRefresh,
  });

  final bool enabled;
  final bool analyzing;
  final String? error;
  final JournalPatternProfile? patternProfile;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    Widget child;
    if (!enabled) {
      child = const Text(
        'Turn this on to analyze recent entries locally and explain why a home or work nudge was suggested. Nothing from this pattern scan leaves the device.',
        style: TextStyle(
          color: JournalColors.textSecondary,
          fontSize: 13,
          height: 1.45,
        ),
      );
    } else if (analyzing) {
      child = const Row(
        children: [
          CupertinoActivityIndicator(color: JournalColors.accent),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              'Scanning recent entries on-device for home, work, family, and timing patterns...',
              style: TextStyle(
                color: JournalColors.textSecondary,
                fontSize: 13,
                height: 1.4,
              ),
            ),
          ),
        ],
      );
    } else if (error != null && error!.isNotEmpty) {
      child = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            error!,
            style: const TextStyle(
              color: JournalColors.textSecondary,
              fontSize: 13,
              height: 1.45,
            ),
          ),
          const SizedBox(height: 12),
          CupertinoButton(
            padding: EdgeInsets.zero,
            onPressed: onRefresh,
            child: const Text(
              'Try Again',
              style: TextStyle(
                color: JournalColors.accent,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      );
    } else if (patternProfile == null || !patternProfile!.hasSignals) {
      child = const Text(
        'The app needs a little more pattern signal before it can personalize these nudges. Saving both home and work helps the work-to-home transition kick in sooner.',
        style: TextStyle(
          color: JournalColors.textSecondary,
          fontSize: 13,
          height: 1.45,
        ),
      );
    } else {
      child = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Suggested because the app found ${patternProfile!.entriesAnalyzed} recent-entry signals like these:',
            style: const TextStyle(
              color: JournalColors.textPrimary,
              fontSize: 14,
              fontWeight: FontWeight.w700,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 12),
          ...patternProfile!.reasons.map(
            (reason) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 6,
                    height: 6,
                    margin: const EdgeInsets.only(top: 6),
                    decoration: const BoxDecoration(
                      color: JournalColors.accent,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      reason,
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
          ),
          const SizedBox(height: 4),
          const Text(
            'Pattern prompts stay explainable and only rewrite local notification copy. They do not upload location history or your movement patterns.',
            style: TextStyle(
              color: JournalColors.textMuted,
              fontSize: 12,
              height: 1.4,
            ),
          ),
        ],
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: _withAlpha(JournalColors.info, 0.14),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  CupertinoIcons.waveform_path_ecg,
                  color: JournalColors.info,
                  size: 19,
                ),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'EXPLAINABLE SIGNALS',
                      style: TextStyle(
                        color: JournalColors.textMuted,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.2,
                      ),
                    ),
                    SizedBox(height: 4),
                    Text(
                      'Why the nudge got smarter',
                      style: TextStyle(
                        color: JournalColors.textPrimary,
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              CupertinoButton(
                padding: EdgeInsets.zero,
                onPressed: enabled && !analyzing ? onRefresh : null,
                child: const Text(
                  'Refresh',
                  style: TextStyle(
                    color: JournalColors.accent,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          child,
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

class _SmartPlaceCard extends StatelessWidget {
  const _SmartPlaceCard({
    required this.loading,
    required this.suggestion,
    required this.hasLocationAccess,
    required this.savedPlaces,
    required this.onRefresh,
    required this.onSave,
  });

  final bool loading;
  final Map<String, dynamic>? suggestion;
  final bool hasLocationAccess;
  final List<NudgePlace> savedPlaces;
  final Future<void> Function({bool silent}) onRefresh;
  final Future<void> Function() onSave;

  @override
  Widget build(BuildContext context) {
    final placeName = suggestion?['placeName']?.toString().trim();
    final alreadySaved = placeName != null &&
        placeName.isNotEmpty &&
        savedPlaces.any(
          (place) => place.name.trim().toLowerCase() == placeName.toLowerCase(),
        );

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            _withAlpha(JournalColors.accent, 0.14),
            _withAlpha(JournalColors.info, 0.08),
            _withAlpha(JournalColors.bgSurface, 0.92),
          ],
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _withAlpha(JournalColors.borderBright, 0.9)),
        boxShadow: const [
          BoxShadow(
            color: JournalColors.accentGlow,
            blurRadius: 18,
            offset: Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: _withAlpha(JournalColors.accent, 0.16),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(
                  CupertinoIcons.sparkles,
                  color: JournalColors.textPrimary,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'SMART PLACE DETECTION',
                      style: TextStyle(
                        color: JournalColors.textMuted,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.2,
                      ),
                    ),
                    SizedBox(height: 4),
                    Text(
                      'Catch the place you are actually standing in.',
                      style: TextStyle(
                        color: JournalColors.textPrimary,
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          if (!hasLocationAccess)
            const Text(
              'Enable location access and this screen can suggest your current place while you are here, without always-on background tracking.',
              style: TextStyle(
                color: JournalColors.textSecondary,
                fontSize: 13,
                height: 1.45,
              ),
            )
          else if (loading)
            const Row(
              children: [
                CupertinoActivityIndicator(color: JournalColors.accent),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Checking your current spot...',
                    style: TextStyle(
                      color: JournalColors.textSecondary,
                      fontSize: 13,
                    ),
                  ),
                ),
              ],
            )
          else if (placeName != null && placeName.isNotEmpty)
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  placeName,
                  style: const TextStyle(
                    color: JournalColors.textPrimary,
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    height: 1.1,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  alreadySaved
                      ? 'Already saved for location nudges. Refresh if you moved somewhere new.'
                      : 'Looks like you are here right now. Save it and let iPhone ask about Wyatt or an activity the next time you arrive.',
                  style: const TextStyle(
                    color: JournalColors.textSecondary,
                    fontSize: 13,
                    height: 1.45,
                  ),
                ),
              ],
            )
          else
            const Text(
              'No nearby place name came back yet. Refresh while you are physically at the park, home, school, or store you care about.',
              style: TextStyle(
                color: JournalColors.textSecondary,
                fontSize: 13,
                height: 1.45,
              ),
            ),
          const SizedBox(height: 14),
          Row(
            children: [
              if (!alreadySaved)
                Expanded(
                  child: _PrimarySheetButton(
                    label: 'Save This Place',
                    enabled: hasLocationAccess && !loading,
                    onPressed: hasLocationAccess && !loading ? onSave : null,
                  ),
                ),
              if (!alreadySaved) const SizedBox(width: 10),
              CupertinoButton(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                onPressed: loading ? null : () => onRefresh(silent: false),
                child: const Text(
                  'Refresh',
                  style: TextStyle(
                    color: JournalColors.accent,
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

class _CurrentPlaceStatusRow extends StatelessWidget {
  const _CurrentPlaceStatusRow({
    required this.loading,
    required this.suggestion,
    required this.hasLocationAccess,
    required this.onRefresh,
  });

  final bool loading;
  final Map<String, dynamic>? suggestion;
  final bool hasLocationAccess;
  final Future<void> Function({bool silent}) onRefresh;

  @override
  Widget build(BuildContext context) {
    final placeName =
        suggestion?['placeName']?.toString().trim() ?? 'Current place';

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
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: _withAlpha(JournalColors.success, 0.14),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(
              CupertinoIcons.check_mark_circled_solid,
              color: JournalColors.success,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  hasLocationAccess && !loading
                      ? 'Current place: $placeName'
                      : 'Current place detection unavailable',
                  style: const TextStyle(
                    color: JournalColors.textPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  hasLocationAccess && !loading
                      ? 'Already saved for nudges.'
                      : 'Enable location access to keep this updated.',
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
          GestureDetector(
            onTap: loading ? null : () => onRefresh(silent: false),
            child: Text(
              'Refresh',
              style: TextStyle(
                color: loading ? JournalColors.textMuted : JournalColors.accent,
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

class _PlaceDraft {
  const _PlaceDraft({
    required this.name,
    required this.kind,
    this.latitude,
    this.longitude,
    this.address = '',
  });

  final String name;
  final String kind;
  final double? latitude;
  final double? longitude;
  final String address;
}

class _AddPlaceSheet extends StatefulWidget {
  const _AddPlaceSheet({
    required this.suggestedName,
    required this.addressLabel,
    required this.initialKind,
    required this.latitude,
    required this.longitude,
    this.allowCoordinateEditing = false,
  });

  final String suggestedName;
  final String? addressLabel;
  final String initialKind;
  final double latitude;
  final double longitude;
  final bool allowCoordinateEditing;

  @override
  State<_AddPlaceSheet> createState() => _AddPlaceSheetState();
}

class _AddPlaceSheetState extends State<_AddPlaceSheet> {
  late final TextEditingController _nameController;
  late final TextEditingController _addressController;
  late String _selectedKind;
  String? _error;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.suggestedName);
    _addressController = TextEditingController(text: widget.addressLabel ?? '');
    _selectedKind = widget.initialKind;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _addressController.dispose();
    super.dispose();
  }

  void _submit() {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Give this place a name first.');
      return;
    }

    final address = _addressController.text.trim();
    if (widget.allowCoordinateEditing && address.isEmpty) {
      setState(() => _error = 'Enter the address for this place.');
      return;
    }

    Navigator.of(context).pop(
      _PlaceDraft(
        name: name,
        kind: _selectedKind,
        latitude: widget.allowCoordinateEditing ? null : widget.latitude,
        longitude: widget.allowCoordinateEditing ? null : widget.longitude,
        address: address,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    return SafeArea(
      top: false,
      child: AnimatedPadding(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
        padding:
            EdgeInsets.only(bottom: bottomInset > 0 ? bottomInset + 12 : 12),
        child: SingleChildScrollView(
          physics: const ClampingScrollPhysics(),
          child: Container(
            margin: const EdgeInsets.fromLTRB(12, 0, 12, 0),
            padding: const EdgeInsets.fromLTRB(18, 14, 18, 20),
            decoration: BoxDecoration(
              color: _withAlpha(JournalColors.bgCard, 0.98),
              borderRadius: BorderRadius.circular(28),
              border: Border.all(color: JournalColors.borderBright),
              boxShadow: const [
                BoxShadow(
                  color: JournalColors.accentGlow,
                  blurRadius: 28,
                  offset: Offset(0, 16),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 42,
                    height: 4,
                    decoration: BoxDecoration(
                      color: _withAlpha(JournalColors.textMuted, 0.5),
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Container(
                      width: 52,
                      height: 52,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            _withAlpha(JournalColors.accent, 0.24),
                            _withAlpha(JournalColors.info, 0.16),
                          ],
                        ),
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: JournalColors.borderBright),
                      ),
                      child: const Icon(
                        CupertinoIcons.location_solid,
                        color: JournalColors.textPrimary,
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.allowCoordinateEditing
                                ? 'ADD A PLACE MANUALLY'
                                : 'SAVE A NUDGE PLACE',
                            style: const TextStyle(
                              color: JournalColors.textMuted,
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 1.2,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            widget.allowCoordinateEditing
                                ? 'Drop in a place name and coordinates.'
                                : 'Turn this spot into a smarter arrival reminder.',
                            style: const TextStyle(
                              color: JournalColors.textPrimary,
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                              height: 1.2,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                if (widget.suggestedName.isNotEmpty)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: _withAlpha(JournalColors.bgSurface, 0.75),
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: JournalColors.border),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'ON-DEVICE PLACE SUGGESTION',
                          style: TextStyle(
                            color: JournalColors.textMuted,
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 1.1,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          widget.suggestedName,
                          style: const TextStyle(
                            color: JournalColors.textPrimary,
                            fontSize: 17,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        if (widget.addressLabel != null &&
                            widget.addressLabel!.trim().isNotEmpty &&
                            widget.addressLabel!.trim().toLowerCase() !=
                                widget.suggestedName.trim().toLowerCase()) ...[
                          const SizedBox(height: 4),
                          Text(
                            widget.addressLabel!,
                            style: const TextStyle(
                              color: JournalColors.textSecondary,
                              fontSize: 12,
                              height: 1.35,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                if (widget.suggestedName.isNotEmpty) const SizedBox(height: 14),
                Text(
                  widget.allowCoordinateEditing
                      ? 'Use any name you want, then enter the address where the reminder should fire.'
                      : 'Name this place however you want it to appear in the notification.',
                  style: const TextStyle(
                    color: JournalColors.textSecondary,
                    fontSize: 13,
                    height: 1.45,
                  ),
                ),
                const SizedBox(height: 14),
                _PlaceKindSelector(
                  initialKind: _selectedKind,
                  onChanged: (kind) => _selectedKind = kind,
                ),
                const SizedBox(height: 12),
                CupertinoTextField(
                  controller: _nameController,
                  placeholder: 'Boyce Park, Soccer Field, Mom’s House...',
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  decoration: BoxDecoration(
                    color: JournalColors.bgSurface,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: JournalColors.borderBright),
                  ),
                  style: const TextStyle(
                    color: JournalColors.textPrimary,
                    fontSize: 16,
                  ),
                  placeholderStyle: const TextStyle(
                    color: JournalColors.textMuted,
                  ),
                  autofocus: true,
                  textCapitalization: TextCapitalization.words,
                ),
                if (widget.allowCoordinateEditing) ...[
                  const SizedBox(height: 12),
                  CupertinoTextField(
                    controller: _addressController,
                    placeholder: '123 Main St, Pittsburgh, PA',
                    keyboardType: TextInputType.streetAddress,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 14,
                    ),
                    decoration: BoxDecoration(
                      color: JournalColors.bgSurface,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: JournalColors.border),
                    ),
                    style: const TextStyle(
                      color: JournalColors.textPrimary,
                      fontSize: 16,
                    ),
                    placeholderStyle: const TextStyle(
                      color: JournalColors.textMuted,
                    ),
                    maxLines: 2,
                  ),
                ] else ...[
                  const SizedBox(height: 12),
                  Text(
                    'Coordinates: ${widget.latitude.toStringAsFixed(4)}, ${widget.longitude.toStringAsFixed(4)}',
                    style: const TextStyle(
                      color: JournalColors.textMuted,
                      fontSize: 11,
                    ),
                  ),
                ],
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    _error!,
                    style: const TextStyle(
                      color: JournalColors.orange,
                      fontSize: 12,
                    ),
                  ),
                ],
                const SizedBox(height: 18),
                Row(
                  children: [
                    Expanded(
                      child: CupertinoButton(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        color: _withAlpha(JournalColors.bgSurface, 0.9),
                        borderRadius: BorderRadius.circular(16),
                        onPressed: () => Navigator.of(context).pop(),
                        child: const Text(
                          'Cancel',
                          style: TextStyle(color: JournalColors.textSecondary),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _PrimarySheetButton(
                        label: 'Save Place',
                        enabled: true,
                        onPressed: _submit,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PlaceKindSelector extends StatefulWidget {
  const _PlaceKindSelector({
    required this.initialKind,
    required this.onChanged,
  });

  final String initialKind;
  final ValueChanged<String> onChanged;

  @override
  State<_PlaceKindSelector> createState() => _PlaceKindSelectorState();
}

class _PlaceKindSelectorState extends State<_PlaceKindSelector> {
  late String _selectedKind;

  static const _options = <({String id, String label})>[
    (id: 'park', label: 'Park / Kid Spot'),
    (id: 'doctor', label: 'Doctor / Health'),
    (id: 'school', label: 'School'),
    (id: 'home', label: 'Home / Family'),
    (id: 'work', label: 'Work / Errands'),
    (id: 'general', label: 'General'),
  ];

  @override
  void initState() {
    super.initState();
    _selectedKind = widget.initialKind;
    widget.onChanged(_selectedKind);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'WHAT KIND OF PLACE IS THIS?',
          style: TextStyle(
            color: JournalColors.textMuted,
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.1,
          ),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: _options.map((option) {
            final selected = option.id == _selectedKind;
            return GestureDetector(
              onTap: () {
                setState(() => _selectedKind = option.id);
                widget.onChanged(option.id);
              },
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: selected
                      ? _withAlpha(JournalColors.accent, 0.18)
                      : _withAlpha(JournalColors.bgSurface, 0.9),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(
                    color: selected
                        ? JournalColors.borderBright
                        : JournalColors.border,
                  ),
                ),
                child: Text(
                  option.label,
                  style: TextStyle(
                    color: selected
                        ? JournalColors.textPrimary
                        : JournalColors.textSecondary,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }
}

class _PrimarySheetButton extends StatelessWidget {
  const _PrimarySheetButton({
    required this.label,
    required this.enabled,
    required this.onPressed,
  });

  final String label;
  final bool enabled;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return CupertinoButton(
      padding: EdgeInsets.zero,
      onPressed: enabled ? onPressed : null,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 15),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: enabled
                ? [
                    JournalColors.accent,
                    JournalColors.info,
                  ]
                : [
                    _withAlpha(JournalColors.textMuted, 0.28),
                    _withAlpha(JournalColors.textMuted, 0.18),
                  ],
          ),
          borderRadius: BorderRadius.circular(18),
          boxShadow: enabled
              ? const [
                  BoxShadow(
                    color: JournalColors.accentGlow,
                    blurRadius: 18,
                    offset: Offset(0, 10),
                  ),
                ]
              : null,
        ),
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: enabled
                ? JournalColors.textPrimary
                : _withAlpha(JournalColors.textMuted, 0.9),
            fontSize: 17,
            fontWeight: FontWeight.w700,
          ),
        ),
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
