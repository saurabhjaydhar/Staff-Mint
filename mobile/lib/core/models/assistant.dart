import '../utils/json.dart';

class AssistantOption {
  const AssistantOption({required this.id, required this.label});
  final String id;
  final String label;
  factory AssistantOption.fromJson(Json j) => AssistantOption(id: asString(j['id']), label: asString(j['label']));
}

class AssistantPreviewRow {
  const AssistantPreviewRow({required this.label, required this.value});
  final String label;
  final String value;
  factory AssistantPreviewRow.fromJson(Json j) =>
      AssistantPreviewRow(label: asString(j['label']), value: asString(j['value']));
}

class AssistantPreview {
  const AssistantPreview({required this.title, this.rows = const []});
  final String title;
  final List<AssistantPreviewRow> rows;
  factory AssistantPreview.fromJson(Json j) =>
      AssistantPreview(title: asString(j['title']), rows: asList(j['rows'], AssistantPreviewRow.fromJson));
}

class AssistantAttachment {
  const AssistantAttachment({required this.url, required this.filename});
  final String url;
  final String filename;
  factory AssistantAttachment.fromJson(Json j) =>
      AssistantAttachment(url: asString(j['url']), filename: asString(j['filename'], 'file'));
}

class AssistantReply {
  const AssistantReply({
    required this.sessionId,
    required this.kind,
    required this.text,
    this.options = const [],
    this.pendingActionId,
    this.preview,
    this.data,
    this.attachment,
    this.transcript,
  });

  final String? sessionId;
  final String kind; // answer | confirm | choose | done | cancelled | error
  final String text;
  final List<AssistantOption> options;
  final String? pendingActionId;
  final AssistantPreview? preview;
  final Object? data;
  final AssistantAttachment? attachment;

  /// What Mint heard in a voice note, when the server sends it.
  final String? transcript;

  factory AssistantReply.fromJson(Json j) => AssistantReply(
    sessionId: asStringOrNull(j['sessionId']),
    kind: asString(j['kind'], 'answer'),
    text: asString(j['text']),
    options: asList(j['options'], AssistantOption.fromJson),
    pendingActionId: asStringOrNull(j['pendingActionId']),
    preview: j['preview'] is Map ? AssistantPreview.fromJson(asMap(j['preview'])) : null,
    data: j['data'],
    attachment: j['attachment'] is Map ? AssistantAttachment.fromJson(asMap(j['attachment'])) : null,
    transcript: asStringOrNull(j['transcript']),
  );
}
