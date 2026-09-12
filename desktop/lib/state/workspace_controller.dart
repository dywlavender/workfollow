import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/migration.dart';
import '../models/task.dart';
import '../services/local_workspace_store.dart';

enum WorkspaceView {
  home,
  today,
  inbox,
  plan,
  all,
  completed,
  calendar,
  notes,
  trash,
  work,
  study,
  personal,
}

/// Reflects the real persistence state, never a fixed label.
enum SaveStatus { saved, saving, failed }

List<MigrationListRecord> _defaultLists() => const [
      MigrationListRecord(
        id: null,
        name: '收集箱',
        sortOrder: 0,
        protectedList: true,
      ),
      MigrationListRecord(
        id: null,
        name: '工作',
        sortOrder: 1,
        protectedList: true,
      ),
      MigrationListRecord(
        id: null,
        name: '个人',
        sortOrder: 2,
        protectedList: true,
      ),
      MigrationListRecord(
        id: null,
        name: '学习',
        sortOrder: 3,
        protectedList: true,
      ),
    ];

List<MigrationFolderRecord> _defaultFolders() => const [
      MigrationFolderRecord(
        id: 'folder-work',
        parentId: null,
        name: '工作笔记',
        sortOrder: 0,
        createdAt: null,
        updatedAt: null,
      ),
      MigrationFolderRecord(
        id: 'folder-ideas',
        parentId: null,
        name: '灵感',
        sortOrder: 1,
        createdAt: null,
        updatedAt: null,
      ),
      MigrationFolderRecord(
        id: 'folder-study',
        parentId: null,
        name: '学习',
        sortOrder: 2,
        createdAt: null,
        updatedAt: null,
      ),
    ];

class MigrationImportSummary {
  const MigrationImportSummary({
    required this.importedTasks,
    required this.skippedTasks,
    required this.importedNotes,
    required this.skippedNotes,
    required this.importedLists,
    required this.importedFolders,
  });

  final int importedTasks;
  final int skippedTasks;
  final int importedNotes;
  final int skippedNotes;
  final int importedLists;
  final int importedFolders;
}

class WorkspaceController extends ChangeNotifier {
  WorkspaceController({LocalWorkspaceStore? store})
      : _store = store ?? LocalWorkspaceStore(),
        _tasks = _seedTasks(),
        _notes = _seedNotes(),
        _lists = _defaultLists(),
        _folders = _defaultFolders();

  /// Starter tasks shown before any local snapshot exists. They carry real
  /// dates so derived buckets stay consistent across a save/load round trip.
  static List<TaskItem> _seedTasks() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    DateTime at(int dayOffset, int hour, int minute) =>
        DateTime(today.year, today.month, today.day + dayOffset, hour, minute);
    return [
      TaskItem(
        id: 'task-01',
        title: '准备季度产品评审演示文稿',
        listName: '工作',
        bucket: TaskBucket.today,
        dueAt: at(0, 14, 0).toIso8601String(),
        timeLabel: '今天 14:00',
        note: '把核心指标、用户反馈和下季度优先级整理成一份清晰的演示。',
        priority: TaskPriority.high,
        subtasks: [
          const TaskSubtask(
              id: 'sub-seed-1', title: '整理核心指标数据', completed: true),
          const TaskSubtask(
              id: 'sub-seed-2', title: '完成增长章节图表', completed: true),
          const TaskSubtask(id: 'sub-seed-3', title: '排练一遍讲述节奏'),
        ],
      ),
      TaskItem(
        id: 'task-02',
        title: '整理用户反馈：移动端适配问题清单',
        listName: '工作',
        bucket: TaskBucket.today,
        dueAt: at(0, 18, 0).toIso8601String(),
        timeLabel: '今天 18:00',
        priority: TaskPriority.medium,
      ),
      TaskItem(
        id: 'task-03',
        title: '给设计顾问发一封确认邮件',
        listName: '收集箱',
        bucket: TaskBucket.today,
        dueAt: at(0, 0, 0).toIso8601String(),
        timeLabel: '今天',
        priority: TaskPriority.low,
      ),
      TaskItem(
        id: 'task-04',
        title: '核对报销单据并提交财务系统',
        listName: '工作',
        bucket: TaskBucket.overdue,
        dueAt: at(-1, 9, 0).toIso8601String(),
        timeLabel: '昨天 09:00',
        priority: TaskPriority.high,
      ),
      TaskItem(
        id: 'task-05',
        title: '阅读《设计心理学》第 4 章并做摘录',
        listName: '学习',
        bucket: TaskBucket.later,
        dueAt: at(2, 0, 0).toIso8601String(),
        timeLabel: '后天',
        note: '记录三个可以应用到任务列表的交互细节。',
      ),
      TaskItem(
        id: 'task-06',
        title: '为周末徒步准备一份轻量清单',
        listName: '个人',
        bucket: TaskBucket.later,
        dueAt: at(3, 0, 0).toIso8601String(),
        timeLabel: taskTimeLabelFor(at(3, 0, 0)),
        hasAttachment: true,
      ),
      TaskItem(
        id: 'task-07',
        title: '整理五月份的项目复盘资料',
        listName: '工作',
        bucket: TaskBucket.today,
        completed: true,
        dueAt: at(0, 9, 42).toIso8601String(),
        timeLabel: '已完成',
      ),
    ];
  }

  static List<NoteItem> _seedNotes() => [
        NoteItem(
          id: 'note-01',
          title: '季度评审 · 叙事结构',
          preview: '先讲变化，再解释原因，最后把决策留给下一步。',
          updatedLabel: '刚刚',
          folder: '工作笔记',
          folderId: 'folder-work',
          accent: ColorValue(0xFFC23377),
        ),
        NoteItem(
          id: 'note-02',
          title: '灵感收集 · 好的空状态',
          preview: '空白不是结束，它应该告诉用户下一步可以做什么。',
          updatedLabel: '昨天',
          folder: '灵感',
          folderId: 'folder-ideas',
          accent: ColorValue(0xFF4F46E5),
        ),
        NoteItem(
          id: 'note-03',
          title: '读书摘录 · 设计心理学',
          preview: '熟悉感来自稳定的反馈，而不是重复的装饰。',
          updatedLabel: '8 月 24 日',
          folder: '学习',
          folderId: 'folder-study',
          accent: ColorValue(0xFF0F766E),
        ),
      ];

  final LocalWorkspaceStore _store;
  List<TaskItem> _tasks;
  List<NoteItem> _notes;
  List<MigrationListRecord> _lists;
  List<MigrationFolderRecord> _folders;
  WorkspaceView _view = WorkspaceView.home;
  String? _selectedListName;
  String? _selectedTaskId = 'task-01';
  String? _selectedNoteId;
  String? _lastCompletedTaskId;
  String? _lastRemovedTaskId;
  String? _lastRemovedNoteId;
  String? _lastRecurrenceSpawnId;
  String? _lastCompletedRecurrenceType;
  Map<String, dynamic>? _lastCompletedRecurrenceConfig;
  Set<String> _multiSelectedTaskIds = {};
  String? _multiSelectAnchorId;
  _BulkTaskUndo? _lastBulkUndo;
  int _completionVersion = 0;
  int _actionVersion = 0;
  String _lastActionMessage = '';
  String _lastActionKind = '';
  int _taskSequence = 8;
  int _noteSequence = 4;
  int _folderSequence = 4;
  bool _restoredFromDisk = false;
  SaveStatus _saveStatus = SaveStatus.saved;
  String? _saveError;
  DateTime? _lastSavedAt;
  String? _loadError;
  bool _disposed = false;
  // Notes view filters live here so menus and shortcuts (Cmd-N "new note in
  // the current folder") agree with what the screen shows.
  String? _notesFolderFilter;
  bool _notesFavoritesOnly = false;
  bool _notesUnfiledOnly = false;
  // Cross-widget focus requests: a menu or keyboard command can ask the quick
  // add field or the inspector title editor to take focus.
  bool _quickAddFocusPending = false;
  int _inspectorTitleFocusVersion = 0;

  WorkspaceView get view => _view;
  bool get isTaskView => switch (_view) {
        WorkspaceView.today ||
        WorkspaceView.inbox ||
        WorkspaceView.plan ||
        WorkspaceView.all ||
        WorkspaceView.completed ||
        WorkspaceView.work ||
        WorkspaceView.study ||
        WorkspaceView.personal =>
          true,
        WorkspaceView.home ||
        WorkspaceView.calendar ||
        WorkspaceView.notes ||
        WorkspaceView.trash =>
          false,
      };
  String? get selectedTaskId => _selectedTaskId;
  String? get selectedNoteId => _selectedNoteId;
  int get completionVersion => _completionVersion;
  int get actionVersion => _actionVersion;
  String get lastActionMessage => _lastActionMessage;
  String? get selectedListName => _selectedListName;
  String get viewTitle =>
      _selectedListName ??
      switch (_view) {
        WorkspaceView.home => '首页',
        WorkspaceView.today => '今天',
        WorkspaceView.inbox => '收集箱',
        WorkspaceView.plan => '计划',
        WorkspaceView.all => '全部任务',
        WorkspaceView.completed => '已完成',
        WorkspaceView.work => '工作',
        WorkspaceView.study => '学习',
        WorkspaceView.personal => '个人',
        WorkspaceView.calendar => '日历',
        WorkspaceView.notes => '笔记',
        WorkspaceView.trash => '废纸篓',
      };
  List<TaskItem> get tasks => List.unmodifiable(_tasks);
  List<NoteItem> get notes => List.unmodifiable(_notes);

  /// Tasks and notes that are not in the trash.
  List<TaskItem> get activeTasks =>
      List.unmodifiable(_tasks.where((task) => task.deletedAt == null));
  List<NoteItem> get activeNotes =>
      List.unmodifiable(_notes.where((note) => note.deletedAt == null));
  List<TaskItem> get deletedTasks =>
      List.unmodifiable(_tasks.where((task) => task.deletedAt != null));
  List<NoteItem> get deletedNotes =>
      List.unmodifiable(_notes.where((note) => note.deletedAt != null));

  List<MigrationListRecord> get lists => List.unmodifiable(_lists);
  List<MigrationFolderRecord> get folders => List.unmodifiable(_folders);
  bool get restoredFromDisk => _restoredFromDisk;
  SaveStatus get saveStatus => _saveStatus;
  String? get saveError => _saveError;
  DateTime? get lastSavedAt => _lastSavedAt;
  String? get loadError => _loadError;
  String? get notesFolderFilter => _notesFolderFilter;
  bool get notesFavoritesOnly => _notesFavoritesOnly;
  bool get notesUnfiledOnly => _notesUnfiledOnly;
  bool get quickAddFocusPending => _quickAddFocusPending;
  int get inspectorTitleFocusVersion => _inspectorTitleFocusVersion;

  void setNotesFolderFilter(String? folderId) {
    if (_notesFolderFilter == folderId) return;
    _notesFolderFilter = folderId;
    _notesFavoritesOnly = false;
    _notesUnfiledOnly = false;
    _notify();
  }

  void setNotesFavoritesOnly(bool value) {
    _notesFavoritesOnly = value;
    if (value) _notesUnfiledOnly = false;
    _notesFolderFilter = null;
    _notify();
  }

  void setNotesUnfiledOnly(bool value) {
    _notesUnfiledOnly = value;
    if (value) _notesFavoritesOnly = false;
    _notesFolderFilter = null;
    _notify();
  }

  void clearNotesFilters() {
    _notesFolderFilter = null;
    _notesFavoritesOnly = false;
    _notesUnfiledOnly = false;
    _notify();
  }

  /// Asks whichever quick add field is on screen to take focus (Cmd-N on task
  /// views). The pending flag also covers fields that are built afterwards,
  /// e.g. after switching from Calendar to Today.
  void requestQuickAddFocus() {
    _quickAddFocusPending = true;
    _notify();
  }

  void consumeQuickAddFocus() {
    _quickAddFocusPending = false;
  }

  /// Asks the task inspector to focus its title editor (Return on a task row).
  void requestInspectorTitleFocus() {
    _inspectorTitleFocusVersion += 1;
    _notify();
  }

  /// Creates a note in the folder the notes view currently shows, so Cmd-N
  /// behaves like the button in the sidebar.
  String addNoteInCurrentFolder() {
    final folderId = _notesUnfiledOnly ? null : _notesFolderFilter;
    final id = addNote(folderId: folderId);
    _selectedNoteId = id;
    _view = WorkspaceView.notes;
    _notify();
    return id;
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  void _notify() {
    if (_disposed) return;
    notifyListeners();
  }

  Future<void> restoreFromDisk() async {
    final result = await _store.load();
    if (result.failed) {
      // The snapshot exists but cannot be parsed. Keep the file untouched and
      // pause auto-save instead of overwriting it with starter data.
      _loadError = '本地快照无法解析，自动保存已暂停；原文件已保留，可通过导入数据覆盖。';
      _saveError = result.error.toString();
      _saveStatus = SaveStatus.failed;
      _notify();
      return;
    }
    if (result.bundle == null) return;
    _applyBundle(result.bundle!);
    _restoredFromDisk = true;
    _saveStatus = SaveStatus.saved;
    _notify();
  }

  Future<MigrationImportSummary> importMigration(MigrationBundle bundle) async {
    // Importing is a deliberate replacement, so it also lifts the auto-save
    // pause that a damaged snapshot triggered.
    _loadError = null;
    _saveError = null;
    _folders = _mergeFolders(bundle.folders, _folders);
    _lists = _mergeLists(bundle.lists, _lists);
    final taskIds = _tasks.map((task) => task.id).toSet();
    final noteIds = _notes.map((note) => note.id).toSet();
    final importedTasks = <TaskItem>[];
    final importedNotes = <NoteItem>[];

    for (final record in bundle.tasks) {
      if (taskIds.add(record.id)) {
        importedTasks.add(TaskItem.fromMigration(record));
      }
    }
    for (final record in bundle.notes) {
      if (noteIds.add(record.id)) {
        importedNotes.add(NoteItem.fromMigration(
          record,
          _folderNameForImport(record.folderId, bundle.folders),
          _accentFor(importedNotes.length),
          folderIdOverride: _folderIdForImport(record.folderId, bundle.folders),
        ));
      }
    }

    _tasks = [...importedTasks, ..._tasks];
    _notes = [...importedNotes, ..._notes];
    for (final task in importedTasks) {
      if (_lists.every((list) => list.name != task.listName)) {
        _lists = [
          ..._lists,
          MigrationListRecord(
            id: null,
            name: task.listName,
            sortOrder: _lists.length,
            protectedList: false,
          ),
        ];
      }
    }
    _taskSequence = _nextTaskSequence();
    _noteSequence = _nextNoteSequence();
    _folderSequence = _nextFolderSequence();
    _restoredFromDisk = true;
    if ((_selectedTaskId == null ||
            _tasks.every((task) => task.id != _selectedTaskId)) &&
        _tasks.isNotEmpty) {
      _selectedTaskId = _tasks.first.id;
    }
    await _store.save(_snapshot());
    _notify();
    return MigrationImportSummary(
      importedTasks: importedTasks.length,
      skippedTasks: bundle.tasks.length - importedTasks.length,
      importedNotes: importedNotes.length,
      skippedNotes: bundle.notes.length - importedNotes.length,
      importedLists: bundle.lists.length,
      importedFolders: bundle.folders.length,
    );
  }

  /// Replaces the whole workspace with the bundle: the escape hatch for a
  /// first import (so starter content never mixes with real data) and for
  /// restoring a snapshot whose IDs collide with local records.
  Future<MigrationImportSummary> replaceWithMigration(
      MigrationBundle bundle) async {
    _loadError = null;
    _saveError = null;
    _lists = bundle.lists.isEmpty
        ? List.from(_defaultLists())
        : List.from(bundle.lists);
    _folders = List.from(bundle.folders);
    _tasks = bundle.tasks.map(TaskItem.fromMigration).toList();
    for (final task in _tasks) {
      if (_lists.every((list) => list.name != task.listName)) {
        _lists = [
          ..._lists,
          MigrationListRecord(
            id: null,
            name: task.listName,
            sortOrder: _lists.length,
            protectedList: false,
          ),
        ];
      }
    }
    _notes = bundle.notes
        .asMap()
        .entries
        .map((entry) => NoteItem.fromMigration(
              entry.value,
              _folderName(entry.value.folderId),
              _accentFor(entry.key),
            ))
        .toList();
    _taskSequence = _nextTaskSequence();
    _noteSequence = _nextNoteSequence();
    _folderSequence = _nextFolderSequence();
    _restoredFromDisk = true;
    _selectedTaskId = _tasks.isEmpty ? null : _tasks.first.id;
    _selectedListName = null;
    _selectedNoteId = _notes.isEmpty ? null : _notes.first.id;
    _lastCompletedTaskId = null;
    _lastRemovedTaskId = null;
    _lastRemovedNoteId = null;
    _lastActionKind = '';
    _lastActionMessage = '';
    await _store.save(_snapshot());
    _notify();
    return MigrationImportSummary(
      importedTasks: _tasks.length,
      skippedTasks: 0,
      importedNotes: _notes.length,
      skippedNotes: 0,
      importedLists: bundle.lists.length,
      importedFolders: bundle.folders.length,
    );
  }

  TaskItem? get selectedTask {
    for (final task in _tasks) {
      if (task.id == _selectedTaskId) return task;
    }
    return null;
  }

  List<TaskItem> get visibleTasks {
    if (_view == WorkspaceView.trash) {
      return List.unmodifiable(_tasks.where((task) => task.deletedAt != null));
    }
    final active = _tasks.where((task) => task.deletedAt == null);
    if (_selectedListName != null && _view == WorkspaceView.all) {
      return List.unmodifiable(
          active.where((task) => task.listName == _selectedListName));
    }
    final filtered = switch (_view) {
      WorkspaceView.home => active,
      WorkspaceView.today => active.where((task) =>
          task.bucket == TaskBucket.today || task.bucket == TaskBucket.overdue),
      WorkspaceView.inbox => active.where((task) => task.listName == '收集箱'),
      WorkspaceView.plan =>
        active.where((task) => task.bucket == TaskBucket.later),
      WorkspaceView.all => active,
      WorkspaceView.completed => active.where((task) => task.completed),
      WorkspaceView.work => active.where((task) => task.listName == '工作'),
      WorkspaceView.study => active.where((task) => task.listName == '学习'),
      WorkspaceView.personal => active.where((task) => task.listName == '个人'),
      WorkspaceView.calendar ||
      WorkspaceView.notes ||
      WorkspaceView.trash =>
        const <TaskItem>[],
    };
    return List.unmodifiable(filtered);
  }

  /// Tasks whose scheduled date falls on [day], independent of the current
  /// navigation filters, so the calendar never borrows another view's list.
  List<TaskItem> tasksForDay(DateTime day) {
    return List.unmodifiable(activeTasks.where((task) {
      if (task.dueAt == null) return false;
      final due = DateTime.tryParse(task.dueAt!);
      return due != null &&
          due.year == day.year &&
          due.month == day.month &&
          due.day == day.day;
    }));
  }

  int countFor(WorkspaceView destination) {
    final active = _tasks.where((task) => task.deletedAt == null);
    final dueTodayOrOverdue = (TaskItem task) =>
        task.bucket == TaskBucket.today || task.bucket == TaskBucket.overdue;
    return switch (destination) {
      WorkspaceView.home => active
          .where((task) => !task.completed && dueTodayOrOverdue(task))
          .length,
      WorkspaceView.today => active
          .where((task) => !task.completed && dueTodayOrOverdue(task))
          .length,
      WorkspaceView.inbox => active
          .where((task) => task.listName == '收集箱' && !task.completed)
          .length,
      WorkspaceView.plan => active
          .where((task) => task.bucket == TaskBucket.later && !task.completed)
          .length,
      WorkspaceView.all => active.where((task) => !task.completed).length,
      WorkspaceView.completed => active.where((task) => task.completed).length,
      WorkspaceView.work =>
        active.where((task) => task.listName == '工作' && !task.completed).length,
      WorkspaceView.study =>
        active.where((task) => task.listName == '学习' && !task.completed).length,
      WorkspaceView.personal =>
        active.where((task) => task.listName == '个人' && !task.completed).length,
      WorkspaceView.calendar || WorkspaceView.notes => 0,
      WorkspaceView.trash =>
        _tasks.where((task) => task.deletedAt != null).length,
    };
  }

  int countForList(String listName) => _tasks
      .where((task) =>
          task.listName == listName &&
          !task.completed &&
          task.deletedAt == null)
      .length;

  bool isListSelected(String listName) =>
      _view == WorkspaceView.all && _selectedListName == listName;

  void selectView(WorkspaceView destination) {
    if (_view == destination && _selectedListName == null) return;
    _view = destination;
    _selectedListName = null;
    _multiSelectedTaskIds = {};
    _multiSelectAnchorId = null;
    final available = visibleTasks;
    if (available.isNotEmpty &&
        !available.any((task) => task.id == _selectedTaskId)) {
      _selectedTaskId = available.first.id;
    }
    _notify();
  }

  void selectList(String listName) {
    final name = listName.trim();
    if (name.isEmpty) return;
    if (_view == WorkspaceView.all && _selectedListName == name) return;
    _view = WorkspaceView.all;
    _selectedListName = name;
    _multiSelectedTaskIds = {};
    _multiSelectAnchorId = null;
    final available = visibleTasks;
    if (available.isNotEmpty) _selectedTaskId = available.first.id;
    _notify();
  }

  void selectTask(String id) {
    if (_selectedTaskId == id) return;
    if (_tasks.every((task) => task.id != id)) return;
    _selectedTaskId = id;
    _notify();
  }

  void selectNote(String id) {
    if (_notes.every((note) => note.id != id || note.deletedAt != null)) return;
    if (_selectedNoteId == id) return;
    _selectedNoteId = id;
    _notify();
  }

  /// Opens a task from search or links: lands on the view that owns it and
  /// selects it, so the inspector always shows the requested task.
  void openTask(String id) {
    TaskItem? task;
    for (final candidate in _tasks) {
      if (candidate.id == id && candidate.deletedAt == null) {
        task = candidate;
        break;
      }
    }
    if (task == null) return;
    final name = task.listName.trim();
    if (name == '收集箱') {
      _view = WorkspaceView.inbox;
      _selectedListName = null;
    } else if (name.isNotEmpty) {
      _view = WorkspaceView.all;
      _selectedListName = name;
    } else {
      _view = task.bucket == TaskBucket.later
          ? WorkspaceView.plan
          : WorkspaceView.today;
      _selectedListName = null;
    }
    _selectedTaskId = id;
    _notify();
  }

  /// Opens a note from search: switches to Notes and selects the exact note,
  /// so editing the second result edits that note and not the first one.
  void openNote(String id) {
    if (_notes.every((note) => note.id != id || note.deletedAt != null)) {
      return;
    }
    _selectedNoteId = id;
    _view = WorkspaceView.notes;
    _notify();
  }

  void moveTaskToToday(String id) {
    final index =
        _tasks.indexWhere((task) => task.id == id && task.deletedAt == null);
    if (index < 0) return;
    final task = _tasks[index];
    final now = DateTime.now();
    final previousDue =
        task.dueAt == null ? null : DateTime.tryParse(task.dueAt!);
    final due = DateTime(
      now.year,
      now.month,
      now.day,
      previousDue?.hour ?? 0,
      previousDue?.minute ?? 0,
    );
    _tasks[index] = task.copyWith(
      dueAt: due.toIso8601String(),
      bucket: taskBucketForDate(due, completed: task.completed),
      timeLabel: taskTimeLabelFor(due, completed: task.completed),
      updatedAt: now.toIso8601String(),
    );
    _view = WorkspaceView.today;
    _selectedTaskId = id;
    _schedulePersist();
    _notify();
  }

  void toggleTask(String id) {
    final index = _tasks.indexWhere((task) => task.id == id);
    if (index < 0) return;
    final task = _tasks[index];
    final completing = !task.completed;
    final now = DateTime.now();
    final nowLabel = now.toIso8601String();
    final due = task.dueAt == null ? null : DateTime.tryParse(task.dueAt!);
    var updated = task.copyWith(
      completed: completing,
      completedAt: completing ? nowLabel : null,
      clearCompletedAt: !completing,
      updatedAt: nowLabel,
      timeLabel: completing ? '已完成 · 刚刚' : (taskTimeLabelFor(due) ?? '未安排'),
    );
    TaskItem? spawn;
    if (completing) {
      _completionVersion += 1;
      _actionVersion += 1;
      _lastActionKind = 'completion';
      _lastActionMessage = '任务已完成';
      spawn = _spawnNextRecurrence(updated, completedAt: now);
      if (spawn != null) {
        _taskSequence += 1;
        // The historical record stops recurring so a later manual un-complete
        // never spawns a duplicate chain.
        updated = updated.copyWith(
          recurrenceType: 'NONE',
          clearRecurrenceConfig: true,
        );
        _selectedTaskId = spawn.id;
      }
    }
    // Assign the original slot first; prepending the spawn shifts every
    // following index and must not race this write.
    _tasks[index] = updated;
    if (spawn != null) {
      _tasks = [spawn, ..._tasks];
    }
    _lastCompletedTaskId = completing ? id : null;
    _lastRecurrenceSpawnId = spawn?.id;
    _lastCompletedRecurrenceType = spawn != null ? task.recurrenceType : null;
    _lastCompletedRecurrenceConfig =
        spawn != null ? task.recurrenceConfig : null;
    _schedulePersist();
    _notify();
  }

  /// Creates the next occurrence when a recurring task completes. The chain
  /// keeps its fixed schedule: due + interval, or the completion date when the
  /// task had no date.
  TaskItem? _spawnNextRecurrence(TaskItem task,
      {required DateTime completedAt}) {
    final type = task.recurrenceType.toUpperCase();
    if (type == 'NONE') return null;
    final due = task.dueAt == null ? null : DateTime.tryParse(task.dueAt!);
    final nextDue =
        _nextRecurrenceDate(type, task.recurrenceConfig, due, completedAt);
    if (nextDue == null) return null;

    DateTime? shiftedReminder;
    if (task.reminderAt != null && due != null) {
      final reminder = DateTime.tryParse(task.reminderAt!);
      if (reminder != null) {
        final delta = nextDue.difference(due);
        shiftedReminder = reminder.add(delta);
      }
    }
    final now = DateTime.now().toIso8601String();
    return TaskItem(
      id: 'task-${_taskSequence.toString().padLeft(2, '0')}',
      title: task.title,
      listName: task.listName,
      bucket: taskBucketForDate(nextDue),
      timeLabel: taskTimeLabelFor(nextDue),
      dueAt: nextDue.toIso8601String(),
      note: task.note,
      description: task.description,
      contentJson: task.contentJson,
      reminderAt: shiftedReminder?.toIso8601String(),
      recurrenceType: task.recurrenceType,
      recurrenceConfig: task.recurrenceConfig,
      tags: task.tags,
      subtasks: task.subtasks
          .map((subtask) => TaskSubtask(
              id: subtask.id, title: subtask.title, completed: false))
          .toList(),
      priority: task.priority,
      createdAt: now,
      updatedAt: now,
    );
  }

  DateTime? _nextRecurrenceDate(String type, Map<String, dynamic>? config,
      DateTime? due, DateTime completedAt) {
    final base =
        due ?? DateTime(completedAt.year, completedAt.month, completedAt.day);
    switch (type) {
      case 'DAILY':
        return base.add(const Duration(days: 1));
      case 'WEEKLY':
        final weekday = (config?['weekday'] as num?)?.toInt();
        if (weekday != null && weekday >= 1 && weekday <= 7) {
          var next = base.add(const Duration(days: 1));
          while (next.weekday != weekday) {
            next = next.add(const Duration(days: 1));
          }
          return next;
        }
        return base.add(const Duration(days: 7));
      case 'MONTHLY':
        final day = (config?['dayOfMonth'] as num?)?.toInt();
        final targetDay =
            (day != null && day >= 1 && day <= 31) ? day : base.day;
        var year = base.year;
        var month = base.month + 1;
        if (month > 12) {
          month = 1;
          year += 1;
        }
        final lastDay = DateTime(year, month + 1, 0).day;
        // Months without that day (e.g. the 31st in February) land on the
        // last day of the month.
        final clamped = targetDay > lastDay ? lastDay : targetDay;
        return DateTime(year, month, clamped, base.hour, base.minute);
      default:
        return null;
    }
  }

  bool undoLastCompletion() {
    final id = _lastCompletedTaskId;
    if (id == null) return false;
    final index = _tasks.indexWhere((task) => task.id == id);
    if (index < 0) return false;
    final task = _tasks[index];
    final due = task.dueAt == null ? null : DateTime.tryParse(task.dueAt!);
    var updated = task.copyWith(
      completed: false,
      clearCompletedAt: true,
      updatedAt: DateTime.now().toIso8601String(),
      timeLabel: taskTimeLabelFor(due) ?? '未安排',
    );
    // Undo also reverts the recurrence: the generated next occurrence is
    // removed and the completed record carries its rule again.
    final spawnId = _lastRecurrenceSpawnId;
    if (spawnId != null && _lastCompletedRecurrenceType != null) {
      updated = updated.copyWith(
        recurrenceType: _lastCompletedRecurrenceType!,
        recurrenceConfig: _lastCompletedRecurrenceConfig,
        clearRecurrenceConfig: _lastCompletedRecurrenceConfig == null,
      );
      _tasks.removeWhere((item) => item.id == spawnId);
    }
    // removeWhere may have shifted positions; re-locate before writing.
    final writeIndex = _tasks.indexWhere((item) => item.id == id);
    if (writeIndex >= 0) {
      _tasks[writeIndex] = updated;
    }
    _lastCompletedTaskId = null;
    _lastRecurrenceSpawnId = null;
    _lastCompletedRecurrenceType = null;
    _lastCompletedRecurrenceConfig = null;
    _lastActionKind = '';
    if (_tasks.any((item) => item.id == id)) {
      _selectedTaskId = id;
    }
    _schedulePersist();
    _notify();
    return true;
  }

  /// Soft-deletes a task: it stays in the workspace with a `deletedAt` mark,
  /// so the trash is persistent and the promise in the undo toast is real.
  void removeTask(String id) {
    final index = _tasks.indexWhere((task) => task.id == id);
    if (index < 0 || _tasks[index].deletedAt != null) return;
    final now = DateTime.now().toIso8601String();
    _tasks[index] = _tasks[index].copyWith(deletedAt: now, updatedAt: now);
    _lastCompletedTaskId = null;
    _lastRemovedTaskId = id;
    _lastRemovedNoteId = null;
    _actionVersion += 1;
    _lastActionKind = 'removal';
    _lastActionMessage = '任务已移到废纸篓';
    if (_selectedTaskId == id) {
      _selectedTaskId = _nextSelectableTaskId(index);
    }
    _schedulePersist();
    _notify();
  }

  void restoreTask(String id) {
    final index = _tasks.indexWhere((task) => task.id == id);
    if (index < 0) return;
    _tasks[index] = _tasks[index].copyWith(
      clearDeletedAt: true,
      updatedAt: DateTime.now().toIso8601String(),
    );
    _schedulePersist();
    _notify();
  }

  void purgeTask(String id) {
    final index = _tasks.indexWhere((task) => task.id == id);
    if (index < 0) return;
    _tasks.removeAt(index);
    if (_selectedTaskId == id) _selectedTaskId = null;
    _schedulePersist();
    _notify();
  }

  /// Picks the task that should take the selection after [removedIndex] is
  /// filtered out of the current view.
  String? _nextSelectableTaskId(int removedIndex) {
    final visible = visibleTasks;
    if (visible.isEmpty) return null;
    return visible[removedIndex.clamp(0, visible.length - 1).toInt()].id;
  }

  // ---------------------------------------------------------------------------
  // Multi-select and bulk operations. Cmd-click toggles membership, Shift-click
  // extends a range; the bulk bar offers complete / reschedule / move / delete,
  // all revertible through the undo toast.
  // ---------------------------------------------------------------------------

  Set<String> get multiSelectedTaskIds =>
      Set.unmodifiable(_multiSelectedTaskIds);
  int get multiSelectCount => _multiSelectedTaskIds.length;
  bool isTaskMultiSelected(String id) => _multiSelectedTaskIds.contains(id);

  void toggleMultiSelect(String id) {
    if (!_multiSelectedTaskIds.add(id)) {
      _multiSelectedTaskIds.remove(id);
    }
    _multiSelectAnchorId = id;
    _notify();
  }

  void extendMultiSelectTo(String id) {
    final visible = visibleTasks;
    final anchorIndex =
        visible.indexWhere((task) => task.id == _multiSelectAnchorId);
    final targetIndex = visible.indexWhere((task) => task.id == id);
    if (anchorIndex < 0 || targetIndex < 0) {
      _multiSelectedTaskIds.add(id);
    } else {
      final start = anchorIndex < targetIndex ? anchorIndex : targetIndex;
      final end = anchorIndex < targetIndex ? targetIndex : anchorIndex;
      for (var i = start; i <= end; i++) {
        _multiSelectedTaskIds.add(visible[i].id);
      }
    }
    _notify();
  }

  void selectAllVisibleTasks() {
    _multiSelectedTaskIds = visibleTasks.map((task) => task.id).toSet();
    _notify();
  }

  void clearMultiSelect() {
    if (_multiSelectedTaskIds.isEmpty) return;
    _multiSelectedTaskIds = {};
    _multiSelectAnchorId = null;
    _notify();
  }

  void bulkCompleteSelected() {
    if (_multiSelectedTaskIds.isEmpty) return;
    final now = DateTime.now();
    final nowLabel = now.toIso8601String();
    final completedIds = <String>[];
    final spawnedIds = <String>[];
    final spawned = <TaskItem>[];
    final rules = <String, (String, Map<String, dynamic>?)>{};
    for (final id in _multiSelectedTaskIds) {
      final index = _tasks.indexWhere((task) => task.id == id);
      if (index < 0) continue;
      final task = _tasks[index];
      if (task.completed || task.deletedAt != null) continue;
      final next = _spawnNextRecurrence(task, completedAt: now);
      var updated = task.copyWith(
        completed: true,
        completedAt: nowLabel,
        updatedAt: nowLabel,
        timeLabel: '已完成 · 刚刚',
      );
      if (next != null) {
        _taskSequence += 1;
        spawned.add(next);
        spawnedIds.add(next.id);
        rules[id] = (task.recurrenceType, task.recurrenceConfig);
        updated = updated.copyWith(
          recurrenceType: 'NONE',
          clearRecurrenceConfig: true,
        );
      }
      _tasks[index] = updated;
      completedIds.add(id);
    }
    if (completedIds.isEmpty) return;
    if (spawned.isNotEmpty) _tasks = [...spawned, ..._tasks];
    _completionVersion += 1;
    _lastBulkUndo = _BulkTaskUndo(
      completedIds: completedIds,
      spawnedIds: spawnedIds,
      recurrenceRules: rules,
    );
    _lastActionKind = 'bulk';
    _lastActionMessage = '已完成 ${completedIds.length} 个任务';
    _actionVersion += 1;
    _endBulkSelection();
    _schedulePersist();
    _notify();
  }

  /// Reschedules every selected task to [day] (keeping each task's clock
  /// time), or clears dates when [day] is null.
  void bulkRescheduleSelected(DateTime? day) {
    if (_multiSelectedTaskIds.isEmpty) return;
    final previous = <String, String?>{};
    final now = DateTime.now().toIso8601String();
    var touched = 0;
    for (final id in _multiSelectedTaskIds) {
      final index = _tasks.indexWhere((task) => task.id == id);
      if (index < 0) continue;
      final task = _tasks[index];
      if (task.deletedAt != null) continue;
      previous[id] = task.dueAt;
      DateTime? due;
      if (day != null) {
        final existing =
            task.dueAt == null ? null : DateTime.tryParse(task.dueAt!);
        due = DateTime(day.year, day.month, day.day, existing?.hour ?? 0,
            existing?.minute ?? 0);
      }
      _tasks[index] = task.copyWith(
        dueAt: due?.toIso8601String(),
        clearDueAt: due == null,
        bucket: taskBucketForDate(due, completed: task.completed),
        timeLabel: due == null
            ? (task.completed ? '已完成' : '未安排')
            : taskTimeLabelFor(due, completed: task.completed),
        updatedAt: now,
      );
      touched += 1;
    }
    if (touched == 0) return;
    _lastBulkUndo = _BulkTaskUndo(previousDueAts: previous);
    _lastActionKind = 'bulk';
    _lastActionMessage = '已更新 $touched 个任务的日期';
    _actionVersion += 1;
    _endBulkSelection();
    _schedulePersist();
    _notify();
  }

  void bulkMoveSelectedToList(String rawListName) {
    final listName = rawListName.trim();
    if (listName.isEmpty || _multiSelectedTaskIds.isEmpty) return;
    if (_lists.every((list) => list.name != listName)) addList(listName);
    final previous = <String, String>{};
    final now = DateTime.now().toIso8601String();
    var touched = 0;
    for (final id in _multiSelectedTaskIds) {
      final index = _tasks.indexWhere((task) => task.id == id);
      if (index < 0) continue;
      final task = _tasks[index];
      if (task.deletedAt != null || task.listName == listName) continue;
      previous[id] = task.listName;
      _tasks[index] = task.copyWith(
        listName: listName,
        updatedAt: now,
      );
      touched += 1;
    }
    if (touched == 0) return;
    _lastBulkUndo = _BulkTaskUndo(previousListNames: previous);
    _lastActionKind = 'bulk';
    _lastActionMessage = '已移动 $touched 个任务到「$listName」';
    _actionVersion += 1;
    _endBulkSelection();
    _schedulePersist();
    _notify();
  }

  void bulkDeleteSelected() {
    if (_multiSelectedTaskIds.isEmpty) return;
    final removedIds = <String>[];
    final now = DateTime.now().toIso8601String();
    for (final id in _multiSelectedTaskIds) {
      final index = _tasks.indexWhere((task) => task.id == id);
      if (index < 0) continue;
      if (_tasks[index].deletedAt != null) continue;
      _tasks[index] = _tasks[index].copyWith(deletedAt: now, updatedAt: now);
      removedIds.add(id);
    }
    if (removedIds.isEmpty) return;
    _lastBulkUndo = _BulkTaskUndo(removedIds: removedIds);
    _lastActionKind = 'bulk';
    _lastActionMessage = '${removedIds.length} 个任务已移到废纸篓';
    _actionVersion += 1;
    _lastCompletedTaskId = null;
    if (_selectedTaskId != null && removedIds.contains(_selectedTaskId)) {
      _selectedTaskId = null;
    }
    _endBulkSelection();
    _schedulePersist();
    _notify();
  }

  void _endBulkSelection() {
    _multiSelectedTaskIds = {};
    _multiSelectAnchorId = null;
  }

  void _revertBulkUndo(_BulkTaskUndo bulk) {
    final now = DateTime.now().toIso8601String();
    for (final id in bulk.completedIds) {
      final index = _tasks.indexWhere((task) => task.id == id);
      if (index < 0) continue;
      final task = _tasks[index];
      final due = task.dueAt == null ? null : DateTime.tryParse(task.dueAt!);
      final rule = bulk.recurrenceRules[id];
      _tasks[index] = task.copyWith(
        completed: false,
        clearCompletedAt: true,
        updatedAt: now,
        timeLabel: taskTimeLabelFor(due) ?? '未安排',
        recurrenceType: rule?.$1 ?? task.recurrenceType,
        recurrenceConfig: rule?.$2,
        clearRecurrenceConfig: rule != null && rule.$2 == null,
      );
    }
    final spawnIds = bulk.spawnedIds.toSet();
    if (spawnIds.isNotEmpty) {
      _tasks.removeWhere((task) => spawnIds.contains(task.id));
    }
    for (final id in bulk.removedIds) {
      final index = _tasks.indexWhere((task) => task.id == id);
      if (index < 0) continue;
      _tasks[index] =
          _tasks[index].copyWith(clearDeletedAt: true, updatedAt: now);
    }
    bulk.previousDueAts.forEach((id, value) {
      final index = _tasks.indexWhere((task) => task.id == id);
      if (index < 0) return;
      final task = _tasks[index];
      final due = value == null ? null : DateTime.tryParse(value);
      _tasks[index] = task.copyWith(
        dueAt: value,
        clearDueAt: value == null,
        bucket: taskBucketForDate(due, completed: task.completed),
        timeLabel: due == null
            ? (task.completed ? '已完成' : '未安排')
            : taskTimeLabelFor(due, completed: task.completed),
        updatedAt: now,
      );
    });
    bulk.previousListNames.forEach((id, value) {
      final index = _tasks.indexWhere((task) => task.id == id);
      if (index < 0) return;
      _tasks[index] = _tasks[index].copyWith(listName: value, updatedAt: now);
    });
    _lastBulkUndo = null;
    _lastActionKind = '';
    _endBulkSelection();
    _schedulePersist();
    _notify();
  }

  /// Moves a task to [day] from a calendar drag, keeping its clock time.
  void rescheduleTask(String id, DateTime day) {
    final index =
        _tasks.indexWhere((task) => task.id == id && task.deletedAt == null);
    if (index < 0) return;
    final task = _tasks[index];
    final existing = task.dueAt == null ? null : DateTime.tryParse(task.dueAt!);
    updateTaskDue(
      id,
      DateTime(day.year, day.month, day.day, existing?.hour ?? 0,
          existing?.minute ?? 0),
    );
  }

  bool undoLastAction() {
    final bulk = _lastBulkUndo;
    if (bulk != null) {
      _revertBulkUndo(bulk);
      return true;
    }
    if (_lastActionKind == 'completion') return undoLastCompletion();
    if (_lastActionKind == 'removal' && _lastRemovedTaskId != null) {
      final index = _tasks.indexWhere((task) => task.id == _lastRemovedTaskId);
      if (index < 0) return false;
      _tasks[index] = _tasks[index].copyWith(
        clearDeletedAt: true,
        updatedAt: DateTime.now().toIso8601String(),
      );
      _selectedTaskId = _lastRemovedTaskId;
      _lastRemovedTaskId = null;
      _lastActionKind = '';
      _schedulePersist();
      _notify();
      return true;
    }
    if (_lastActionKind == 'note-removal' && _lastRemovedNoteId != null) {
      final index = _notes.indexWhere((note) => note.id == _lastRemovedNoteId);
      if (index < 0) return false;
      _notes[index] = _notes[index].copyWith(
        clearDeletedAt: true,
        updatedAt: DateTime.now().toIso8601String(),
      );
      _selectedNoteId = _lastRemovedNoteId;
      _lastRemovedNoteId = null;
      _lastActionKind = '';
      _schedulePersist();
      _notify();
      return true;
    }
    return false;
  }

  /// Creates a task in the current context. When no explicit list/date is
  /// given, the active view decides: a list view keeps its list, Today
  /// schedules for today, and capture elsewhere lands in the inbox unscheduled.
  bool addTask(String rawTitle, {String? listName, DateTime? dueAt}) {
    final title = rawTitle.trim();
    if (title.isEmpty) return false;
    final targetList = (listName ?? _creationListName()).trim();
    if (targetList.isEmpty) return false;
    final effectiveDue = dueAt ?? _creationDueDate();
    if (_lists.every((list) => list.name != targetList)) addList(targetList);
    final now = DateTime.now().toIso8601String();
    final task = TaskItem(
      id: 'task-${_taskSequence.toString().padLeft(2, '0')}',
      title: title,
      listName: targetList,
      bucket: taskBucketForDate(effectiveDue),
      timeLabel: taskTimeLabelFor(effectiveDue),
      dueAt: effectiveDue?.toIso8601String(),
      createdAt: now,
      updatedAt: now,
    );
    _taskSequence += 1;
    _tasks = [task, ..._tasks];
    _selectedTaskId = task.id;
    _schedulePersist();
    _notify();
    return true;
  }

  String _creationListName() {
    if (_selectedListName != null) return _selectedListName!;
    return switch (_view) {
      WorkspaceView.inbox => '收集箱',
      WorkspaceView.work => '工作',
      WorkspaceView.study => '学习',
      WorkspaceView.personal => '个人',
      _ => '收集箱',
    };
  }

  DateTime? _creationDueDate() {
    // Quick capture inside Today schedules for today; everywhere else a new
    // task stays unscheduled so capture and planning remain separate.
    if (_view != WorkspaceView.today) return null;
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day);
  }

  /// Human-readable target for command palettes and menus.
  String get creationTargetLabel {
    final listName = _creationListName();
    if (_creationDueDate() != null) return '$listName · 安排到今天';
    return listName;
  }

  void updateSelectedTitle(String title) {
    final id = _selectedTaskId;
    if (id == null) return;
    updateTaskTitle(id, title);
  }

  void updateTaskTitle(String id, String rawTitle) {
    final title = rawTitle.trim();
    if (title.isEmpty) return;
    _replaceTask(
        id,
        (task) => task.copyWith(
              title: title,
              updatedAt: DateTime.now().toIso8601String(),
            ));
  }

  void updateTaskDescription(String id, String rawDescription) {
    final description = rawDescription.trim();
    _replaceTask(
      id,
      (task) => description.isEmpty
          ? task.copyWith(
              note: null,
              clearNote: true,
              description: null,
              clearDescription: true,
              updatedAt: DateTime.now().toIso8601String(),
            )
          : task.copyWith(
              note: description,
              description: description,
              updatedAt: DateTime.now().toIso8601String(),
            ),
    );
  }

  void updateTaskPriority(String id, TaskPriority priority) {
    _replaceTask(
        id,
        (task) => task.copyWith(
              priority: priority,
              updatedAt: DateTime.now().toIso8601String(),
            ));
  }

  void updateTaskDue(String id, DateTime? due) {
    final normalized = due == null
        ? null
        : DateTime(due.year, due.month, due.day, due.hour, due.minute);
    _replaceTask(
      id,
      (task) => task.copyWith(
        dueAt: normalized?.toIso8601String(),
        clearDueAt: normalized == null,
        bucket: taskBucketForDate(normalized, completed: task.completed),
        timeLabel: normalized == null
            ? (task.completed ? '已完成' : '未安排')
            : taskTimeLabelFor(normalized, completed: task.completed),
        updatedAt: DateTime.now().toIso8601String(),
      ),
    );
  }

  void updateTaskReminder(String id, DateTime? reminder) {
    final normalized = reminder == null
        ? null
        : DateTime(reminder.year, reminder.month, reminder.day, reminder.hour,
            reminder.minute);
    _replaceTask(
      id,
      (task) => task.copyWith(
        reminderAt: normalized?.toIso8601String(),
        clearReminderAt: normalized == null,
        updatedAt: DateTime.now().toIso8601String(),
      ),
    );
  }

  void updateTaskRecurrence(String id, String type,
      {Map<String, dynamic>? config}) {
    final normalized = type.trim().toUpperCase();
    final recurrenceType =
        const {'NONE', 'DAILY', 'WEEKLY', 'MONTHLY'}.contains(normalized)
            ? normalized
            : 'NONE';
    _replaceTask(
      id,
      (task) => task.copyWith(
        recurrenceType: recurrenceType,
        recurrenceConfig: config,
        clearRecurrenceConfig: config == null,
        updatedAt: DateTime.now().toIso8601String(),
      ),
    );
  }

  void updateTaskTags(String id, List<String> rawTags) {
    final tags = <String>[];
    for (final rawTag in rawTags) {
      final tag = rawTag.trim();
      if (tag.isNotEmpty && !tags.contains(tag)) tags.add(tag);
    }
    _replaceTask(
        id,
        (task) => task.copyWith(
              tags: List.unmodifiable(tags),
              updatedAt: DateTime.now().toIso8601String(),
            ));
  }

  bool moveTaskToList(String id, String rawListName) {
    final listName = rawListName.trim();
    if (listName.isEmpty || _tasks.every((task) => task.id != id)) return false;
    if (_lists.every((list) => list.name != listName)) {
      addList(listName);
    }
    _replaceTask(
        id,
        (task) => task.copyWith(
              listName: listName,
              updatedAt: DateTime.now().toIso8601String(),
            ));
    return true;
  }

  bool addSubtask(String taskId, String rawTitle) {
    final title = rawTitle.trim();
    if (title.isEmpty) return false;
    final subtask = TaskSubtask(
      id: 'sub-${DateTime.now().microsecondsSinceEpoch}',
      title: title,
    );
    return _replaceTask(
      taskId,
      (task) => task.copyWith(
        subtasks: [...task.subtasks, subtask],
        updatedAt: DateTime.now().toIso8601String(),
      ),
    );
  }

  bool toggleSubtask(String taskId, String subtaskId) {
    return _replaceTask(
      taskId,
      (task) => task.copyWith(
        subtasks: task.subtasks
            .map((subtask) => subtask.id == subtaskId
                ? subtask.copyWith(completed: !subtask.completed)
                : subtask)
            .toList(),
        updatedAt: DateTime.now().toIso8601String(),
      ),
    );
  }

  bool renameSubtask(String taskId, String subtaskId, String rawTitle) {
    final title = rawTitle.trim();
    if (title.isEmpty) return false;
    return _replaceTask(
      taskId,
      (task) => task.copyWith(
        subtasks: task.subtasks
            .map((subtask) => subtask.id == subtaskId
                ? subtask.copyWith(title: title)
                : subtask)
            .toList(),
        updatedAt: DateTime.now().toIso8601String(),
      ),
    );
  }

  bool removeSubtask(String taskId, String subtaskId) {
    return _replaceTask(
      taskId,
      (task) => task.copyWith(
        subtasks:
            task.subtasks.where((subtask) => subtask.id != subtaskId).toList(),
        updatedAt: DateTime.now().toIso8601String(),
      ),
    );
  }

  /// Renames a list and every task that belongs to it.
  bool renameList(String rawOldName, String rawNewName) {
    final oldName = rawOldName.trim();
    final newName = rawNewName.trim();
    if (oldName.isEmpty ||
        newName.isEmpty ||
        oldName == '收集箱' ||
        newName == '收集箱') {
      return false;
    }
    if (_lists.every((list) => list.name != oldName)) return false;
    if (_lists.any((list) => list.name == newName)) return false;
    _lists = _lists
        .map((list) => list.name == oldName
            ? MigrationListRecord(
                id: list.id,
                name: newName,
                sortOrder: list.sortOrder,
                protectedList: list.protectedList,
              )
            : list)
        .toList();
    _tasks = _tasks
        .map((task) => task.listName == oldName
            ? task.copyWith(
                listName: newName,
                updatedAt: DateTime.now().toIso8601String(),
              )
            : task)
        .toList();
    if (_selectedListName == oldName) _selectedListName = newName;
    _schedulePersist();
    _notify();
    return true;
  }

  /// Deletes a list and moves its tasks back to the inbox, so no task is
  /// lost by removing the container.
  bool deleteList(String rawName) {
    final name = rawName.trim();
    if (name.isEmpty || name == '收集箱') return false;
    if (_lists.every((list) => list.name != name)) return false;
    _lists = _lists.where((list) => list.name != name).toList();
    _tasks = _tasks
        .map((task) => task.listName == name
            ? task.copyWith(
                listName: '收集箱',
                updatedAt: DateTime.now().toIso8601String(),
              )
            : task)
        .toList();
    if (_selectedListName == name) {
      _view = WorkspaceView.inbox;
      _selectedListName = null;
    }
    _schedulePersist();
    _notify();
    return true;
  }

  bool addList(String rawName) {
    final name = rawName.trim();
    if (name.isEmpty || _lists.any((list) => list.name == name)) return false;
    _lists = [
      ..._lists,
      MigrationListRecord(
        id: 'list-local-${_lists.length + 1}',
        name: name,
        sortOrder: _lists.length,
        protectedList: false,
      ),
    ];
    _schedulePersist();
    _notify();
    return true;
  }

  MigrationFolderRecord? addFolder(String rawName) {
    final name = rawName.trim();
    if (name.isEmpty || _folders.any((folder) => folder.name == name)) {
      return null;
    }
    final now = DateTime.now().toIso8601String();
    final folder = MigrationFolderRecord(
      id: 'folder-local-${_folderSequence.toString().padLeft(2, '0')}',
      parentId: null,
      name: name,
      sortOrder: _folders.length,
      createdAt: now,
      updatedAt: now,
    );
    _folderSequence += 1;
    _folders = [..._folders, folder];
    _schedulePersist();
    _notify();
    return folder;
  }

  String addNote({String? folderId, String title = '未命名笔记'}) {
    final now = DateTime.now().toIso8601String();
    final note = NoteItem(
      id: 'note-${_noteSequence.toString().padLeft(2, '0')}',
      title: title.trim().isEmpty ? '未命名笔记' : title.trim(),
      preview: '',
      updatedLabel: '刚刚',
      folder: _folderName(folderId),
      folderId: folderId,
      accent: _accentFor(_notes.length),
      plainText: '',
      contentJson: const <String, dynamic>{},
      createdAt: now,
      updatedAt: now,
    );
    _noteSequence += 1;
    _notes = [note, ..._notes];
    _schedulePersist();
    _notify();
    return note.id;
  }

  void updateNoteTitle(String id, String rawTitle) {
    final title = rawTitle.trim();
    if (title.isEmpty) return;
    final now = DateTime.now().toIso8601String();
    _replaceNote(
        id,
        (note) => note.copyWith(
              title: title,
              updatedLabel: noteUpdatedLabelFor(now),
              updatedAt: now,
            ));
  }

  void updateNoteBody(String id, String body) {
    final now = DateTime.now().toIso8601String();
    _replaceNote(
        id,
        (note) => note.copyWith(
              preview: notePreviewFromText(body),
              plainText: body,
              // Regenerate the structured body from the edited plain text so
              // the two fields never describe different versions.
              contentJson: noteContentJsonFromPlainText(body),
              updatedLabel: noteUpdatedLabelFor(now),
              updatedAt: now,
            ));
  }

  void toggleNoteFavorite(String id) {
    final now = DateTime.now().toIso8601String();
    _replaceNote(
        id,
        (note) => note.copyWith(
              isFavorite: !note.isFavorite,
              updatedLabel: noteUpdatedLabelFor(now),
              updatedAt: now,
            ));
  }

  bool moveNoteToFolder(String id, String? folderId) {
    if (folderId != null && _folders.every((folder) => folder.id != folderId)) {
      return false;
    }
    final now = DateTime.now().toIso8601String();
    _replaceNote(
      id,
      (note) => note.copyWith(
        folder: _folderName(folderId),
        folderId: folderId,
        clearFolderId: folderId == null,
        updatedLabel: noteUpdatedLabelFor(now),
        updatedAt: now,
      ),
    );
    return true;
  }

  /// Soft-deletes a note into the persistent trash; the toast can undo it.
  bool removeNote(String id) {
    final index = _notes.indexWhere((note) => note.id == id);
    if (index < 0 || _notes[index].deletedAt != null) return false;
    final now = DateTime.now().toIso8601String();
    _notes[index] = _notes[index].copyWith(deletedAt: now, updatedAt: now);
    _lastRemovedNoteId = id;
    _lastRemovedTaskId = null;
    _actionVersion += 1;
    _lastActionKind = 'note-removal';
    _lastActionMessage = '笔记已移到废纸篓';
    _schedulePersist();
    _notify();
    return true;
  }

  void restoreNote(String id) {
    final index = _notes.indexWhere((note) => note.id == id);
    if (index < 0) return;
    _notes[index] = _notes[index].copyWith(
      clearDeletedAt: true,
      updatedAt: DateTime.now().toIso8601String(),
    );
    _schedulePersist();
    _notify();
  }

  void purgeNote(String id) {
    final index = _notes.indexWhere((note) => note.id == id);
    if (index < 0) return;
    _notes.removeAt(index);
    if (_selectedNoteId == id) _selectedNoteId = null;
    _schedulePersist();
    _notify();
  }

  void moveTaskBefore(String draggedId, String targetId) {
    if (draggedId == targetId) return;
    final from = _tasks.indexWhere((task) => task.id == draggedId);
    final to = _tasks.indexWhere((task) => task.id == targetId);
    if (from < 0 || to < 0) return;
    final item = _tasks.removeAt(from);
    final adjustedTo = from < to ? to - 1 : to;
    _tasks.insert(adjustedTo.clamp(0, _tasks.length).toInt(), item);
    _selectedTaskId = draggedId;
    _schedulePersist();
    _notify();
  }

  void _applyBundle(MigrationBundle bundle) {
    _lists = List<MigrationListRecord>.from(bundle.lists);
    _folders = List<MigrationFolderRecord>.from(bundle.folders);
    _tasks = bundle.tasks.map(TaskItem.fromMigration).toList();
    _notes = bundle.notes
        .asMap()
        .entries
        .map((entry) => NoteItem.fromMigration(
              entry.value,
              _folderName(entry.value.folderId),
              _accentFor(entry.key),
            ))
        .toList();
    _taskSequence = _nextTaskSequence();
    _noteSequence = _nextNoteSequence();
    _folderSequence = _nextFolderSequence();
    _selectedTaskId = _tasks.isEmpty ? null : _tasks.first.id;
    _selectedListName = null;
    _selectedNoteId = _notes.isEmpty ? null : _notes.first.id;
    _lastCompletedTaskId = null;
    _lastRemovedTaskId = null;
    _lastRemovedNoteId = null;
    _lastRecurrenceSpawnId = null;
    _lastCompletedRecurrenceType = null;
    _lastCompletedRecurrenceConfig = null;
    _lastActionKind = '';
    _lastActionMessage = '';
  }

  MigrationBundle _snapshot() {
    return MigrationBundle(
      format: localSnapshotFormat,
      schemaVersion: migrationSchemaVersion,
      exportedAt: DateTime.now().toIso8601String(),
      lists: List.unmodifiable(_lists),
      folders: List.unmodifiable(_folders),
      tasks: _tasks.map((task) => task.toMigrationRecord()).toList(),
      notes: _notes.map((note) => note.toMigrationRecord()).toList(),
    );
  }

  void _schedulePersist() {
    // A damaged snapshot pauses persistence: writing starter data over a file
    // we failed to parse could destroy recoverable content. Importing lifts
    // the pause because it is an explicit replacement.
    if (_loadError != null) return;
    _saveStatus = SaveStatus.saving;
    _saveError = null;
    unawaited(() async {
      try {
        final bundle = _snapshot();
        await _store.save(bundle);
        _lastSavedAt = DateTime.now();
        _saveError = null;
        _saveStatus = SaveStatus.saved;
      } on Object catch (error) {
        _saveError = error.toString();
        _saveStatus = SaveStatus.failed;
      }
      _notify();
    }());
  }

  String _folderName(String? folderId) {
    if (folderId == null) return '未归档';
    for (final folder in _folders) {
      if (folder.id == folderId) return folder.name;
    }
    return '未归档';
  }

  String _folderNameForImport(
      String? folderId, List<MigrationFolderRecord> incoming) {
    final incomingFolder = incoming.cast<MigrationFolderRecord?>().firstWhere(
          (folder) => folder?.id == folderId,
          orElse: () => null,
        );
    if (incomingFolder != null) return incomingFolder.name;
    return _folderName(folderId);
  }

  String? _folderIdForImport(
      String? folderId, List<MigrationFolderRecord> incoming) {
    final incomingFolder = incoming.cast<MigrationFolderRecord?>().firstWhere(
          (folder) => folder?.id == folderId,
          orElse: () => null,
        );
    if (incomingFolder == null) return folderId;
    for (final folder in _folders) {
      if (folder.name == incomingFolder.name) return folder.id;
    }
    return incomingFolder.id;
  }

  ColorValue _accentFor(int index) {
    const values = [0xFFC23377, 0xFF4F46E5, 0xFF0F766E, 0xFFB45309];
    return ColorValue(values[index % values.length]);
  }

  List<MigrationListRecord> _mergeLists(
      List<MigrationListRecord> incoming, List<MigrationListRecord> existing) {
    final merged = List<MigrationListRecord>.from(existing);
    final names = merged.map((list) => list.name).toSet();
    for (final list in incoming) {
      if (list.name.trim().isEmpty || !names.add(list.name)) continue;
      merged.add(list);
    }
    return merged;
  }

  List<MigrationFolderRecord> _mergeFolders(
      List<MigrationFolderRecord> incoming,
      List<MigrationFolderRecord> existing) {
    final merged = List<MigrationFolderRecord>.from(existing);
    final ids = merged.map((folder) => folder.id).toSet();
    final names = merged.map((folder) => folder.name).toSet();
    for (final folder in incoming) {
      if (!ids.add(folder.id) || !names.add(folder.name)) continue;
      merged.add(folder);
    }
    return merged;
  }

  int _nextTaskSequence() {
    var highest = 0;
    final pattern = RegExp(r'task-(\d+)$');
    for (final task in _tasks) {
      final match = pattern.firstMatch(task.id);
      final value = match == null ? 0 : int.tryParse(match.group(1)!) ?? 0;
      if (value > highest) highest = value;
    }
    return highest + 1;
  }

  int _nextNoteSequence() {
    var highest = 0;
    final pattern = RegExp(r'note-(\d+)$');
    for (final note in _notes) {
      final match = pattern.firstMatch(note.id);
      final value = match == null ? 0 : int.tryParse(match.group(1)!) ?? 0;
      if (value > highest) highest = value;
    }
    return highest + 1;
  }

  int _nextFolderSequence() {
    var highest = 0;
    final pattern = RegExp(r'folder-(?:local-)?(\d+)$');
    for (final folder in _folders) {
      final match = pattern.firstMatch(folder.id);
      final value = match == null ? 0 : int.tryParse(match.group(1)!) ?? 0;
      if (value > highest) highest = value;
    }
    return highest + 1;
  }

  bool _replaceTask(String id, TaskItem Function(TaskItem task) update) {
    final index = _tasks.indexWhere((task) => task.id == id);
    if (index < 0) return false;
    _tasks[index] = update(_tasks[index]);
    _schedulePersist();
    _notify();
    return true;
  }

  void _replaceNote(String id, NoteItem Function(NoteItem note) update) {
    final index = _notes.indexWhere((note) => note.id == id);
    if (index < 0) return;
    _notes[index] = update(_notes[index]);
    _schedulePersist();
    _notify();
  }
}

/// Everything needed to revert one bulk operation. Only the parts the
/// operation touched are populated; the rest stays empty.
class _BulkTaskUndo {
  const _BulkTaskUndo({
    this.completedIds = const [],
    this.spawnedIds = const [],
    this.recurrenceRules = const {},
    this.removedIds = const [],
    this.previousDueAts = const {},
    this.previousListNames = const {},
  });

  final List<String> completedIds;
  final List<String> spawnedIds;
  final Map<String, (String, Map<String, dynamic>?)> recurrenceRules;
  final List<String> removedIds;
  final Map<String, String?> previousDueAts;
  final Map<String, String> previousListNames;
}
