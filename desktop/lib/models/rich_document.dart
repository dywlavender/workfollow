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
/// Converts a task into a note document. [children] (already retired by the
/// caller) become checklist lines so 转为笔记 keeps the task's action items.
Map<String, dynamic> noteContentFromTask(TaskItem task,
    {List<TaskItem> children = const []}) {
  final delta = <Map<String, dynamic>>[];
  final attached = <String>{};

  for (final operation in taskDocumentDelta(task)) {
    final insert = operation['insert'];
    if (insert is Map && insert['workfollow-block'] is String) {
      final block = jsonDecode(insert['workfollow-block'] as String);
      if (block is Map && block['type'] == 'taskSubtasks') {
        // Legacy marker: children are real tasks now, the embed carries no
        // data and contributes nothing to the projection.
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
  for (final child in children) {
    delta.add({'insert': child.title.trim().isEmpty ? '无标题' : child.title});
    delta.add({
      'insert': '\n',
      'attributes': {'list': child.completed ? 'checked' : 'unchecked'}
    });
  }
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
