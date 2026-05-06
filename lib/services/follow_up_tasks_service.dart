import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'package:image/image.dart' as img;
import 'package:shared_preferences/shared_preferences.dart';

import 'api_service.dart';
import 'local_storage_paths.dart';

const _portableImageMaxBytes = 24 * 1024 * 1024;

DateTime _startOfDay(DateTime date) {
  return DateTime(date.year, date.month, date.day);
}

String? _normalizedText(dynamic value) {
  final text = value?.toString().trim();
  if (text == null || text.isEmpty) return null;
  return text;
}

class FollowUpAttachment {
  const FollowUpAttachment({
    required this.name,
    required this.path,
    required this.extension,
    this.previewPath,
    this.previewBase64,
    this.imageBase64,
  });

  final String name;
  final String path;
  final String extension;
  final String? previewPath;
  final String? previewBase64;
  final String? imageBase64;

  bool get isImage => switch (extension.toLowerCase()) {
        'jpg' || 'jpeg' || 'png' || 'webp' || 'gif' || 'heic' || 'heif' => true,
        _ => false,
      };

  String get displayExtension =>
      extension.isNotEmpty ? extension.toUpperCase() : 'FILE';

  FollowUpAttachment copyWith({
    String? name,
    String? path,
    String? extension,
    String? previewPath,
    String? previewBase64,
    String? imageBase64,
  }) {
    return FollowUpAttachment(
      name: name ?? this.name,
      path: path ?? this.path,
      extension: extension ?? this.extension,
      previewPath: previewPath ?? this.previewPath,
      previewBase64: previewBase64 ?? this.previewBase64,
      imageBase64: imageBase64 ?? this.imageBase64,
    );
  }

  Map<String, dynamic> toJson() => {
        'name': name,
        'path': path,
        'extension': extension,
        if (previewPath != null && previewPath!.trim().isNotEmpty)
          'preview_path': previewPath,
        if (previewBase64 != null && previewBase64!.trim().isNotEmpty)
          'preview_base64': previewBase64,
        if (imageBase64 != null && imageBase64!.trim().isNotEmpty)
          'image_base64': imageBase64,
      };

  factory FollowUpAttachment.fromJson(Map<String, dynamic> json) {
    return FollowUpAttachment(
      name: _normalizedText(json['name']) ?? 'attachment',
      path: _normalizedText(json['path']) ?? '',
      extension: _normalizedText(json['extension']) ?? '',
      previewPath: _normalizedText(json['preview_path']),
      previewBase64: _normalizedText(json['preview_base64']),
      imageBase64: _normalizedText(json['image_base64']),
    );
  }
}

class FollowUpComment {
  const FollowUpComment({
    required this.id,
    required this.body,
    required this.createdAt,
    this.attachments = const [],
  });

  final String id;
  final String body;
  final DateTime createdAt;
  final List<FollowUpAttachment> attachments;

  FollowUpComment copyWith({
    String? id,
    String? body,
    DateTime? createdAt,
    List<FollowUpAttachment>? attachments,
  }) {
    return FollowUpComment(
      id: id ?? this.id,
      body: body ?? this.body,
      createdAt: createdAt ?? this.createdAt,
      attachments: attachments ?? this.attachments,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'body': body,
        'created_at': createdAt.toIso8601String(),
        'attachments': attachments.map((item) => item.toJson()).toList(),
      };

  factory FollowUpComment.fromJson(Map<String, dynamic> json) {
    return FollowUpComment(
      id: json['id']?.toString() ?? '',
      body: _normalizedText(json['body']) ?? '',
      createdAt: DateTime.tryParse(json['created_at']?.toString() ?? '') ??
          DateTime.now(),
      attachments: (json['attachments'] as List?)
              ?.whereType<Map>()
              .map(
                (item) => FollowUpAttachment.fromJson(
                  Map<String, dynamic>.from(item),
                ),
              )
              .where(
                (item) =>
                    item.path.trim().isNotEmpty ||
                    (item.previewBase64 ?? '').trim().isNotEmpty ||
                    (item.imageBase64 ?? '').trim().isNotEmpty,
              )
              .toList() ??
          const [],
    );
  }
}

class FollowUpTask {
  const FollowUpTask({
    required this.id,
    required this.title,
    required this.bucket,
    required this.status,
    required this.priority,
    required this.createdAt,
    required this.lastTouchedAt,
    this.counterparty,
    this.nextAction,
    this.notes,
    this.followUpAt,
    this.followUpTimeSet = false,
    this.completedAt,
    this.attachments = const [],
    this.comments = const [],
  });

  final String id;
  final String title;
  final String bucket;
  final String status;
  final String priority;
  final DateTime createdAt;
  final DateTime lastTouchedAt;
  final String? counterparty;
  final String? nextAction;
  final String? notes;
  final DateTime? followUpAt;
  final bool followUpTimeSet;
  final DateTime? completedAt;
  final List<FollowUpAttachment> attachments;
  final List<FollowUpComment> comments;

  bool get isDone => status == 'done';
  bool get isArchived => status == 'archived';
  bool get isWaiting => status == 'waiting';
  bool get isActive => status == 'active';
  bool get isOpen => !isDone && !isArchived;

  DateTime? get effectiveFollowUpAt {
    final followUp = followUpAt;
    if (followUp == null) return null;
    if (followUpTimeSet) return followUp;
    return _defaultReminderDateTime(followUp, priority);
  }

  bool isOverdue([DateTime? now]) {
    final followUp = effectiveFollowUpAt;
    if (!isOpen || followUp == null) return false;
    final current = now ?? DateTime.now();
    return followUp.isBefore(current);
  }

  bool isDueSoon([DateTime? now, int withinDays = 3]) {
    final followUp = effectiveFollowUpAt;
    if (!isOpen || followUp == null) return false;
    final current = now ?? DateTime.now();
    if (followUp.isBefore(current)) return false;
    return !followUp.isAfter(current.add(Duration(days: withinDays)));
  }

  FollowUpTask copyWith({
    String? id,
    String? title,
    String? bucket,
    String? status,
    String? priority,
    DateTime? createdAt,
    DateTime? lastTouchedAt,
    String? counterparty,
    String? nextAction,
    String? notes,
    DateTime? followUpAt,
    bool clearFollowUpAt = false,
    bool? followUpTimeSet,
    DateTime? completedAt,
    bool clearCompletedAt = false,
    List<FollowUpAttachment>? attachments,
    List<FollowUpComment>? comments,
  }) {
    return FollowUpTask(
      id: id ?? this.id,
      title: title ?? this.title,
      bucket: bucket ?? this.bucket,
      status: status ?? this.status,
      priority: priority ?? this.priority,
      createdAt: createdAt ?? this.createdAt,
      lastTouchedAt: lastTouchedAt ?? this.lastTouchedAt,
      counterparty: counterparty ?? this.counterparty,
      nextAction: nextAction ?? this.nextAction,
      notes: notes ?? this.notes,
      followUpAt: clearFollowUpAt ? null : (followUpAt ?? this.followUpAt),
      followUpTimeSet: followUpTimeSet ?? this.followUpTimeSet,
      completedAt: clearCompletedAt ? null : (completedAt ?? this.completedAt),
      attachments: attachments ?? this.attachments,
      comments: comments ?? this.comments,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'bucket': bucket,
        'status': status,
        'priority': priority,
        'created_at': createdAt.toIso8601String(),
        'last_touched_at': lastTouchedAt.toIso8601String(),
        'counterparty': counterparty,
        'next_action': nextAction,
        'notes': notes,
        'follow_up_at': followUpAt?.toIso8601String(),
        'follow_up_time_set': followUpTimeSet,
        'completed_at': completedAt?.toIso8601String(),
        'attachments': attachments.map((item) => item.toJson()).toList(),
        'comments': comments.map((item) => item.toJson()).toList(),
      };

  factory FollowUpTask.fromJson(Map<String, dynamic> json) {
    return FollowUpTask(
      id: json['id']?.toString() ?? '',
      title: json['title']?.toString() ?? '',
      bucket: json['bucket']?.toString() ?? 'job_application',
      status: json['status']?.toString() ?? 'active',
      priority: json['priority']?.toString() ?? 'normal',
      createdAt: DateTime.tryParse(json['created_at']?.toString() ?? '') ??
          DateTime.now(),
      lastTouchedAt:
          DateTime.tryParse(json['last_touched_at']?.toString() ?? '') ??
              DateTime.now(),
      counterparty: _normalizedText(json['counterparty']),
      nextAction: _normalizedText(json['next_action']),
      notes: _normalizedText(json['notes']),
      followUpAt: DateTime.tryParse(json['follow_up_at']?.toString() ?? ''),
      followUpTimeSet: (json['follow_up_time_set'] as bool?) ??
          _hasMeaningfulTime(
            DateTime.tryParse(json['follow_up_at']?.toString() ?? ''),
          ),
      completedAt: DateTime.tryParse(json['completed_at']?.toString() ?? ''),
      attachments: (json['attachments'] as List?)
              ?.whereType<Map>()
              .map(
                (item) => FollowUpAttachment.fromJson(
                  Map<String, dynamic>.from(item),
                ),
              )
              .where(
                (item) =>
                    item.path.trim().isNotEmpty ||
                    (item.previewBase64 ?? '').trim().isNotEmpty ||
                    (item.imageBase64 ?? '').trim().isNotEmpty,
              )
              .toList() ??
          const [],
      comments: (json['comments'] as List?)
              ?.whereType<Map>()
              .map(
                (item) => FollowUpComment.fromJson(
                  Map<String, dynamic>.from(item),
                ),
              )
              .where((item) =>
                  item.body.trim().isNotEmpty || item.attachments.isNotEmpty)
              .toList() ??
          const [],
    );
  }
}

class FollowUpTaskService {
  static const _storageKey = 'follow_up_tasks.v1';
  static List<FollowUpTask>? _memoryCache;

  final ApiService _api;

  FollowUpTaskService({ApiService? api}) : _api = api ?? ApiService();

  Future<List<FollowUpTask>> loadTasks() async {
    final cached = _memoryCache;
    if (cached != null) return List<FollowUpTask>.from(cached);
    return _loadTasksFromLocalCache();
  }

  Future<List<FollowUpTask>> syncTasksFromServer() async {
    final localCached = await _loadTasksFromLocalCache();
    try {
      final remoteTasks = await _api.getFollowUpTasks();
      _debugLog('sync fetched ${remoteTasks.length} remote tasks');
      final tasks = remoteTasks
          .map((item) => FollowUpTask.fromJson(item))
          .where((item) => item.title.trim().isNotEmpty)
          .toList();
      if (tasks.isEmpty && localCached.isNotEmpty) {
        unawaited(_pushTasksToServer(localCached));
        return localCached;
      }
      final repaired = await _repairTaskAttachments(tasks);
      repaired.$1.sort(compareTasks);
      await _writeLocalCache(repaired.$1);
      _debugLog('sync hydrated ${repaired.$1.length} local tasks');
      if (repaired.$2) {
        try {
          await _pushTasksToServer(repaired.$1);
        } on DioException {
          // Keep repaired local cache even if the sync cannot complete now.
        }
      }
      return repaired.$1;
    } on DioException catch (_) {
      _debugLog('sync failed with DioException');
      return localCached;
    } catch (_) {
      _debugLog('sync failed');
      return localCached;
    }
  }

  Future<void> saveTasks(List<FollowUpTask> tasks) async {
    final sorted = List<FollowUpTask>.from(tasks)..sort(compareTasks);
    final repaired = await _repairTaskAttachments(sorted);
    _memoryCache = List<FollowUpTask>.from(repaired.$1);
    await _writeLocalCache(repaired.$1);
    unawaited(_pushTasksToServer(repaired.$1));
    _debugLog('save cached ${repaired.$1.length} tasks and queued push');
  }

  Future<List<FollowUpTask>> _loadTasksFromLocalCache() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_storageKey);
    if (raw == null || raw.isEmpty) return const [];

    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      final tasks = decoded
          .whereType<Map>()
          .map((item) => FollowUpTask.fromJson(Map<String, dynamic>.from(item)))
          .where((item) => item.title.trim().isNotEmpty)
          .toList();
      tasks.sort(compareTasks);
      _memoryCache = List<FollowUpTask>.from(tasks);
      return tasks;
    } catch (_) {
      return const [];
    }
  }

  Future<void> _writeLocalCache(List<FollowUpTask> tasks) async {
    _memoryCache = List<FollowUpTask>.from(tasks);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _storageKey,
      jsonEncode(tasks.map((task) => task.toJson()).toList()),
    );
  }

  Future<void> _pushTasksToServer(List<FollowUpTask> tasks) async {
    try {
      await _api.saveFollowUpTasks(
        tasks.map(_taskServerJson).toList(),
      );
      _debugLog('push completed with ${tasks.length} tasks');
    } on DioException {
      // Keep local state fast and resilient even when sync cannot complete.
      _debugLog('push failed with DioException');
    }
  }

  void _debugLog(String message) {
    if (kDebugMode) {
      debugPrint('[follow-ups-sync] $message');
    }
  }

  Map<String, dynamic> _taskServerJson(FollowUpTask task) {
    return {
      'id': task.id,
      'title': task.title,
      'bucket': task.bucket,
      'status': task.status,
      'priority': task.priority,
      'created_at': task.createdAt.toIso8601String(),
      'last_touched_at': task.lastTouchedAt.toIso8601String(),
      'counterparty': task.counterparty,
      'next_action': task.nextAction,
      'notes': task.notes,
      'follow_up_at': task.followUpAt?.toIso8601String(),
      'follow_up_time_set': task.followUpTimeSet,
      'completed_at': task.completedAt?.toIso8601String(),
      'attachments': task.attachments.map(_attachmentServerJson).toList(),
      'comments': task.comments.map(_commentServerJson).toList(),
    };
  }

  Map<String, dynamic> _commentServerJson(FollowUpComment comment) {
    return {
      'id': comment.id,
      'body': comment.body,
      'created_at': comment.createdAt.toIso8601String(),
      'attachments': comment.attachments.map(_attachmentServerJson).toList(),
    };
  }

  Map<String, dynamic> _attachmentServerJson(FollowUpAttachment attachment) {
    return {
      'name': attachment.name,
      'path': attachment.path,
      'extension': attachment.extension,
      if (attachment.previewBase64 != null &&
          attachment.previewBase64!.trim().isNotEmpty)
        'preview_base64': attachment.previewBase64,
      if (attachment.imageBase64 != null &&
          attachment.imageBase64!.trim().isNotEmpty)
        'image_base64': attachment.imageBase64,
    };
  }

  Future<(List<FollowUpTask>, bool)> _repairTaskAttachments(
    List<FollowUpTask> tasks,
  ) async {
    var changed = false;
    final repairedTasks = <FollowUpTask>[];
    for (final task in tasks) {
      var taskChanged = false;
      final repairedAttachments = <FollowUpAttachment>[];
      for (final attachment in task.attachments) {
        final repaired = await _migrateAttachmentIfNeeded(attachment);
        if (_attachmentChanged(repaired, attachment)) {
          taskChanged = true;
        }
        repairedAttachments.add(repaired);
      }
      if (taskChanged) {
        changed = true;
        repairedTasks.add(task.copyWith(attachments: repairedAttachments));
      } else {
        repairedTasks.add(task);
      }

      if (task.comments.isNotEmpty) {
        final baseTask = repairedTasks.removeLast();
        var commentsChanged = false;
        final repairedComments = <FollowUpComment>[];
        for (final comment in baseTask.comments) {
          var commentChanged = false;
          final repairedCommentAttachments = <FollowUpAttachment>[];
          for (final attachment in comment.attachments) {
            final repaired = await _migrateAttachmentIfNeeded(attachment);
            if (_attachmentChanged(repaired, attachment)) {
              commentChanged = true;
            }
            repairedCommentAttachments.add(repaired);
          }
          if (commentChanged) {
            commentsChanged = true;
            repairedComments.add(
              comment.copyWith(attachments: repairedCommentAttachments),
            );
          } else {
            repairedComments.add(comment);
          }
        }
        if (commentsChanged) {
          changed = true;
          repairedTasks.add(baseTask.copyWith(comments: repairedComments));
        } else {
          repairedTasks.add(baseTask);
        }
      }
    }
    return (repairedTasks, changed);
  }

  bool _attachmentChanged(
    FollowUpAttachment repaired,
    FollowUpAttachment original,
  ) {
    return repaired.path != original.path ||
        repaired.name != original.name ||
        repaired.extension != original.extension ||
        (repaired.previewPath ?? '') != (original.previewPath ?? '') ||
        (repaired.previewBase64 ?? '') != (original.previewBase64 ?? '') ||
        (repaired.imageBase64 ?? '') != (original.imageBase64 ?? '');
  }

  Future<FollowUpAttachment> _migrateAttachmentIfNeeded(
    FollowUpAttachment attachment,
  ) async {
    final inlinePreview = attachment.previewBase64?.trim();
    final inlineImage = attachment.imageBase64?.trim();
    final sourcePath = attachment.path.trim();
    if (sourcePath.isEmpty && (inlineImage == null || inlineImage.isEmpty)) {
      return attachment;
    }

    if (sourcePath.isEmpty) {
      return _restoreInlineImageAttachment(attachment);
    }

    final source = File(sourcePath);
    if (!await source.exists()) {
      if (inlineImage != null && inlineImage.isNotEmpty) {
        return _restoreInlineImageAttachment(attachment);
      }
      if (attachment.isImage &&
          (inlinePreview == null || inlinePreview.isEmpty)) {
        final previewFromFile = await _loadPreviewBase64FromPreviewPath(
          attachment,
        );
        if (previewFromFile != null && previewFromFile.isNotEmpty) {
          return attachment.copyWith(previewBase64: previewFromFile);
        }
      }
      final repairedPath = await _resolveAttachmentPathByName(attachment);
      if (repairedPath != null) {
        return attachment.copyWith(path: repairedPath);
      }
      return attachment;
    }

    final supportDir = await resolveAppSupportDirectory();
    final attachmentsDir = Directory(
      '${supportDir.path}/follow_up_attachments',
    );
    await attachmentsDir.create(recursive: true);

    final normalizedSource = source.absolute.path;
    final normalizedTargetRoot = attachmentsDir.absolute.path;
    if (normalizedSource.startsWith(normalizedTargetRoot)) {
      if (attachment.isImage) {
        final previewBytes = await _generateAttachmentPreviewBytes(source);
        final previewPath = await _ensureAttachmentPreviewFile(
          source,
          attachmentsDir,
          attachment,
        );
        final previewBase64 = previewBytes != null && previewBytes.isNotEmpty
            ? base64Encode(previewBytes)
            : inlinePreview;
        final imageBase64 =
            await _encodePortableImageBase64(source, fallback: inlineImage);
        if ((attachment.previewPath ?? '').trim() != (previewPath ?? '') ||
            (attachment.previewBase64 ?? '').trim() !=
                (previewBase64 ?? '').trim() ||
            (attachment.imageBase64 ?? '').trim() !=
                (imageBase64 ?? '').trim()) {
          return attachment.copyWith(
            previewPath: previewPath,
            previewBase64: previewBase64,
            imageBase64: imageBase64,
          );
        }
      }
      return attachment;
    }

    final baseName = attachment.name.trim().isNotEmpty
        ? attachment.name.trim()
        : source.uri.pathSegments.isNotEmpty
            ? source.uri.pathSegments.last
            : 'attachment';
    final sanitized = _sanitizeAttachmentFileName(baseName);
    final extension = attachment.extension.trim().toLowerCase();
    final dot = sanitized.lastIndexOf('.');
    final stem = dot > 0 ? sanitized.substring(0, dot) : sanitized;
    final targetName = extension.isEmpty
        ? '${stem}_${DateTime.now().microsecondsSinceEpoch}'
        : '${stem}_${DateTime.now().microsecondsSinceEpoch}.$extension';
    final copied = await source.copy('${attachmentsDir.path}/$targetName');
    final previewBytes = attachment.isImage
        ? await _generateAttachmentPreviewBytes(copied)
        : null;
    final previewPath = attachment.isImage
        ? await _ensureAttachmentPreviewFile(copied, attachmentsDir, attachment)
        : attachment.previewPath;
    final imageBase64 =
        await _encodePortableImageBase64(copied, fallback: inlineImage);
    return FollowUpAttachment(
      name: baseName,
      path: copied.path,
      extension: extension,
      previewPath: previewPath,
      previewBase64: previewBytes != null && previewBytes.isNotEmpty
          ? base64Encode(previewBytes)
          : inlinePreview,
      imageBase64: imageBase64,
    );
  }

  Future<FollowUpAttachment> _restoreInlineImageAttachment(
    FollowUpAttachment attachment,
  ) async {
    final inlineImage = attachment.imageBase64?.trim();
    if (inlineImage == null || inlineImage.isEmpty) return attachment;
    try {
      final imageBytes = base64Decode(inlineImage);
      if (imageBytes.isEmpty) return attachment;
      final supportDir = await resolveAppSupportDirectory();
      final attachmentsDir = Directory(
        '${supportDir.path}/follow_up_attachments',
      );
      await attachmentsDir.create(recursive: true);
      final safeBase = _sanitizeAttachmentFileName(
        attachment.name.trim().isNotEmpty
            ? attachment.name.trim()
            : 'image.jpg',
      );
      final dot = safeBase.lastIndexOf('.');
      final stem = dot > 0 ? safeBase.substring(0, dot) : safeBase;
      final extension = attachment.extension.trim().isNotEmpty
          ? attachment.extension.trim().toLowerCase()
          : 'jpg';
      final restored = File(
        '${attachmentsDir.path}/${stem}_${DateTime.now().microsecondsSinceEpoch}.$extension',
      );
      await restored.writeAsBytes(imageBytes, flush: true);
      final previewPath = attachment.isImage
          ? await _ensureAttachmentPreviewFile(
              restored,
              attachmentsDir,
              attachment,
            )
          : attachment.previewPath;
      final previewBytes = attachment.isImage
          ? await _generateAttachmentPreviewBytes(restored)
          : null;
      return attachment.copyWith(
        path: restored.path,
        previewPath: previewPath,
        previewBase64: previewBytes != null && previewBytes.isNotEmpty
            ? base64Encode(previewBytes)
            : attachment.previewBase64,
      );
    } catch (_) {
      return attachment;
    }
  }

  Future<String?> _encodePortableImageBase64(
    File file, {
    String? fallback,
  }) async {
    try {
      final bytes = await file.readAsBytes();
      if (bytes.isEmpty) return fallback;
      if (bytes.length <= _portableImageMaxBytes) {
        return base64Encode(bytes);
      }

      final decoded = img.decodeImage(bytes);
      if (decoded == null) return fallback;
      var working = img.bakeOrientation(decoded);
      const maxDimension = 4096;
      if (working.width > maxDimension || working.height > maxDimension) {
        if (working.width >= working.height) {
          working = img.copyResize(
            working,
            width: maxDimension,
            interpolation: img.Interpolation.cubic,
          );
        } else {
          working = img.copyResize(
            working,
            height: maxDimension,
            interpolation: img.Interpolation.cubic,
          );
        }
      }
      for (final quality in [94, 90, 86, 82, 78, 74, 68]) {
        final encoded =
            Uint8List.fromList(img.encodeJpg(working, quality: quality));
        if (encoded.length <= _portableImageMaxBytes) {
          return base64Encode(encoded);
        }
      }
      return fallback;
    } catch (_) {
      return fallback;
    }
  }

  Future<String?> _resolveAttachmentPathByName(
    FollowUpAttachment attachment,
  ) async {
    final supportDir = await resolveAppSupportDirectory();
    final attachmentsDir = Directory(
      '${supportDir.path}/follow_up_attachments',
    );
    if (!await attachmentsDir.exists()) return null;

    final candidates = <String>{
      attachment.name.trim(),
      attachment.path.trim().split('/').last,
    }.where((item) => item.isNotEmpty).toSet();

    for (final candidate in candidates) {
      final file = File('${attachmentsDir.path}/$candidate');
      if (await file.exists()) return file.path;
    }

    return null;
  }

  Future<String?> _loadPreviewBase64FromPreviewPath(
    FollowUpAttachment attachment,
  ) async {
    final previewPath = attachment.previewPath?.trim();
    if (previewPath == null || previewPath.isEmpty) return null;
    final previewFile = File(previewPath);
    if (!await previewFile.exists()) return null;
    try {
      final bytes = await previewFile.readAsBytes();
      if (bytes.isEmpty) return null;
      return base64Encode(bytes);
    } catch (_) {
      return null;
    }
  }

  Future<String?> _ensureAttachmentPreviewFile(
    File file,
    Directory attachmentsDir,
    FollowUpAttachment attachment,
  ) async {
    final existingPreviewPath = attachment.previewPath?.trim();
    if (existingPreviewPath != null && existingPreviewPath.isNotEmpty) {
      final existing = File(existingPreviewPath);
      if (await existing.exists()) return existing.path;
    }
    final previewBytes = await _generateAttachmentPreviewBytes(file);
    if (previewBytes == null || previewBytes.isEmpty) return null;
    final safeBase = _sanitizeAttachmentFileName(
      attachment.name.trim().isNotEmpty ? attachment.name.trim() : 'attachment',
    );
    final dot = safeBase.lastIndexOf('.');
    final stem = dot > 0 ? safeBase.substring(0, dot) : safeBase;
    final previewFile = File(
      '${attachmentsDir.path}/${stem}_${DateTime.now().microsecondsSinceEpoch}_preview.jpg',
    );
    await previewFile.writeAsBytes(previewBytes, flush: true);
    return previewFile.path;
  }

  Future<Uint8List?> _generateAttachmentPreviewBytes(File file) async {
    try {
      final bytes = await file.readAsBytes();
      if (bytes.isEmpty) return null;
      final decoded = img.decodeImage(bytes);
      if (decoded == null) return null;
      final baked = img.bakeOrientation(decoded);
      final resized = img.copyResize(
        baked,
        width: baked.width >= baked.height ? 320 : null,
        height: baked.height > baked.width ? 320 : null,
        interpolation: img.Interpolation.average,
      );
      return Uint8List.fromList(img.encodeJpg(resized, quality: 72));
    } catch (_) {
      return null;
    }
  }

  String buildSageContext(List<FollowUpTask> tasks) {
    if (tasks.isEmpty) return '';

    final now = DateTime.now();
    final open = tasks.where((task) => task.isOpen).toList();
    final overdue = open.where((task) => task.isOverdue(now)).toList();
    final dueSoon = open.where((task) => task.isDueSoon(now)).toList();
    final waiting = open.where((task) => task.isWaiting).toList();
    final active = open.where((task) => task.isActive).toList();
    final recentDone = tasks.where((task) => task.isDone).take(3).toList();
    final topLines = open.take(8).map((task) => _sageTaskLine(task)).join('\n');

    final lines = <String>[
      '[FOLLOW-UPS]',
      'This list is separate from Exit Plan. Use it for active pipelines, callbacks, job applications, waiting threads, and practical follow-up pressure.',
      'Open items: ${open.length}',
      'Overdue follow-ups: ${overdue.length}',
      'Due within 3 days: ${dueSoon.length}',
      'Waiting on someone else: ${waiting.length}',
      'Needs direct action: ${active.length}',
      if (topLines.isNotEmpty) 'Priority items:\n$topLines',
    ];

    if (recentDone.isNotEmpty) {
      lines.add(
        'Recently completed:\n${recentDone.map((task) => _sageTaskLine(task)).join('\n')}',
      );
    }

    return '${lines.join('\n')}\n';
  }

  String buildClipboardSummary(List<FollowUpTask> tasks) {
    if (tasks.isEmpty) {
      return 'Follow-Ups\nNo tasks logged yet.';
    }

    final open = tasks.where((task) => task.isOpen).toList();
    final overdue = open.where((task) => task.isOverdue()).toList();
    final dueSoon = open.where((task) => task.isDueSoon()).toList();

    return [
      'Follow-Ups',
      'Separate from Exit Plan. Use for living follow-up pressure and response tracking.',
      'Open items: ${open.length}',
      'Overdue: ${overdue.length}',
      'Due soon: ${dueSoon.length}',
      if (open.isNotEmpty)
        'Most urgent:\n${open.take(8).map(formatTaskSummary).join('\n')}',
    ].join('\n');
  }

  FollowUpTaskSummary summarize(List<FollowUpTask> tasks) {
    final open = tasks.where((task) => task.isOpen).toList();
    final overdue = open.where((task) => task.isOverdue()).toList();
    final dueSoon = open.where((task) => task.isDueSoon()).toList();
    final waiting = open.where((task) => task.isWaiting).toList();
    final staleWaiting = waiting.where((task) {
      final cutoff = DateTime.now().subtract(const Duration(days: 6));
      return task.lastTouchedAt.isBefore(cutoff);
    }).toList();

    return FollowUpTaskSummary(
      openCount: open.length,
      overdueCount: overdue.length,
      dueSoonCount: dueSoon.length,
      waitingCount: waiting.length,
      nextTask: open.isEmpty ? null : open.first,
      overdueTasks: overdue,
      dueSoonTasks: dueSoon,
      staleWaitingTasks: staleWaiting,
    );
  }

  static int compareTasks(FollowUpTask a, FollowUpTask b) {
    final scoreA = _sortScore(a);
    final scoreB = _sortScore(b);
    if (scoreA != scoreB) return scoreA.compareTo(scoreB);

    final priorityCompare = _priorityRank(a.priority).compareTo(
      _priorityRank(b.priority),
    );
    if (priorityCompare != 0) return priorityCompare;

    final followA = a.effectiveFollowUpAt;
    final followB = b.effectiveFollowUpAt;
    if (followA != null && followB != null) {
      final compareFollow = followA.compareTo(followB);
      if (compareFollow != 0) return compareFollow;
    } else if (followA != null) {
      return -1;
    } else if (followB != null) {
      return 1;
    }

    return b.lastTouchedAt.compareTo(a.lastTouchedAt);
  }

  static int _sortScore(FollowUpTask task) {
    if (task.isOverdue()) return 0;
    if (task.isDueSoon()) return 1;
    if (task.isActive) return 2;
    if (task.isWaiting) return 3;
    if (task.isDone) return 4;
    return 5;
  }

  static String formatTaskSummary(FollowUpTask task) {
    final date = DateFormat('MMM d');
    final pieces = <String>[
      '- ${task.title}',
      if ((task.counterparty ?? '').trim().isNotEmpty)
        '@ ${task.counterparty!.trim()}',
      '[${bucketLabel(task.bucket)} | ${statusLabel(task.status)} | ${priorityLabel(task.priority)}]',
      if (task.effectiveFollowUpAt != null)
        'follow up ${date.format(task.effectiveFollowUpAt!)}',
      if ((task.nextAction ?? '').trim().isNotEmpty)
        'next: ${task.nextAction!.trim()}',
    ];
    return pieces.join(' ');
  }

  static String _sageTaskLine(FollowUpTask task) {
    final date = DateFormat('MMM d, yyyy');
    final bits = <String>[
      '- ${task.title}',
      if ((task.counterparty ?? '').trim().isNotEmpty)
        '@ ${task.counterparty!.trim()}',
      '| ${bucketLabel(task.bucket)}',
      '| ${statusLabel(task.status)}',
      '| ${priorityLabel(task.priority)} priority',
      if (task.effectiveFollowUpAt != null)
        '| follow up ${date.format(task.effectiveFollowUpAt!)}',
      '| last touched ${date.format(task.lastTouchedAt)}',
      if ((task.nextAction ?? '').trim().isNotEmpty)
        '| next ${task.nextAction!.trim()}',
    ];
    return bits.join(' ');
  }

  static String bucketLabel(String bucket) {
    switch (bucket) {
      case 'apartment':
        return 'Apartment';
      case 'housing':
        return 'Housing';
      case 'legal':
        return 'Legal';
      case 'finance':
        return 'Finance';
      case 'support':
        return 'Support';
      case 'job_application':
        return 'Job application';
      case 'recruiter':
        return 'Recruiter';
      case 'networking':
        return 'Networking';
      case 'interview':
        return 'Interview';
      case 'admin':
        return 'Admin';
      default:
        return 'Personal';
    }
  }

  static String statusLabel(String status) {
    switch (status) {
      case 'waiting':
        return 'Waiting';
      case 'done':
        return 'Done';
      case 'archived':
        return 'Archived';
      default:
        return 'Active';
    }
  }

  static String priorityLabel(String priority) {
    switch (priority) {
      case 'urgent':
        return 'Urgent';
      case 'high':
        return 'High';
      case 'low':
        return 'Low';
      default:
        return 'Normal';
    }
  }

  static int _priorityRank(String priority) {
    switch (priority) {
      case 'urgent':
        return 0;
      case 'high':
        return 1;
      case 'normal':
        return 2;
      default:
        return 3;
    }
  }

  static String pressureHeadline(FollowUpTaskSummary summary) {
    final nextTask = summary.nextTask;
    if (summary.overdueCount > 0 && nextTask != null) {
      return summary.overdueCount == 1
          ? '${bucketLabel(nextTask.bucket)} follow-up is overdue'
          : '${summary.overdueCount} follow-ups are overdue';
    }
    if (summary.dueSoonCount > 0 && nextTask != null) {
      return summary.dueSoonCount == 1
          ? '${bucketLabel(nextTask.bucket)} follow-up is due soon'
          : '${summary.dueSoonCount} follow-ups are due soon';
    }
    if (summary.waitingCount > 0 && nextTask != null) {
      return summary.waitingCount == 1
          ? '${bucketLabel(nextTask.bucket)} thread is waiting on a reply'
          : '${summary.waitingCount} threads are waiting on replies';
    }
    return 'You have live follow-up pressure building';
  }

  static String pressureBody(FollowUpTaskSummary summary) {
    final nextTask = summary.nextTask;
    if (nextTask == null) {
      return 'Open Follow-Ups and pick one thread to move today.';
    }

    final nextAction = nextTask.nextAction?.trim();
    if (nextAction != null && nextAction.isNotEmpty) {
      final lead = switch (nextTask.bucket) {
        'apartment' => 'Apartment move',
        'housing' => 'Housing move',
        'legal' => 'Legal move',
        'finance' => 'Money move',
        'support' => 'Support move',
        _ => 'Next move',
      };
      return '$lead: $nextAction.';
    }

    return switch (nextTask.bucket) {
      'apartment' =>
        'Open listings, send the message, or book the tour. Do not let the apartment search stay abstract today.',
      'housing' =>
        'Move one housing thread today so it stops living in your head as unfinished pressure.',
      'legal' =>
        'Make the call, send the email, or gather the document so this legal thread stops stalling.',
      'finance' =>
        'Handle the money task before it turns into background dread again.',
      'support' =>
        'Reach out, ask for help, or lock in the support step instead of carrying it alone.',
      _ => nextTask.title,
    };
  }

  static String overdueNotificationBody(FollowUpTaskSummary summary) {
    final first = summary.overdueTasks.isEmpty
        ? summary.nextTask
        : summary.overdueTasks.first;
    if (first == null) {
      return 'Open Follow-Ups and move the most overdue thread.';
    }
    if (summary.overdueCount == 1) {
      return switch (first.bucket) {
        'apartment' =>
          '${first.title} is overdue. Send the message or book the tour today.',
        'housing' =>
          '${first.title} is overdue. Move the housing thread before it slips again.',
        'legal' =>
          '${first.title} is overdue. Handle the legal next step today.',
        'finance' =>
          '${first.title} is overdue. Close the money loop instead of avoiding it.',
        _ => '${first.title} needs a real next move today.',
      };
    }
    return 'Start with ${first.title} and clear the oldest stalled thread today.';
  }

  static String dueSoonNotificationBody(FollowUpTaskSummary summary) {
    final first = summary.dueSoonTasks.isEmpty
        ? summary.nextTask
        : summary.dueSoonTasks.first;
    if (first == null) {
      return 'Get ahead of one follow-up before it turns overdue.';
    }
    if (summary.dueSoonCount == 1) {
      return switch (first.bucket) {
        'apartment' =>
          '${first.title} is coming up. Get ahead of the apartment move now.',
        'housing' =>
          '${first.title} is coming up. Stay ahead of the housing thread now.',
        _ => '${first.title} is coming up. Get ahead of it now.',
      };
    }
    return '${first.title} is first in line. Knock out the next touch before it slips.';
  }

  static String waitingNotificationBody(FollowUpTask task) {
    return switch (task.bucket) {
      'apartment' =>
        '${task.title} has gone quiet. Ping them, widen the search, or close the loop today.',
      'housing' =>
        '${task.title} has gone quiet. Decide whether to ping, pivot, or close the housing loop.',
      _ =>
        '${task.title} has been sitting quiet. Decide whether to ping, park it, or close the loop.',
    };
  }

  static String sagePressurePrompt(
    FollowUpTask task, {
    required String frame,
  }) {
    final searchTarget = _propertySearchTarget(task);
    final isApartmentSearch =
        task.bucket == 'apartment' || task.bucket == 'housing';

    final lines = <String>[
      frame,
      'Use my Follow-Ups context and respond with concrete, useful pressure.',
      'Call out if I am stalling and tell me the exact next move.',
      'Focus on "${task.title}"'
          '${(task.counterparty ?? '').trim().isNotEmpty ? ' with ${(task.counterparty ?? '').trim()}' : ''}.',
      if ((task.nextAction ?? '').trim().isNotEmpty)
        'Use the saved next action as the default move unless you see a better one.',
    ];

    if (isApartmentSearch && searchTarget != null) {
      lines.addAll([
        'If web search is enabled in this session, look up "$searchTarget" and use current listing intel if it helps.',
        'Prioritize pricing, availability, pet policy, parking or garage details, fees, and red flags only if relevant to the next move.',
      ]);
    } else if (isApartmentSearch) {
      lines.add(
        'If web search is enabled in this session, use it only if current apartment or housing intel would improve the advice.',
      );
    }

    return lines.join('\n');
  }

  static String? _propertySearchTarget(FollowUpTask task) {
    final candidates = [
      task.counterparty?.trim() ?? '',
      task.title.trim(),
    ];
    for (final candidate in candidates) {
      if (candidate.isEmpty) continue;
      final lower = candidate.toLowerCase();
      if (lower.contains('apartment') ||
          lower.contains('apartments') ||
          lower.contains('leasing') ||
          lower.contains('property') ||
          lower.contains('residences') ||
          lower.contains('villas') ||
          lower.contains('homes')) {
        return candidate;
      }
    }
    return candidates
            .firstWhere(
              (candidate) => candidate.isNotEmpty,
              orElse: () => '',
            )
            .trim()
            .isEmpty
        ? null
        : candidates.firstWhere((candidate) => candidate.isNotEmpty);
  }
}

String _sanitizeAttachmentFileName(String name) {
  final trimmed = name.trim();
  if (trimmed.isEmpty) return 'attachment';
  return trimmed.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
}

class FollowUpTaskSummary {
  const FollowUpTaskSummary({
    required this.openCount,
    required this.overdueCount,
    required this.dueSoonCount,
    required this.waitingCount,
    required this.nextTask,
    required this.overdueTasks,
    required this.dueSoonTasks,
    required this.staleWaitingTasks,
  });

  final int openCount;
  final int overdueCount;
  final int dueSoonCount;
  final int waitingCount;
  final FollowUpTask? nextTask;
  final List<FollowUpTask> overdueTasks;
  final List<FollowUpTask> dueSoonTasks;
  final List<FollowUpTask> staleWaitingTasks;

  bool get hasPressure =>
      overdueCount > 0 || dueSoonCount > 0 || waitingCount > 0;
}

bool _hasMeaningfulTime(DateTime? date) {
  if (date == null) return false;
  return date.hour != 0 || date.minute != 0;
}

DateTime _defaultReminderDateTime(DateTime date, String priority) {
  final day = _startOfDay(date);
  final (hour, minute) = switch (priority) {
    'urgent' => (8, 30),
    'high' => (10, 0),
    'low' => (18, 0),
    _ => (13, 0),
  };
  return DateTime(day.year, day.month, day.day, hour, minute);
}
