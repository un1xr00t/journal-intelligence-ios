import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

class NotificationNudgeService {
  static const _channel = MethodChannel('journal_intelligence/notifications');
  static const _prefsKey = 'notification_nudges.settings.v1';
  static const _morningId = 'nudge.morning';
  static const _eveningId = 'nudge.evening';
  static const _weeklyWyattId = 'nudge.weekly_wyatt';

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

  Future<void> syncSchedules(NotificationNudgeSettings nextSettings) async {
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
        final notificationContent = buildLocationNotificationContent(place);
        await _channel.invokeMethod<void>('scheduleLocationNotification', {
          'id': _placeNotificationId(place.id),
          'title': notificationContent.title,
          'body': notificationContent.body,
          'latitude': place.latitude,
          'longitude': place.longitude,
          'radius': place.radiusMeters,
          'notifyOnEntry': true,
          'notifyOnExit': false,
          'repeats': true,
          'categoryId': 'location_journal',
          'route': _buildWriteRoute(_locationPrefill(place)),
          'routeSage': _buildSageRoute(_locationSagePrefill(place)),
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
    ids.addAll(settings.places.map((place) => _placeNotificationId(place.id)));
    return ids;
  }

  String _placeNotificationId(String placeId) => 'nudge.place.$placeId';

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

  String _locationPrefill(NudgePlace place) {
    return switch (place.kind) {
      'park' ||
      'play' =>
        'I am at ${place.name}. If Wyatt is here or we are doing something together, I want to capture the activity, what happened, and how it felt.',
      'doctor' ||
      'health' =>
        'I am at ${place.name}. I want to log the appointment, what was discussed, anything important about Wyatt or family logistics, and how I felt leaving.',
      'school' =>
        'I am at ${place.name}. I want to note anything important about pickup, dropoff, school events, Wyatt, or how this moment felt.',
      'work' =>
        'I am at ${place.name}. I want to capture anything important about work, scheduling, stress, Wyatt planning, or what happened here.',
      'home' =>
        'I am at ${place.name}. I want to capture what is happening here, any Wyatt-related moment, and how the environment feels right now.',
      _ =>
        'I am at ${place.name}. I want to capture what happened here, why this place mattered, and whether it connects to Wyatt, family, or my day.',
    };
  }

  String _locationSagePrefill(NudgePlace place) {
    final focus = switch (place.kind) {
      'park' || 'play' => 'an activity or outing with Wyatt',
      'doctor' || 'health' => 'an appointment or health-related note',
      'school' => 'a school-related moment or logistics note',
      'work' => 'a work-related moment or schedule note',
      'home' => 'a home or family moment',
      _ => 'the right kind of journal note for this place',
    };
    return "I'm at or near ${place.name}. Use web search if it's enabled to confirm the correct place name, tell me what kind of place this is, and help me log $focus.";
  }

  ({String title, String body}) buildLocationNotificationContent(
      NudgePlace place) {
    return switch (place.kind) {
      'park' || 'play' => (
          title: 'At ${place.name} with Wyatt?',
          body: 'Capture the activity before the details disappear.'
        ),
      'doctor' || 'health' => (
          title: 'Leaving ${place.name}?',
          body:
              'Save a quick note about the appointment, takeaway, or next step.'
        ),
      'school' => (
          title: 'At ${place.name}?',
          body: 'Log the school moment, pickup detail, or anything about Wyatt.'
        ),
      'work' => (
          title: 'At ${place.name}?',
          body:
              'Want to log anything important about work, stress, or scheduling?'
        ),
      'home' => (
          title: 'At ${place.name}?',
          body: 'Capture a quick family, home, or Wyatt-related moment.'
        ),
      _ => (
          title: 'At ${place.name}?',
          body: 'Want to save a quick note about what happened here?'
        ),
    };
  }
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
