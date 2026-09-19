// The document footer's right-hand corner, in both editors.
//
// A saved document used to say so twice over — a check icon and "已保存" in the
// corner, and "自动保存" before the first write landed — with "保存中…" while a
// write was in flight. A document that saves itself has nothing to report, and
// that corner is where the document's own actions live. What must survive is
// the one state a reader cannot infer: a save that failed, which they may have
// to retry and which is silent if nothing is drawn.
import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:workfollow_personal/features/editor/presentation/document_save_status.dart';
import 'package:workfollow_personal/models/migration.dart';
import 'package:workfollow_personal/services/local_workspace_store.dart';
import 'package:workfollow_personal/state/workspace_controller.dart';
import 'package:workfollow_personal/theme/workfollow_theme.dart';
import 'package:workfollow_personal/widgets/task_inspector.dart';

/// Accepts every write, without touching the disk.
///
/// The store-less controller writes to the real workspace file, and a real
/// write cannot complete inside the fake clock a widget test runs on —
/// `waitForPendingSaves()` would wait forever. A store that finishes in a
/// microtask keeps the controller's own state machine under test.
class _MemoryStore extends LocalWorkspaceStore {
  MigrationBundle? saved;

  @override
  Future<void> save(MigrationBundle bundle) async {
    saved = bundle;
  }
}

/// Holds every write open, so the controller sits in [SaveStatus.saving].
class _StalledStore extends LocalWorkspaceStore {
  final pending = <Completer<void>>[];

  @override
  Future<void> save(MigrationBundle bundle) {
    final write = Completer<void>();
    pending.add(write);
    return write.future;
  }

  void release() {
    for (final write in pending) {
      if (!write.isCompleted) write.complete();
    }
  }
}

/// Refuses every write, so the controller sits in [SaveStatus.failed].
class _RefusingStore extends LocalWorkspaceStore {
  @override
  Future<void> save(MigrationBundle bundle) async {
    throw const FileSystemException('disk full', 'workspace.json');
  }
}

Future<void> _mountStatus(WidgetTester tester, WorkspaceController controller) async {
  await tester.pumpWidget(MaterialApp(
    theme: WorkFollowThemeData.light(),
    home: Scaffold(
        body: Center(child: DocumentSaveStatus(controller: controller))),
  ));
  await tester.pump();
}

void main() {
  testWidgets('a document that saves itself says nothing', (tester) async {
    final store = _MemoryStore();
    final controller = WorkspaceController(seedData: false, store: store);
    addTearDown(controller.dispose);
    controller.addTask('自己保存的任务');
    await controller.waitForPendingSaves();
    await _mountStatus(tester, controller);

    expect(controller.saveStatus, SaveStatus.saved,
        reason: 'the fixture has to reach the resting state this covers');
    expect(store.saved, isNotNull, reason: 'the write really landed');
    expect(find.byKey(const ValueKey('save-status-indicator')), findsNothing);
    for (final label in const ['已保存', '自动保存']) {
      expect(find.text(label), findsNothing,
          reason: 'the corner stays empty once the write has landed');
    }
  });

  testWidgets('a write in flight says nothing either', (tester) async {
    final store = _StalledStore();
    final controller = WorkspaceController(seedData: false, store: store);
    addTearDown(controller.dispose);
    addTearDown(store.release);
    controller.addTask('写入中的任务');
    await _mountStatus(tester, controller);

    expect(controller.saveStatus, SaveStatus.saving,
        reason: 'the fixture has to hold a write open to cover this state');
    expect(find.byKey(const ValueKey('save-status-indicator')), findsNothing);
    expect(find.text('保存中…'), findsNothing);

    store.release();
    await controller.waitForPendingSaves();
  });

  testWidgets('a save that failed still speaks', (tester) async {
    final controller =
        WorkspaceController(seedData: false, store: _RefusingStore());
    addTearDown(controller.dispose);
    controller.addTask('保存失败的任务');
    await controller.waitForPendingSaves();
    await _mountStatus(tester, controller);

    expect(controller.saveStatus, SaveStatus.failed);
    expect(find.byKey(const ValueKey('save-status-indicator')), findsOneWidget,
        reason: 'a failed save with nothing on screen is a silent one');
    expect(find.textContaining('保存失败'), findsOneWidget);
  });

  testWidgets(
      'the task editor footer is empty in its corner, and keeps its actions',
      (tester) async {
    final store = _MemoryStore();
    final controller = WorkspaceController(seedData: false, store: store);
    addTearDown(controller.dispose);
    controller.addTask('页脚的任务');
    await controller.waitForPendingSaves();
    await tester.pumpWidget(MaterialApp(
      theme: WorkFollowThemeData.light(),
      home: Scaffold(
          body: TaskInspector(
              task: controller.tasks.single, controller: controller)),
    ));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('task-inspector-footer')), findsOneWidget);
    expect(find.byKey(const ValueKey('save-status-indicator')), findsNothing);
    for (final label in const ['已保存', '自动保存', '保存中…']) {
      expect(find.text(label), findsNothing);
    }
    // Dropping the status must not have taken the document's own controls with
    // it: they are what the corner is for now.
    expect(find.byKey(const ValueKey('task-more-actions')), findsOneWidget);
  });

  test('no editor writes a saved hint of its own', () {
    // Both editors take their status from the one widget above, and that widget
    // is silent while a document saves itself. A second hint written beside it
    // would be a second answer to "did that stick?".
    final offenders = <String>[];
    for (final entity in Directory('lib').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final source = entity.readAsStringSync();
      if (source.contains("'已保存'") || source.contains("'自动保存'")) {
        offenders.add(entity.path);
      }
    }
    expect(offenders, isEmpty,
        reason: 'a saved document does not announce itself: the states that '
            'remain are the ones a reader cannot infer');
  });
}
