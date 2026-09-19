import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// SUB-100..103/110: the legacy checklist-shaped subtask system stays dead.
/// Business sources may not reference the old model, its CRUD or the embed;
/// only the migration compatibility layer and the legacy document projection
/// (which skips old markers) keep reading v1/v2 data.
void main() {
  test('runtime sources stay on the hierarchy model', () {
    final forbidden = <String, Pattern>{
      'TaskSubtask': 'TaskSubtask',
      'task.subtasks getter': 'task.subtasks',
      'subtaskTotal': 'subtaskTotal',
      'subtaskCompleted': 'subtaskCompleted',
      'addSubtask': 'addSubtask(',
      'toggleSubtask': 'toggleSubtask(',
      'renameSubtask': 'renameSubtask(',
      'removeSubtask': 'removeSubtask(',
      'insertSubtaskBlock': 'insertSubtaskBlock(',
      'taskSubtasks embed': "taskSubtasks'",
    };
    const whitelisted = {
      'lib/models/migration.dart',
      'lib/models/rich_document.dart',
      'lib/models/task.dart',
    };
    final offenders = <String>[];
    for (final entity in Directory('lib').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final normalized = entity.path.replaceAll('\\', '/');
      if (whitelisted.contains(normalized)) continue;
      final source = entity.readAsStringSync();
      for (final entry in forbidden.entries) {
        if (source.contains(entry.value)) {
          offenders.add('${entity.path}: ${entry.key}');
        }
      }
    }
    expect(offenders, isEmpty,
        reason: 'subtasks live in parentTaskId/childOrder now; the checklist '
            'model and its CRUD/embed paths must not come back');
  });

}
