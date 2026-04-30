import 'dart:convert';
import 'dart:math' as math;

class AiResponseLimits {
  const AiResponseLimits._();

  static const int sageReplyMaxTokens = 1400;
  static const int sageUtilityMaxTokens = 500;

  static const int speechChunkMaxChars = 2800;
  static const int speechChunkMaxBytes = 3500;
  static const int speechFirstChunkMaxChars = 900;
  static const int speechFirstChunkMaxBytes = 1200;

  static const int livingSummarySpeechMaxChars = 5600;
  static const int livingSummarySpeechMaxBytes = 7200;
  static const int livingSummarySageHandoffMaxChars = 5600;
  static const int livingSummarySageHandoffMaxBytes = 7200;
}

List<String> buildSpeechChunks(String raw) {
  final withoutActions = raw.split('---ACTIONS---').first;
  final cleaned = withoutActions
      .replaceAll(RegExp(r'```[\s\S]*?```'), ' ')
      .replaceAll(RegExp(r'[*_`>#~-]+'), ' ')
      .replaceAll(RegExp(r'\[[^\]]+\]\([^)]+\)'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  if (cleaned.isEmpty) return const [];

  final chunks = <String>[];
  var remaining = cleaned;
  var firstChunk = true;

  while (remaining.isNotEmpty) {
    final maxChars = firstChunk
        ? AiResponseLimits.speechFirstChunkMaxChars
        : AiResponseLimits.speechChunkMaxChars;
    final maxBytes = firstChunk
        ? AiResponseLimits.speechFirstChunkMaxBytes
        : AiResponseLimits.speechChunkMaxBytes;

    if (remaining.length <= maxChars &&
        utf8.encode(remaining).length <= maxBytes) {
      chunks.add(remaining);
      break;
    }

    var hardLimit = 0;
    var bytes = 0;
    for (var i = 0; i < remaining.length; i++) {
      bytes += utf8.encode(remaining[i]).length;
      if (i >= maxChars || bytes >= maxBytes) {
        break;
      }
      hardLimit = i + 1;
    }

    if (hardLimit <= 0) {
      hardLimit = remaining.length.clamp(0, maxChars);
    }

    var splitAt = remaining.lastIndexOf(RegExp(r'[.!?]\s'), hardLimit);
    if (splitAt < hardLimit * 0.45) {
      splitAt = remaining.lastIndexOf(RegExp(r'[,;:]\s'), hardLimit);
    }
    if (splitAt < hardLimit * 0.45) {
      splitAt = remaining.lastIndexOf(' ', hardLimit);
    }
    if (splitAt < hardLimit * 0.45) splitAt = hardLimit;

    chunks.add(remaining.substring(0, splitAt).trim());
    remaining = remaining.substring(splitAt).trim();
    firstChunk = false;
  }

  return chunks.where((chunk) => chunk.isNotEmpty).toList();
}

String truncateUtf8Text(
  String text, {
  required int maxChars,
  required int maxBytes,
  required String truncatedSuffix,
}) {
  if (text.length <= maxChars && utf8.encode(text).length <= maxBytes) {
    return text;
  }

  final suffix = truncatedSuffix.trim();
  final suffixBytes = utf8.encode('\n\n$suffix').length;
  final safeByteBudget = math.max(0, maxBytes - suffixBytes);
  final safeCharBudget = math.max(0, maxChars - suffix.length);
  final buffer = StringBuffer();
  var bytes = 0;
  var chars = 0;

  for (final rune in text.runes) {
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
  return trimmed.isEmpty ? suffix : '$trimmed\n\n$suffix';
}
