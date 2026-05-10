import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart' show SelectionArea;
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';

import '../models/detective_entry_draft.dart';
import '../services/ai_response_limits.dart';
import '../services/api_service.dart';
import '../services/follow_up_tasks_service.dart';
import '../services/sage_profile_service.dart';
import '../services/tts_audio_file_helper.dart';
import '../theme/app_theme.dart';
import '../widgets/glass_card.dart';
import 'admin_screen.dart';
import 'ask_journal_screen.dart';
import 'budget_planner_screen.dart';
import 'detective_screen.dart';
import 'early_warning_screen.dart';
import 'exit_plan_screen.dart';
import 'fairness_ledger_screen.dart';
import 'follow_ups_screen.dart';
import 'invite_access_screen.dart';
import 'mental_health_screen.dart';
import 'proof_vault_screen.dart';
import 'resources_screen.dart';
import 'saved_sage_chats_screen.dart';
import 'sage_settings_screen.dart';
import 'sage_tracks_screen.dart';
import 'settings_screen.dart';
import 'timeline_screen.dart';
import 'today_screen.dart';
import 'war_room_screen.dart';
import 'write_screen.dart';

const _kSageSystemPrompt = '''
You are Sage — a journal intelligence copilot and the user's closest digital
confidant. You are part best friend, part pattern reader, part strategist, and
part evidence-aware thinking partner.

IDENTITY & TONE:
You speak like a real friend who actually gives a damn. Use the user's name
("William") naturally — not every sentence, but when it lands. "Bro" works
when the vibe fits. Blunt is fine. Warm is fine. Both at once is fine.
Never be sycophantic. Never be clinical. Never give corporate-assistant energy.
You can swear when it genuinely fits the moment — not for effect, just when
it's right.

WHAT YOU KNOW:
You have access to context sections below when present: journal summaries,
emotional patterns, memory profile, people intelligence, budget data, fairness
ledger, mental health signals, proof vault summaries, detective cases, exit
plan, resources, alerts, and settings.

HOW TO USE DATA:
Use the user's real data when it is present. If a section is missing, stale,
or only high-level, say so plainly — do not pretend. Never fabricate numbers,
dates, events, legal facts, medical facts, budget rows, or app state. When
your confidence is limited, name the limit and give the best next step anyway.

Budget: use actual fields from expanded context if present. If absent, say you
cannot see the breakdown and suggest opening Budget Planner. Do not substitute
a journal anecdote for real budget data.

People: when someone is mentioned, connect to people intelligence, journal
patterns, fairness data, evidence, and detective cases if present.

ANTI-REPETITION:
Do not keep surfacing the same life event or detail because it is in context.
Reference a specific detail only when it changes the advice or the user brings
it up. After mentioning a concrete event, leave it alone for the next few
replies unless it is clearly necessary again. Come at the user's current
question with a fresh angle.

WEB SEARCH (when enabled):
If the SAGE SETTINGS block says web search is ENABLED, you may receive
real-time search results injected into context with the label
[WEB SEARCH RESULTS]. Treat those results as ground truth for the current
query and cite them directly in your answer.

When a question would benefit from a location-specific search (lawyers, doctors,
shelters, housing, legal aid, local resources), do NOT assume any location and
do NOT ask for location permissions or GPS access. This journal is private.
Just ask the user directly in plain conversational language — something like:
"What city or area are you in?" — keep it natural and brief. Once you have it,
give a real, specific answer using the search results.

If web search is DISABLED, rely only on in-app data and your own knowledge.
Tell the user when something would benefit from a live search and suggest they
enable it in Sage Settings.

FILE REVIEW (when files are attached):
If the user attaches files, you may receive extracted file text in the prompt.
Treat that text as part of the current question. Quote or summarize it when
helpful, but say plainly if the file looked incomplete, truncated, or hard to
parse. Never pretend you saw content that was not included in the extracted
text.

IMAGE REVIEW (when images are attached):
If the user attaches images, inspect the actual visual content. Describe what
you can see, read visible text, and connect the image to journal context when
that is useful. Be explicit when an image is blurry, cropped, too small, or
otherwise uncertain.
''';

const _kSageDefaultWelcomeMessage = '''
I’m here and I’ve got your context loaded.

Ask me to:
- spot patterns
- think through a situation
- sanity-check what happened
- turn chaos into a plan

You can also drop in a screenshot, file, or rough thought and we’ll work from there.
''';

const _kSageKnowledgeChips = <({String label, String prompt})>[
  (
    label: 'Journal entries & mood trends',
    prompt: 'What mood and stress patterns have been showing up lately?'
  ),
  (
    label: 'Narrative summary',
    prompt:
        'Give me the clearest read on what chapter of life I am in right now.'
  ),
  (
    label: 'Active alerts',
    prompt: 'What active alerts or warning patterns matter most right now?'
  ),
  (
    label: 'Evidence vault',
    prompt: 'What evidence or documentation should I be collecting next?'
  ),
  (
    label: 'Detective cases',
    prompt: 'What case-building threads or contradictions should I review next?'
  ),
  (
    label: 'Exit plan progress',
    prompt: 'How is my exit plan actually progressing, and where am I stuck?'
  ),
  (
    label: 'Fairness ledger',
    prompt:
        'What does the fairness ledger say about load, effort, or imbalance?'
  ),
  (
    label: 'Budget & spending',
    prompt: 'Based on my budget, what financial pressure points need attention?'
  ),
  (
    label: 'People intelligence',
    prompt:
        'What should I notice about the people showing up most in my journal?'
  ),
  (
    label: 'User memory/profile',
    prompt: 'Use what you know about me and tell me what I may be overlooking.'
  ),
];

Color _withAlpha(Color color, double alpha) => color.withValues(alpha: alpha);

const _kSupportedSageFileExtensions = <String>{
  'txt',
  'md',
  'markdown',
  'json',
  'csv',
  'tsv',
  'log',
  'yaml',
  'yml',
  'xml',
  'html',
  'htm',
  'rtf',
  'sql',
  'docx',
  'odt',
  'pdf',
};

const _kSupportedSageImageExtensions = <String>{
  'jpg',
  'jpeg',
  'png',
  'webp',
  'gif',
};

const _kMaxSageFileChars = 12000;
const _kMaxSageImageBytes = 12 * 1024 * 1024;
const _kAnthropicImageMaxBytes = 5 * 1024 * 1024;
const _kAnthropicImageTargetBytes = 4500000;
const _kAnthropicImageMaxDimension = 1568;
const _kSeededSummaryTranscriptMaxChars = 900;
const _kSeededSummaryTranscriptMaxBytes = 1200;

String _extensionForName(String filename) {
  final dot = filename.lastIndexOf('.');
  if (dot <= 0 || dot == filename.length - 1) return '';
  return filename.substring(dot + 1).toLowerCase();
}

String _decodeBasicHtmlEntities(String input) {
  return input
      .replaceAll('&nbsp;', ' ')
      .replaceAll('&amp;', '&')
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&quot;', '"')
      .replaceAll('&#39;', "'");
}

String? _finalizeExtractedText(String raw) {
  final cleaned = raw
      .replaceAll('\u0000', '')
      .replaceAll('\r\n', '\n')
      .replaceAll('\r', '\n')
      .replaceAll(RegExp(r'\n{3,}'), '\n\n')
      .trim();
  if (cleaned.isEmpty) return null;

  final truncated = cleaned.length > _kMaxSageFileChars
      ? '${cleaned.substring(0, _kMaxSageFileChars)}\n... [truncated]'
      : cleaned;
  return truncated;
}

String _stripMarkdownImages(String text) {
  return text.replaceAll(RegExp(r'!\[[^\]]*\]\([^)]+\)'), '').replaceAll(
      RegExp(r'^\s*\[[^\]]*\]:\s*data:image/[^\n]+$', multiLine: true), '');
}

Future<String?> _readPlainTextFile(String path) async {
  try {
    final file = File(path);
    if (!await file.exists()) return null;
    final bytes = await file.readAsBytes();
    if (bytes.isEmpty) return null;

    String text;
    try {
      text = utf8.decode(bytes, allowMalformed: true);
    } catch (_) {
      text = latin1.decode(bytes, allowInvalid: true);
    }
    return _finalizeExtractedText(_stripMarkdownImages(text));
  } catch (_) {
    return null;
  }
}

Future<String?> _readHtmlTextFile(String path) async {
  final text = await _readPlainTextFile(path);
  if (text == null) return null;

  final withoutImages =
      text.replaceAll(RegExp(r'<img\b[^>]*>', caseSensitive: false), ' ');
  final withoutScript = withoutImages
      .replaceAll(
          RegExp(r'<script\b[^>]*>[\s\S]*?</script>', caseSensitive: false),
          ' ')
      .replaceAll(
          RegExp(r'<style\b[^>]*>[\s\S]*?</style>', caseSensitive: false), ' ');
  final withBreaks = withoutScript
      .replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n')
      .replaceAll(RegExp(r'</p\s*>', caseSensitive: false), '\n\n')
      .replaceAll(RegExp(r'</div\s*>', caseSensitive: false), '\n')
      .replaceAll(RegExp(r'</li\s*>', caseSensitive: false), '\n');
  final stripped = withBreaks.replaceAll(RegExp(r'<[^>]+>'), ' ');
  return _finalizeExtractedText(_decodeBasicHtmlEntities(stripped));
}

String _decodeRtfHexEscapes(String text) {
  return text.replaceAllMapped(RegExp(r"\\'([0-9a-fA-F]{2})"), (match) {
    final value = int.tryParse(match.group(1) ?? '', radix: 16);
    if (value == null) return '';
    return latin1.decode([value], allowInvalid: true);
  });
}

Future<String?> _readRtfTextFile(String path) async {
  final text = await _readPlainTextFile(path);
  if (text == null) return null;

  final withoutPictures = text.replaceAll(
    RegExp(r'\{\\pict[\s\S]*?\}', multiLine: true),
    ' ',
  );
  final decoded = _decodeRtfHexEscapes(withoutPictures);
  final withBreaks = decoded
      .replaceAll(RegExp(r'\\par[d]?'), '\n')
      .replaceAll(RegExp(r'\\line'), '\n')
      .replaceAll(RegExp(r'\\tab'), '\t');
  final stripped = withBreaks
      .replaceAll(RegExp(r'\\[a-zA-Z]+\d* ?'), ' ')
      .replaceAll(RegExp(r'[{}]'), ' ');
  return _finalizeExtractedText(stripped);
}

String _extractTextFromXmlDocument(String xml) {
  final withBreaks = xml
      .replaceAll(RegExp(r'<w:tab\b[^>]*/>'), '\t')
      .replaceAll(RegExp(r'<text:tab\b[^>]*/>'), '\t')
      .replaceAll(RegExp(r'<w:(br|cr)\b[^>]*/>'), '\n')
      .replaceAll(RegExp(r'<text:line-break\b[^>]*/>'), '\n')
      .replaceAll('</w:p>', '\n\n')
      .replaceAll('</text:p>', '\n\n')
      .replaceAll('</text:h>', '\n\n')
      .replaceAll('</table:table-row>', '\n');
  final stripped = withBreaks.replaceAll(RegExp(r'<[^>]+>'), ' ');
  return _decodeBasicHtmlEntities(stripped);
}

Future<String?> _readZipXmlTextFile(
  String path, {
  required bool Function(String name) includeFile,
}) async {
  try {
    final file = File(path);
    if (!await file.exists()) return null;
    final bytes = await file.readAsBytes();
    if (bytes.isEmpty) return null;

    final archive = ZipDecoder().decodeBytes(bytes, verify: false);
    final xmlTexts = archive.files
        .where((entry) => !entry.isFile ? false : includeFile(entry.name))
        .map((entry) {
          final content = entry.content;
          if (content is List<int>) {
            return utf8.decode(content, allowMalformed: true);
          }
          if (content is Uint8List) {
            return utf8.decode(content, allowMalformed: true);
          }
          return '';
        })
        .where((text) => text.trim().isNotEmpty)
        .toList();
    if (xmlTexts.isEmpty) return null;

    final combined = xmlTexts.map(_extractTextFromXmlDocument).join('\n\n');
    return _finalizeExtractedText(combined);
  } catch (_) {
    return null;
  }
}

Future<String?> _readDocxTextFile(String path) {
  return _readZipXmlTextFile(
    path,
    includeFile: (name) =>
        name.startsWith('word/') &&
        name.endsWith('.xml') &&
        !name.contains('/_rels/'),
  );
}

Future<String?> _readOdtTextFile(String path) {
  return _readZipXmlTextFile(
    path,
    includeFile: (name) => name == 'content.xml',
  );
}

Future<String?> _readPdfTextFile(String path) async {
  try {
    final file = File(path);
    if (!await file.exists()) return null;
    final bytes = await file.readAsBytes();
    if (bytes.isEmpty) return null;

    final document = PdfDocument(inputBytes: bytes);
    try {
      final extractor = PdfTextExtractor(document);
      final text = extractor.extractText();
      return _finalizeExtractedText(text);
    } finally {
      document.dispose();
    }
  } catch (_) {
    return null;
  }
}

Future<String?> _readTextFile(String path, String extension) {
  switch (extension) {
    case 'html':
    case 'htm':
      return _readHtmlTextFile(path);
    case 'rtf':
      return _readRtfTextFile(path);
    case 'docx':
      return _readDocxTextFile(path);
    case 'odt':
      return _readOdtTextFile(path);
    case 'pdf':
      return _readPdfTextFile(path);
    default:
      return _readPlainTextFile(path);
  }
}

enum _SageAttachmentSource {
  photoLibrary,
  camera,
  files,
}

String _imageMediaTypeForExtension(String extension) {
  switch (extension.toLowerCase()) {
    case 'png':
      return 'image/png';
    case 'webp':
      return 'image/webp';
    case 'gif':
      return 'image/gif';
    case 'jpg':
    case 'jpeg':
    default:
      return 'image/jpeg';
  }
}

class _NormalizedSageImage {
  const _NormalizedSageImage({
    required this.bytes,
    required this.extension,
    required this.mediaType,
  });

  final Uint8List bytes;
  final String extension;
  final String mediaType;
}

Future<_NormalizedSageImage?> _normalizeSageImageBytes({
  required Uint8List bytes,
  required String extension,
}) async {
  if (bytes.isEmpty) return null;
  if (bytes.length <= _kAnthropicImageTargetBytes) {
    return _NormalizedSageImage(
      bytes: bytes,
      extension: extension,
      mediaType: _imageMediaTypeForExtension(extension),
    );
  }

  final decoded = img.decodeImage(bytes);
  if (decoded == null) return null;

  var working = img.bakeOrientation(decoded);
  if (working.width > _kAnthropicImageMaxDimension ||
      working.height > _kAnthropicImageMaxDimension) {
    if (working.width >= working.height) {
      working = img.copyResize(
        working,
        width: _kAnthropicImageMaxDimension,
        interpolation: img.Interpolation.cubic,
      );
    } else {
      working = img.copyResize(
        working,
        height: _kAnthropicImageMaxDimension,
        interpolation: img.Interpolation.cubic,
      );
    }
  }

  Uint8List encoded(List<int> data) => Uint8List.fromList(data);

  Uint8List resizedBytes = Uint8List(0);
  for (final quality in [85, 80, 75, 70, 65, 60, 55]) {
    resizedBytes = encoded(img.encodeJpg(working, quality: quality));
    if (resizedBytes.length <= _kAnthropicImageTargetBytes) {
      return _NormalizedSageImage(
        bytes: resizedBytes,
        extension: 'jpg',
        mediaType: 'image/jpeg',
      );
    }
  }

  var attempts = 0;
  while (resizedBytes.length > _kAnthropicImageTargetBytes && attempts < 6) {
    attempts += 1;
    final nextWidth = (working.width * 0.85).floor().clamp(1, working.width);
    final nextHeight = (working.height * 0.85).floor().clamp(1, working.height);
    if (nextWidth == working.width && nextHeight == working.height) {
      break;
    }
    working = img.copyResize(
      working,
      width: nextWidth,
      height: nextHeight,
      interpolation: img.Interpolation.cubic,
    );
    resizedBytes = encoded(img.encodeJpg(working, quality: 75));
  }

  if (resizedBytes.isEmpty || resizedBytes.length > _kAnthropicImageMaxBytes) {
    return null;
  }

  return _NormalizedSageImage(
    bytes: resizedBytes,
    extension: 'jpg',
    mediaType: 'image/jpeg',
  );
}

String _labelForSageSessionTone(String tone) {
  switch (tone) {
    case 'best_friend':
      return 'Best Friend';
    case 'coach':
      return 'Coach';
    case 'mentor':
      return 'Mentor';
    case 'inner_critic':
      return 'Inner Critic';
    case 'chaos_agent':
      return 'Chaos Agent';
    case 'therapist':
    default:
      return 'Therapist';
  }
}

SageSettings _settingsForSageSessionTone(
  SageSettings base,
  String? tone,
) {
  switch (tone) {
    case 'best_friend':
      return base.copyWith(
        warmth: 'close',
        directness: 'gentle',
        allowSwearing: true,
      );
    case 'coach':
      return base.copyWith(
        warmth: 'warm',
        directness: 'direct',
        allowSwearing: base.allowSwearing,
      );
    case 'mentor':
      return base.copyWith(
        warmth: 'warm',
        directness: 'direct',
        allowSwearing: false,
      );
    case 'inner_critic':
      return base.copyWith(
        warmth: 'calm',
        directness: 'blunt',
        allowSwearing: true,
      );
    case 'chaos_agent':
      return base.copyWith(
        warmth: 'close',
        directness: 'blunt',
        allowSwearing: true,
      );
    case 'therapist':
      return base.copyWith(
        warmth: 'calm',
        directness: 'gentle',
        allowSwearing: false,
      );
    default:
      return base;
  }
}

String _promptInstructionForSageSessionTone(String? tone) {
  switch (tone) {
    case 'best_friend':
      return '''
[TEMPORARY HANDOFF TONE]
This Sage session started from a living summary in the Best Friend tone.
For this session only, sound warm, familiar, validating, and conversational.
Keep it grounded in the user's real data and still be honest when something is off.
''';
    case 'coach':
      return '''
[TEMPORARY HANDOFF TONE]
This Sage session started from a living summary in the Coach tone.
For this session only, sound motivating, forward-moving, and practical.
Turn insight into next steps without getting preachy or generic.
''';
    case 'mentor':
      return '''
[TEMPORARY HANDOFF TONE]
This Sage session started from a living summary in the Mentor tone.
For this session only, sound steady, wise, and long-view.
Offer perspective and pattern recognition without becoming distant or vague.
''';
    case 'inner_critic':
      return '''
[TEMPORARY HANDOFF TONE]
This Sage session started from a living summary in the Inner Critic tone.
For this session only, be sharper, more challenging, and more unsparing than usual.
Stay accurate and useful. Push hard on avoidance, but do not become cruel or insulting.
''';
    case 'chaos_agent':
      return '''
[TEMPORARY HANDOFF TONE]
This Sage session started from a living summary in the Chaos Agent tone.
For this session only, sound bold, unconventional, irreverent, and pattern-breaking.
Use surprise, edge, and blunt honesty when it helps, but keep the advice coherent and anchored to real context.
''';
    case 'therapist':
      return '''
[TEMPORARY HANDOFF TONE]
This Sage session started from a living summary in the Therapist tone.
For this session only, sound measured, reflective, and emotionally attuned.
Name patterns carefully, slow the pace a little, and avoid unnecessary sharpness.
''';
    default:
      return '';
  }
}

class SageHandoff {
  const SageHandoff({
    this.initialAssistantMessage,
    this.prefillText,
    this.initialAttachments = const [],
    this.autoSendPrefill = false,
    this.autoSendPrefillHidden = false,
    this.autoStartGreeting = true,
    this.showDefaultWelcome = false,
    this.sessionToneOverride,
  });

  const SageHandoff.standard()
      : initialAssistantMessage = null,
        prefillText = null,
        initialAttachments = const [],
        autoSendPrefill = false,
        autoSendPrefillHidden = false,
        autoStartGreeting = false,
        showDefaultWelcome = true,
        sessionToneOverride = null;

  SageHandoff.livingSummary(
    String insight, {
    this.sessionToneOverride,
  })  : initialAssistantMessage = insight,
        prefillText = null,
        initialAttachments = const [],
        autoSendPrefill = false,
        autoSendPrefillHidden = false,
        autoStartGreeting = false,
        showDefaultWelcome = false;

  final String? initialAssistantMessage;
  final String? prefillText;
  final List<SageHandoffAttachment> initialAttachments;
  final bool autoSendPrefill;
  final bool autoSendPrefillHidden;
  final bool autoStartGreeting;
  final bool showDefaultWelcome;
  final String? sessionToneOverride;

  String get seededAssistantMessage => initialAssistantMessage?.trim() ?? '';

  String get normalizedPrefill => prefillText?.trim() ?? '';

  bool get hasSeededAssistantMessage => seededAssistantMessage.isNotEmpty;

  bool get hasPrefill => normalizedPrefill.isNotEmpty;

  bool get hasInitialAttachments => initialAttachments.isNotEmpty;

  bool get shouldAutoStartGreeting =>
      autoStartGreeting &&
      !hasSeededAssistantMessage &&
      !hasPrefill &&
      !hasInitialAttachments;

  bool get shouldShowDefaultWelcome =>
      !hasSeededAssistantMessage && showDefaultWelcome;

  bool get shouldAutoSendPrefill =>
      autoSendPrefill && (hasPrefill || hasInitialAttachments);

  SageHandoff forNewChat() => SageHandoff(
        autoStartGreeting: false,
        showDefaultWelcome: true,
        sessionToneOverride: sessionToneOverride,
      );
}

class SageHandoffAttachment {
  const SageHandoffAttachment({
    required this.name,
    required this.path,
    required this.extension,
  });

  final String name;
  final String path;
  final String extension;
}

Future<T?> pushSageScreen<T>(
  BuildContext context, {
  SageHandoff handoff = const SageHandoff.standard(),
}) {
  return Navigator.push<T>(
    context,
    CupertinoPageRoute(
      builder: (_) => DefaultTextStyle.merge(
        style: const TextStyle(decoration: TextDecoration.none),
        child: SageScreen(handoff: handoff),
      ),
    ),
  );
}

class SageScreen extends StatefulWidget {
  const SageScreen({
    super.key,
    this.handoff = const SageHandoff.standard(),
  });

  final SageHandoff handoff;

  @override
  State<SageScreen> createState() => _SageScreenState();
}

class _SageScreenState extends State<SageScreen> with WidgetsBindingObserver {
  final _api = ApiService();
  final _profile = SageProfileService();
  final _followUpTasks = FollowUpTaskService();
  final _composerCtrl = TextEditingController();
  final _scroll = ScrollController();
  final _focusNode = FocusNode();
  final _audioPlayer = AudioPlayer();
  final _imagePicker = ImagePicker();

  List<_SageMessage> _messages = const [];
  List<SageMemoryItem> _memoryItems = const [];
  String _followUpContext = '';
  List<_SageFileDraft> _pendingAttachments = const [];
  SageFocusTrack? _activeTrack;
  SageSettings _settings = SageSettings.defaults;
  String? _contextString;
  String? _expandedContextString;
  String? _contextError;
  String? _replyError;
  bool _contextLoading = true;
  bool _replyLoading = false;
  bool _profileLoading = true;
  bool _pickingAttachments = false;
  bool _savingConversation = false;
  String? _speakingMessageId;
  String? _ttsLoadingMessageId;
  String? _ttsErrorMessageId;
  String? _ttsErrorText;
  String? _ttsTempAudioPath;
  String? _savedConversationId;
  int _messageCounter = 0;
  int _ttsRequestCounter = 0;
  bool _ttsSequenceActive = false;
  bool _seededInitialAssistantMessage = false;
  bool _appliedInitialPrefill = false;
  bool _appliedInitialAttachments = false;
  bool _sentInitialPrefill = false;
  bool _useTrackForSession = true;
  String? _actionPrefillLabel;
  double _lastKeyboardInset = 0;
  late SageHandoff _handoff;

  bool get _canSend =>
      !_replyLoading &&
      !_contextLoading &&
      (_composerCtrl.text.trim().isNotEmpty || _pendingAttachments.isNotEmpty);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _handoff = widget.handoff;
    _composerCtrl.addListener(_handleComposerChanged);
    unawaited(configureTtsAudioPlayer(_audioPlayer));
    _audioPlayer.onPlayerComplete.listen((_) {
      if (mounted && !_ttsSequenceActive) {
        setState(() {
          _speakingMessageId = null;
          _ttsLoadingMessageId = null;
        });
      }
    });
    _loadSageProfile();
    _loadContextAndStart(
      autoStartGreeting: _handoff.shouldAutoStartGreeting,
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _composerCtrl.removeListener(_handleComposerChanged);
    _composerCtrl.dispose();
    _scroll.dispose();
    _focusNode.dispose();
    _audioPlayer.dispose();
    unawaited(deleteTtsAudioTempFile(_ttsTempAudioPath));
    super.dispose();
  }

  @override
  void didChangeMetrics() {
    super.didChangeMetrics();
    if (!mounted) return;
    final view = View.of(context);
    final keyboardInset = view.viewInsets.bottom / view.devicePixelRatio;
    final keyboardOpened = keyboardInset > _lastKeyboardInset + 8;
    _lastKeyboardInset = keyboardInset;
    if (keyboardOpened) {
      _scrollDown();
    }
  }

  void _handleComposerChanged() {
    if (mounted) setState(() {});
  }

  String _parseError(dynamic e) {
    if (e is DioException) {
      final data = e.response?.data;
      if (data is Map) {
        final detail = data['detail'];
        if (detail is String && detail.trim().isNotEmpty) return detail.trim();
        if (detail is List && detail.isNotEmpty) {
          return detail.map((item) {
            if (item is Map) {
              final msg = item['msg']?.toString() ?? '';
              final loc = (item['loc'] as List?)?.join(' → ') ?? '';
              return loc.isNotEmpty ? '$msg  [loc: $loc]' : msg;
            }
            return item.toString();
          }).join('\n');
        }
      }
      if (data is String && data.trim().isNotEmpty) return data.trim();
      final status = e.response?.statusCode;
      if (status != null) {
        return 'Server error ($status). Check the Sage file review request.';
      }
    }
    final str = e.toString();
    final match = RegExp(r'"detail"\s*:\s*"([^"]+)"').firstMatch(str);
    return match?.group(1) ?? 'Something went wrong.';
  }

  Future<void> _loadSageProfile() async {
    try {
      final results = await Future.wait<dynamic>([
        _profile.loadSettings(),
        _profile.loadMemoryItems(),
        _followUpTasks.loadTasks(),
      ]);
      final settings = results[0] as SageSettings;
      final memory = results[1] as List<SageMemoryItem>;
      final followUps = results[2] as List<FollowUpTask>;
      if (!mounted) return;
      setState(() {
        _settings = settings;
        _memoryItems = memory;
        _followUpContext = _followUpTasks.buildSageContext(followUps);
        _profileLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _profileLoading = false);
    }
  }

  Future<void> _chooseAttachmentSource() async {
    if (_replyLoading || _pickingAttachments) return;
    final source = await showCupertinoModalPopup<_SageAttachmentSource>(
      context: context,
      builder: (_) => CupertinoActionSheet(
        title: const Text('Add Attachment'),
        actions: [
          CupertinoActionSheetAction(
            onPressed: () =>
                Navigator.pop(context, _SageAttachmentSource.photoLibrary),
            child: const Text('Photo Library'),
          ),
          CupertinoActionSheetAction(
            onPressed: () =>
                Navigator.pop(context, _SageAttachmentSource.camera),
            child: const Text('Take Photo'),
          ),
          CupertinoActionSheetAction(
            onPressed: () =>
                Navigator.pop(context, _SageAttachmentSource.files),
            child: const Text('Browse Files'),
          ),
        ],
        cancelButton: CupertinoActionSheetAction(
          isDestructiveAction: true,
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
      ),
    );
    if (source == null) return;

    switch (source) {
      case _SageAttachmentSource.photoLibrary:
        await _pickPhotosFromLibrary();
        break;
      case _SageAttachmentSource.camera:
        await _pickPhotoFromCamera();
        break;
      case _SageAttachmentSource.files:
        await _pickFileAttachments();
        break;
    }
  }

  Future<void> _pickPhotosFromLibrary() async {
    if (_replyLoading || _pickingAttachments) return;
    setState(() => _pickingAttachments = true);
    try {
      final picked = await _imagePicker.pickMultiImage(imageQuality: 85);
      await _addPickedImages(picked);
    } catch (_) {
      if (!mounted) return;
      setState(() => _pickingAttachments = false);
    }
  }

  Future<void> _pickPhotoFromCamera() async {
    if (_replyLoading || _pickingAttachments) return;
    setState(() => _pickingAttachments = true);
    try {
      final picked = await _imagePicker.pickImage(
        source: ImageSource.camera,
        imageQuality: 85,
      );
      await _addPickedImages([
        if (picked != null) picked,
      ]);
    } catch (_) {
      if (!mounted) return;
      setState(() => _pickingAttachments = false);
    }
  }

  Future<void> _addPickedImages(List<XFile> picked) async {
    if (picked.isEmpty) {
      if (!mounted) return;
      setState(() => _pickingAttachments = false);
      return;
    }

    final next = List<_SageFileDraft>.from(_pendingAttachments);
    final oversizedImages = <String>[];
    for (final image in picked) {
      final draft = await _SageFileDraft.fromXFile(
        image,
        onOversizedImage: oversizedImages.add,
      );
      if (draft != null) next.add(draft);
    }

    if (!mounted) return;
    setState(() {
      _pendingAttachments = next;
      _pickingAttachments = false;
    });
    if (oversizedImages.isNotEmpty) {
      await _showOversizedImagesDialog(oversizedImages);
    }
  }

  Future<void> _pickFileAttachments() async {
    if (_replyLoading || _pickingAttachments) return;
    setState(() => _pickingAttachments = true);
    try {
      final result = await FilePicker.platform.pickFiles(
        allowMultiple: true,
        withData: false,
        type: FileType.any,
      );
      if (result == null || result.files.isEmpty) {
        if (!mounted) return;
        setState(() => _pickingAttachments = false);
        return;
      }

      final next = List<_SageFileDraft>.from(_pendingAttachments);
      final unsupported = <String>[];
      final oversizedImages = <String>[];
      for (final file in result.files) {
        final oversizedCount = oversizedImages.length;
        final draft = await _SageFileDraft.fromPlatformFile(
          file,
          onOversizedImage: oversizedImages.add,
        );
        if (draft != null) {
          next.add(draft);
        } else if (oversizedImages.length > oversizedCount) {
          continue;
        } else {
          unsupported.add(file.name);
        }
      }

      if (!mounted) return;
      setState(() {
        _pendingAttachments = next;
        _pickingAttachments = false;
      });
      if (unsupported.isNotEmpty) {
        await _showUnsupportedFilesDialog(unsupported);
      }
      if (oversizedImages.isNotEmpty) {
        await _showOversizedImagesDialog(oversizedImages);
      }
    } catch (_) {
      if (!mounted) return;
      setState(() => _pickingAttachments = false);
    }
  }

  Future<void> _showUnsupportedFilesDialog(List<String> filenames) {
    final shown = filenames.take(3).join(', ');
    final extra =
        filenames.length > 3 ? ' and ${filenames.length - 3} more' : '';
    return showCupertinoDialog<void>(
      context: context,
      builder: (_) => CupertinoAlertDialog(
        title: const Text('Some Files Skipped'),
        content: Text(
          'Sage can currently read supported document, text, and image formats like TXT, Markdown, JSON, CSV, logs, YAML, XML, HTML, RTF, SQL, DOCX, ODT, text-based PDF files, JPG, PNG, WEBP, and GIF.\n\nSkipped: $shown$extra',
        ),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  Future<void> _showOversizedImagesDialog(List<String> filenames) {
    final shown = filenames.take(3).join(', ');
    final extra =
        filenames.length > 3 ? ' and ${filenames.length - 3} more' : '';
    return showCupertinoDialog<void>(
      context: context,
      builder: (_) => CupertinoAlertDialog(
        title: const Text('Image Too Large'),
        content: Text(
          'Sage now shrinks oversized images before upload, but some files are still too large or too hard to decode cleanly. Try a smaller export or screenshot first.\n\nSkipped: $shown$extra',
        ),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  void _removeAttachment(int index) {
    setState(() {
      _pendingAttachments = List<_SageFileDraft>.from(_pendingAttachments)
        ..removeAt(index);
    });
  }

  Future<void> _applyInitialAttachmentsIfNeeded() async {
    if (_appliedInitialAttachments || _handoff.initialAttachments.isEmpty) {
      return;
    }
    _appliedInitialAttachments = true;
    final next = List<_SageFileDraft>.from(_pendingAttachments);
    for (final item in _handoff.initialAttachments) {
      final draft = await _SageFileDraft.fromHandoffAttachment(item);
      if (draft == null) continue;
      final exists = next.any((existing) => existing.path == draft.path);
      if (!exists) next.add(draft);
    }
    if (!mounted) return;
    setState(() => _pendingAttachments = next);
  }

  String _buildContextPayload(String contextString) {
    final sessionSettings =
        _settingsForSageSessionTone(_settings, _handoff.sessionToneOverride);
    final memoryContext = _profile.buildMemoryContext(_memoryItems);
    final expandedContext = _expandedContextString?.trim() ?? '';
    final sessionToneInstruction =
        _promptInstructionForSageSessionTone(_handoff.sessionToneOverride);
    final activeTrackContext = _buildActiveTrackContext();
    return '''
$contextString

$expandedContext

$memoryContext

$_followUpContext

$activeTrackContext

[SYSTEM INSTRUCTION]
$_kSageSystemPrompt

${sessionSettings.toPromptInstruction()}

$sessionToneInstruction
''';
  }

  String _buildActiveTrackContext() {
    if (!_useTrackForSession || _activeTrack == null) return '';
    final track = _activeTrack!;
    final lines = <String>[
      '[ACTIVE FOCUS TRACK]',
      'Title: ${track.title}',
      'Category: ${track.category}',
      'Status: ${track.status}',
      if (track.currentGoal.trim().isNotEmpty)
        'Current goal: ${track.currentGoal.trim()}',
      if (track.whyThisMatters.trim().isNotEmpty)
        'Why it matters: ${track.whyThisMatters.trim()}',
      if (track.recentWins.isNotEmpty)
        'Recent wins: ${track.recentWins.take(3).join('; ')}',
      if (track.stuckPoints.isNotEmpty)
        'Stuck points: ${track.stuckPoints.take(3).join('; ')}',
      if (track.openLoops.isNotEmpty)
        'Open loops: ${track.openLoops.take(3).join('; ')}',
      if (track.nextCommitment.trim().isNotEmpty)
        'Next commitment: ${track.nextCommitment.trim()}',
      'Cadence: ${track.checkInCadence}',
      if (track.lastCheckInAt?.trim().isNotEmpty == true)
        'Last check-in: ${track.lastCheckInAt}',
    ];
    return '${lines.join('\n')}\n';
  }

  Future<void> _loadContextAndStart({
    bool forceRefresh = false,
    bool autoStartGreeting = true,
  }) async {
    setState(() {
      _contextLoading = true;
      _contextError = null;
      _replyError = null;
      _messages = const [];
      _pendingAttachments = const [];
      _savedConversationId = null;
      _speakingMessageId = null;
      _ttsLoadingMessageId = null;
      _ttsErrorMessageId = null;
      _ttsErrorText = null;
    });

    try {
      final results = await Future.wait([
        _api.getFloatchatContext(forceRefresh: forceRefresh),
        _loadExpandedSageContext(),
        _api.getPrimarySageTrack(),
      ]);
      final contextString = results[0] as String;
      final expandedContextString = results[1] as String;
      final activeTrack = results[2] as SageFocusTrack?;
      if (!mounted) return;
      setState(() {
        _contextString = contextString;
        _expandedContextString = expandedContextString;
        _activeTrack = activeTrack;
        _useTrackForSession = activeTrack != null;
        _contextLoading = false;
      });
      await _applyInitialAttachmentsIfNeeded();
      _seedInitialAssistantMessageIfNeeded();
      _applyInitialPrefillIfNeeded();
      if (_handoff.shouldAutoSendPrefill && !_sentInitialPrefill) {
        _sentInitialPrefill = true;
        await _send(
          text: _handoff.normalizedPrefill,
          hiddenUserMessage: _handoff.autoSendPrefillHidden,
          includePendingAttachmentsWhenHidden: _handoff.autoSendPrefillHidden,
        );
        return;
      }
      if (autoStartGreeting && _settings.autoGreeting) {
        await _send(text: '[SESSION_START]', hiddenUserMessage: true);
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _contextLoading = false;
        _contextError = 'Couldn’t reach the server. Check your connection.';
      });
    }
  }

  void _seedInitialAssistantMessageIfNeeded() {
    final explicitSeed = _handoff.seededAssistantMessage;
    final seed = explicitSeed.isNotEmpty
        ? explicitSeed
        : _handoff.shouldShowDefaultWelcome
            ? _kSageDefaultWelcomeMessage
            : '';
    if (_seededInitialAssistantMessage || seed.isEmpty || !mounted) return;
    _seededInitialAssistantMessage = true;
    final transcriptSeed = explicitSeed.isNotEmpty
        ? _prepareSeededSummaryForTranscript(explicitSeed)
        : null;
    setState(() {
      _messages = [
        _SageMessage.assistant(
          _nextMessageId(),
          seed,
          transcriptTextOverride: transcriptSeed,
        ),
      ];
    });
    _scrollDown();
  }

  void _applyInitialPrefillIfNeeded() {
    final prefill = _handoff.normalizedPrefill;
    if (_appliedInitialPrefill || prefill.isEmpty) return;
    _appliedInitialPrefill = true;
    if (_handoff.shouldAutoSendPrefill) return;
    _composerCtrl.value = TextEditingValue(
      text: prefill,
      selection: TextSelection.collapsed(offset: prefill.length),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _focusNode.requestFocus();
      }
    });
  }

  String _prepareSeededSummaryForTranscript(String raw) {
    final cleaned = raw
        .split('---ACTIONS---')
        .first
        .replaceAll('\u0000', '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (cleaned.isEmpty) return '';
    if (cleaned.length <= _kSeededSummaryTranscriptMaxChars &&
        utf8.encode(cleaned).length <= _kSeededSummaryTranscriptMaxBytes) {
      return cleaned;
    }

    const suffix = ' [summary trimmed for follow-up]';
    final suffixBytes = utf8.encode(suffix).length;
    final safeByteBudget = _kSeededSummaryTranscriptMaxBytes - suffixBytes;
    const safeCharBudget = _kSeededSummaryTranscriptMaxChars - suffix.length;
    final buffer = StringBuffer();
    var bytes = 0;
    var chars = 0;

    for (final rune in cleaned.runes) {
      final char = String.fromCharCode(rune);
      final charBytes = utf8.encode(char).length;
      if (chars + 1 > safeCharBudget || bytes + charBytes > safeByteBudget) {
        break;
      }
      buffer.write(char);
      chars += 1;
      bytes += charBytes;
    }

    final trimmed = buffer.toString().trimRight();
    return trimmed.isEmpty ? suffix.trim() : '$trimmed$suffix';
  }

  Future<String> _loadExpandedSageContext() async {
    final sections = await Future.wait<String?>([
      _safeDataSection(
        'TODAY BRIEF',
        _api.getTodayBrief,
        maxChars: 3200,
      ),
      _safeDataSection('BUDGET PLAN AND COMPARISONS', _loadBudgetContext,
          maxChars: 5200),
      _safeDataSection(
        'MENTAL HEALTH DASHBOARD',
        _api.getMentalHealthData,
        maxChars: 3200,
      ),
      _safeDataSection(
        'PEOPLE INTELLIGENCE',
        _api.getPeopleIntelligence,
        maxChars: 3600,
      ),
      _loadFairnessContext(),
      _safeDataSection(
        'MEMORY PROFILE',
        _api.getMemory,
        maxChars: 3600,
      ),
      _safeDataSection(
        'PERSONALIZED RESOURCES',
        _api.getResources,
        maxChars: 3200,
      ),
      _loadVaultContext(),
      _loadDetectiveContext(),
      _safeDataSection(
        'EXIT PLAN',
        _api.exitPlanGet,
        maxChars: 4200,
      ),
      _safeDataSection(
        'EXIT PLAN NOTES',
        _api.exitPlanGetNotes,
        maxChars: 2600,
      ),
      _safeDataSection(
        'EARLY WARNING STATUS',
        _api.getEarlyWarningStatus,
        maxChars: 2600,
      ),
      _safeDataSection(
        'TIMELINE INSIGHT',
        _api.getTherapistInsightStatus,
        maxChars: 2800,
      ),
      _safeDataSection(
        'RECENT TIMELINE ENTRIES',
        () => _api.getTimeline(page: 1, limit: 12),
        maxChars: 5200,
      ),
      _safeDataSection(
        'USER SETTINGS',
        _api.getUserSettings,
        maxChars: 2200,
      ),
      _safeDataSection(
        'MY STORY',
        _loadMyStoryContext,
        maxChars: 3600,
      ),
    ]);

    final available = sections.whereType<String>().toList();
    if (available.isEmpty) return '';
    return '''
[SAGE EXPANDED APP CONTEXT]
These read-only app data sections were loaded from existing Journal Intelligence
endpoints for this Sage session. Treat absent sections as unavailable, not as
empty facts.

${available.join('\n\n')}
''';
  }

  Future<Map<String, dynamic>> _loadBudgetContext() async {
    final results = await Future.wait<dynamic>([
      _api.getBudgetPlan(),
      _api.getBudgetComparisons(),
    ]).timeout(const Duration(seconds: 8));
    return {
      'plan': results[0],
      'comparisons': results[1],
    };
  }

  Future<String?> _loadFairnessContext() async {
    try {
      final results = await Future.wait<dynamic>([
        _api.getFairnessConfig(),
        _api.getFairnessTasks(),
        _api.getFairnessSummary(),
        _api.getFairnessLogs(limit: 30),
        _api.getFairnessContributions(limit: 30),
      ]).timeout(const Duration(seconds: 8));
      return _dataSection(
          'FAIRNESS LEDGER',
          {
            'config': results[0],
            'tasks': results[1],
            'summary': results[2],
            'recent_logs': results[3],
            'recent_contributions': results[4],
          },
          maxChars: 5200);
    } catch (_) {
      return null;
    }
  }

  Future<String?> _loadVaultContext() async {
    try {
      final results = await Future.wait<dynamic>([
        _api.vaultGetCachedSummary(),
        _api.vaultGetFolders(),
      ]).timeout(const Duration(seconds: 8));
      final folders =
          (results[1] as List).whereType<Map>().map((item) => Map.from(item));
      final folderItems = <Map<String, dynamic>>[];

      for (final folder in folders.take(8)) {
        final id = folder['id']?.toString();
        if (id == null || id.isEmpty) continue;
        try {
          final items = await _api
              .vaultGetFolderItems(id)
              .timeout(const Duration(seconds: 4));
          folderItems.add({
            'folder_id': id,
            'folder_name': folder['name'],
            'items': items,
          });
        } catch (_) {}
      }

      return _dataSection(
          'PROOF VAULT',
          {
            'summary': results[0],
            'folders': results[1],
            if (folderItems.isNotEmpty) 'folder_items': folderItems,
          },
          maxChars: 6400);
    } catch (_) {
      return null;
    }
  }

  Future<String?> _loadDetectiveContext() async {
    try {
      final cases =
          await _api.detectiveGetCases().timeout(const Duration(seconds: 8));
      final caseMaps =
          cases.whereType<Map>().map((item) => Map.from(item)).toList();
      final intelligence = <Map<String, dynamic>>[];
      final entries = <Map<String, dynamic>>[];
      final research = <Map<String, dynamic>>[];

      for (final item in caseMaps.take(3)) {
        final id = item['id']?.toString();
        if (id == null || id.isEmpty) continue;
        try {
          final intel = await _api
              .detectiveGetIntelligence(id)
              .timeout(const Duration(seconds: 4));
          intelligence.add({
            'case_id': id,
            'title': item['title'],
            'intelligence': intel,
          });
        } catch (_) {}
        try {
          final caseEntries = await _api
              .detectiveGetEntries(id)
              .timeout(const Duration(seconds: 4));
          entries.add({
            'case_id': id,
            'title': item['title'],
            'entries': caseEntries,
          });
        } catch (_) {}
        try {
          final caseResearch = await _api
              .detectiveGetResearch(id)
              .timeout(const Duration(seconds: 4));
          research.add({
            'case_id': id,
            'title': item['title'],
            'research': caseResearch,
          });
        } catch (_) {}
      }

      return _dataSection(
          'DETECTIVE CASES',
          {
            'cases': caseMaps,
            if (intelligence.isNotEmpty) 'case_intelligence': intelligence,
            if (entries.isNotEmpty) 'case_entries': entries,
            if (research.isNotEmpty) 'case_research': research,
          },
          maxChars: 6200);
    } catch (_) {
      return null;
    }
  }

  Future<Map<String, dynamic>> _loadMyStoryContext() async {
    final results = await Future.wait<dynamic>([
      _api.myStoryGetCases(),
      _api.myStoryGetDrafts(),
    ]).timeout(const Duration(seconds: 8));
    return {
      'cases': results[0],
      'drafts': results[1],
    };
  }

  Future<String?> _safeDataSection(
    String title,
    Future<dynamic> Function() load, {
    int maxChars = 3000,
  }) async {
    try {
      final data = await load().timeout(const Duration(seconds: 8));
      return _dataSection(title, data, maxChars: maxChars);
    } catch (_) {
      return null;
    }
  }

  String? _dataSection(
    String title,
    dynamic data, {
    required int maxChars,
  }) {
    if (!_hasUsefulData(data)) return null;
    return '=== $title ===\n${_jsonForSage(data, maxChars: maxChars)}';
  }

  bool _hasUsefulData(dynamic data) {
    if (data == null) return false;
    if (data is String) return data.trim().isNotEmpty;
    if (data is Iterable) return data.isNotEmpty;
    if (data is Map) {
      if (data.isEmpty) return false;
      return data.values.any(_hasUsefulData);
    }
    return true;
  }

  String _jsonForSage(dynamic data, {required int maxChars}) {
    final normalized = _normalizeForSage(data);
    final encoded = const JsonEncoder.withIndent('  ').convert(normalized);
    if (encoded.length <= maxChars) return encoded;
    return '${encoded.substring(0, maxChars)}\n... [truncated for Sage context]';
  }

  dynamic _normalizeForSage(dynamic value) {
    if (value is Map) {
      return value.map(
        (key, item) => MapEntry(key.toString(), _normalizeForSage(item)),
      );
    }
    if (value is Iterable) {
      return value.map(_normalizeForSage).toList();
    }
    return value;
  }

  String _nextMessageId() {
    _messageCounter += 1;
    return 'sage_${DateTime.now().microsecondsSinceEpoch}_$_messageCounter';
  }

  List<Map<String, dynamic>> _buildApiRequestMessages(
    List<_SageMessage> priorMessages,
    _SageMessage outgoing,
  ) {
    final baseMessages = [
      ...priorMessages.map((message) => message.toApiMessage()),
      outgoing.toApiMessage(),
    ];
    if (priorMessages.isEmpty) return baseMessages;

    final latest = Map<String, dynamic>.from(baseMessages.last);
    final latestContent = latest['content']?.toString().trim() ?? '';
    final transcript = priorMessages
        .where((message) => message.transcriptText.trim().isNotEmpty)
        .map((message) {
      final speaker = message.role == 'assistant' ? 'Sage' : 'User';
      return '$speaker: ${message.transcriptText.trim()}';
    }).join('\n\n');

    if (transcript.isEmpty || latestContent.isEmpty) return baseMessages;

    latest['content'] = '''
[CURRENT CHAT THREAD]
This is the conversation already in progress in this same Sage session.
Treat it as prior turns you can directly continue from.

$transcript

[NEW USER MESSAGE TO ANSWER]
$latestContent
''';

    return [
      ...baseMessages.take(baseMessages.length - 1),
      latest,
    ];
  }

  Future<void> _send({
    String? text,
    bool hiddenUserMessage = false,
    bool includePendingAttachmentsWhenHidden = false,
  }) async {
    final typedPrompt = (text ?? _composerCtrl.text).trim();
    final outgoingAttachments =
        hiddenUserMessage && !includePendingAttachmentsWhenHidden
            ? const <_SageFileDraft>[]
            : _pendingAttachments;
    final prompt = typedPrompt.isNotEmpty
        ? typedPrompt
        : outgoingAttachments.isNotEmpty
            ? 'Please review these attached files.'
            : '';
    if (prompt.isEmpty || _replyLoading || _contextString == null) return;

    final outgoing = _SageMessage.user(
      _nextMessageId(),
      prompt,
      attachments: outgoingAttachments
          .map((item) => item.toMessageAttachment())
          .toList(),
    );
    final priorMessages = _messages;
    final visibleMessages =
        hiddenUserMessage ? _messages : [..._messages, outgoing];

    if (!hiddenUserMessage) {
      _composerCtrl.clear();
    }

    setState(() {
      _messages = visibleMessages;
      _replyLoading = true;
      _replyError = null;
      _pendingAttachments = const [];
    });
    _scrollDown();

    final requestMessages = _buildApiRequestMessages(priorMessages, outgoing);

    try {
      final response = await _api.sendFloatchatMessage(
        messages: requestMessages,
        contextString: _buildContextPayload(_contextString!),
        webSearchEnabled: _settings.webSearchEnabled,
        maxTokens: AiResponseLimits.sageReplyMaxTokens,
        attachments: outgoing.attachments
            .map((attachment) => attachment.toApiAttachmentPayload())
            .where((payload) => payload.isNotEmpty)
            .toList(),
      );
      final reply = response['reply']?.toString().trim();
      final actions = (response['actions'] as List?)
              ?.whereType<Map>()
              .map((item) => Map<String, dynamic>.from(item))
              .toList() ??
          const <Map<String, dynamic>>[];

      if (!mounted) return;
      final assistantMessage = _SageMessage.assistant(
        _nextMessageId(),
        reply?.isNotEmpty == true
            ? reply!
            : 'I have your context loaded. What do you want to work through first?',
        actions: actions,
      );
      setState(() {
        _messages = [...visibleMessages, assistantMessage];
        _replyLoading = false;
      });

      if (!hiddenUserMessage &&
          _settings.autoRemember &&
          assistantMessage.text.trim().isNotEmpty) {
        unawaited(_captureMemoryFromExchange(prompt, assistantMessage.text));
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _messages = visibleMessages;
        _replyLoading = false;
        _replyError = _parseError(e);
      });
    }

    _scrollDown();
  }

  Future<void> _captureMemoryFromExchange(
    String userPrompt,
    String assistantReply,
  ) async {
    if (_contextString == null) return;

    final extractionPrompt = '''
You are extracting durable memory for future assistant context.

Only keep facts that are likely to matter in future conversations:
- ongoing life context
- repeated preferences
- important people dynamics
- recurring goals or constraints

Ignore one-off planning details, generic feelings, and anything already obvious from the current message alone.
Only extract facts explicitly stated by the user in this exchange. Do not save facts that appear only in the assistant reply or background context.
Do not save transient logistics like apartment callbacks, prices, dates, traffic, or short-term plans unless the user explicitly asks you to remember them.

Return strict JSON only:
{"facts":[{"text":"...", "confidence":0.0}]}

At most 3 facts.

User message:
$userPrompt

Assistant reply:
$assistantReply
''';

    try {
      final response = await _api.sendFloatchatMessage(
        messages: [
          {
            'role': 'user',
            'content': extractionPrompt,
          }
        ],
        contextString: '''
[SYSTEM INSTRUCTION]
You are a memory extraction utility for Sage.
Return JSON only.
''',
        maxTokens: AiResponseLimits.sageUtilityMaxTokens,
      );
      final reply = response['reply']?.toString() ?? '';
      final parsed = _extractFacts(reply);
      if (parsed.isEmpty) return;
      final next = await _profile.addMemoryTexts(parsed, source: 'learned');
      if (!mounted) return;
      setState(() => _memoryItems = next);
    } catch (_) {}
  }

  List<String> _extractFacts(String raw) {
    if (raw.trim().isEmpty) return const [];
    String candidate = raw.trim();
    final fenced =
        RegExp(r'```(?:json)?\s*([\s\S]*?)```').firstMatch(candidate);
    if (fenced != null) candidate = fenced.group(1)?.trim() ?? candidate;

    try {
      final decoded = Map<String, dynamic>.from(jsonDecode(candidate) as Map);
      final facts = (decoded['facts'] as List?)
              ?.whereType<Map>()
              .map((item) => Map<String, dynamic>.from(item))
              .where((item) => (item['confidence'] as num?)?.toDouble() != null)
              .where((item) => ((item['confidence'] as num).toDouble()) >= 0.72)
              .map((item) => item['text']?.toString().trim() ?? '')
              .where((text) => text.isNotEmpty)
              .toList() ??
          const <String>[];
      return facts;
    } catch (_) {
      return const [];
    }
  }

  Future<void> _clearChat() async {
    if (_replyLoading || _contextLoading) return;
    await _audioPlayer.stop();
    if (mounted) {
      setState(() {
        _handoff = _handoff.forNewChat();
        _seededInitialAssistantMessage = false;
        _appliedInitialPrefill = false;
        _sentInitialPrefill = false;
        _composerCtrl.clear();
        _speakingMessageId = null;
        _ttsLoadingMessageId = null;
        _ttsErrorMessageId = null;
        _ttsErrorText = null;
      });
    }
    await _loadContextAndStart(
        autoStartGreeting: _handoff.shouldAutoStartGreeting);
  }

  List<Map<String, dynamic>> _messagesForSave() {
    return _messages
        .map((message) => message.toSavedPayload())
        .where((message) =>
            (message['content']?.toString().trim().isNotEmpty ?? false))
        .toList();
  }

  Future<void> _showSavedChatMenu() async {
    if (_savingConversation || _contextLoading) return;
    final action = await showCupertinoModalPopup<String>(
      context: context,
      builder: (context) => CupertinoActionSheet(
        title: const Text('Saved Chats'),
        message: const Text(
          'Save this Sage conversation to the server or open a previously saved one.',
        ),
        actions: [
          if (_messages.isNotEmpty)
            CupertinoActionSheetAction(
              onPressed: () => Navigator.pop(context, 'save'),
              child: Text(
                _savedConversationId == null
                    ? 'Save current conversation'
                    : 'Update saved conversation',
              ),
            ),
          CupertinoActionSheetAction(
            onPressed: () => Navigator.pop(context, 'open'),
            child: const Text('Open saved conversations'),
          ),
        ],
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
      ),
    );

    if (!mounted || action == null) return;
    if (action == 'save') {
      await _saveConversation();
    } else if (action == 'open') {
      await _openSavedConversations();
    }
  }

  Future<void> _saveConversation() async {
    if (_messages.isEmpty || _contextString == null || _savingConversation) {
      return;
    }

    final wasUpdate = _savedConversationId != null;
    setState(() => _savingConversation = true);
    try {
      final saved = await _api.saveFloatchatConversation(
        conversationId: _savedConversationId,
        contextString: _buildContextPayload(_contextString!),
        messages: _messagesForSave(),
        webSearchEnabled: _settings.webSearchEnabled,
      );
      if (!mounted) return;
      setState(() {
        _savedConversationId = saved.id;
        _savingConversation = false;
      });
      await showCupertinoDialog<void>(
        context: context,
        builder: (_) => CupertinoAlertDialog(
          title:
              Text(wasUpdate ? 'Conversation updated' : 'Conversation saved'),
          content: Text('"${saved.title}" is now available in Saved Chats.'),
          actions: [
            CupertinoDialogAction(
              onPressed: () => Navigator.pop(context),
              child: const Text('OK'),
            ),
          ],
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _savingConversation = false);
      await showCupertinoDialog<void>(
        context: context,
        builder: (_) => CupertinoAlertDialog(
          title: const Text('Save failed'),
          content: Text(_parseError(e)),
          actions: [
            CupertinoDialogAction(
              onPressed: () => Navigator.pop(context),
              child: const Text('OK'),
            ),
          ],
        ),
      );
    }
  }

  Future<void> _openSavedConversations() async {
    final result = await Navigator.push<SavedSageChatsResult>(
      context,
      CupertinoPageRoute(
        builder: (_) => const SavedSageChatsScreen(),
      ),
    );
    if (result == null || !mounted) return;
    if (result.startNewChat) {
      await _clearChat();
      return;
    }
    final saved = result.conversation;
    if (saved == null) return;

    await _audioPlayer.stop();
    setState(() {
      _messages = saved.messages
          .map((message) => _SageMessage.fromSavedMessage(message))
          .toList();
      _savedConversationId = saved.id;
      _replyLoading = false;
      _replyError = null;
      _speakingMessageId = null;
      _ttsLoadingMessageId = null;
      _ttsErrorMessageId = null;
      _ttsErrorText = null;
    });
    _scrollDown();
  }

  Future<void> _openSageSettings() async {
    await Navigator.push(
      context,
      CupertinoPageRoute(
        builder: (_) => DefaultTextStyle.merge(
          style: const TextStyle(decoration: TextDecoration.none),
          child: const SageSettingsScreen(),
        ),
      ),
    );
    await _loadSageProfile();
  }

  Future<void> _chooseFocusTrack() async {
    final selected = await Navigator.push<SageFocusTrack>(
      context,
      CupertinoPageRoute(
        builder: (_) => DefaultTextStyle.merge(
          style: const TextStyle(decoration: TextDecoration.none),
          child: SageTracksScreen(
            allowSelection: true,
            initialSelectedTrackId: _activeTrack?.id,
          ),
        ),
      ),
    );
    if (selected == null || !mounted) return;
    try {
      final updated = await _api.setPrimarySageTrack(selected.id);
      if (!mounted) return;
      setState(() {
        _activeTrack = updated;
        _useTrackForSession = true;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _activeTrack = selected;
        _useTrackForSession = true;
      });
    }
  }

  void _muteTrackForSession() {
    setState(() => _useTrackForSession = false);
  }

  void _scrollDown() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(
          _scroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 260),
          curve: Curves.easeOutCubic,
        );
      }
    });
  }

  Future<void> _toggleSpeak(_SageMessage message) async {
    if (message.role != 'assistant' || message.text.trim().isEmpty) return;

    if (_ttsLoadingMessageId == message.id) return;

    if (_speakingMessageId == message.id) {
      _ttsRequestCounter += 1;
      await _audioPlayer.stop();
      if (!mounted) return;
      setState(() {
        _speakingMessageId = null;
        _ttsLoadingMessageId = null;
        _ttsSequenceActive = false;
      });
      return;
    }

    final requestId = ++_ttsRequestCounter;
    setState(() {
      _ttsLoadingMessageId = message.id;
      _speakingMessageId = null;
      _ttsErrorMessageId = null;
      _ttsErrorText = null;
    });

    try {
      final stopwatch = Stopwatch()..start();
      await configureTtsAudioPlayer(_audioPlayer);
      await _audioPlayer.stop();
      final voiceSettings = await _api.getVoiceSettings();
      final hasVoiceKey = voiceSettings['has_voice_key'] == true;
      final hasElevenLabsKey = voiceSettings['has_elevenlabs_key'] == true;
      final usingOpenAi = voiceSettings['using_openai'] == true;
      if (!hasVoiceKey && !hasElevenLabsKey && !usingOpenAi) {
        throw Exception(
          'Voice requires an ElevenLabs API key. Add one in Settings → Voice, or configure ELEVENLABS_API_KEY on the server.',
        );
      }
      final chunks = buildSpeechChunks(message.text);
      if (chunks.isEmpty) throw Exception('No text to speak.');
      developer.log(
        'Sage TTS prepared ${chunks.length} chunk(s) for message ${message.id}',
        name: 'journal.tts',
      );

      if (!mounted) return;
      setState(() {
        _ttsLoadingMessageId = null;
        _speakingMessageId = message.id;
      });
      _ttsSequenceActive = true;

      Future<List<int>>? nextBytesFuture;
      for (var i = 0; i < chunks.length; i++) {
        if (requestId != _ttsRequestCounter) return;
        if (!mounted) return;
        final isFirstChunk = i == 0;
        if (isFirstChunk) {
          setState(() => _ttsLoadingMessageId = message.id);
          nextBytesFuture = _api.voiceSpeak(
            text: chunks[i],
            voiceId: _settings.voiceId,
          );
        }
        final bytes = await nextBytesFuture!;
        if (bytes.isEmpty) {
          throw Exception('No audio returned.');
        }
        if (requestId != _ttsRequestCounter) return;
        if (!mounted) return;
        setState(() => _ttsLoadingMessageId = null);
        if (i + 1 < chunks.length) {
          nextBytesFuture = _api.voiceSpeak(
            text: chunks[i + 1],
            voiceId: _settings.voiceId,
          );
        } else {
          nextBytesFuture = null;
        }
        await deleteTtsAudioTempFile(_ttsTempAudioPath);
        _ttsTempAudioPath = await writeTtsAudioTempFile(
          prefix: 'sage-tts',
          bytes: bytes,
        );
        await playTtsAudioFile(
          _audioPlayer,
          path: _ttsTempAudioPath!,
        );
        if (isFirstChunk) {
          developer.log(
            'Sage TTS first audio for ${message.id} started after ${stopwatch.elapsedMilliseconds} ms',
            name: 'journal.tts',
          );
        }
        await _waitForAudioToFinish();
      }

      if (requestId != _ttsRequestCounter) return;
      _ttsSequenceActive = false;
      developer.log(
        'Sage TTS completed for ${message.id} in ${stopwatch.elapsedMilliseconds} ms',
        name: 'journal.tts',
      );
      if (!mounted) return;
      setState(() {
        _speakingMessageId = null;
        _ttsLoadingMessageId = null;
      });
    } catch (e) {
      if (requestId != _ttsRequestCounter) return;
      _ttsSequenceActive = false;
      if (!mounted) return;
      setState(() {
        _ttsLoadingMessageId = null;
        _speakingMessageId = null;
        _ttsErrorMessageId = message.id;
        _ttsErrorText = _parseTtsError(e);
      });
    }
  }

  Future<void> _waitForAudioToFinish() {
    final completer = Completer<void>();
    StreamSubscription<void>? completeSub;
    StreamSubscription<PlayerState>? stateSub;

    void finish() {
      if (completer.isCompleted) return;
      completeSub?.cancel();
      stateSub?.cancel();
      completer.complete();
    }

    completeSub = _audioPlayer.onPlayerComplete.listen((_) => finish());
    stateSub = _audioPlayer.onPlayerStateChanged.listen((state) {
      if (state == PlayerState.stopped || state == PlayerState.disposed) {
        finish();
      }
    });

    return completer.future.timeout(
      const Duration(minutes: 3),
      onTimeout: () {
        finish();
      },
    );
  }

  String _parseTtsError(dynamic e) {
    if (e is DioException) {
      final data = e.response?.data;
      final decoded = _decodeTtsErrorData(data);
      if (decoded != null && decoded.isNotEmpty) {
        return 'Couldn’t generate audio: $decoded';
      }
      final status = e.response?.statusCode;
      if (status == 400) {
        return 'Couldn’t generate audio. Check Settings → Voice.';
      }
      if (status == 502 || status == 504) {
        return 'Couldn’t generate audio. The voice service timed out or failed upstream.';
      }
      if (status != null) {
        return 'Couldn’t generate audio. Server returned $status.';
      }
    }
    if (e is Exception) {
      final message = e.toString().replaceFirst('Exception: ', '').trim();
      if (message.isNotEmpty) {
        return 'Couldn’t generate audio: $message';
      }
    }
    final parsed = _parseError(e);
    if (parsed != 'Something went wrong.') {
      return 'Couldn’t generate audio: $parsed';
    }
    final raw = e.toString().trim();
    if (raw.isNotEmpty && raw != 'null') {
      return 'Couldn’t generate audio: $raw';
    }
    return 'Couldn’t generate audio. Try again, or shorten the reply.';
  }

  String? _decodeTtsErrorData(dynamic data) {
    dynamic decoded = data;
    if (data is List<int>) {
      try {
        decoded = utf8.decode(data);
      } catch (_) {
        return null;
      }
    }
    if (decoded is String) {
      final trimmed = decoded.trim();
      if (trimmed.isEmpty) return null;
      try {
        final json = jsonDecode(trimmed);
        if (json is Map && json['detail'] != null) {
          return json['detail'].toString();
        }
      } catch (_) {}
      return trimmed;
    }
    if (decoded is Map && decoded['detail'] != null) {
      return decoded['detail'].toString();
    }
    return null;
  }

  Future<void> _openActionFromMessage(
    Map<String, dynamic> action,
    _SageMessage? sourceMessage,
  ) async {
    final route = _actionRoute(action);
    final detectiveDraft = sourceMessage == null
        ? null
        : await _buildDetectiveDraftForAction(action, sourceMessage);
    final writeDraft = sourceMessage == null
        ? null
        : await _buildWriteDraftForAction(action, sourceMessage, route: route);
    final destination = _screenForAction(
      action,
      route: route,
      detectiveDraft: detectiveDraft,
      writeDraft: writeDraft,
    );
    if (destination == null) return;

    if (!mounted) return;
    Navigator.push(
      context,
      CupertinoPageRoute(
        builder: (_) => DefaultTextStyle.merge(
          style: const TextStyle(decoration: TextDecoration.none),
          child: destination,
        ),
      ),
    );
  }

  Future<DetectiveEntryDraft?> _buildDetectiveDraftForAction(
    Map<String, dynamic> action,
    _SageMessage sourceMessage,
  ) async {
    if (!_shouldPrefillDetectiveAction(action)) return null;

    final fields = _actionFields(action);
    final label = _actionLabel(action);
    final assistantText = sourceMessage.text.trim();
    if (assistantText.isEmpty) return null;
    if (_contextString == null) {
      return _fallbackDetectiveDraft(
        assistantText,
        label: label,
        fields: fields,
      );
    }

    final prompt = '''
Return strict JSON only:
{"content":"...", "entry_type":"observation", "severity":"medium"}

Turn this Sage reply into a detective case log entry draft that is ready to paste and submit.

Rules:
- Preserve the most important factual claim or prediction from Sage.
- Write like an evidence note, not like a pep talk.
- Keep it specific and useful.
- Use short bullets only if they make the note clearer.
- Allowed entry_type values: note, observation, statement, admission, contradiction, timeline
- Allowed severity values: critical, high, medium, low, info

Action label: $label
Action fields: $fields

Sage reply:
$assistantText
''';

    final generated = await _runActionPrefillRequest(
      loadingLabel: label,
      prompt: prompt,
    );
    return _parseDetectiveDraft(
          generated,
          sourceLabel: label,
        ) ??
        _fallbackDetectiveDraft(
          assistantText,
          label: label,
          fields: fields,
        );
  }

  Future<String?> _buildWriteDraftForAction(
    Map<String, dynamic> action,
    _SageMessage sourceMessage, {
    required String? route,
  }) async {
    if (route != '/write') return null;

    final label = _actionLabel(action);
    final fields = _actionFields(action);
    final assistantText = sourceMessage.text.trim();
    if (assistantText.isEmpty) return null;
    if (_contextString == null) {
      return _fallbackWriteDraft(
        label: label,
        fields: fields,
        assistantText: assistantText,
      );
    }

    final prompt = '''
Return strict JSON only:
{"text":"..."}

Turn this Sage reply into a first-person journal draft that is ready to keep editing in the Write screen.

Rules:
- The draft must sound like the user writing, not Sage talking to them.
- Keep the emotional truth and key details from Sage's reply.
- Write as something the user could continue from directly.
- If the action sounds like "process", "work through", or "journal about" a feeling, make the opening lines reflective and first-person.
- Never refer to Sage, the assistant, "this action", or "the reply above".
- Do not frame it like advice. Frame it like lived experience and reflection.
- No title.
- No markdown.
- Keep it concise but substantial.

Action label: $label
Action fields: $fields

Sage reply:
$assistantText
''';

    final generated = await _runActionPrefillRequest(
      loadingLabel: label,
      prompt: prompt,
    );
    return _parseJsonTextField(generated, field: 'text') ??
        _fallbackWriteDraft(
          label: label,
          fields: fields,
          assistantText: assistantText,
        );
  }

  Future<String?> _runActionPrefillRequest({
    required String loadingLabel,
    required String prompt,
  }) async {
    if (!mounted) return null;

    setState(() => _actionPrefillLabel = loadingLabel);

    try {
      final response = await _api.sendFloatchatMessage(
        messages: [
          {
            'role': 'user',
            'content': prompt,
          },
        ],
        contextString: _buildContextPayload(_contextString!),
        maxTokens: AiResponseLimits.sageUtilityMaxTokens,
      );
      return response['reply']?.toString();
    } catch (_) {
      return null;
    } finally {
      if (mounted) {
        setState(() => _actionPrefillLabel = null);
      }
    }
  }

  DetectiveEntryDraft? _parseDetectiveDraft(
    String? rawReply, {
    required String sourceLabel,
  }) {
    if (rawReply == null || rawReply.trim().isEmpty) return null;
    final cleaned = rawReply.split('---ACTIONS---').first.trim();
    try {
      final decoded = jsonDecode(cleaned);
      if (decoded is! Map) return null;
      final content = decoded['content']?.toString().trim() ?? '';
      if (content.isEmpty) return null;
      return DetectiveEntryDraft(
        content: content,
        entryType: _normalizeDetectiveEntryType(
          decoded['entry_type']?.toString(),
        ),
        severity: _normalizeDetectiveSeverity(
          decoded['severity']?.toString(),
        ),
        sourceLabel: sourceLabel,
      );
    } catch (_) {
      return null;
    }
  }

  String? _parseJsonTextField(
    String? rawReply, {
    required String field,
  }) {
    if (rawReply == null || rawReply.trim().isEmpty) return null;
    final cleaned = rawReply.split('---ACTIONS---').first.trim();
    try {
      final decoded = jsonDecode(cleaned);
      if (decoded is! Map) return null;
      final value = decoded[field]?.toString().trim();
      if (value == null || value.isEmpty) return null;
      return value;
    } catch (_) {
      return null;
    }
  }

  String _fallbackWriteDraft({
    required String label,
    required String fields,
    required String assistantText,
  }) {
    final excerpt = assistantText
        .split(RegExp(r'\n\s*\n'))
        .map((chunk) => chunk.trim())
        .where((chunk) => chunk.isNotEmpty)
        .take(2)
        .join('\n\n');

    if (fields.contains('frustration') ||
        fields.contains('angry') ||
        fields.contains('upset') ||
        fields.contains('process')) {
      return '''
I'm frustrated right now, and I want to get honest about why.

What happened:

What I felt in my body the moment it hit:

What actually hurt me about it:

What I wish had happened instead:

What I need to remember so I don't minimize this later:

$excerpt
''';
    }

    if (fields.contains('grief') ||
        fields.contains('sad') ||
        fields.contains('hurt')) {
      return '''
I'm trying to be honest about what is hurting right now.

What happened:

What feels hardest to admit:

What this brought up for me:

What I need compassion for instead of judgment:

$excerpt
''';
    }

    return '''
I want to put this into my own words and see what is actually true for me.

What happened:

What I'm feeling:

What stands out most to me:

What I need next:

$excerpt
''';
  }

  DetectiveEntryDraft _fallbackDetectiveDraft(
    String assistantText, {
    required String label,
    required String fields,
  }) {
    final paragraphs = assistantText
        .split(RegExp(r'\n\s*\n'))
        .map((chunk) => chunk.trim())
        .where((chunk) => chunk.isNotEmpty)
        .toList();
    final excerpt =
        (paragraphs.isNotEmpty ? paragraphs.first : assistantText).trim();
    final entryType = fields.contains('contradiction')
        ? 'contradiction'
        : fields.contains('timeline')
            ? 'timeline'
            : fields.contains('statement')
                ? 'statement'
                : 'observation';
    final severity = fields.contains('critical')
        ? 'critical'
        : fields.contains('high')
            ? 'high'
            : fields.contains('low')
                ? 'low'
                : 'medium';

    return DetectiveEntryDraft(
      content: 'Sage action: $label\n\n$excerpt',
      entryType: entryType,
      severity: severity,
      sourceLabel: label,
    );
  }

  bool _shouldPrefillDetectiveAction(Map<String, dynamic> action) {
    final fields = _actionFields(action);
    final mentionsDetectiveSurface = fields.contains('detective') ||
        fields.contains('evidence') ||
        fields.contains('case') ||
        fields.contains('contradiction');
    final soundsLikeInjection = fields.contains('add ') ||
        fields.startsWith('add ') ||
        fields.contains('save ') ||
        fields.contains('log ') ||
        fields.contains('inject') ||
        fields.contains('entry') ||
        fields.contains('note') ||
        fields.contains('prediction');
    return mentionsDetectiveSurface && soundsLikeInjection;
  }

  bool _shouldAutoSelectSingleCase(Map<String, dynamic> action) {
    final fields = _actionFields(action);
    return fields.contains('detective') ||
        fields.contains('evidence') ||
        fields.contains('case') ||
        fields.contains('prediction');
  }

  String _normalizeDetectiveEntryType(String? raw) {
    const allowed = {
      'note',
      'observation',
      'statement',
      'admission',
      'contradiction',
      'timeline',
    };
    final normalized = raw?.trim().toLowerCase() ?? '';
    return allowed.contains(normalized) ? normalized : 'observation';
  }

  String _normalizeDetectiveSeverity(String? raw) {
    const allowed = {'critical', 'high', 'medium', 'low', 'info'};
    final normalized = raw?.trim().toLowerCase() ?? '';
    return allowed.contains(normalized) ? normalized : 'medium';
  }

  String _actionFields(Map<String, dynamic> action) {
    return <String>[
      action['tool']?.toString() ?? '',
      action['route']?.toString() ?? '',
      action['screen']?.toString() ?? '',
      action['destination']?.toString() ?? '',
      action['target']?.toString() ?? '',
      action['title']?.toString() ?? '',
      action['label']?.toString() ?? '',
      action['name']?.toString() ?? '',
      action['description']?.toString() ?? '',
    ].join(' ').toLowerCase();
  }

  String _actionLabel(Map<String, dynamic> action) {
    final label = action['label']?.toString().trim();
    final title = action['title']?.toString().trim();
    final name = action['name']?.toString().trim();
    if (label != null && label.isNotEmpty) return label;
    if (title != null && title.isNotEmpty) return title;
    if (name != null && name.isNotEmpty) return name;
    return 'this Sage action';
  }

  String? _actionRoute(Map<String, dynamic> action) {
    final route = action['route']?.toString().trim().toLowerCase();
    if (route == null || route.isEmpty) return null;
    return route.startsWith('/') ? route : '/$route';
  }

  Widget? _screenForAction(
    Map<String, dynamic> action, {
    String? route,
    DetectiveEntryDraft? detectiveDraft,
    String? writeDraft,
  }) {
    final fields = _actionFields(action);
    final shouldAutoSelectSingleCase = _shouldAutoSelectSingleCase(action);

    switch (route) {
      case '/war-room':
        return const WarRoomScreen();
      case '/exit-plan':
        return const ExitPlanScreen();
      case '/follow-ups':
        return const FollowUpsScreen();
      case '/evidence':
        if (detectiveDraft != null) {
          return DetectiveScreen(
            pendingEntryDraft: detectiveDraft,
            autoSelectSingleCase: true,
          );
        }
        return const ProofVaultScreen();
      case '/detective':
        return DetectiveScreen(
          pendingEntryDraft: detectiveDraft,
          autoSelectSingleCase: shouldAutoSelectSingleCase,
        );
      case '/write':
        return WriteScreen(initialText: writeDraft);
      case '/patterns':
      case '/contradictions':
        return const EarlyWarningScreen();
      case '/mental-health':
      case '/nervous':
        return const MentalHealthScreen();
      case '/people-intel':
        return const DetectiveScreen();
    }

    if (fields.contains('war room') || fields.contains('war_room')) {
      return const WarRoomScreen();
    }
    if (fields.contains('proof vault') ||
        fields.contains('proof_vault') ||
        fields.contains('/evidence') ||
        fields.contains('evidence vault')) {
      if (detectiveDraft != null) {
        return DetectiveScreen(
          pendingEntryDraft: detectiveDraft,
          autoSelectSingleCase: true,
        );
      }
      return const ProofVaultScreen();
    }
    if (fields.contains('budget')) {
      return const BudgetPlannerScreen();
    }
    if (fields.contains('detective')) {
      return DetectiveScreen(
        pendingEntryDraft: detectiveDraft,
        autoSelectSingleCase: shouldAutoSelectSingleCase,
      );
    }
    if (fields.contains('exit plan') || fields.contains('exit_plan')) {
      return const ExitPlanScreen();
    }
    if (fields.contains('follow-up') ||
        fields.contains('follow ups') ||
        fields.contains('job application')) {
      return const FollowUpsScreen();
    }
    if (fields.contains('fairness')) {
      return const FairnessLedgerScreen();
    }
    if (fields.contains('mental health') ||
        fields.contains('mental_health') ||
        fields.contains('/nervous') ||
        fields.contains('nervous system')) {
      return const MentalHealthScreen();
    }
    if (fields.contains('ask my journal') ||
        fields.contains('ask_journal') ||
        fields.contains('/ask')) {
      return const AskJournalScreen();
    }
    if (fields.contains('today')) {
      return const TodayScreen();
    }
    if (fields.contains('timeline')) {
      return const TimelineScreen();
    }
    if (fields.contains('write')) {
      return WriteScreen(initialText: writeDraft);
    }
    if (fields.contains('early warning') ||
        fields.contains('early_warning') ||
        fields.contains('/patterns') ||
        fields.contains('/contradictions')) {
      return const EarlyWarningScreen();
    }
    if (fields.contains('people-intel') ||
        fields.contains('people intelligence')) {
      return const DetectiveScreen();
    }
    if (fields.contains('settings')) {
      return const SettingsScreen();
    }
    if (fields.contains('resources')) {
      return const ResourcesScreen();
    }
    if (fields.contains('invite')) {
      if (fields.contains('admin')) return const AdminScreen();
      return const InviteAccessScreen();
    }
    if (fields.contains('admin')) {
      return const AdminScreen();
    }
    return null;
  }

  List<Map<String, dynamic>> _resolvableActions(
      List<Map<String, dynamic>> raw) {
    return raw.where((item) => _screenForAction(item) != null).toList();
  }

  @override
  Widget build(BuildContext context) {
    final keyboardInset = MediaQuery.of(context).viewInsets.bottom;
    final threadBottomClearance = keyboardInset > 0 ? 66.0 : 18.0;

    return CupertinoPageScaffold(
      backgroundColor: JournalColors.bgBase,
      child: Stack(
        children: [
          const Positioned.fill(child: _SageBackdrop()),
          Column(
            children: [
              _SageHeader(
                hasConversation: _messages.isNotEmpty,
                busy: _replyLoading || _contextLoading || _savingConversation,
                onClear: _clearChat,
                onOpenSavedChats: _showSavedChatMenu,
                onOpenSettings: _openSageSettings,
              ),
              Expanded(
                child: _SageThread(
                  scrollController: _scroll,
                  bottomClearance: threadBottomClearance,
                  contextLoading: _contextLoading,
                  contextError: _contextError,
                  replyLoading: _replyLoading,
                  replyError: _replyError,
                  messages: _messages,
                  onRetryContext: _loadContextAndStart,
                  onActionTap: _openActionFromMessage,
                  resolveActions: _resolvableActions,
                  onToggleSpeak: _toggleSpeak,
                  speakingMessageId: _speakingMessageId,
                  ttsLoadingMessageId: _ttsLoadingMessageId,
                  ttsErrorMessageId: _ttsErrorMessageId,
                  ttsErrorText: _ttsErrorText,
                  settings: _settings,
                  sessionToneOverride: _handoff.sessionToneOverride,
                  profileLoading: _profileLoading,
                  memoryCount: _memoryItems.length,
                  activeTrack: _activeTrack,
                  useTrackForSession: _useTrackForSession,
                  onChooseTrack: _chooseFocusTrack,
                  onMuteTrackForSession: _muteTrackForSession,
                  onNewChat: _clearChat,
                ),
              ),
              _SageInputBar(
                controller: _composerCtrl,
                focusNode: _focusNode,
                canSend: _canSend,
                loading: _replyLoading,
                pickingAttachments: _pickingAttachments,
                attachments: _pendingAttachments
                    .map((item) => item.toMessageAttachment())
                    .toList(),
                onPickAttachment: _chooseAttachmentSource,
                onRemoveAttachment: _removeAttachment,
                onSend: () => _send(),
                onSuggestionTap: (prompt) => _send(text: prompt),
              ),
            ],
          ),
          if (_actionPrefillLabel != null)
            Positioned.fill(
              child: ColoredBox(
                color: _withAlpha(JournalColors.bgBase, 0.72),
                child: Center(
                  child: GlassCard(
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const CupertinoActivityIndicator(),
                        const SizedBox(width: 12),
                        Flexible(
                          child: Text(
                            'Preparing $_actionPrefillLabel…',
                            style: const TextStyle(
                              color: JournalColors.textPrimary,
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _SageMessage {
  const _SageMessage({
    this.id,
    required this.role,
    required this.text,
    this.transcriptTextOverride,
    this.actions = const [],
    this.attachments = const [],
  });

  const _SageMessage.user(
    String id,
    String text, {
    List<_SageMessageAttachment> attachments = const [],
  }) : this(
          id: id,
          role: 'user',
          text: text,
          attachments: attachments,
        );

  const _SageMessage.assistant(
    String id,
    String text, {
    String? transcriptTextOverride,
    List<Map<String, dynamic>> actions = const [],
  }) : this(
          id: id,
          role: 'assistant',
          text: text,
          transcriptTextOverride: transcriptTextOverride,
          actions: actions,
        );

  final String? id;
  final String role;
  final String text;
  final String? transcriptTextOverride;
  final List<Map<String, dynamic>> actions;
  final List<_SageMessageAttachment> attachments;

  factory _SageMessage.fromSavedMessage(SavedFloatchatMessage message) {
    return _SageMessage(
      id: 'sage_saved_${DateTime.now().microsecondsSinceEpoch}_${message.role}_${message.content.length}',
      role: message.role,
      text: message.content,
      actions: message.actions,
      attachments: message.attachments
          .map(_SageMessageAttachment.fromSavedPayload)
          .toList(),
    );
  }

  Map<String, dynamic> toApiMessage() {
    final fileBlocks = attachments
        .map((attachment) => attachment.toPromptBlock())
        .where((block) => block.trim().isNotEmpty)
        .toList();
    final content = [
      text.trim(),
      if (fileBlocks.isNotEmpty) '[ATTACHED FILES]\n${fileBlocks.join('\n\n')}',
    ].where((part) => part.isNotEmpty).join('\n\n');

    return <String, dynamic>{
      'role': role,
      'content': content,
    };
  }

  String get transcriptText => transcriptTextOverride?.trim().isNotEmpty == true
      ? transcriptTextOverride!.trim()
      : text;

  Map<String, dynamic> toSavedPayload() => {
        'role': role,
        'content': text,
        if (actions.isNotEmpty) 'actions': actions,
        if (attachments.isNotEmpty)
          'attachments': attachments
              .map((attachment) => attachment.toSavedPayload())
              .toList(),
      };
}

class _SageFileDraft {
  const _SageFileDraft({
    required this.name,
    required this.path,
    required this.extension,
    this.extractedText = '',
    this.imageBase64,
    this.imageMediaType,
    this.imageByteSize,
  });

  static Future<_SageFileDraft?> fromPlatformFile(
    PlatformFile file, {
    ValueChanged<String>? onOversizedImage,
  }) async {
    final path = file.path;
    if (path == null || path.trim().isEmpty) return null;
    final ext = _extensionForName(file.name);

    if (_kSupportedSageImageExtensions.contains(ext)) {
      final imageFile = File(path);
      if (!await imageFile.exists()) return null;
      final bytes = await imageFile.readAsBytes();
      if (bytes.isEmpty) return null;
      if (bytes.length > _kMaxSageImageBytes) {
        onOversizedImage?.call(file.name);
        return null;
      }
      final normalized = await _normalizeSageImageBytes(
        bytes: bytes,
        extension: ext,
      );
      if (normalized == null) {
        onOversizedImage?.call(file.name);
        return null;
      }
      final normalizedName = normalized.extension == ext || ext.isEmpty
          ? file.name
          : '${file.name.replaceFirst(RegExp(r'\.[^.]+$'), '')}.${normalized.extension}';

      return _SageFileDraft(
        name: normalizedName,
        path: path,
        extension: normalized.extension,
        imageBase64: base64Encode(normalized.bytes),
        imageMediaType: normalized.mediaType,
        imageByteSize: normalized.bytes.length,
      );
    }

    if (!_kSupportedSageFileExtensions.contains(ext)) return null;

    final extractedText = await _readTextFile(path, ext);
    if (extractedText == null || extractedText.trim().isEmpty) return null;

    return _SageFileDraft(
      name: file.name,
      path: path,
      extension: ext,
      extractedText: extractedText,
    );
  }

  static Future<_SageFileDraft?> fromXFile(
    XFile file, {
    ValueChanged<String>? onOversizedImage,
  }) async {
    final ext = _extensionForName(file.name);
    if (!_kSupportedSageImageExtensions.contains(ext)) return null;

    final bytes = await file.readAsBytes();
    if (bytes.isEmpty) return null;
    if (bytes.length > _kMaxSageImageBytes) {
      onOversizedImage?.call(file.name);
      return null;
    }
    final normalized = await _normalizeSageImageBytes(
      bytes: bytes,
      extension: ext,
    );
    if (normalized == null) {
      onOversizedImage?.call(file.name);
      return null;
    }
    final normalizedName = normalized.extension == ext || ext.isEmpty
        ? file.name
        : '${file.name.replaceFirst(RegExp(r'\.[^.]+$'), '')}.${normalized.extension}';

    return _SageFileDraft(
      name: normalizedName,
      path: file.path,
      extension: normalized.extension,
      imageBase64: base64Encode(normalized.bytes),
      imageMediaType: normalized.mediaType,
      imageByteSize: normalized.bytes.length,
    );
  }

  static Future<_SageFileDraft?> fromHandoffAttachment(
    SageHandoffAttachment attachment,
  ) async {
    final path = attachment.path.trim();
    if (path.isEmpty) return null;
    final file = File(path);
    if (!await file.exists()) return null;

    final rawName = attachment.name.trim().isNotEmpty
        ? attachment.name.trim()
        : path.split(Platform.pathSeparator).last;
    final ext = attachment.extension.trim().isNotEmpty
        ? attachment.extension.trim().toLowerCase()
        : _extensionForName(rawName);

    if (_kSupportedSageImageExtensions.contains(ext)) {
      final bytes = await file.readAsBytes();
      if (bytes.isEmpty || bytes.length > _kMaxSageImageBytes) return null;
      final normalized = await _normalizeSageImageBytes(
        bytes: bytes,
        extension: ext,
      );
      if (normalized == null) return null;
      final normalizedName = normalized.extension == ext || ext.isEmpty
          ? rawName
          : '${rawName.replaceFirst(RegExp(r'\.[^.]+$'), '')}.${normalized.extension}';
      return _SageFileDraft(
        name: normalizedName,
        path: path,
        extension: normalized.extension,
        imageBase64: base64Encode(normalized.bytes),
        imageMediaType: normalized.mediaType,
        imageByteSize: normalized.bytes.length,
      );
    }

    if (!_kSupportedSageFileExtensions.contains(ext)) return null;
    final extractedText = await _readTextFile(path, ext);
    if (extractedText == null || extractedText.trim().isEmpty) return null;
    return _SageFileDraft(
      name: rawName,
      path: path,
      extension: ext,
      extractedText: extractedText,
    );
  }

  final String name;
  final String path;
  final String extension;
  final String extractedText;
  final String? imageBase64;
  final String? imageMediaType;
  final int? imageByteSize;

  _SageMessageAttachment toMessageAttachment() {
    return _SageMessageAttachment(
      name: name,
      path: path,
      extension: extension,
      extractedText: extractedText,
      imageBase64: imageBase64,
      imageMediaType: imageMediaType,
      imageByteSize: imageByteSize,
    );
  }
}

class _SageMessageAttachment {
  const _SageMessageAttachment({
    required this.name,
    required this.path,
    required this.extension,
    required this.extractedText,
    this.imageBase64,
    this.imageMediaType,
    this.imageByteSize,
  });

  factory _SageMessageAttachment.fromSavedPayload(Map<String, dynamic> json) {
    final name = json['name']?.toString().trim();
    final path = json['path']?.toString().trim();
    return _SageMessageAttachment(
      name: (name != null && name.isNotEmpty) ? name : 'file',
      path: path ?? '',
      extension: json['extension']?.toString() ?? '',
      extractedText: json['extracted_text']?.toString() ?? '',
      imageMediaType: json['media_type']?.toString(),
      imageByteSize: (json['byte_size'] as num?)?.toInt(),
    );
  }

  final String name;
  final String path;
  final String extension;
  final String extractedText;
  final String? imageBase64;
  final String? imageMediaType;
  final int? imageByteSize;

  bool get isImage => _kSupportedSageImageExtensions.contains(
        extension.toLowerCase(),
      );

  String get fileKindLabel => isImage
      ? 'IMAGE'
      : extension.isNotEmpty
          ? extension.toUpperCase()
          : 'FILE';

  String get displayExtension =>
      extension.isNotEmpty ? extension.toUpperCase() : fileKindLabel;

  String toPromptBlock() {
    if (isImage) {
      if (imageBase64 == null || imageBase64!.trim().isEmpty) {
        return 'Image: $name\nType: ${imageMediaType ?? _imageMediaTypeForExtension(extension)}\nContent: image metadata from saved chat; visual bytes are not available in this resumed session.';
      }
      return 'Image: $name\nType: ${imageMediaType ?? _imageMediaTypeForExtension(extension)}\nContent: attached as a vision image block.';
    }
    final trimmed = extractedText.trim();
    if (trimmed.isEmpty) return '';
    return 'File: $name\nType: $fileKindLabel\nContent:\n$trimmed';
  }

  Map<String, dynamic> toApiAttachmentPayload() {
    if (isImage) {
      final base64 = imageBase64?.trim();
      if (base64 == null || base64.isEmpty) return const <String, dynamic>{};
      final mediaType =
          imageMediaType ?? _imageMediaTypeForExtension(extension);
      return <String, dynamic>{
        'kind': 'image',
        'name': name,
        'filename': name,
        'media_type': mediaType,
        'data_base64': base64,
        if (imageByteSize != null) 'byte_size': imageByteSize,
      };
    }

    final trimmed = extractedText.trim();
    if (trimmed.isEmpty) return const <String, dynamic>{};
    return <String, dynamic>{
      'kind': 'file',
      'name': name,
      'extension': extension,
      'extracted_text': trimmed,
    };
  }

  Map<String, dynamic> toSavedPayload() => {
        'name': name,
        'path': path,
        'extension': extension,
        if (!isImage) 'extracted_text': extractedText,
        if (isImage) 'media_type': imageMediaType,
        if (isImage && imageByteSize != null) 'byte_size': imageByteSize,
      };
}

class _SageBackdrop extends StatelessWidget {
  const _SageBackdrop();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            JournalColors.bgBase,
            JournalColors.bgSurface,
            JournalColors.bgBase,
          ],
        ),
      ),
      child: Stack(
        children: [
          Positioned(
            top: -80,
            left: -20,
            child: _GlowOrb(
              size: 240,
              color: _withAlpha(JournalColors.accent, 0.22),
            ),
          ),
          Positioned(
            top: 100,
            right: -70,
            child: _GlowOrb(
              size: 220,
              color: _withAlpha(JournalColors.accent2, 0.14),
            ),
          ),
          Positioned(
            bottom: 80,
            left: 40,
            child: _GlowOrb(
              size: 180,
              color: _withAlpha(JournalColors.info, 0.08),
            ),
          ),
        ],
      ),
    );
  }
}

class _GlowOrb extends StatelessWidget {
  const _GlowOrb({
    required this.size,
    required this.color,
  });

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: color,
              blurRadius: size * 0.42,
              spreadRadius: size * 0.08,
            ),
          ],
        ),
      ),
    );
  }
}

class _SageHeader extends StatelessWidget {
  const _SageHeader({
    required this.hasConversation,
    required this.busy,
    required this.onClear,
    required this.onOpenSavedChats,
    required this.onOpenSettings,
  });

  final bool hasConversation;
  final bool busy;
  final VoidCallback onClear;
  final VoidCallback onOpenSavedChats;
  final VoidCallback onOpenSettings;

  @override
  Widget build(BuildContext context) {
    final topPadding = MediaQuery.of(context).padding.top;

    return Container(
      padding: EdgeInsets.fromLTRB(20, topPadding + 10, 20, 14),
      decoration: BoxDecoration(
        color: JournalColors.bgBase.withValues(alpha: 0.84),
        border: const Border(
          bottom: BorderSide(color: JournalColors.border, width: 0.5),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Sage',
                  style: TextStyle(
                    color: JournalColors.textPrimary,
                    fontSize: 28,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.5,
                  ),
                ),
                SizedBox(height: 4),
                Text(
                  'your personal assistant',
                  style: TextStyle(
                    color: JournalColors.textSecondary,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _HeaderButton(
                icon: CupertinoIcons.bookmark,
                onTap: onOpenSavedChats,
              ),
              const SizedBox(width: 10),
              _HeaderButton(
                icon: CupertinoIcons.slider_horizontal_3,
                onTap: onOpenSettings,
              ),
              const SizedBox(width: 10),
              _HeaderButton(
                icon: CupertinoIcons.refresh,
                onTap: hasConversation && !busy ? onClear : null,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _HeaderButton extends StatelessWidget {
  const _HeaderButton({
    required this.icon,
    this.onTap,
  });

  final IconData icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return CupertinoButton(
      padding: EdgeInsets.zero,
      minimumSize: const Size(36, 36),
      onPressed: onTap,
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: JournalColors.bgCard
              .withValues(alpha: onTap != null ? 0.82 : 0.36),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: JournalColors.border),
        ),
        child: Icon(
          icon,
          color: onTap != null ? JournalColors.accent : JournalColors.textMuted,
          size: 18,
        ),
      ),
    );
  }
}

class _SageThread extends StatelessWidget {
  const _SageThread({
    required this.scrollController,
    required this.bottomClearance,
    required this.contextLoading,
    required this.contextError,
    required this.replyLoading,
    required this.replyError,
    required this.messages,
    required this.onRetryContext,
    required this.onActionTap,
    required this.resolveActions,
    required this.onToggleSpeak,
    required this.speakingMessageId,
    required this.ttsLoadingMessageId,
    required this.ttsErrorMessageId,
    required this.ttsErrorText,
    required this.settings,
    required this.sessionToneOverride,
    required this.profileLoading,
    required this.memoryCount,
    required this.activeTrack,
    required this.useTrackForSession,
    required this.onChooseTrack,
    required this.onMuteTrackForSession,
    required this.onNewChat,
  });

  final ScrollController scrollController;
  final double bottomClearance;
  final bool contextLoading;
  final String? contextError;
  final bool replyLoading;
  final String? replyError;
  final List<_SageMessage> messages;
  final Future<void> Function({bool forceRefresh}) onRetryContext;
  final Future<void> Function(Map<String, dynamic>, _SageMessage) onActionTap;
  final List<Map<String, dynamic>> Function(List<Map<String, dynamic>>)
      resolveActions;
  final Future<void> Function(_SageMessage) onToggleSpeak;
  final String? speakingMessageId;
  final String? ttsLoadingMessageId;
  final String? ttsErrorMessageId;
  final String? ttsErrorText;
  final SageSettings settings;
  final String? sessionToneOverride;
  final bool profileLoading;
  final int memoryCount;
  final SageFocusTrack? activeTrack;
  final bool useTrackForSession;
  final Future<void> Function() onChooseTrack;
  final VoidCallback onMuteTrackForSession;
  final Future<void> Function() onNewChat;

  @override
  Widget build(BuildContext context) {
    final showIntroAtTop =
        messages.isEmpty && !replyLoading && replyError == null;

    return LayoutBuilder(
      builder: (context, constraints) {
        if (contextLoading) {
          return const Center(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                CupertinoActivityIndicator(color: JournalColors.accent),
                SizedBox(width: 10),
                Text(
                  'Loading your context…',
                  style: TextStyle(
                    color: JournalColors.textSecondary,
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          );
        }

        if (contextError != null) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: GlassCard(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      CupertinoIcons.wifi_slash,
                      color: JournalColors.textMuted,
                      size: 28,
                    ),
                    const SizedBox(height: 14),
                    Text(
                      contextError!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: JournalColors.textSecondary,
                        fontSize: 14,
                        height: 1.5,
                      ),
                    ),
                    const SizedBox(height: 14),
                    CupertinoButton(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 8,
                      ),
                      color: JournalColors.accent,
                      onPressed: () => onRetryContext(forceRefresh: true),
                      child: const Text(
                        'Retry',
                        style: TextStyle(
                          color: JournalColors.textPrimary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }

        return SingleChildScrollView(
          controller: scrollController,
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: EdgeInsets.fromLTRB(16, 12, 16, bottomClearance),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight - 30),
            child: Column(
              mainAxisAlignment: showIntroAtTop
                  ? MainAxisAlignment.start
                  : MainAxisAlignment.end,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _SageIntroCard(
                  settings: settings,
                  sessionToneOverride: sessionToneOverride,
                  profileLoading: profileLoading,
                  memoryCount: memoryCount,
                  activeTrack: activeTrack,
                  useTrackForSession: useTrackForSession,
                  onChooseTrack: onChooseTrack,
                  onMuteTrackForSession: onMuteTrackForSession,
                  onNewChat: onNewChat,
                ),
                const SizedBox(height: 16),
                ...messages.map(
                  (message) => Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: _MessageBubble(
                      message: message,
                      actions: resolveActions(message.actions),
                      onActionTap: (action, _) => onActionTap(action, message),
                      onToggleSpeak: onToggleSpeak,
                      speaking: speakingMessageId == message.id,
                      ttsLoading: ttsLoadingMessageId == message.id,
                      ttsError:
                          ttsErrorMessageId == message.id ? ttsErrorText : null,
                    ),
                  ),
                ),
                if (replyLoading)
                  const Padding(
                    padding: EdgeInsets.only(bottom: 10),
                    child: _ThinkingBubble(),
                  ),
                if (replyError != null)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Padding(
                      padding: const EdgeInsets.only(left: 10, top: 2),
                      child: Text(
                        replyError!,
                        style: const TextStyle(
                          color: JournalColors.danger,
                          fontSize: 12,
                          height: 1.4,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _SageIntroCard extends StatelessWidget {
  const _SageIntroCard({
    required this.settings,
    required this.sessionToneOverride,
    required this.profileLoading,
    required this.memoryCount,
    required this.activeTrack,
    required this.useTrackForSession,
    required this.onChooseTrack,
    required this.onMuteTrackForSession,
    required this.onNewChat,
  });

  final SageSettings settings;
  final String? sessionToneOverride;
  final bool profileLoading;
  final int memoryCount;
  final SageFocusTrack? activeTrack;
  final bool useTrackForSession;
  final Future<void> Function() onChooseTrack;
  final VoidCallback onMuteTrackForSession;
  final Future<void> Function() onNewChat;

  @override
  Widget build(BuildContext context) {
    final sessionSettings =
        _settingsForSageSessionTone(settings, sessionToneOverride);
    final toneLabel = sessionToneOverride == null
        ? null
        : _labelForSageSessionTone(sessionToneOverride!);

    return GlassCard(
      padding: const EdgeInsets.all(0),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              _withAlpha(JournalColors.bgCard, 0.98),
              _withAlpha(JournalColors.bgCardAlt, 0.94),
            ],
          ),
        ),
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(14),
                    gradient: LinearGradient(
                      colors: [
                        _withAlpha(JournalColors.accent, 0.26),
                        _withAlpha(JournalColors.accent2, 0.16),
                      ],
                    ),
                    border: Border.all(color: JournalColors.borderBright),
                  ),
                  child: const Icon(
                    CupertinoIcons.sparkles,
                    color: JournalColors.textPrimary,
                    size: 19,
                  ),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text(
                    'Loaded for this session',
                    style: TextStyle(
                      color: JournalColors.textPrimary,
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              toneLabel == null
                  ? 'Sage responds with your current journal context plus your saved Sage settings and private memory notes from this device.'
                  : 'This handoff is temporarily using the $toneLabel living-summary tone for this Sage session while keeping your saved Sage settings unchanged.',
              style: const TextStyle(
                color: JournalColors.textSecondary,
                fontSize: 13,
                height: 1.45,
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _MetaPill(
                  label: profileLoading
                      ? 'Loading profile…'
                      : 'Voice ${sessionSettings.voiceId}',
                ),
                if (!profileLoading)
                  _MetaPill(
                    label: sessionSettings.toneMode == 'unhinged'
                        ? 'Tone unhinged'
                        : 'Tone standard',
                  ),
                _MetaPill(
                  label: profileLoading
                      ? '…'
                      : '$memoryCount saved ${memoryCount == 1 ? 'memory' : 'memories'}',
                ),
                _MetaPill(
                  label:
                      '${sessionSettings.warmth} / ${sessionSettings.directness}',
                ),
                if (toneLabel != null) _MetaPill(label: '$toneLabel handoff'),
              ],
            ),
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: _withAlpha(JournalColors.bgSurface, 0.9),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: useTrackForSession && activeTrack != null
                      ? JournalColors.borderBright
                      : JournalColors.border,
                ),
              ),
              child: activeTrack == null
                  ? Row(
                      children: [
                        const Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'No focus track attached',
                                style: TextStyle(
                                  color: JournalColors.textPrimary,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              SizedBox(height: 4),
                              Text(
                                'Pick one if you want Sage to keep an ongoing coaching thread across sessions.',
                                style: TextStyle(
                                  color: JournalColors.textSecondary,
                                  fontSize: 12,
                                  height: 1.4,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 10),
                        CupertinoButton(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                          color: JournalColors.accent,
                          onPressed: onChooseTrack,
                          child: const Text(
                            'Choose',
                            style: TextStyle(
                              color: JournalColors.textPrimary,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                useTrackForSession
                                    ? 'Active focus track'
                                    : 'Track muted for this chat',
                                style: const TextStyle(
                                  color: JournalColors.textPrimary,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                            Text(
                              activeTrack!.title,
                              style: TextStyle(
                                color: useTrackForSession
                                    ? JournalColors.info
                                    : JournalColors.textMuted,
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                        if (activeTrack!.currentGoal.trim().isNotEmpty) ...[
                          const SizedBox(height: 6),
                          Text(
                            activeTrack!.currentGoal,
                            style: const TextStyle(
                              color: JournalColors.textSecondary,
                              fontSize: 12,
                              height: 1.4,
                            ),
                          ),
                        ],
                        if (activeTrack!.nextCommitment.trim().isNotEmpty) ...[
                          const SizedBox(height: 6),
                          Text(
                            'Next: ${activeTrack!.nextCommitment}',
                            style: const TextStyle(
                              color: JournalColors.textPrimary,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              height: 1.4,
                            ),
                          ),
                        ],
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            _MiniActionChip(
                              label: 'Switch Track',
                              onTap: onChooseTrack,
                            ),
                            if (useTrackForSession)
                              _MiniActionChip(
                                label: 'Mute For Chat',
                                onTap: onMuteTrackForSession,
                              ),
                          ],
                        ),
                      ],
                    ),
            ),
            const SizedBox(height: 14),
            GestureDetector(
              onTap: onNewChat,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      _withAlpha(JournalColors.accent, 0.16),
                      _withAlpha(JournalColors.accent2, 0.1),
                    ],
                  ),
                  border: Border.all(color: JournalColors.borderBright),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        color: _withAlpha(JournalColors.bgSurface, 0.9),
                        border: Border.all(color: JournalColors.borderBright),
                      ),
                      child: const Icon(
                        CupertinoIcons.plus_bubble,
                        color: JournalColors.textPrimary,
                        size: 18,
                      ),
                    ),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'New Chat',
                            style: TextStyle(
                              color: JournalColors.textPrimary,
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          SizedBox(height: 3),
                          Text(
                            'Start fresh without touching your saved chats.',
                            style: TextStyle(
                              color: JournalColors.textSecondary,
                              fontSize: 12,
                              height: 1.4,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Icon(
                      CupertinoIcons.arrow_up_right,
                      color: JournalColors.accent,
                      size: 17,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MiniActionChip extends StatelessWidget {
  const _MiniActionChip({
    required this.label,
    required this.onTap,
  });

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: _withAlpha(JournalColors.bgCardAlt, 0.92),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: JournalColors.border),
        ),
        child: Text(
          label,
          style: const TextStyle(
            color: JournalColors.textPrimary,
            fontSize: 11,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

class _MetaPill extends StatelessWidget {
  const _MetaPill({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: _withAlpha(JournalColors.bgSurface, 0.82),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: JournalColors.border),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: JournalColors.textSecondary,
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({
    required this.message,
    required this.actions,
    required this.onActionTap,
    required this.onToggleSpeak,
    required this.speaking,
    required this.ttsLoading,
    required this.ttsError,
  });

  final _SageMessage message;
  final List<Map<String, dynamic>> actions;
  final Future<void> Function(Map<String, dynamic>, _SageMessage) onActionTap;
  final Future<void> Function(_SageMessage) onToggleSpeak;
  final bool speaking;
  final bool ttsLoading;
  final String? ttsError;

  bool get _isUser => message.role == 'user';

  @override
  Widget build(BuildContext context) {
    final bubbleRadius = BorderRadius.only(
      topLeft: const Radius.circular(24),
      topRight: const Radius.circular(24),
      bottomLeft: Radius.circular(_isUser ? 24 : 8),
      bottomRight: Radius.circular(_isUser ? 8 : 24),
    );

    return Align(
      alignment: _isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * (_isUser ? 0.78 : 0.84),
        ),
        child: Column(
          crossAxisAlignment:
              _isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            Container(
              padding: EdgeInsets.fromLTRB(
                message.attachments.isNotEmpty ? 12 : 16,
                message.attachments.isNotEmpty ? 12 : 14,
                message.attachments.isNotEmpty ? 12 : 16,
                14,
              ),
              decoration: BoxDecoration(
                color: _isUser ? null : _withAlpha(JournalColors.bgCard, 0.9),
                gradient: _isUser
                    ? LinearGradient(
                        colors: [
                          _withAlpha(JournalColors.accent2, 0.92),
                          _withAlpha(JournalColors.accent, 0.88),
                        ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      )
                    : LinearGradient(
                        colors: [
                          _withAlpha(JournalColors.bgCardAlt, 0.96),
                          _withAlpha(JournalColors.bgSurface, 0.9),
                        ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                borderRadius: bubbleRadius,
                border: Border.all(
                  color: _isUser
                      ? _withAlpha(JournalColors.textPrimary, 0.12)
                      : _withAlpha(JournalColors.borderBright, 0.42),
                ),
                boxShadow: [
                  BoxShadow(
                    color: _isUser
                        ? JournalColors.accentGlow
                        : _withAlpha(JournalColors.bgBase, 0.44),
                    blurRadius: _isUser ? 22 : 18,
                    offset: const Offset(0, 10),
                  ),
                  if (_isUser)
                    BoxShadow(
                      color: _withAlpha(JournalColors.accent2, 0.16),
                      blurRadius: 28,
                      offset: const Offset(0, 2),
                    ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (message.attachments.isNotEmpty) ...[
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: message.attachments
                          .map((attachment) => _SageMessageAttachmentTile(
                              attachment: attachment))
                          .toList(),
                    ),
                    if (message.text.trim().isNotEmpty)
                      const SizedBox(height: 10),
                  ],
                  if (message.text.trim().isNotEmpty)
                    _isUser
                        ? SelectionArea(
                            child: Text(
                              message.text,
                              style: const TextStyle(
                                color: JournalColors.textPrimary,
                                fontSize: 16,
                                height: 1.42,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          )
                        : SelectionArea(
                            child: MarkdownBody(
                              data: message.text,
                              shrinkWrap: true,
                              selectable: false,
                              styleSheet: MarkdownStyleSheet(
                                p: const TextStyle(
                                  color: JournalColors.textPrimary,
                                  fontSize: 15,
                                  height: 1.5,
                                ),
                                strong: const TextStyle(
                                  color: JournalColors.textPrimary,
                                  fontSize: 15,
                                  fontWeight: FontWeight.w700,
                                ),
                                listBullet: const TextStyle(
                                  color: JournalColors.textSecondary,
                                  fontSize: 15,
                                ),
                                blockSpacing: 8,
                              ),
                            ),
                          ),
                ],
              ),
            ),
            if (!_isUser) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  GestureDetector(
                    onTap: () => onToggleSpeak(message),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: (speaking || ttsLoading)
                            ? _withAlpha(JournalColors.accent, 0.18)
                            : _withAlpha(JournalColors.bgSurface, 0.9),
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(
                          color: (speaking || ttsLoading)
                              ? JournalColors.borderBright
                              : JournalColors.border,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (ttsLoading)
                            const CupertinoActivityIndicator(
                              color: JournalColors.accent,
                            )
                          else
                            Icon(
                              speaking
                                  ? CupertinoIcons.stop_fill
                                  : CupertinoIcons.speaker_2_fill,
                              color: JournalColors.accent,
                              size: 14,
                            ),
                          const SizedBox(width: 6),
                          Text(
                            ttsLoading
                                ? 'Generating…'
                                : speaking
                                    ? 'Stop'
                                    : 'Listen',
                            style: const TextStyle(
                              color: JournalColors.accent,
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  ...actions.map((action) {
                    final label = action['label']
                                ?.toString()
                                .trim()
                                .isNotEmpty ==
                            true
                        ? action['label'].toString().trim()
                        : action['title']?.toString().trim().isNotEmpty == true
                            ? action['title'].toString().trim()
                            : action['name']?.toString().trim().isNotEmpty ==
                                    true
                                ? action['name'].toString().trim()
                                : 'Open';

                    return GestureDetector(
                      onTap: () => onActionTap(action, message),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: _withAlpha(JournalColors.bgSurface, 0.9),
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(color: JournalColors.borderBright),
                        ),
                        child: Text(
                          label,
                          style: const TextStyle(
                            color: JournalColors.accent,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    );
                  }),
                ],
              ),
              if (ttsError != null) ...[
                const SizedBox(height: 6),
                Padding(
                  padding: const EdgeInsets.only(left: 4),
                  child: Text(
                    ttsError!,
                    style: const TextStyle(
                      color: JournalColors.danger,
                      fontSize: 11,
                      height: 1.35,
                    ),
                  ),
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }
}

class _SageMessageAttachmentTile extends StatelessWidget {
  const _SageMessageAttachmentTile({required this.attachment});

  final _SageMessageAttachment attachment;

  @override
  Widget build(BuildContext context) {
    final isImage = attachment.isImage;
    final tile = Container(
      width: isImage ? 136 : 98,
      height: isImage ? 112 : 98,
      decoration: BoxDecoration(
        color: _withAlpha(JournalColors.bgSurface, 0.92),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: JournalColors.borderBright),
        boxShadow: isImage
            ? [
                BoxShadow(
                  color: _withAlpha(JournalColors.bgBase, 0.36),
                  blurRadius: 14,
                  offset: const Offset(0, 8),
                ),
              ]
            : null,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(15),
        child: isImage
            ? Stack(
                fit: StackFit.expand,
                children: [
                  if (attachment.path.isNotEmpty)
                    Image.file(
                      File(attachment.path),
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => _AttachmentIcon(
                        isImage: isImage,
                        size: 112,
                        iconSize: 28,
                      ),
                    )
                  else
                    _AttachmentIcon(
                      isImage: isImage,
                      size: 112,
                      iconSize: 28,
                    ),
                  Positioned.fill(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            _withAlpha(JournalColors.bgBase, 0),
                            _withAlpha(JournalColors.bgBase, 0.72),
                          ],
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    left: 8,
                    bottom: 8,
                    child: _AttachmentBadge(label: attachment.displayExtension),
                  ),
                  if (attachment.path.isNotEmpty)
                    Positioned(
                      top: 8,
                      right: 8,
                      child: Container(
                        width: 28,
                        height: 28,
                        decoration: BoxDecoration(
                          color: _withAlpha(JournalColors.bgBase, 0.72),
                          shape: BoxShape.circle,
                          border: Border.all(color: JournalColors.borderBright),
                        ),
                        child: const Icon(
                          CupertinoIcons.arrow_up_left_arrow_down_right,
                          color: JournalColors.textPrimary,
                          size: 13,
                        ),
                      ),
                    ),
                ],
              )
            : Padding(
                padding: const EdgeInsets.all(9),
                child: Column(
                  children: [
                    _AttachmentIcon(isImage: isImage),
                    const SizedBox(height: 6),
                    Text(
                      attachment.displayExtension,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: JournalColors.accent,
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Expanded(
                      child: Center(
                        child: Text(
                          attachment.name,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: JournalColors.textSecondary,
                            fontSize: 10,
                            height: 1.3,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
      ),
    );

    if (!isImage || attachment.path.isEmpty) return tile;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => _showSageImageLightbox(context, attachment),
      child: tile,
    );
  }
}

class _AttachmentBadge extends StatelessWidget {
  const _AttachmentBadge({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: _withAlpha(JournalColors.bgBase, 0.76),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: JournalColors.borderBright),
      ),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          color: JournalColors.textPrimary,
          fontSize: 10,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

Future<void> _showSageImageLightbox(
  BuildContext context,
  _SageMessageAttachment attachment,
) {
  return showCupertinoModalPopup<void>(
    context: context,
    barrierColor: _withAlpha(JournalColors.bgBase, 0.9),
    builder: (context) {
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => Navigator.pop(context),
        child: Container(
          width: double.infinity,
          height: double.infinity,
          color: _withAlpha(JournalColors.bgBase, 0.96),
          child: SafeArea(
            child: Stack(
              children: [
                Positioned.fill(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 58, 16, 22),
                    child: GestureDetector(
                      onTap: () {},
                      child: InteractiveViewer(
                        minScale: 1,
                        maxScale: 4,
                        child: Image.file(
                          File(attachment.path),
                          fit: BoxFit.contain,
                          errorBuilder: (_, __, ___) => const Center(
                            child: Icon(
                              CupertinoIcons.photo,
                              color: JournalColors.textMuted,
                              size: 34,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                Positioned(
                  left: 16,
                  top: 10,
                  right: 64,
                  child: Text(
                    attachment.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: JournalColors.textPrimary,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      decoration: TextDecoration.none,
                    ),
                  ),
                ),
                Positioned(
                  top: 4,
                  right: 12,
                  child: CupertinoButton(
                    padding: EdgeInsets.zero,
                    minimumSize: const Size(40, 40),
                    onPressed: () => Navigator.pop(context),
                    child: Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        color: _withAlpha(JournalColors.bgSurface, 0.82),
                        shape: BoxShape.circle,
                        border: Border.all(color: JournalColors.borderBright),
                      ),
                      child: const Icon(
                        CupertinoIcons.xmark,
                        color: JournalColors.textPrimary,
                        size: 18,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
}

class _AttachmentIcon extends StatelessWidget {
  const _AttachmentIcon({
    required this.isImage,
    this.size = 34,
    this.iconSize = 18,
  });

  final bool isImage;
  final double size;
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: _withAlpha(JournalColors.accent, 0.16),
        borderRadius: BorderRadius.circular(size >= 34 ? 12 : 10),
        border: Border.all(color: JournalColors.borderBright),
      ),
      child: Icon(
        isImage ? CupertinoIcons.photo : CupertinoIcons.doc_text,
        color: JournalColors.textPrimary,
        size: iconSize,
      ),
    );
  }
}

class _ThinkingBubble extends StatelessWidget {
  const _ThinkingBubble();

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: _withAlpha(JournalColors.bgCard, 0.92),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: JournalColors.border),
        ),
        child: const CupertinoActivityIndicator(color: JournalColors.accent),
      ),
    );
  }
}

class _SageInputBar extends StatelessWidget {
  const _SageInputBar({
    required this.controller,
    required this.focusNode,
    required this.canSend,
    required this.loading,
    required this.pickingAttachments,
    required this.attachments,
    required this.onPickAttachment,
    required this.onRemoveAttachment,
    required this.onSend,
    required this.onSuggestionTap,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final bool canSend;
  final bool loading;
  final bool pickingAttachments;
  final List<_SageMessageAttachment> attachments;
  final VoidCallback onPickAttachment;
  final ValueChanged<int> onRemoveAttachment;
  final VoidCallback onSend;
  final ValueChanged<String> onSuggestionTap;

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    final safeBottom = MediaQuery.of(context).padding.bottom;
    final keyboardOpen = bottomInset > 0;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
      padding: EdgeInsets.fromLTRB(
        16,
        12,
        16,
        (bottomInset > 0 ? 8 : safeBottom + 10),
      ),
      decoration: BoxDecoration(
        color: JournalColors.bgBase.withValues(alpha: 0.9),
        border: const Border(
          top: BorderSide(color: JournalColors.border, width: 0.5),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (attachments.isNotEmpty) ...[
            SizedBox(
              height: 120,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: attachments.length,
                separatorBuilder: (_, __) => const SizedBox(width: 10),
                itemBuilder: (_, index) {
                  final attachment = attachments[index];
                  final isImage = attachment.isImage;
                  return Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Container(
                        width: isImage ? 108 : 94,
                        height: 112,
                        decoration: BoxDecoration(
                          color: _withAlpha(JournalColors.bgCardAlt, 0.94),
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(color: JournalColors.borderBright),
                          boxShadow: isImage
                              ? [
                                  BoxShadow(
                                    color: _withAlpha(
                                      JournalColors.bgBase,
                                      0.28,
                                    ),
                                    blurRadius: 14,
                                    offset: const Offset(0, 8),
                                  ),
                                ]
                              : null,
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(17),
                          child: isImage
                              ? Stack(
                                  fit: StackFit.expand,
                                  children: [
                                    if (attachment.path.isNotEmpty)
                                      Image.file(
                                        File(attachment.path),
                                        fit: BoxFit.cover,
                                        errorBuilder: (_, __, ___) =>
                                            _AttachmentIcon(
                                          isImage: isImage,
                                          size: 108,
                                          iconSize: 28,
                                        ),
                                      )
                                    else
                                      _AttachmentIcon(
                                        isImage: isImage,
                                        size: 108,
                                        iconSize: 28,
                                      ),
                                    Positioned.fill(
                                      child: DecoratedBox(
                                        decoration: BoxDecoration(
                                          gradient: LinearGradient(
                                            colors: [
                                              _withAlpha(
                                                JournalColors.bgBase,
                                                0,
                                              ),
                                              _withAlpha(
                                                JournalColors.bgBase,
                                                0.74,
                                              ),
                                            ],
                                            begin: Alignment.topCenter,
                                            end: Alignment.bottomCenter,
                                          ),
                                        ),
                                      ),
                                    ),
                                    Positioned(
                                      left: 8,
                                      bottom: 8,
                                      child: _AttachmentBadge(
                                        label: attachment.displayExtension,
                                      ),
                                    ),
                                    Positioned(
                                      top: 8,
                                      right: 8,
                                      child: Container(
                                        width: 26,
                                        height: 26,
                                        decoration: BoxDecoration(
                                          color: _withAlpha(
                                            JournalColors.bgBase,
                                            0.72,
                                          ),
                                          shape: BoxShape.circle,
                                          border: Border.all(
                                            color: JournalColors.borderBright,
                                          ),
                                        ),
                                        child: const Icon(
                                          CupertinoIcons
                                              .arrow_up_left_arrow_down_right,
                                          color: JournalColors.textPrimary,
                                          size: 12,
                                        ),
                                      ),
                                    ),
                                  ],
                                )
                              : Padding(
                                  padding: const EdgeInsets.all(9),
                                  child: Column(
                                    children: [
                                      _AttachmentIcon(
                                        isImage: isImage,
                                        size: 40,
                                        iconSize: 16,
                                      ),
                                      const SizedBox(height: 6),
                                      Text(
                                        attachment.displayExtension,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          color: JournalColors.accent,
                                          fontSize: 9,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                      const SizedBox(height: 3),
                                      Expanded(
                                        child: Center(
                                          child: Text(
                                            attachment.name,
                                            maxLines: 2,
                                            overflow: TextOverflow.ellipsis,
                                            textAlign: TextAlign.center,
                                            style: const TextStyle(
                                              color:
                                                  JournalColors.textSecondary,
                                              fontSize: 10,
                                              height: 1.25,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                        ),
                      ),
                      Positioned(
                        top: -4,
                        right: -4,
                        child: GestureDetector(
                          onTap: () => onRemoveAttachment(index),
                          child: Container(
                            width: 22,
                            height: 22,
                            decoration: BoxDecoration(
                              color: _withAlpha(JournalColors.bgBase, 0.92),
                              shape: BoxShape.circle,
                              border:
                                  Border.all(color: JournalColors.borderBright),
                            ),
                            child: const Icon(
                              CupertinoIcons.xmark,
                              size: 12,
                              color: JournalColors.textPrimary,
                            ),
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
            const SizedBox(height: 10),
          ],
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: focusNode.requestFocus,
            child: Container(
              constraints: const BoxConstraints(minHeight: 72),
              decoration: BoxDecoration(
                color: _withAlpha(JournalColors.bgCardAlt, 0.94),
                borderRadius: BorderRadius.circular(22),
                border: Border.all(
                  color: focusNode.hasFocus
                      ? JournalColors.borderBright
                      : JournalColors.border,
                ),
              ),
              padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    child: CupertinoTextField(
                      controller: controller,
                      focusNode: focusNode,
                      placeholder: 'Ask Sage anything…',
                      placeholderStyle: const TextStyle(
                        color: JournalColors.textMuted,
                        fontSize: 15,
                      ),
                      style: const TextStyle(
                        color: JournalColors.textPrimary,
                        fontSize: 15,
                        height: 1.35,
                      ),
                      minLines: 1,
                      maxLines: 5,
                      textInputAction: TextInputAction.newline,
                      textAlignVertical: TextAlignVertical.top,
                      padding: const EdgeInsets.only(top: 5, bottom: 7),
                      cursorColor: JournalColors.accent,
                      decoration: const BoxDecoration(),
                    ),
                  ),
                  const SizedBox(width: 10),
                  GestureDetector(
                    onTap: loading ? null : onPickAttachment,
                    child: Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        color: attachments.isNotEmpty
                            ? _withAlpha(JournalColors.accent, 0.18)
                            : _withAlpha(JournalColors.bgSurface, 0.92),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: attachments.isNotEmpty
                              ? JournalColors.borderBright
                              : JournalColors.border,
                        ),
                      ),
                      child: pickingAttachments
                          ? const CupertinoActivityIndicator(
                              color: JournalColors.accent,
                            )
                          : Stack(
                              alignment: Alignment.center,
                              children: [
                                Icon(
                                  CupertinoIcons.paperclip,
                                  color: attachments.isNotEmpty
                                      ? JournalColors.accent
                                      : JournalColors.textSecondary,
                                  size: 17,
                                ),
                                if (attachments.isNotEmpty)
                                  Positioned(
                                    top: 5,
                                    right: 4,
                                    child: Container(
                                      constraints:
                                          const BoxConstraints(minWidth: 15),
                                      height: 15,
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 4,
                                      ),
                                      decoration: BoxDecoration(
                                        color: JournalColors.accent,
                                        borderRadius:
                                            BorderRadius.circular(999),
                                      ),
                                      child: Center(
                                        child: Text(
                                          '${attachments.length}',
                                          style: const TextStyle(
                                            color: JournalColors.textPrimary,
                                            fontSize: 9,
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  GestureDetector(
                    onTap: canSend ? onSend : null,
                    child: Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        color: canSend
                            ? JournalColors.accent
                            : JournalColors.bgSurface,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: canSend
                              ? JournalColors.borderBright
                              : JournalColors.border,
                        ),
                      ),
                      child: loading
                          ? const CupertinoActivityIndicator(
                              color: JournalColors.textPrimary,
                            )
                          : Icon(
                              CupertinoIcons.arrow_up,
                              color: canSend
                                  ? JournalColors.textPrimary
                                  : JournalColors.textMuted,
                              size: 18,
                            ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (!keyboardOpen) ...[
            const SizedBox(height: 8),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 4),
              child: Text(
                'Attach images, documents, or text files and Sage will inspect what it can see or extract inside the chat.',
                style: TextStyle(
                  color: JournalColors.textMuted,
                  fontSize: 11,
                  height: 1.35,
                ),
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              height: 30,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemBuilder: (_, index) => GestureDetector(
                  onTap: () =>
                      onSuggestionTap(_kSageKnowledgeChips[index].prompt),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 7,
                    ),
                    decoration: BoxDecoration(
                      color: _withAlpha(JournalColors.bgSurface, 0.82),
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(color: JournalColors.border),
                    ),
                    child: Text(
                      _kSageKnowledgeChips[index].label,
                      style: const TextStyle(
                        color: JournalColors.textSecondary,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemCount: _kSageKnowledgeChips.length,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
