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
    required this.latitude,
    required this.longitude,
    this.radiusMeters = 200,
  });

  final String id;
  final String name;
  final double latitude;
  final double longitude;
  final double radiusMeters;

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'latitude': latitude,
      'longitude': longitude,
      'radiusMeters': radiusMeters,
    };
  }

  factory NudgePlace.fromJson(Map<String, dynamic> json) {
    return NudgePlace(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? 'Saved Place',
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
        await _channel.invokeMethod<void>('scheduleLocationNotification', {
          'id': _placeNotificationId(place.id),
          'title': 'At ${place.name}?',
          'body': 'If this is a Wyatt moment, save a quick activity entry now.',
          'latitude': place.latitude,
          'longitude': place.longitude,
          'radius': place.radiusMeters,
          'notifyOnEntry': true,
          'notifyOnExit': false,
          'repeats': true,
          'categoryId': 'location_journal',
          'route': _buildWriteRoute(_locationPrefill(place.name)),
          'routeSage': _buildSageRoute(_locationSagePrefill(place.name)),
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

  String _locationPrefill(String placeName) {
    return 'I am at $placeName. If Wyatt is here or this place matters to us, I want to capture the activity, what happened, and how it felt.';
  }

  String _locationSagePrefill(String placeName) {
    return "I'm at or near $placeName. Use web search if it's enabled to confirm the correct place name, tell me what this location is, and help me log a quick activity or memory with Wyatt.";
  }
}
