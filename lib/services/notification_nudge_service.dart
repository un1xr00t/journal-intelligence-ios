import 'dart:math' as math;
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api_service.dart';

class NotificationBridgeStatus {
  const NotificationBridgeStatus({
    required this.notificationStatus,
    required this.notificationsAuthorized,
    required this.locationStatus,
  });

  final String notificationStatus;
  final bool notificationsAuthorized;
  final String locationStatus;

  bool get locationAuthorized {
    return locationStatus == 'authorizedWhenInUse' ||
        locationStatus == 'authorizedAlways';
  }

  factory NotificationBridgeStatus.fromMap(Map<dynamic, dynamic> map) {
    return NotificationBridgeStatus(
      notificationStatus: map['notificationStatus']?.toString() ?? 'unknown',
      notificationsAuthorized:
          (map['notificationsAuthorized'] as bool?) ?? false,
      locationStatus: map['locationStatus']?.toString() ?? 'unknown',
    );
  }
}

class NudgePlace {
  const NudgePlace({
    required this.id,
    required this.name,
    required this.kind,
    required this.latitude,
    required this.longitude,
    this.radiusMeters = 200,
  });

  final String id;
  final String name;
  final String kind;
  final double latitude;
  final double longitude;
  final double radiusMeters;

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'kind': kind,
      'latitude': latitude,
      'longitude': longitude,
      'radiusMeters': radiusMeters,
    };
  }

  factory NudgePlace.fromJson(Map<String, dynamic> json) {
    return NudgePlace(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? 'Saved Place',
      kind:
          json['kind']?.toString() ?? inferPlaceKind(json['name']?.toString()),
      latitude: (json['latitude'] as num?)?.toDouble() ?? 0,
      longitude: (json['longitude'] as num?)?.toDouble() ?? 0,
      radiusMeters: (json['radiusMeters'] as num?)?.toDouble() ?? 200,
    );
  }
}

class NotificationNudgeSettings {
  const NotificationNudgeSettings({
    required this.locationPromptsEnabled,
    required this.journalPatternPromptsEnabled,
    required this.morningPromptEnabled,
    required this.eveningPromptEnabled,
    required this.weeklyWyattPromptEnabled,
    required this.morningHour,
    required this.morningMinute,
    required this.eveningHour,
    required this.eveningMinute,
    required this.weeklyHour,
    required this.weeklyMinute,
    required this.places,
  });

  final bool locationPromptsEnabled;
  final bool journalPatternPromptsEnabled;
  final bool morningPromptEnabled;
  final bool eveningPromptEnabled;
  final bool weeklyWyattPromptEnabled;
  final int morningHour;
  final int morningMinute;
  final int eveningHour;
  final int eveningMinute;
  final int weeklyHour;
  final int weeklyMinute;
  final List<NudgePlace> places;

  factory NotificationNudgeSettings.defaults() {
    return const NotificationNudgeSettings(
      locationPromptsEnabled: false,
      journalPatternPromptsEnabled: false,
      morningPromptEnabled: false,
      eveningPromptEnabled: false,
      weeklyWyattPromptEnabled: false,
      morningHour: 9,
      morningMinute: 0,
      eveningHour: 20,
      eveningMinute: 0,
      weeklyHour: 18,
      weeklyMinute: 0,
      places: <NudgePlace>[],
    );
  }

  NotificationNudgeSettings copyWith({
    bool? locationPromptsEnabled,
    bool? journalPatternPromptsEnabled,
    bool? morningPromptEnabled,
    bool? eveningPromptEnabled,
    bool? weeklyWyattPromptEnabled,
    int? morningHour,
    int? morningMinute,
    int? eveningHour,
    int? eveningMinute,
    int? weeklyHour,
    int? weeklyMinute,
    List<NudgePlace>? places,
  }) {
    return NotificationNudgeSettings(
      locationPromptsEnabled:
          locationPromptsEnabled ?? this.locationPromptsEnabled,
      journalPatternPromptsEnabled:
          journalPatternPromptsEnabled ?? this.journalPatternPromptsEnabled,
      morningPromptEnabled: morningPromptEnabled ?? this.morningPromptEnabled,
      eveningPromptEnabled: eveningPromptEnabled ?? this.eveningPromptEnabled,
      weeklyWyattPromptEnabled:
          weeklyWyattPromptEnabled ?? this.weeklyWyattPromptEnabled,
      morningHour: morningHour ?? this.morningHour,
      morningMinute: morningMinute ?? this.morningMinute,
      eveningHour: eveningHour ?? this.eveningHour,
      eveningMinute: eveningMinute ?? this.eveningMinute,
      weeklyHour: weeklyHour ?? this.weeklyHour,
      weeklyMinute: weeklyMinute ?? this.weeklyMinute,
      places: places ?? this.places,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'locationPromptsEnabled': locationPromptsEnabled,
      'journalPatternPromptsEnabled': journalPatternPromptsEnabled,
      'morningPromptEnabled': morningPromptEnabled,
      'eveningPromptEnabled': eveningPromptEnabled,
      'weeklyWyattPromptEnabled': weeklyWyattPromptEnabled,
      'morningHour': morningHour,
      'morningMinute': morningMinute,
      'eveningHour': eveningHour,
      'eveningMinute': eveningMinute,
      'weeklyHour': weeklyHour,
      'weeklyMinute': weeklyMinute,
      'places': places.map((place) => place.toJson()).toList(),
    };
  }

  factory NotificationNudgeSettings.fromJson(Map<String, dynamic> json) {
    final placesJson = json['places'] as List<dynamic>? ?? const [];
    return NotificationNudgeSettings(
      locationPromptsEnabled:
          (json['locationPromptsEnabled'] as bool?) ?? false,
      journalPatternPromptsEnabled:
          (json['journalPatternPromptsEnabled'] as bool?) ?? false,
      morningPromptEnabled: (json['morningPromptEnabled'] as bool?) ?? false,
      eveningPromptEnabled: (json['eveningPromptEnabled'] as bool?) ?? false,
      weeklyWyattPromptEnabled:
          (json['weeklyWyattPromptEnabled'] as bool?) ?? false,
      morningHour: (json['morningHour'] as int?) ?? 9,
      morningMinute: (json['morningMinute'] as int?) ?? 0,
      eveningHour: (json['eveningHour'] as int?) ?? 20,
      eveningMinute: (json['eveningMinute'] as int?) ?? 0,
      weeklyHour: (json['weeklyHour'] as int?) ?? 18,
      weeklyMinute: (json['weeklyMinute'] as int?) ?? 0,
      places: placesJson
          .whereType<Map>()
          .map((place) => NudgePlace.fromJson(Map<String, dynamic>.from(place)))
          .toList(),
    );
  }
}

class JournalPatternProfile {
  const JournalPatternProfile({
    required this.entriesAnalyzed,
    required this.homeLooksStressful,
    required this.hasHomePlace,
    required this.hasWorkPlace,
    required this.workUsuallyLeadsHome,
    required this.learnedWorkToHomeTransitions,
    required this.totalObservedWorkExits,
    required this.wyattShowsUpAfterWork,
    required this.familyShowsUpInHeavierEntries,
    required this.topStressWindowLabel,
    required this.reasons,
  });

  final int entriesAnalyzed;
  final bool homeLooksStressful;
  final bool hasHomePlace;
  final bool hasWorkPlace;
  final bool workUsuallyLeadsHome;
  final int learnedWorkToHomeTransitions;
  final int totalObservedWorkExits;
  final bool wyattShowsUpAfterWork;
  final bool familyShowsUpInHeavierEntries;
  final String? topStressWindowLabel;
  final List<String> reasons;

  bool get hasSignals => reasons.isNotEmpty;

  bool supportsSmartPromptFor(
    NudgePlace place, {
    required String transition,
  }) {
    if (transition == 'exit' &&
        place.kind == 'work' &&
        workUsuallyLeadsHome &&
        homeLooksStressful) {
      return true;
    }

    if (transition == 'entry' && place.kind == 'home' && homeLooksStressful) {
      return true;
    }

    return false;
  }
}

class LocationNudgeEvent {
  const LocationNudgeEvent({
    required this.identifier,
    required this.deliveredAt,
    required this.placeId,
    required this.placeName,
    required this.placeKind,
    required this.transition,
  });

  final String identifier;
  final DateTime deliveredAt;
  final String placeId;
  final String placeName;
  final String placeKind;
  final String transition;

  String get dedupeKey =>
      '$identifier|${deliveredAt.toUtc().toIso8601String()}|$transition';

  Map<String, dynamic> toJson() {
    return {
      'identifier': identifier,
      'deliveredAt': deliveredAt.toUtc().toIso8601String(),
      'placeId': placeId,
      'placeName': placeName,
      'placeKind': placeKind,
      'transition': transition,
    };
  }

  factory LocationNudgeEvent.fromJson(Map<String, dynamic> json) {
    final deliveredAtRaw = json['deliveredAt']?.toString() ?? '';
    return LocationNudgeEvent(
      identifier: json['identifier']?.toString() ?? '',
      deliveredAt:
          DateTime.tryParse(deliveredAtRaw)?.toLocal() ?? DateTime.now(),
      placeId: json['placeId']?.toString() ?? '',
      placeName: json['placeName']?.toString() ?? 'Saved Place',
      placeKind: json['placeKind']?.toString() ?? 'general',
      transition: json['transition']?.toString() ?? 'entry',
    );
  }

  factory LocationNudgeEvent.fromBridgeMap(Map<dynamic, dynamic> map) {
    final deliveredAtRaw = map['deliveredAt']?.toString() ?? '';
    return LocationNudgeEvent(
      identifier: map['identifier']?.toString() ?? '',
      deliveredAt:
          DateTime.tryParse(deliveredAtRaw)?.toLocal() ?? DateTime.now(),
      placeId: map['placeId']?.toString() ?? '',
      placeName: map['placeName']?.toString() ?? 'Saved Place',
      placeKind: map['placeKind']?.toString() ?? 'general',
      transition: map['transition']?.toString() ?? 'entry',
    );
  }
}

class NotificationNudgeService {
  static const _channel = MethodChannel('journal_intelligence/notifications');
  static const _prefsKey = 'notification_nudges.settings.v1';
  static const _observedLocationEventsKey =
      'notification_nudges.location_events.v1';
  static const _morningId = 'nudge.morning';
  static const _eveningId = 'nudge.evening';
  static const _weeklyWyattId = 'nudge.weekly_wyatt';
  final _api = ApiService();

  Future<NotificationBridgeStatus> getStatus() async {
    final raw = await _channel.invokeMethod<Map<Object?, Object?>>('getStatus');
    return NotificationBridgeStatus.fromMap(raw ?? const {});
  }

  Future<NotificationBridgeStatus> requestNotificationPermission() async {
    final raw = await _channel.invokeMethod<Map<Object?, Object?>>(
      'requestNotificationPermission',
    );
    return NotificationBridgeStatus.fromMap(raw ?? const {});
  }

  Future<NotificationBridgeStatus> requestLocationPermission() async {
    final raw = await _channel.invokeMethod<Map<Object?, Object?>>(
      'requestLocationPermission',
    );
    return NotificationBridgeStatus.fromMap(raw ?? const {});
  }

  Future<Map<String, double>> getCurrentLocation() async {
    final raw = await _channel.invokeMethod<Map<Object?, Object?>>(
      'getCurrentLocation',
    );
    final map = raw ?? const <Object?, Object?>{};
    return {
      'latitude': (map['latitude'] as num?)?.toDouble() ?? 0,
      'longitude': (map['longitude'] as num?)?.toDouble() ?? 0,
      'accuracy': (map['accuracy'] as num?)?.toDouble() ?? 0,
    };
  }

  Future<Map<String, dynamic>> getCurrentLocationDetails() async {
    final raw = await _channel.invokeMethod<Map<Object?, Object?>>(
      'getCurrentLocation',
    );
    final map = raw ?? const <Object?, Object?>{};
    return {
      'latitude': (map['latitude'] as num?)?.toDouble() ?? 0,
      'longitude': (map['longitude'] as num?)?.toDouble() ?? 0,
      'accuracy': (map['accuracy'] as num?)?.toDouble() ?? 0,
      'placeName': map['placeName']?.toString(),
      'addressLabel': map['addressLabel']?.toString(),
      'resolvedBy': map['resolvedBy']?.toString(),
    };
  }

  Future<Map<String, dynamic>> resolveAddress(String address) async {
    final raw = await _channel.invokeMethod<Map<Object?, Object?>>(
      'resolveAddress',
      {'address': address},
    );
    final map = raw ?? const <Object?, Object?>{};
    return {
      'latitude': (map['latitude'] as num?)?.toDouble() ?? 0,
      'longitude': (map['longitude'] as num?)?.toDouble() ?? 0,
      'addressLabel': map['addressLabel']?.toString(),
    };
  }

  Future<NotificationNudgeSettings> loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefsKey);
    if (raw == null || raw.isEmpty) {
      return NotificationNudgeSettings.defaults();
    }

    try {
      return NotificationNudgeSettings.fromJson(
        jsonDecode(raw) as Map<String, dynamic>,
      );
    } catch (_) {
      return NotificationNudgeSettings.defaults();
    }
  }

  Future<void> saveSettings(NotificationNudgeSettings settings) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, jsonEncode(settings.toJson()));
  }

  Future<List<LocationNudgeEvent>> loadObservedLocationEvents() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_observedLocationEventsKey);
    if (raw == null || raw.trim().isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw) as List<dynamic>;
      return decoded
          .whereType<Map>()
          .map((item) =>
              LocationNudgeEvent.fromJson(Map<String, dynamic>.from(item)))
          .toList()
        ..sort((a, b) => a.deliveredAt.compareTo(b.deliveredAt));
    } catch (_) {
      return const [];
    }
  }

  Future<void> _saveObservedLocationEvents(
    List<LocationNudgeEvent> events,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final capped = [...events]
      ..sort((a, b) => a.deliveredAt.compareTo(b.deliveredAt));
    final trimmed =
        capped.length > 160 ? capped.sublist(capped.length - 160) : capped;
    await prefs.setString(
      _observedLocationEventsKey,
      jsonEncode(trimmed.map((event) => event.toJson()).toList()),
    );
  }

  Future<List<LocationNudgeEvent>> syncObservedLocationEvents() async {
    final existing = await loadObservedLocationEvents();
    final existingKeys = existing.map((event) => event.dedupeKey).toSet();
    final raw = await _channel
        .invokeMethod<List<Object?>>('getDeliveredLocationEvents');
    final incoming = (raw ?? const <Object?>[])
        .whereType<Map>()
        .map(LocationNudgeEvent.fromBridgeMap)
        .where(
            (event) => event.identifier.isNotEmpty && event.placeId.isNotEmpty)
        .toList();

    if (incoming.isEmpty) return existing;

    final merged = [...existing];
    for (final event in incoming) {
      if (existingKeys.add(event.dedupeKey)) {
        merged.add(event);
      }
    }
    await _saveObservedLocationEvents(merged);
    return merged..sort((a, b) => a.deliveredAt.compareTo(b.deliveredAt));
  }

  Future<void> syncSchedules(
    NotificationNudgeSettings nextSettings, {
    JournalPatternProfile? journalPatternProfile,
  }) async {
    final previousSettings = await loadSettings();
    final idsToCancel = <String>{
      ..._allNotificationIdsFor(previousSettings),
      ..._allNotificationIdsFor(nextSettings),
    }.toList();

    if (idsToCancel.isNotEmpty) {
      await _channel.invokeMethod<void>('cancelNotifications', {
        'ids': idsToCancel,
      });
    }

    if (nextSettings.morningPromptEnabled) {
      await _channel.invokeMethod<void>('scheduleCalendarNotification', {
        'id': _morningId,
        'title': 'Morning check-in',
        'body':
            'Take a minute to name what feels heavy, hopeful, or unfinished.',
        'hour': nextSettings.morningHour,
        'minute': nextSettings.morningMinute,
        'repeats': true,
        'route': _buildWriteRoute(_morningPrefill),
      });
    }

    if (nextSettings.eveningPromptEnabled) {
      await _channel.invokeMethod<void>('scheduleCalendarNotification', {
        'id': _eveningId,
        'title': 'Evening wrap-up',
        'body': 'Capture what mattered today before it fades.',
        'hour': nextSettings.eveningHour,
        'minute': nextSettings.eveningMinute,
        'repeats': true,
        'route': _buildWriteRoute(_eveningPrefill),
      });
    }

    if (nextSettings.weeklyWyattPromptEnabled) {
      await _channel.invokeMethod<void>('scheduleCalendarNotification', {
        'id': _weeklyWyattId,
        'title': 'Wyatt check-in',
        'body': 'Add a quick activity or memory entry about Wyatt this week.',
        'hour': nextSettings.weeklyHour,
        'minute': nextSettings.weeklyMinute,
        'repeats': true,
        'route': _buildWriteRoute(_weeklyWyattPrefill),
      });
    }

    if (nextSettings.locationPromptsEnabled) {
      for (final place in nextSettings.places) {
        final entryContent = buildLocationNotificationContent(
          place,
          transition: 'entry',
          journalPatternProfile: journalPatternProfile,
        );
        await _channel.invokeMethod<void>('scheduleLocationNotification', {
          'id': _placeEntryNotificationId(place.id),
          'title': entryContent.title,
          'body': entryContent.body,
          'latitude': place.latitude,
          'longitude': place.longitude,
          'radius': place.radiusMeters,
          'notifyOnEntry': true,
          'notifyOnExit': false,
          'repeats': true,
          'categoryId': 'location_journal',
          'eventKind': 'location_nudge',
          'placeId': place.id,
          'placeName': place.name,
          'placeKind': place.kind,
          'transition': 'entry',
          'route': _buildWriteRoute(entryContent.writePrefill),
          'routeSage': _buildSageRoute(entryContent.sagePrefill),
        });

        final exitContent = buildLocationNotificationContent(
          place,
          transition: 'exit',
          journalPatternProfile: journalPatternProfile,
        );
        await _channel.invokeMethod<void>('scheduleLocationNotification', {
          'id': _placeExitNotificationId(place.id),
          'title': exitContent.title,
          'body': exitContent.body,
          'latitude': place.latitude,
          'longitude': place.longitude,
          'radius': place.radiusMeters,
          'notifyOnEntry': false,
          'notifyOnExit': true,
          'repeats': true,
          'categoryId': 'location_journal',
          'eventKind': 'location_nudge',
          'placeId': place.id,
          'placeName': place.name,
          'placeKind': place.kind,
          'transition': 'exit',
          'route': _buildWriteRoute(exitContent.writePrefill),
          'routeSage': _buildSageRoute(exitContent.sagePrefill),
        });
      }
    }

    await saveSettings(nextSettings);
  }

  List<String> _allNotificationIdsFor(NotificationNudgeSettings settings) {
    final ids = <String>[];
    ids.add(_morningId);
    ids.add(_eveningId);
    ids.add(_weeklyWyattId);
    ids.addAll(
      settings.places.expand(
        (place) => [
          _legacyPlaceNotificationId(place.id),
          _placeEntryNotificationId(place.id),
          _placeExitNotificationId(place.id),
        ],
      ),
    );
    return ids;
  }

  String _legacyPlaceNotificationId(String placeId) => 'nudge.place.$placeId';

  String _placeEntryNotificationId(String placeId) =>
      'nudge.place.entry.$placeId';

  String _placeExitNotificationId(String placeId) =>
      'nudge.place.exit.$placeId';

  String _buildWriteRoute(String prefill) {
    return Uri(
      path: '/write',
      queryParameters: {'prefill': prefill, 'source': 'nudge'},
    ).toString();
  }

  String _buildSageRoute(String prefill) {
    return Uri(
      path: '/sage',
      queryParameters: {
        'prefill': prefill,
        'auto_send': '1',
        'source': 'nudge',
      },
    ).toString();
  }

  static const _morningPrefill =
      'Morning check-in. What feels heavy, hopeful, or unfinished today?';
  static const _eveningPrefill =
      'Evening wrap-up. What happened today that deserves to be remembered?';
  static const _weeklyWyattPrefill =
      'Quick Wyatt check-in. What activity, memory, or moment with Wyatt stands out from this week?';

  Future<JournalPatternProfile?> buildJournalPatternProfile(
    NotificationNudgeSettings settings,
  ) async {
    if (!settings.journalPatternPromptsEnabled) return null;

    final homePlaces = settings.places.where((place) => place.kind == 'home');
    final workPlaces = settings.places.where((place) => place.kind == 'work');
    final hasHomePlace = homePlaces.isNotEmpty;
    final hasWorkPlace = workPlaces.isNotEmpty;
    final observedEvents = await loadObservedLocationEvents();
    final transitionStats = _inferTransitionStats(observedEvents);

    final entries = <Map<String, dynamic>>[];
    var page = 1;
    var hasMore = true;
    while (hasMore && entries.length < 80) {
      final timelinePage = await _api.getTimelinePage(page: page, limit: 20);
      entries.addAll(timelinePage.entries);
      hasMore = timelinePage.hasMore;
      page += 1;
      if (timelinePage.entries.isEmpty) break;
    }

    if (entries.isEmpty) {
      return JournalPatternProfile(
        entriesAnalyzed: 0,
        homeLooksStressful: false,
        hasHomePlace: hasHomePlace,
        hasWorkPlace: hasWorkPlace,
        workUsuallyLeadsHome: transitionStats.workExitUsuallyLeadsHome ||
            (hasHomePlace && hasWorkPlace),
        learnedWorkToHomeTransitions: transitionStats.workToHomeTransitions,
        totalObservedWorkExits: transitionStats.totalObservedWorkExits,
        wyattShowsUpAfterWork: false,
        familyShowsUpInHeavierEntries: false,
        topStressWindowLabel: null,
        reasons: [
          if (transitionStats.workToHomeTransitions > 0)
            'The app has already observed ${transitionStats.workToHomeTransitions} local work-to-home transition ${transitionStats.workToHomeTransitions == 1 ? 'sequence' : 'sequences'} on this device.',
          if (hasHomePlace && hasWorkPlace)
            'Work and home are both saved, so nudges can treat that transition as meaningful even before journal patterns fill in.',
        ],
      );
    }

    final homeKeywords = <String>{
      'home',
      'house',
      'apartment',
      'family',
      'angelina',
      'wife',
      'girlfriend',
      'partner',
    };
    final workKeywords = <String>{
      'work',
      'job',
      'office',
      'shift',
      'coworker',
      'manager',
      'boss',
    };
    final stressKeywords = <String>{
      'stress',
      'stressed',
      'anxious',
      'anxiety',
      'panic',
      'angry',
      'rage',
      'fight',
      'argument',
      'chaos',
      'overwhelmed',
      'tense',
      'drained',
      'upset',
      'meltdown',
      'craziness',
    };
    final familyKeywords = <String>{
      'angelina',
      'wyatt',
      'family',
      'wife',
      'partner',
      'home',
      'kid',
      'son',
      'daughter',
    };

    final stressWindowCounts = <String, int>{};
    var homeStressSignals = 0.0;
    var workStressSignals = 0.0;
    var familyStressSignals = 0;
    var afterWorkWyattSignals = 0;

    for (final entry in entries.take(80)) {
      final text = _entryText(entry);
      if (text.isEmpty) continue;

      final severity = (entry['severity_score'] as num?)?.toDouble() ?? 0.0;
      final stressHits = _keywordHits(text, stressKeywords);
      final homeHits = _keywordHits(text, homeKeywords);
      final workHits = _keywordHits(text, workKeywords);
      final familyHits = _keywordHits(text, familyKeywords);
      final stressWeight = stressHits > 0 || severity >= 0.55
          ? 1.0 + severity + (stressHits * 0.35)
          : 0.0;

      if (homeHits > 0 && stressWeight > 0) {
        homeStressSignals += stressWeight + (homeHits * 0.25);
      }
      if (workHits > 0 && stressWeight > 0) {
        workStressSignals += stressWeight + (workHits * 0.2);
      }
      if (familyHits > 0 && stressWeight > 0) {
        familyStressSignals += 1;
      }

      final timestamp = _entryDateTime(entry);
      if (timestamp != null &&
          timestamp.hour >= 16 &&
          _containsWord(text, 'wyatt')) {
        afterWorkWyattSignals += 1;
      }

      if (stressWeight > 0 && timestamp != null) {
        final windowLabel = _stressWindowLabel(timestamp);
        stressWindowCounts.update(windowLabel, (count) => count + 1,
            ifAbsent: () => 1);
      }
    }

    String? topStressWindowLabel;
    var topStressWindowCount = 0;
    stressWindowCounts.forEach((label, count) {
      if (count > topStressWindowCount) {
        topStressWindowLabel = label;
        topStressWindowCount = count;
      }
    });

    final homeLooksStressful =
        homeStressSignals >= 2.2 && homeStressSignals >= workStressSignals;
    final workUsuallyLeadsHome = transitionStats.workExitUsuallyLeadsHome ||
        (hasHomePlace && hasWorkPlace);
    final wyattShowsUpAfterWork = afterWorkWyattSignals >= 2;
    final familyShowsUpInHeavierEntries = familyStressSignals >= 2;

    final reasons = <String>[
      if (transitionStats.workToHomeTransitions > 0)
        'The app observed ${transitionStats.workToHomeTransitions} work-exit to home-arrival ${transitionStats.workToHomeTransitions == 1 ? 'transition' : 'transitions'} locally${transitionStats.totalObservedWorkExits > 0 ? ' out of ${transitionStats.totalObservedWorkExits} tracked work exits' : ''}.',
      if (homeLooksStressful)
        'Recent entries use heavier stress language around home and family context than other saved-place patterns.',
      if (workUsuallyLeadsHome && transitionStats.workToHomeTransitions == 0)
        'You have both work and home saved, so leaving work can be treated as a likely transition toward home.',
      if (wyattShowsUpAfterWork)
        'Wyatt comes up repeatedly in later-day entries, so after-work nudges can protect that part of the routine too.',
      if (familyShowsUpInHeavierEntries)
        'Family-related language appears in multiple heavier entries, which makes home-entry prompts more context-aware.',
      if (topStressWindowLabel != null)
        'Your heavier entries cluster most around $topStressWindowLabel.',
    ];

    return JournalPatternProfile(
      entriesAnalyzed: entries.take(80).length,
      homeLooksStressful: homeLooksStressful,
      hasHomePlace: hasHomePlace,
      hasWorkPlace: hasWorkPlace,
      workUsuallyLeadsHome: workUsuallyLeadsHome,
      learnedWorkToHomeTransitions: transitionStats.workToHomeTransitions,
      totalObservedWorkExits: transitionStats.totalObservedWorkExits,
      wyattShowsUpAfterWork: wyattShowsUpAfterWork,
      familyShowsUpInHeavierEntries: familyShowsUpInHeavierEntries,
      topStressWindowLabel: topStressWindowLabel,
      reasons: reasons,
    );
  }

  ({String title, String body, String writePrefill, String sagePrefill})
      buildLocationNotificationContent(
    NudgePlace place, {
    required String transition,
    JournalPatternProfile? journalPatternProfile,
  }) {
    if (journalPatternProfile != null &&
        journalPatternProfile.supportsSmartPromptFor(
          place,
          transition: transition,
        )) {
      final smartPrompts = _smartPatternPromptVariants(
        place,
        transition: transition,
        journalPatternProfile: journalPatternProfile,
      );
      final smartIndex = _dailyPromptIndex(
        seed: '${place.id}:$transition:${place.kind}:smart',
        count: smartPrompts.length,
      );
      return smartPrompts[smartIndex];
    }

    final prompts = _locationPromptVariants(place, transition: transition);
    final index = _dailyPromptIndex(
      seed: '${place.id}:$transition:${place.kind}',
      count: prompts.length,
    );
    return prompts[index];
  }
}

class _TransitionStats {
  const _TransitionStats({
    required this.totalObservedWorkExits,
    required this.workToHomeTransitions,
    required this.workExitUsuallyLeadsHome,
  });

  final int totalObservedWorkExits;
  final int workToHomeTransitions;
  final bool workExitUsuallyLeadsHome;
}

_TransitionStats _inferTransitionStats(List<LocationNudgeEvent> events) {
  if (events.isEmpty) {
    return const _TransitionStats(
      totalObservedWorkExits: 0,
      workToHomeTransitions: 0,
      workExitUsuallyLeadsHome: false,
    );
  }

  final sorted = [...events]
    ..sort((a, b) => a.deliveredAt.compareTo(b.deliveredAt));
  final workExits = sorted
      .where((event) => event.placeKind == 'work' && event.transition == 'exit')
      .toList();
  var workToHomeTransitions = 0;

  for (final event in workExits) {
    final matchingHomeArrival = sorted.any(
      (candidate) =>
          candidate.deliveredAt.isAfter(event.deliveredAt) &&
          candidate.deliveredAt.difference(event.deliveredAt).inMinutes <=
              240 &&
          candidate.placeKind == 'home' &&
          candidate.transition == 'entry',
    );
    if (matchingHomeArrival) {
      workToHomeTransitions += 1;
    }
  }

  final totalObservedWorkExits = workExits.length;
  final ratio = totalObservedWorkExits == 0
      ? 0.0
      : workToHomeTransitions / totalObservedWorkExits;

  return _TransitionStats(
    totalObservedWorkExits: totalObservedWorkExits,
    workToHomeTransitions: workToHomeTransitions,
    workExitUsuallyLeadsHome: workToHomeTransitions >= 2 && ratio >= 0.5,
  );
}

List<({String title, String body, String writePrefill, String sagePrefill})>
    _smartPatternPromptVariants(
  NudgePlace place, {
  required String transition,
  required JournalPatternProfile journalPatternProfile,
}) {
  if (place.kind == 'work' && transition == 'exit') {
    final extraLine = journalPatternProfile.wyattShowsUpAfterWork
        ? 'Keep whatever matters for Wyatt and tonight, and let the rest stay at work.'
        : 'Name what needs to stay at work before the next environment starts pressing on you.';
    return [
      (
        title: 'Heading home soon?',
        body:
            'Take 30 seconds before the shift changes. What are you carrying from work, and what do you need to protect in yourself tonight?',
        writePrefill:
            'I am leaving ${place.name} and usually head home after work. Before the next environment takes over, what am I carrying from work, what needs to stay here, and what do I need to protect in myself tonight?',
        sagePrefill:
            "I'm leaving ${place.name} and usually heading home next. Help me separate what belongs to work from what I need to stay steady for tonight.",
      ),
      (
        title: 'Before you walk into the next wave...',
        body:
            'You usually head home after work. Clear what belongs to this shift and decide what version of you needs protection tonight.',
        writePrefill:
            'I just left ${place.name}. I usually go home next. What belongs to this shift, what does not, and what inner boundary do I need before I walk into tonight?',
        sagePrefill:
            "I'm leaving ${place.name} and usually going home. Help me do a fast decompression so I do not drag the whole workday into tonight.",
      ),
      (
        title: 'Work ends here if you let it.',
        body: extraLine,
        writePrefill:
            'I am heading out from ${place.name}. Home has been carrying some stress lately. What do I want to leave here, and what do I need to keep steady as I head into tonight?',
        sagePrefill:
            "I'm leaving ${place.name}. Home has felt heavier lately, and I want help entering tonight with more intention and less spillover.",
      ),
    ];
  }

  if (place.kind == 'home' && transition == 'entry') {
    final timingLine = journalPatternProfile.topStressWindowLabel != null
        ? 'This is one of the times your entries tend to read heaviest.'
        : 'Your recent entries suggest home has been carrying a lot.';
    return [
      (
        title: 'Walking into a lot tonight?',
        body:
            'Home has looked heavier in recent entries. What do you need to protect in yourself before the temperature rises?',
        writePrefill:
            'I just arrived at ${place.name}. Home has felt heavy lately. What energy am I walking into, what do I need to protect in myself tonight, and what would help me stay steady?',
        sagePrefill:
            "I'm home and this environment has felt heavy lately. Help me name what I'm walking into and what I need to stay grounded tonight.",
      ),
      (
        title: 'Before home takes over...',
        body:
            'Name the atmosphere, the trigger risk, and the part of yourself you do not want to lose tonight.',
        writePrefill:
            'I am at ${place.name}. Before the night moves fast, what is the emotional temperature here, what feels risky, and what part of me do I want to protect tonight?',
        sagePrefill:
            "I'm at ${place.name}. Help me take a quick emotional reading of home and decide how I want to show up tonight.",
      ),
      (
        title: 'Home check-in',
        body: timingLine,
        writePrefill:
            'I am at ${place.name}. What kind of version of home am I walking into right now, what do I expect, and what support or boundary do I need tonight?',
        sagePrefill:
            "I'm home. Help me take a clear read on the environment and figure out what I need before tonight unfolds.",
      ),
    ];
  }

  return _locationPromptVariants(place, transition: transition);
}

List<({String title, String body, String writePrefill, String sagePrefill})>
    _locationPromptVariants(
  NudgePlace place, {
  required String transition,
}) {
  final isExit = transition == 'exit';
  return switch (place.kind) {
    'park' || 'play' => isExit
        ? [
            (
              title: 'Leaving ${place.name}?',
              body: 'Catch the best moment before the ride home edits it.',
              writePrefill:
                  'I am leaving ${place.name}. What felt alive, fun, hard, or worth remembering about this outing, especially with Wyatt if he was part of it?',
              sagePrefill:
                  "I'm leaving ${place.name}. Help me turn this outing into a vivid journal note and pull out the detail most worth keeping.",
            ),
            (
              title: '${place.name} still in your head?',
              body: 'Grab the laugh, meltdown, win, or tiny detail now.',
              writePrefill:
                  'I just wrapped up time at ${place.name}. I want to capture the standout moment, the emotional tone, and anything I do not want to lose.',
              sagePrefill:
                  "I'm heading out from ${place.name}. Help me quickly log the emotional high points, friction points, and anything Wyatt-related.",
            ),
            (
              title: 'Before ${place.name} fades...',
              body: 'Save the memory while it still has color.',
              writePrefill:
                  'I am leaving ${place.name}. What happened here, what mattered, and what detail will I be glad I wrote down later?',
              sagePrefill:
                  "I'm leaving ${place.name}. Help me write a sharp note that preserves the texture of this outing.",
            ),
          ]
        : [
            (
              title: 'At ${place.name} with Wyatt?',
              body: 'Catch the activity before the details disappear.',
              writePrefill:
                  'I am at ${place.name}. If Wyatt is here or we are doing something together, I want to capture the activity, what happened, and how it felt.',
              sagePrefill:
                  "I'm at ${place.name}. Help me capture this outing, including what we are doing, the mood, and any detail worth remembering.",
            ),
            (
              title: '${place.name} moment incoming?',
              body: 'Log the scene while you are still inside it.',
              writePrefill:
                  'I just arrived at ${place.name}. What are we doing, what is the vibe, and what do I want to notice before this moment passes?',
              sagePrefill:
                  "I'm at ${place.name}. Help me notice what matters about this activity and turn it into a journal entry.",
            ),
            (
              title: 'Want to freeze this ${place.name} moment?',
              body: 'A quick note now can save the whole memory later.',
              writePrefill:
                  'I am at ${place.name}. I want to capture the setup, who is here, what matters about this outing, and how it feels right now.',
              sagePrefill:
                  "I'm at ${place.name}. Help me log the outing in a way that preserves both the facts and the feeling.",
            ),
          ],
    'doctor' || 'health' => isExit
        ? [
            (
              title: 'Walking out of ${place.name}?',
              body:
                  'Catch the takeaway, feeling, or next step before it blurs.',
              writePrefill:
                  'I am leaving ${place.name}. What happened in the appointment, what matters next, and how do I feel walking out right now?',
              sagePrefill:
                  "I'm leaving ${place.name}. Help me log the appointment, next steps, emotions, and any Wyatt or family implications.",
            ),
            (
              title: 'Before the appointment fog sets in...',
              body: 'Write the note your future self will need tonight.',
              writePrefill:
                  'I just left ${place.name}. I want to capture what was said, what I need to remember, and what emotion is sticking to me.',
              sagePrefill:
                  "I'm leaving ${place.name}. Help me turn the appointment into a clean note with concrete follow-ups and emotional context.",
            ),
            (
              title: 'Leaving ${place.name} with a lot?',
              body: 'Drop the facts and the feeling in one place.',
              writePrefill:
                  'I am heading out from ${place.name}. What is the headline, what do I need to do next, and what did this stir up in me?',
              sagePrefill:
                  "I'm heading out from ${place.name}. Help me process the medical or therapy visit and save the important parts.",
            ),
          ]
        : [
            (
              title: 'At ${place.name}?',
              body:
                  'Mark the appointment, question, or worry before it runs ahead of you.',
              writePrefill:
                  'I am at ${place.name}. I want to log why I am here, what I am worried about, what I want answered, and how I feel going in.',
              sagePrefill:
                  "I'm at ${place.name}. Help me log the appointment context, what I want to ask, and the emotional state I'm bringing in.",
            ),
            (
              title: 'Quick note before ${place.name} starts?',
              body: 'Capture what matters going in.',
              writePrefill:
                  'I just arrived at ${place.name}. What do I hope to learn, say, or remember from this appointment?',
              sagePrefill:
                  "I'm at ${place.name}. Help me create a focused note before this appointment begins.",
            ),
            (
              title: '${place.name} check-in',
              body: 'Name the concern, the hope, or the question.',
              writePrefill:
                  'I am at ${place.name}. I want to write down the key question, concern, or intention I have before this visit unfolds.',
              sagePrefill:
                  "I'm at ${place.name}. Help me get clear on what matters most before this visit.",
            ),
          ],
    'school' => isExit
        ? [
            (
              title: 'Leaving ${place.name}?',
              body:
                  'Catch the pickup detail, school note, or Wyatt moment now.',
              writePrefill:
                  'I am leaving ${place.name}. What happened here, what do I need to remember, and was there anything important about Wyatt, school, or logistics?',
              sagePrefill:
                  "I'm leaving ${place.name}. Help me log the school moment, logistics, and emotional tone before I lose it.",
            ),
            (
              title: 'School-day residue from ${place.name}?',
              body: 'Save the detail that matters before routine swallows it.',
              writePrefill:
                  'I just left ${place.name}. What was the key moment, update, or feeling I want to remember from this school stop?',
              sagePrefill:
                  "I'm leaving ${place.name}. Help me capture the important school or Wyatt-related detail from this stop.",
            ),
            (
              title: 'Before pickup and dropoff blur together...',
              body: 'Log the one thing worth keeping from this stop.',
              writePrefill:
                  'I am heading away from ${place.name}. What happened, what shifted, and what matters about this school moment?',
              sagePrefill:
                  "I'm leaving ${place.name}. Help me turn this school transition into a useful journal note.",
            ),
          ]
        : [
            (
              title: 'At ${place.name}?',
              body:
                  'Log the school moment, pickup detail, or anything about Wyatt.',
              writePrefill:
                  'I am at ${place.name}. I want to note anything important about pickup, dropoff, school events, Wyatt, or how this moment feels.',
              sagePrefill:
                  "I'm at ${place.name}. Help me capture the school context, logistics, and anything emotionally important about this moment.",
            ),
            (
              title: 'School moment worth catching?',
              body: 'A fast note now can save the whole thread later.',
              writePrefill:
                  'I just arrived at ${place.name}. What is happening here, what matters, and what do I not want to forget?',
              sagePrefill:
                  "I'm at ${place.name}. Help me log the school moment in a way that will still make sense later.",
            ),
            (
              title: '${place.name} check-in',
              body: 'Save the useful detail while you are in it.',
              writePrefill:
                  'I am at ${place.name}. I want to capture the school logistics, Wyatt-related context, and emotional tone of this stop.',
              sagePrefill:
                  "I'm at ${place.name}. Help me write a clear note about this school stop and why it matters.",
            ),
          ],
    'work' => isExit
        ? [
            (
              title: 'Leaving ${place.name}?',
              body: 'What deserves to leave work with you, and what does not?',
              writePrefill:
                  'I am leaving ${place.name}. What happened today, what is still stuck to me, and what do I want to set down before I carry it home?',
              sagePrefill:
                  "I'm leaving ${place.name}. Help me process the workday, separate signal from noise, and save anything worth journaling.",
            ),
            (
              title: 'Work day complete?',
              body: 'Clear the static before the next part of your day starts.',
              writePrefill:
                  'I just left ${place.name}. What drained me, what moved forward, and what do I not want to drag into the rest of my day?',
              sagePrefill:
                  "I'm leaving ${place.name}. Help me unpack the work stress, wins, and unresolved pieces in a clean note.",
            ),
            (
              title: 'Before work follows you home...',
              body: 'Drop the pressure, the win, or the unfinished thing here.',
              writePrefill:
                  'I am heading out from ${place.name}. What felt heavy, what mattered, and what boundary do I want between work and the rest of today?',
              sagePrefill:
                  "I'm leaving ${place.name}. Help me turn the day into a grounded journal note instead of carrying it around.",
            ),
          ]
        : [
            (
              title: 'At ${place.name}?',
              body:
                  'What is the one thing you do not want work to swallow today?',
              writePrefill:
                  'I am at ${place.name}. What matters most today, what feels tense or unfinished already, and what do I want to remember about this workday?',
              sagePrefill:
                  "I'm at ${place.name}. Help me frame this workday, including priorities, stress, and anything I want to keep sight of.",
            ),
            (
              title: 'Work mode at ${place.name}?',
              body: 'Set the tone before the day starts happening to you.',
              writePrefill:
                  'I just arrived at ${place.name}. What is today asking from me, what am I worried about, and what would count as a good day?',
              sagePrefill:
                  "I'm at ${place.name}. Help me create a quick grounding note before the workday takes over.",
            ),
            (
              title: '${place.name} reset',
              body: 'Name the pressure or intention before it multiplies.',
              writePrefill:
                  'I am at ${place.name}. I want to capture the pressure, intention, or decision sitting with me as this work block begins.',
              sagePrefill:
                  "I'm at ${place.name}. Help me get honest about what this workday feels like before it moves too fast.",
            ),
          ],
    'home' => isExit
        ? [
            (
              title: 'Heading out from ${place.name}?',
              body: 'What feeling are you carrying out the door today?',
              writePrefill:
                  'I am leaving ${place.name}. What is the emotional weather at home, what am I carrying with me, and what do I want to leave here instead?',
              sagePrefill:
                  "I'm leaving ${place.name}. Help me capture the home mood, family context, and what I'm carrying into the rest of the day.",
            ),
            (
              title: 'Leaving home with a lot on you?',
              body: 'Set down the feeling before the next thing starts.',
              writePrefill:
                  'I just left ${place.name}. What happened at home, what is lingering, and how do I want to show up after this?',
              sagePrefill:
                  "I'm leaving ${place.name}. Help me process the home transition and name what I am carrying forward.",
            ),
            (
              title: 'Before the day pulls you away...',
              body: 'Catch the mood you are stepping out of.',
              writePrefill:
                  'I am heading away from ${place.name}. What was the tone at home, what mattered in that moment, and what do I want to remember later?',
              sagePrefill:
                  "I'm leaving ${place.name}. Help me turn this home transition into a grounded journal note.",
            ),
          ]
        : [
            (
              title: 'Back at ${place.name}?',
              body: 'Capture a quick family, home, or Wyatt-related moment.',
              writePrefill:
                  'I am at ${place.name}. I want to capture what is happening here, any Wyatt-related moment, and how the environment feels right now.',
              sagePrefill:
                  "I'm at ${place.name}. Help me log the home or family moment and name what matters about the atmosphere.",
            ),
            (
              title: 'Home has a mood right now.',
              body: 'Name it before the night blurs the edges.',
              writePrefill:
                  'I just arrived at ${place.name}. What is the mood at home, what is happening, and what do I want to remember about this moment?',
              sagePrefill:
                  "I'm at ${place.name}. Help me capture the tone of home, the family context, and the detail worth saving.",
            ),
            (
              title: '${place.name} check-in',
              body: 'What kind of version of home are you walking into?',
              writePrefill:
                  'I am at ${place.name}. I want to write down the emotional tone, the family energy, and anything important happening here.',
              sagePrefill:
                  "I'm at ${place.name}. Help me log what kind of home moment this is and why it matters.",
            ),
          ],
    _ => isExit
        ? [
            (
              title: 'Leaving ${place.name}?',
              body: 'Save the detail, feeling, or shift before it disappears.',
              writePrefill:
                  'I am leaving ${place.name}. What happened here, why did it matter, and what feeling am I carrying away?',
              sagePrefill:
                  "I'm leaving ${place.name}. Help me figure out what mattered about this stop and turn it into a journal note.",
            ),
            (
              title: 'Before ${place.name} becomes a blur...',
              body: 'What is the one thing worth keeping from this stop?',
              writePrefill:
                  'I just left ${place.name}. I want to capture the standout detail, the emotional tone, and why this mattered today.',
              sagePrefill:
                  "I'm leaving ${place.name}. Help me capture the signal from this stop before it fades into the day.",
            ),
            (
              title: 'Walking away from ${place.name} with something?',
              body: 'Drop it here while it is still clear.',
              writePrefill:
                  'I am heading out from ${place.name}. What happened, what shifted in me, and what deserves a quick note?',
              sagePrefill:
                  "I'm leaving ${place.name}. Help me make sense of this stop and save the part that matters.",
            ),
          ]
        : [
            (
              title: 'At ${place.name}?',
              body: 'Want to save a quick note about what happened here?',
              writePrefill:
                  'I am at ${place.name}. I want to capture what happened here, why this place mattered, and whether it connects to Wyatt, family, or my day.',
              sagePrefill:
                  "I'm at ${place.name}. Help me figure out the right kind of note for this place and what matters about this moment.",
            ),
            (
              title: '${place.name} might matter more than it looks.',
              body: 'Grab a note while you are still inside the moment.',
              writePrefill:
                  'I just arrived at ${place.name}. What is happening, what feels important, and why might this place matter today?',
              sagePrefill:
                  "I'm at ${place.name}. Help me notice whether this stop belongs in my journal and how to capture it.",
            ),
            (
              title: 'Quick pulse from ${place.name}',
              body: 'Save the moment before the next thing takes it.',
              writePrefill:
                  'I am at ${place.name}. I want to note the context, the emotional tone, and anything I may want to revisit later.',
              sagePrefill:
                  "I'm at ${place.name}. Help me turn this moment into a useful, specific journal note.",
            ),
          ],
  };
}

String _entryText(Map<String, dynamic> entry) {
  final parts = [
    entry['text']?.toString(),
    entry['normalized_text']?.toString(),
    entry['summary_text']?.toString(),
  ].whereType<String>().map((value) => value.trim()).where((v) => v.isNotEmpty);
  return parts.join(' ').toLowerCase();
}

int _keywordHits(String text, Set<String> keywords) {
  var hits = 0;
  for (final keyword in keywords) {
    if (text.contains(keyword)) hits += 1;
  }
  return hits;
}

bool _containsWord(String text, String keyword) {
  return RegExp('\\b${RegExp.escape(keyword)}\\b', caseSensitive: false)
      .hasMatch(text);
}

DateTime? _entryDateTime(Map<String, dynamic> entry) {
  final raw =
      entry['ingested_at']?.toString() ?? entry['entry_date']?.toString();
  if (raw == null || raw.trim().isEmpty) return null;
  return DateTime.tryParse(raw)?.toLocal();
}

String _stressWindowLabel(DateTime dateTime) {
  final weekday = switch (dateTime.weekday) {
    DateTime.monday => 'Monday',
    DateTime.tuesday => 'Tuesday',
    DateTime.wednesday => 'Wednesday',
    DateTime.thursday => 'Thursday',
    DateTime.friday => 'Friday',
    DateTime.saturday => 'Saturday',
    DateTime.sunday => 'Sunday',
    _ => 'Unknown',
  };
  final timeBand = switch (dateTime.hour) {
    >= 5 && < 12 => 'mornings',
    >= 12 && < 17 => 'afternoons',
    >= 17 && < 22 => 'evenings',
    _ => 'late nights',
  };
  return '$weekday $timeBand';
}

int _dailyPromptIndex({
  required String seed,
  required int count,
}) {
  if (count <= 1) return 0;
  final now = DateTime.now();
  final startOfYear = DateTime(now.year, 1, 1);
  final dayOfYear = now.difference(startOfYear).inDays;
  return (seed.hashCode + dayOfYear).abs() % count;
}

String inferPlaceKind(String? rawName) {
  final name = (rawName ?? '').trim().toLowerCase();
  if (name.isEmpty) return 'general';

  if (_containsAny(name, [
    'park',
    'playground',
    'zoo',
    'museum',
    'pool',
    'soccer',
    'baseball',
    'basketball',
    'skate',
    'ice rink',
    'arcade',
  ])) {
    return 'park';
  }
  if (_containsAny(name, [
    'doctor',
    'dr ',
    'dr.',
    'pediatric',
    'hospital',
    'clinic',
    'dentist',
    'therapy',
    'urgent care',
    'medical',
    'health',
  ])) {
    return 'doctor';
  }
  if (_containsAny(name, [
    'school',
    'elementary',
    'middle school',
    'high school',
    'daycare',
    'preschool',
    'academy',
  ])) {
    return 'school';
  }
  if (_containsAny(name, [
    'home',
    'house',
    'apartment',
    'condo',
    'mom',
    'dad',
    'grandma',
    'grandpa',
  ])) {
    return 'home';
  }
  if (_containsAny(name, [
    'work',
    'office',
    'job',
    'warehouse',
    'shop',
    'store',
    'target',
    'walmart',
    'costco',
  ])) {
    return 'work';
  }
  return 'general';
}

bool _containsAny(String value, List<String> needles) {
  for (final needle in needles) {
    if (value.contains(needle)) return true;
  }
  return false;
}

bool placesLikelyMatch(
  NudgePlace place, {
  String? candidateName,
  double? latitude,
  double? longitude,
  double coordinateThresholdMeters = 150,
}) {
  final normalizedCandidate = candidateName?.trim().toLowerCase() ?? '';
  final normalizedPlace = place.name.trim().toLowerCase();
  if (normalizedCandidate.isNotEmpty &&
      normalizedPlace == normalizedCandidate) {
    return true;
  }

  if (latitude == null || longitude == null) return false;
  final distance = _distanceMeters(
    latitude,
    longitude,
    place.latitude,
    place.longitude,
  );
  return distance <= coordinateThresholdMeters;
}

double _distanceMeters(
  double latitudeA,
  double longitudeA,
  double latitudeB,
  double longitudeB,
) {
  const metersPerDegreeLatitude = 111320.0;
  final averageLatitudeRadians =
      ((latitudeA + latitudeB) / 2) * 0.017453292519943295;
  final metersPerDegreeLongitude =
      metersPerDegreeLatitude * math.cos(averageLatitudeRadians);
  final latMeters = (latitudeA - latitudeB) * metersPerDegreeLatitude;
  final lngMeters = (longitudeA - longitudeB) * metersPerDegreeLongitude;
  return math.sqrt((latMeters * latMeters) + (lngMeters * lngMeters));
}
