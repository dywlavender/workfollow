import 'dart:convert';

import 'package:flutter_quill/flutter_quill.dart' as quill;

import 'note_document.dart';
import 'task.dart';

/// Shared document boundary for Notes and Tasks.
///
/// The Web editor stores a ProseMirror document and this app carries a Quill
/// Delta alongside it for local editing. Keeping the adapter here prevents
/// TaskInspector from knowing how either representation is encoded.
List<Map<String, dynamic>> taskDocumentDelta(TaskItem task) {
  final document = task.contentJson;
  final stored = document?['quillDelta'];
  if (stored is List) {
    return stored
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList();
  }
  final plain = task.description ?? task.note ?? '';
  final source = document == null || document.isEmpty
      ? noteContentJsonFromPlainText(plain)
      : document;
  try {
    return proseMirrorToDelta(source);
  } on Object {
    return proseMirrorToDelta(noteContentJsonFromPlainText(plain));
  }
}

Map<String, dynamic> richContentFromDelta(List<dynamic> delta) =>
    noteContentFromDelta(delta);

String richPlainTextFromDelta(List<dynamic> delta) {
  try {
    return quill.Document.fromJson(delta).toPlainText().trimRight();
  } on Object {
    return delta
        .whereType<Map>()
        .map((op) => op['insert'])
        .whereType<String>()
        .join()
        .trimRight();
  }
}

String encodeRichDocument(Map<String, dynamic> document) =>
    jsonEncode(document);
