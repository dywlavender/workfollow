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

/// Convert task-only blocks into editable note content, keeping rich text and
/// attachment blocks in their original positions.
Map<String, dynamic> noteContentFromTask(TaskItem task) {
  final delta = <Map<String, dynamic>>[];
  var insertedSubtasks = false;
  final attached = <String>{};
  void insertSubtasks() {
    if (insertedSubtasks) return;
    insertedSubtasks = true;
    for (final subtask in task.subtasks) {
      delta.add({'insert': subtask.title});
      delta.add({
        'insert': '\n',
        'attributes': {'list': subtask.completed ? 'checked' : 'unchecked'}
      });
    }
  }

  for (final operation in taskDocumentDelta(task)) {
    final insert = operation['insert'];
    if (insert is Map && insert['workfollow-block'] is String) {
      final block = jsonDecode(insert['workfollow-block'] as String);
      if (block is Map && block['type'] == 'taskSubtasks') {
        insertSubtasks();
        continue;
      }
      if (block is Map && block['type'] == 'attachment') {
        final attrs = block['attrs'];
        if (attrs is Map && attrs['localFile'] is String)
          attached.add(attrs['localFile'] as String);
      }
    }
    delta.add(operation);
  }
  insertSubtasks();
  for (final filename in task.attachments) {
    if (!attached.add(filename)) continue;
    delta.add({
      'insert': {
        'workfollow-block': jsonEncode({
          'type': 'attachment',
          'attrs': {'name': filename, 'localFile': filename}
        })
      }
    });
    delta.add({'insert': '\n'});
  }
  if (task.tags.isNotEmpty)
    delta.add({'insert': '\n${task.tags.map((tag) => '#$tag').join(' ')}\n'});
  return richContentFromDelta(delta);
}
