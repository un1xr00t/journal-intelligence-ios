class DetectiveEntryDraft {
  const DetectiveEntryDraft({
    required this.content,
    this.entryType = 'observation',
    this.severity = 'medium',
    this.sourceLabel,
  });

  final String content;
  final String entryType;
  final String severity;
  final String? sourceLabel;
}
