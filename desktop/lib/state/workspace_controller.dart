import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../models/migration.dart';
import '../models/task.dart';
import '../services/local_workspace_store.dart';
import '../services/notification_service.dart';

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
  WorkspaceController(
      {LocalWorkspaceStore? store,
      ReminderScheduler? reminderScheduler,
      bool seedData = true})
      : _store = store ?? LocalWorkspaceStore(),
        _reminders = reminderScheduler ?? NotificationService(),
        _tasks = seedData ? _seedTasks() : [],
        _notes = seedData ? _seedNotes() : [],
        _lists = _defaultLists(),
        _folders = _defaultFolders() {
    // Clicking a delivered reminder opens the task.
    _reminders.onNotificationClicked = openTask;
  }

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
  final ReminderScheduler _reminders;
  List<TaskItem> _tasks;
  List<NoteItem> _notes;
  List<MigrationListRecord> _lists;
  List<MigrationFolderRecord> _folders;
  WorkspaceView _view = WorkspaceView.home;
  String? _selectedListName;
  String? _selectedTaskId;
  int taskOpenVersion = 0;
  int noteOpenVersion = 0;
  DateTime _dateReference = DateTime.now();
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
  Future<void> _pendingPersist = Future<void>.value();
  int _persistVersion = 0;
  final Map<String, int> _reminderSyncVersions = {};
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
  LocalWorkspaceStore get workspaceStore => _store;
  MigrationBundle get snapshot => _snapshot();

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
    if (_notesFolderFilter == folderId &&
        !_notesFavoritesOnly &&
        !_notesUnfiledOnly) return;
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
    noteOpenVersion++;
    _notesFavoritesOnly = false;
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
    await _syncAllReminders();
    _notify();
  }

  Future<MigrationImportSummary> importMigration(MigrationBundle bundle) async {
    await waitForPendingSaves();
    await _store.backupNow();
    await _store.restoreEmbeddedFiles(bundle.embeddedFiles);
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
    await _syncAllReminders();
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
    await waitForPendingSaves();
    await _store.backupNow();
    await _store.restoreEmbeddedFiles(bundle.embeddedFiles);
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
    _selectedTaskId = null;
    _selectedListName = null;
    _selectedNoteId = _notes.isEmpty ? null : _notes.first.id;
    _lastCompletedTaskId = null;
    _lastRemovedTaskId = null;
    _lastRemovedNoteId = null;
    _lastActionKind = '';
    _lastActionMessage = '';
    await _store.save(_snapshot());
    await _syncAllReminders();
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

  bool needsAttentionToday(TaskItem task) {
    if (task.bucket == TaskBucket.today || task.bucket == TaskBucket.overdue)
      return true;
    final deadline = localDateTimeFromStorage(task.deadlineAt);
    final now = DateTime.now();
    return deadline != null &&
        !deadline.isAfter(DateTime(now.year, now.month, now.day));
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
      WorkspaceView.today => active.where(needsAttentionToday),
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
      final due = localDateTimeFromStorage(task.dueAt);
      return due != null &&
          due.year == day.year &&
          due.month == day.month &&
          due.day == day.day;
    }));
  }

  int countFor(WorkspaceView destination) {
    final active = _tasks.where((task) => task.deletedAt == null);
    final dueTodayOrOverdue = needsAttentionToday;
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
    _selectedTaskId = null;
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
    _selectedTaskId = null;
    _notify();
  }

  void clearTaskSelection() {
    if (_selectedTaskId == null) return;
    _selectedTaskId = null;
    _notify();
  }

  void refreshDates() {
    final now = DateTime.now();
    var changed = now.year != _dateReference.year ||
        now.month != _dateReference.month ||
        now.day != _dateReference.day;
    _dateReference = now;
    _tasks = _tasks.map((task) {
      final due = localDateTimeFromStorage(task.dueAt);
      final bucket = taskBucketForDate(due, completed: task.completed);
      final label = taskTimeLabelFor(due, completed: task.completed);
      if (bucket == task.bucket && label == task.timeLabel) return task;
      changed = true;
      return task.copyWith(bucket: bucket, timeLabel: label);
    }).toList();
    if (changed) _notify();
  }

  String? duplicateTask(String id) {
    final source = _tasks.where((task) => task.id == id).firstOrNull;
    if (source == null) return null;
    final copyId = 'task-${_taskSequence.toString().padLeft(2, '0')}';
    _taskSequence += 1;
    final copy = TaskItem.fromMigration(MigrationTaskRecord.fromJson({
      ...source.toMigrationRecord().toJson(),
      'id': copyId,
      'title': '${source.title}（副本）',
      'status': 'TODO',
      'completedAt': null,
      'createdAt': DateTime.now().toIso8601String(),
      'deletedAt': null,
    }));
    _tasks = [copy, ..._tasks];
    _selectedTaskId = copyId;
    _syncReminderFor(copy);
    _schedulePersist();
    _notify();
    return copyId;
  }

  DateTime? get creationDate => _creationDueDate();

  void updateTaskDeadline(String id, DateTime? date) {
    _replaceTask(
        id,
        (task) => task.copyWith(
              deadlineAt: date == null
                  ? null
                  : DateTime(date.year, date.month, date.day).toIso8601String(),
              clearDeadlineAt: date == null,
              updatedAt: DateTime.now().toIso8601String(),
            ));
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
    taskOpenVersion++;
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
    noteOpenVersion++;
    _notesFolderFilter = null;
    _notesFavoritesOnly = false;
    _notesUnfiledOnly = false;
    _view = WorkspaceView.notes;
    _notify();
  }

  void moveTaskToToday(String id) {
    final index =
        _tasks.indexWhere((task) => task.id == id && task.deletedAt == null);
    if (index < 0) return;
    final task = _tasks[index];
    final now = DateTime.now();
    final previousDue = localDateTimeFromStorage(task.dueAt);
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
    final due = localDateTimeFromStorage(task.dueAt);
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
      // The generated occurrence has its own identifier and reminder. Keep
      // it in the system scheduler immediately instead of waiting for the
      // next application launch to reconcile all tasks.
      _syncReminderFor(spawn);
    }
    _lastCompletedTaskId = completing ? id : null;
    _lastRecurrenceSpawnId = spawn?.id;
    _lastCompletedRecurrenceType = spawn != null ? task.recurrenceType : null;
    _lastCompletedRecurrenceConfig =
        spawn != null ? task.recurrenceConfig : null;
    _syncReminderFor(updated);
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
    final due = localDateTimeFromStorage(task.dueAt);
    final nextDue =
        _nextRecurrenceDate(type, task.recurrenceConfig, due, completedAt);
    if (nextDue == null) return null;

    DateTime? shiftedReminder;
    if (task.reminderAt != null && due != null) {
      final reminder = localDateTimeFromStorage(task.reminderAt);
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
      hasDueTime: task.hasDueTime,
      deadlineAt: task.deadlineAt == null
          ? null
          : (localDateTimeFromStorage(task.deadlineAt)!
                  .add(nextDue.difference(due ?? completedAt)))
              .toIso8601String(),
      sourceNoteId: task.sourceNoteId,
      attachments: task.attachments,
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
    final due = localDateTimeFromStorage(task.dueAt);
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
      unawaited(_reminders.cancel(spawnId));
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
    _syncReminderFor(updated);
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
    _syncReminderFor(_tasks[index]);
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
    _syncReminderFor(_tasks[index]);
    _schedulePersist();
    _notify();
  }

  void purgeTask(String id) {
    final index = _tasks.indexWhere((task) => task.id == id);
    if (index < 0) return;
    unawaited(_reminders.cancel(id));
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
      _syncReminderFor(updated);
      if (next != null) _syncReminderFor(next);
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
  void bulkRescheduleSelected(DateTime? day, {bool? hasTime}) {
    if (_multiSelectedTaskIds.isEmpty) return;
    final previous = <String, String?>{};
    final previousTimes = <String, bool>{};
    final now = DateTime.now().toIso8601String();
    var touched = 0;
    for (final id in _multiSelectedTaskIds) {
      final index = _tasks.indexWhere((task) => task.id == id);
      if (index < 0) continue;
      final task = _tasks[index];
      if (task.deletedAt != null) continue;
      previous[id] = task.dueAt;
      previousTimes[id] = task.scheduledWithTime;
      DateTime? due;
      if (day != null) {
        final existing = localDateTimeFromStorage(task.dueAt);
        due = hasTime == null
            ? DateTime(day.year, day.month, day.day, existing?.hour ?? 0,
                existing?.minute ?? 0)
            : hasTime
                ? day
                : DateTime(day.year, day.month, day.day);
      }
      _tasks[index] = task.copyWith(
        dueAt: due?.toIso8601String(),
        clearDueAt: due == null,
        hasDueTime: due != null && (hasTime ?? task.scheduledWithTime),
        bucket: taskBucketForDate(due, completed: task.completed),
        timeLabel: due == null
            ? (task.completed ? '已完成' : '未安排')
            : taskTimeLabelFor(due, completed: task.completed),
        updatedAt: now,
      );
      touched += 1;
    }
    if (touched == 0) return;
    _lastBulkUndo = _BulkTaskUndo(
        previousDueAts: previous, previousDueTimes: previousTimes);
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
      _syncReminderFor(_tasks[index]);
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
      final due = localDateTimeFromStorage(task.dueAt);
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
      for (final id in spawnIds) {
        unawaited(_reminders.cancel(id));
      }
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
      final due = localDateTimeFromStorage(value);
      _tasks[index] = task.copyWith(
        dueAt: value,
        clearDueAt: value == null,
        hasDueTime: bulk.previousDueTimes[id],
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
    for (final id in [...bulk.completedIds, ...bulk.removedIds]) {
      final index = _tasks.indexWhere((task) => task.id == id);
      if (index >= 0) _syncReminderFor(_tasks[index]);
    }
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
    final existing = localDateTimeFromStorage(task.dueAt);
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
      _syncReminderFor(_tasks[index]);
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
  bool addTask(String rawTitle,
      {String? listName, DateTime? dueAt, bool forceUnscheduled = false}) {
    final title = rawTitle.trim();
    if (title.isEmpty) return false;
    final targetList = (listName ?? _creationListName()).trim();
    if (targetList.isEmpty) return false;
    final effectiveDue = forceUnscheduled ? null : dueAt ?? _creationDueDate();
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
    _selectedTaskId = null;
    _schedulePersist();
    _notify();
    return true;
  }

  /// Global/menu-bar capture always means "remember this for later". It must
  /// not inherit the page currently visible in the main window.
  bool addTaskToInboxUnscheduled(String rawTitle) => addTask(
        rawTitle,
        listName: '收集箱',
        forceUnscheduled: true,
      );

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

  void updateTaskDue(String id, DateTime? due, {bool? hasTime}) {
    final normalized = due == null
        ? null
        : DateTime(due.year, due.month, due.day, due.hour, due.minute);
    _replaceTask(
      id,
      (task) => task.copyWith(
        dueAt: normalized?.toIso8601String(),
        clearDueAt: normalized == null,
        hasDueTime: hasTime ??
            (normalized != null &&
                (normalized.hour != 0 || normalized.minute != 0)),
        bucket: taskBucketForDate(normalized, completed: task.completed),
        timeLabel: normalized == null
            ? (task.completed ? '已完成' : '未安排')
            : taskTimeLabelFor(normalized, completed: task.completed),
        updatedAt: DateTime.now().toIso8601String(),
      ),
    );
  }

  /// Registers or withdraws the system notification for one task's reminder,
  /// so what the user sees in the inspector matches what the system will
  /// deliver. Completing, deleting or clearing the reminder withdraws it.
  void _syncReminderFor(TaskItem task) {
    final syncVersion = (_reminderSyncVersions[task.id] ?? 0) + 1;
    _reminderSyncVersions[task.id] = syncVersion;
    final reminder = localDateTimeFromStorage(task.reminderAt);
    final active = !task.completed &&
        task.deletedAt == null &&
        reminder != null &&
        reminder.isAfter(DateTime.now());
    if (!active) {
      unawaited(_reminders.cancel(task.id));
      return;
    }
    unawaited(() async {
      // requestAuthorization returns immediately once already determined.
      await _reminders.requestPermission();
      // A task may have been completed, deleted or edited while permission
      // was being resolved. Do not let this older async request resurrect a
      // notification that the latest task state has already cancelled.
      if (_reminderSyncVersions[task.id] != syncVersion) return;
      await _reminders.schedule(
        taskId: task.id,
        title: task.title,
        body: '打勾 · ${task.listName}',
        at: reminder,
      );
    }());
  }

  Future<void> _syncAllReminders() async {
    // Reconcile from scratch on startup and wholesale imports: cheaper and
    // more reliable than diffing against system state.
    await _reminders.cancelAll();
    for (final task in activeTasks) {
      _syncReminderFor(task);
    }
  }

  void updateTaskReminder(String id, DateTime? reminder) {
    if (reminder != null && !reminder.isAfter(DateTime.now())) return;
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
    final updated = _tasks.where((task) => task.id == id).firstOrNull;
    if (updated != null) _syncReminderFor(updated);
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

  static const _attachmentsFolderName = 'attachments';

  /// Picks a file, copies it into the sandbox container's attachments folder
  /// and records the relative name on the task.
  Future<String?> pickNoteAttachment() async {
    final path = await _store.platform.pickAttachmentFile();
    if (path == null) return null;
    return _copyIntoAttachments(path);
  }

  Future<void> revealWorkspaceAttachment(String filename) async {
    final directory = await _store.platform.applicationSupportDirectory();
    if (directory != null)
      await _store.platform.revealInFinder('$directory/attachments/$filename');
  }

  Future<void> attachFileToTask(String taskId) async {
    final picked = await _store.platform.pickAttachmentFile();
    if (picked == null || picked.trim().isEmpty) return;
    final copied = await _copyIntoAttachments(picked);
    if (copied == null) return;
    _replaceTask(
      taskId,
      (task) => task.copyWith(
        attachments: [...task.attachments, copied],
        updatedAt: DateTime.now().toIso8601String(),
      ),
    );
  }

  Future<String?> _copyIntoAttachments(String sourcePath) async {
    try {
      final base = await _store.platform.applicationSupportDirectory();
      if (base == null || base.trim().isEmpty) return null;
      final directory = Directory('$base/$_attachmentsFolderName');
      await directory.create(recursive: true);
      final source = File(sourcePath);
      if (!await source.exists()) return null;
      final name =
          '${DateTime.now().microsecondsSinceEpoch}-${source.uri.pathSegments.last}';
      await source.copy('${directory.path}/$name');
      return name;
    } on Object {
      // The picker was dismissed or the copy failed; nothing to record.
      return null;
    }
  }

  void removeAttachment(String taskId, String fileName) {
    _replaceTask(
      taskId,
      (task) => task.copyWith(
        attachments:
            task.attachments.where((name) => name != fileName).toList(),
        updatedAt: DateTime.now().toIso8601String(),
      ),
    );
  }

  Future<void> revealAttachment(String taskId, String fileName) async {
    final base = await _store.platform.applicationSupportDirectory();
    if (base == null || base.trim().isEmpty) return;
    await _store.platform
        .revealInFinder('$base/$_attachmentsFolderName/$fileName');
  }

  /// Creates a task from a note selection ("会议记录 → 行动项"): the task
  /// lands in the inbox unscheduled and keeps a link back to its source note,
  /// so the loop can close with "执行后回到记录". The note text is untouched.
  String addTaskFromNote(String noteId, String rawTitle) {
    final title = rawTitle.trim();
    final note = _notes
        .cast<NoteItem?>()
        .firstWhere((note) => note?.id == noteId, orElse: () => null);
    final taskTitle = title.isEmpty ? '来自笔记的行动项' : title;
    final now = DateTime.now().toIso8601String();
    final task = TaskItem(
      id: 'task-${_taskSequence.toString().padLeft(2, '0')}',
      title: taskTitle,
      listName: '收集箱',
      bucket: TaskBucket.unscheduled,
      note: note == null ? null : '来自笔记「${note.title}」',
      sourceNoteId: noteId,
      createdAt: now,
      updatedAt: now,
    );
    _taskSequence += 1;
    _tasks = [task, ..._tasks];
    _selectedTaskId = task.id;
    _schedulePersist();
    _notify();
    return task.id;
  }

  /// The source note of a task, for the inspector's 相关笔记 row.
  NoteItem? sourceNoteFor(String taskId) {
    final task = _tasks.cast<TaskItem?>().firstWhere(
          (task) => task?.id == taskId,
          orElse: () => null,
        );
    final noteId = task?.sourceNoteId;
    if (noteId == null) return null;
    for (final note in _notes) {
      if (note.id == noteId && note.deletedAt == null) return note;
    }
    return null;
  }

  /// Tasks generated from (or linked to) a note, with their live completion
  /// status for the note editor's 关联任务 section.
  List<TaskItem> tasksLinkedToNote(String noteId) {
    return List.unmodifiable(
        activeTasks.where((task) => task.sourceNoteId == noteId));
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

  bool renameFolder(String id, String rawName) {
    final name = rawName.trim();
    final current = _folders.where((folder) => folder.id == id).firstOrNull;
    if (current == null ||
        name.isEmpty ||
        _folders.any((folder) => folder.id != id && folder.name == name))
      return false;
    final now = DateTime.now().toIso8601String();
    _folders = _folders
        .map((folder) => folder.id == id
            ? MigrationFolderRecord(
                id: id,
                parentId: folder.parentId,
                name: name,
                sortOrder: folder.sortOrder,
                createdAt: folder.createdAt,
                updatedAt: now)
            : folder)
        .toList();
    _notes = _notes
        .map((note) => note.folderId == id ? note.copyWith(folder: name) : note)
        .toList();
    _schedulePersist();
    _notify();
    return true;
  }

  bool removeFolder(String id) {
    final folder = _folders.where((folder) => folder.id == id).firstOrNull;
    if (folder == null) return false;
    _folders = _folders
        .where((item) => item.id != id)
        .map((item) => item.parentId == id
            ? MigrationFolderRecord(
                id: item.id,
                parentId: folder.parentId,
                name: item.name,
                sortOrder: item.sortOrder,
                createdAt: item.createdAt,
                updatedAt: item.updatedAt)
            : item)
        .toList();
    _notes = _notes
        .map((note) => note.folderId == id
            ? note.copyWith(folder: '未归档', clearFolderId: true)
            : note)
        .toList();
    if (_notesFolderFilter == id) {
      _notesFolderFilter = null;
      _notesUnfiledOnly = true;
    }
    _schedulePersist();
    _notify();
    return true;
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

  void updateNoteRichContent(
      String id, Map<String, dynamic> document, String plainText) {
    final now = DateTime.now().toIso8601String();
    _replaceNote(
        id,
        (note) => note.copyWith(
              contentJson: document,
              plainText: plainText,
              preview: notePreviewFromText(plainText),
              updatedAt: now,
              updatedLabel: '刚刚',
            ));
  }

  void updateNoteBody(String id, String body) {
    final now = DateTime.now().toIso8601String();
    final current = _notes.cast<NoteItem?>().firstWhere(
          (note) => note?.id == id,
          orElse: () => null,
        );
    if (current == null) return;
    // For imported rich notes, preserve the original JSON. A newline-only
    // append can be represented without touching existing links/lists; use
    // the immutable imported source as the baseline so every TextField
    // onChanged callback can rewrite the complete appended suffix. An edit to
    // protected content stays a visible plain-text draft until the user
    // explicitly chooses conversion in the editor.
    final richContent = current.hasPreservedRichContent
        ? appendToRichContent(
            current.originalContentJson ?? current.contentJson ?? {}, body)
        : null;
    final nextContent = current.hasPreservedRichContent
        ? richContent ?? current.contentJson
        : noteContentJsonFromPlainText(body);
    _replaceNote(
        id,
        (note) => note.copyWith(
              preview: notePreviewFromText(body),
              plainText: body,
              contentJson: nextContent,
              updatedLabel: noteUpdatedLabelFor(now),
              updatedAt: now,
            ));
  }

  /// Creates an independently editable plain-text copy after the user has
  /// explicitly chosen conversion. The imported note and its rich source stay
  /// untouched; the new copy becomes selected in the Notes view.
  bool convertNoteToPlainText(String id) {
    final current = _notes.cast<NoteItem?>().firstWhere(
          (note) => note?.id == id,
          orElse: () => null,
        );
    if (current == null || !current.hasPreservedRichContent) return false;
    final body =
        current.plainText ?? notePlainTextFromContentJson(current.contentJson);
    final now = DateTime.now().toIso8601String();
    final copyId = 'note-${_noteSequence.toString().padLeft(2, '0')}';
    _noteSequence += 1;
    final copy = NoteItem(
      id: copyId,
      title: '${current.title}（纯文本副本）',
      preview: notePreviewFromText(body),
      updatedLabel: '刚刚',
      folder: current.folder,
      folderId: current.folderId,
      accent: _accentFor(_notes.length),
      contentJson: noteContentJsonFromPlainText(body),
      plainText: body,
      isFavorite: current.isFavorite,
      createdAt: now,
      updatedAt: now,
    );
    _notes = [copy, ..._notes];
    _selectedNoteId = copyId;
    _view = WorkspaceView.notes;
    _schedulePersist();
    _notify();
    return true;
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
    _selectedTaskId = null;
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

  /// Completes after all writes requested so far have finished. The app can
  /// use this before an explicit quit without making every keystroke await IO.
  Future<void> waitForPendingSaves() => _pendingPersist;

  Future<void> _persistBundle(MigrationBundle bundle, int version) async {
    try {
      await _store.save(bundle);
      // An older write can finish while a newer edit is still queued. It
      // must not make the UI claim that the latest edit is already saved.
      if (version != _persistVersion) return;
      _lastSavedAt = DateTime.now();
      _saveError = null;
      _saveStatus = SaveStatus.saved;
    } on Object catch (error) {
      if (version != _persistVersion) return;
      _saveError = error.toString();
      _saveStatus = SaveStatus.failed;
    }
    _notify();
  }

  void _schedulePersist() {
    // A damaged snapshot pauses persistence: writing starter data over a file
    // we failed to parse could destroy recoverable content. Importing lifts
    // the pause because it is an explicit replacement.
    if (_loadError != null) return;
    _saveStatus = SaveStatus.saving;
    _saveError = null;
    final version = ++_persistVersion;
    final bundle = _snapshot();
    // Keep writes ordered even for custom stores that do not serialize them
    // internally. The error handler starts the next write rather than
    // poisoning the chain after a failed disk operation.
    final operation = _pendingPersist.then<void>(
      (_) => _persistBundle(bundle, version),
      onError: (_) => _persistBundle(bundle, version),
    );
    _pendingPersist = operation.then<void>((_) {}, onError: (_) {});
    _notify();
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
    this.previousDueTimes = const {},
    this.previousListNames = const {},
  });

  final List<String> completedIds;
  final List<String> spawnedIds;
  final Map<String, (String, Map<String, dynamic>?)> recurrenceRules;
  final List<String> removedIds;
  final Map<String, String?> previousDueAts;
  final Map<String, bool> previousDueTimes;
  final Map<String, String> previousListNames;
}
