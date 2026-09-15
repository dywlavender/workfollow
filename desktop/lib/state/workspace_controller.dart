import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../models/migration.dart';
import '../models/list_color.dart';
import '../models/habit.dart';
import '../models/task.dart';
import '../services/local_workspace_store.dart';
import '../services/notification_service.dart';
import '../services/smart_date_parser.dart';
import '../features/tasks/application/task_actions.dart';
import '../features/tasks/application/task_creator.dart';
import '../features/tasks/application/task_projection.dart';
import '../features/tasks/application/task_selection_controller.dart';
import '../features/tasks/application/task_workspace_ui_state.dart';
import '../features/tasks/domain/task_draft.dart';
import '../features/tasks/domain/task_schedule.dart';
import '../features/tasks/domain/recurrence_engine.dart';

enum WorkspaceView {
  home,
  recent,
  today,
  overdue,
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
  stats,
  matrix,
  board,
  habits,
}

enum MatrixQuadrant {
  doNow,
  schedule,
  delegate,
  later,
}

enum BoardGroupBy { priority, date }

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

class WeeklyReviewSummary {
  const WeeklyReviewSummary({
    required this.completed,
    required this.overdue,
    required this.mostProductiveWeekday,
    required this.weekStart,
    required this.weekEnd,
  });

  final int completed;
  final int overdue;
  final int? mostProductiveWeekday;
  final DateTime weekStart;
  final DateTime weekEnd;

  bool get isEmpty => completed == 0 && overdue == 0;

  String get weekdayLabel {
    final weekday = mostProductiveWeekday;
    if (weekday == null) return '还没有完成记录';
    return '周${const ['一', '二', '三', '四', '五', '六', '日'][weekday - 1]}最高产';
  }
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
        _folders = _defaultFolders(),
        _habits = seedData ? _seedHabits() : [] {
    taskActions = CallbackTaskActions(_dispatchTaskAction);
    taskCreator = TaskCreator(taskActions);
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

  static List<HabitItem> _seedHabits() {
    final now = DateTime.now();
    final today = habitStartOfDay(now);
    final yesterday = today.subtract(const Duration(days: 1));
    return [
      HabitItem(
        id: 'habit-01',
        name: '晨间拉伸',
        icon: 'sun',
        color: '#42A66A',
        schedule: const {1, 2, 3, 4, 5},
        records: {habitDateKey(today), habitDateKey(yesterday)},
        createdAt: now.toIso8601String(),
        updatedAt: now.toIso8601String(),
      ),
      HabitItem(
        id: 'habit-02',
        name: '阅读 20 分钟',
        icon: 'book',
        color: '#5865C8',
        schedule: const {1, 2, 3, 4, 5, 6, 7},
        records: {habitDateKey(yesterday)},
        createdAt: now.toIso8601String(),
        updatedAt: now.toIso8601String(),
      ),
    ];
  }

  final LocalWorkspaceStore _store;
  final ReminderScheduler _reminders;
  final TaskProjection taskProjection = TaskProjection();
  final TaskSelectionController taskSelection = TaskSelectionController();

  /// Ephemeral shell state is kept separate from the persisted task model.
  final TaskWorkspaceUiState taskUiState = TaskWorkspaceUiState();
  late final TaskActions taskActions;
  late final TaskCreator taskCreator;
  List<TaskItem> _tasks;
  List<NoteItem> _notes;
  List<MigrationListRecord> _lists;
  List<MigrationFolderRecord> _folders;
  List<HabitItem> _habits;
  WorkspaceView _view = WorkspaceView.home;
  String? _selectedListName;
  String? _selectedTagName;
  String? _selectedTaskId;
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
  UndoCommand? _lastTaskUndoCommand;
  int _completionVersion = 0;
  int _actionVersion = 0;
  String _lastActionMessage = '';
  String _lastActionKind = '';
  int _taskSequence = 8;
  int _noteSequence = 4;
  int _folderSequence = 4;
  int _habitSequence = 1;
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

  WorkspaceView get view => _view;
  bool get isTaskView => switch (_view) {
        WorkspaceView.recent ||
        WorkspaceView.today ||
        WorkspaceView.overdue ||
        WorkspaceView.inbox ||
        WorkspaceView.plan ||
        WorkspaceView.all ||
        WorkspaceView.completed ||
        WorkspaceView.work ||
        WorkspaceView.study ||
        WorkspaceView.personal =>
          true,
        WorkspaceView.board => true,
        WorkspaceView.stats || WorkspaceView.matrix => false,
        WorkspaceView.habits => false,
        WorkspaceView.home ||
        WorkspaceView.calendar ||
        WorkspaceView.notes ||
        WorkspaceView.trash =>
          false,
      };
  String? get selectedTaskId => taskSelection.selectedTaskId;
  String? get selectedNoteId => _selectedNoteId;
  int get taskOpenVersion => taskUiState.taskOpenVersion;
  int get noteOpenVersion => taskUiState.noteOpenVersion;
  int get completionVersion => _completionVersion;
  int get actionVersion => _actionVersion;
  String get lastActionMessage => _lastActionMessage;
  String? get selectedListName => _selectedListName;
  String? get selectedTagName => _selectedTagName;
  bool get shouldShowWeeklyReview => DateTime.now().weekday <= 3;
  List<HabitItem> get habits => List.unmodifiable(_habits);

  WeeklyReviewSummary get weeklyReview {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final thisMonday = today.subtract(Duration(days: today.weekday - 1));
    final weekStart = thisMonday.subtract(const Duration(days: 7));
    final weekEnd = thisMonday;
    final completionByDay = <int, int>{};
    var completed = 0;
    for (final task in _tasks) {
      if (task.deletedAt != null || !task.completed) continue;
      final value = localDateTimeFromStorage(task.completedAt);
      if (value == null ||
          value.isBefore(weekStart) ||
          !value.isBefore(weekEnd)) {
        continue;
      }
      completed += 1;
      completionByDay[value.weekday] =
          (completionByDay[value.weekday] ?? 0) + 1;
    }
    int? mostProductive;
    for (final entry in completionByDay.entries) {
      if (mostProductive == null ||
          entry.value > (completionByDay[mostProductive] ?? 0) ||
          (entry.value == (completionByDay[mostProductive] ?? 0) &&
              entry.key < mostProductive)) {
        mostProductive = entry.key;
      }
    }
    final overdue = _tasks.where((task) {
      if (task.deletedAt != null || task.completed) return false;
      final due = localDateTimeFromStorage(task.dueAt);
      if (due == null) return false;
      final dueDay = DateTime(due.year, due.month, due.day);
      return dueDay.isBefore(today);
    }).length;
    return WeeklyReviewSummary(
      completed: completed,
      overdue: overdue,
      mostProductiveWeekday: mostProductive,
      weekStart: weekStart,
      weekEnd: weekEnd,
    );
  }

  String get viewTitle {
    if (_view == WorkspaceView.board && _selectedListName != null) {
      return '看板 · $_selectedListName';
    }
    if (_selectedTagName != null) return '标签：$_selectedTagName';
    if (_selectedListName != null) return _selectedListName!;
    return switch (_view) {
      WorkspaceView.home => '首页',
      WorkspaceView.recent => '最近 7 天',
      WorkspaceView.today => '今天',
      WorkspaceView.overdue => '过期',
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
      WorkspaceView.stats => '统计',
      WorkspaceView.matrix => '四象限',
      WorkspaceView.board => '看板',
      WorkspaceView.habits => '习惯',
    };
  }

  LocalWorkspaceStore get workspaceStore => _store;
  MigrationBundle get snapshot => _snapshot();

  List<TaskItem> get tasks => List.unmodifiable(_tasks);
  List<NoteItem> get notes => List.unmodifiable(_notes);

  /// Tasks and notes available to active views. Skipped recurring occurrences
  /// remain persisted for history/undo, but are intentionally not active.
  List<TaskItem> get activeTasks => List.unmodifiable(
      _tasks.where((task) => task.deletedAt == null && !task.isSkipped));
  List<NoteItem> get activeNotes =>
      List.unmodifiable(_notes.where((note) => note.deletedAt == null));
  List<TaskItem> get deletedTasks =>
      List.unmodifiable(_tasks.where((task) => task.deletedAt != null));

  /// Historical records of recurring occurrences that were skipped. They are
  /// kept in the workspace for persistence/undo, but intentionally do not
  /// appear in active projections or the trash.
  List<TaskItem> get skippedTasks =>
      List.unmodifiable(_tasks.where((task) => task.isSkipped));
  List<NoteItem> get deletedNotes =>
      List.unmodifiable(_notes.where((note) => note.deletedAt != null));

  /// TickTick's "最近 7 天" smart list keeps overdue work visible and shows
  /// the next seven calendar days. Unscheduled tasks are intentionally left
  /// out so this view remains a time-based list rather than a second inbox.
  List<TaskItem> get recentTasks =>
      List.unmodifiable(activeTasks.where((task) =>
          !task.completed && _isInRecentWindow(task, now: _dateReference)));

  List<TaskItem> get overdueTasks => List.unmodifiable(activeTasks.where(
      (task) => !task.completed && _isOverdue(task, now: _dateReference)));

  bool _isOverdue(TaskItem task, {DateTime? now}) {
    return taskProjection.isOverdue(task, reference: now ?? _dateReference);
  }

  bool _isInRecentWindow(TaskItem task, {DateTime? now}) {
    return taskProjection.isInRecentWindow(task,
        reference: now ?? _dateReference);
  }

  List<MigrationListRecord> get lists => List.unmodifiable(_lists);
  List<MigrationFolderRecord> get folders => List.unmodifiable(_folders);

  /// Aggregates tags from real task records for the sidebar. Completed tasks
  /// remain discoverable; deleted tasks do not keep stale tag entries alive.
  Map<String, int> allTags() {
    return taskProjection.tagCounts(_tasks);
  }

  int colorValueForList(String listName) {
    final list = _lists.where((item) => item.name == listName).firstOrNull;
    return listColorValueForName(listName, override: list?.color);
  }

  String colorHexForList(String listName) =>
      colorHexFromValue(colorValueForList(listName));

  bool updateListColor(String rawName, String? rawColor) {
    final name = rawName.trim();
    if (name.isEmpty || name == '收集箱') return false;
    final index = _lists.indexWhere((list) => list.name == name);
    if (index < 0) return false;
    final value = colorValueFromHex(rawColor);
    if (value == null) return false;
    final normalized = colorHexFromValue(value);
    final current = _lists[index];
    if (current.color == normalized) return true;
    final updatedLists = List<MigrationListRecord>.from(_lists);
    updatedLists[index] = MigrationListRecord(
      id: current.id,
      name: current.name,
      sortOrder: current.sortOrder,
      protectedList: current.protectedList,
      color: normalized,
      pinned: current.pinned,
    );
    _lists = updatedLists;
    _schedulePersist();
    _notify();
    return true;
  }

  bool toggleListPinned(String rawName) {
    final name = rawName.trim();
    if (name.isEmpty || name == '收集箱') return false;
    final index = _lists.indexWhere((list) => list.name == name);
    if (index < 0) return false;
    final current = _lists[index];
    final updated = List<MigrationListRecord>.from(_lists);
    updated[index] = MigrationListRecord(
      id: current.id,
      name: current.name,
      sortOrder: current.sortOrder,
      protectedList: current.protectedList,
      color: current.color,
      pinned: !current.pinned,
    );
    _lists = updated;
    _schedulePersist();
    _notify();
    return true;
  }

  List<MigrationListRecord> get orderedLists {
    final result = List<MigrationListRecord>.from(_lists);
    result.sort((a, b) {
      if (a.pinned != b.pinned) return a.pinned ? -1 : 1;
      final byOrder = a.sortOrder.compareTo(b.sortOrder);
      return byOrder != 0 ? byOrder : a.name.compareTo(b.name);
    });
    return List.unmodifiable(result);
  }

  bool get restoredFromDisk => _restoredFromDisk;
  SaveStatus get saveStatus => _saveStatus;
  String? get saveError => _saveError;
  DateTime? get lastSavedAt => _lastSavedAt;
  String? get loadError => _loadError;
  String? get notesFolderFilter => _notesFolderFilter;
  bool get notesFavoritesOnly => _notesFavoritesOnly;
  bool get notesUnfiledOnly => _notesUnfiledOnly;
  bool get quickAddFocusPending => taskUiState.quickAddFocusPending;
  int get inspectorTitleFocusVersion => taskUiState.inspectorTitleFocusVersion;

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
    taskUiState.requestQuickAddFocus();
    _notify();
  }

  void consumeQuickAddFocus() {
    taskUiState.consumeQuickAddFocus();
  }

  /// Asks the task inspector to focus its title editor (Return on a task row).
  void requestInspectorTitleFocus() {
    taskUiState.requestInspectorTitleFocus();
    _notify();
  }

  /// Creates a note in the folder the notes view currently shows, so Cmd-N
  /// behaves like the button in the sidebar.
  String addNoteInCurrentFolder() {
    final folderId = _notesUnfiledOnly ? null : _notesFolderFilter;
    final id = addNote(folderId: folderId);
    _selectedNoteId = id;
    taskUiState.markNoteOpened();
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

  void _setSelectedTaskId(String? id) {
    _selectedTaskId = id;
    // A single selection and a Cmd/Shift multi-selection are mutually
    // exclusive. Clearing this in the facade keeps external opens (search,
    // reminders and calendar) from inheriting stale bulk state.
    taskSelection.clearMulti();
    if (id == null) {
      taskSelection.clear();
    } else {
      taskSelection.select(id);
    }
    _syncLegacySelection();
  }

  void _syncLegacySelection() {
    _multiSelectedTaskIds =
        Set<String>.from(taskSelection.multiSelectedTaskIds);
    _multiSelectAnchorId = taskSelection.anchorTaskId;
  }

  TaskItem? _taskById(String id) =>
      _tasks.where((task) => task.id == id).firstOrNull;

  bool _listEquals<T>(List<T> left, List<T> right) {
    if (left.length != right.length) return false;
    for (var i = 0; i < left.length; i++) {
      if (left[i] != right[i]) return false;
    }
    return true;
  }

  bool _mapsEqual(Map<String, dynamic>? left, Map<String, dynamic>? right) {
    if (left == null || right == null) return left == right;
    return mapEquals(left, right);
  }

  TaskDestination _destinationForTask(TaskItem? task) {
    if (task == null || task.deletedAt != null || task.isSkipped) {
      return TaskDestination.hidden;
    }
    if (visibleTasks.any((item) => item.id == task.id)) {
      return TaskDestination.current;
    }
    if (task.completed) return TaskDestination.completed;
    if (task.listName == '收集箱') return TaskDestination.inbox;
    if (task.bucket == TaskBucket.overdue) return TaskDestination.overdue;
    if (task.bucket == TaskBucket.later) return TaskDestination.plan;
    return TaskDestination.list;
  }

  TaskActionResult _taskResult(String id,
      {String? message,
      bool showFeedback = false,
      UndoCommand? undo,
      bool rememberUndo = true}) {
    final task = _taskById(id);
    if (task == null) {
      return TaskActionResult.failure('missing-task', '任务不存在');
    }
    if (rememberUndo) {
      // A new single-task action replaces an older bulk/snapshot command. The
      // next global Undo must always describe the most recent mutation.
      _lastBulkUndo = null;
      _lastTaskUndoCommand = undo;
      _lastActionKind = '';
      _lastCompletedTaskId = null;
      _lastRemovedTaskId = null;
    }
    return TaskActionResult.success(
      taskId: id,
      destination: _destinationForTask(task),
      message: message,
      showFeedback: showFeedback,
      undo: undo,
    );
  }

  bool _restoreTaskSnapshot(TaskItem snapshot) {
    final index = _tasks.indexWhere((task) => task.id == snapshot.id);
    if (index < 0) return false;
    _tasks[index] = snapshot;
    _syncReminderFor(snapshot);
    _schedulePersist();
    _notify();
    return true;
  }

  UndoCommand _undoTaskSnapshot(TaskItem snapshot) {
    late final UndoCommand command;
    command = UndoCommand(
      label: '撤销修改',
      execute: () {
        // A row/inspector may invoke the result's command directly instead of
        // going through the shell toast. Only consume the global slot when it
        // still refers to this exact command; a newer edit must not be lost.
        if (identical(_lastTaskUndoCommand, command)) {
          _lastTaskUndoCommand = null;
        }
        return _restoreTaskSnapshot(snapshot);
      },
    );
    return command;
  }

  /// Completion has side effects beyond the original record: a recurring
  /// task can create a next occurrence and register a second reminder. Keep
  /// the pre-completion snapshot and spawned id in the command so an old toast
  /// can never undo a later property edit.
  UndoCommand _undoCompletion(TaskItem before, String? spawnedId) {
    late final UndoCommand command;
    command = UndoCommand(
      label: '撤销完成',
      execute: () {
        if (identical(_lastTaskUndoCommand, command)) {
          _lastTaskUndoCommand = null;
        }
        return _restoreCompletionSnapshot(before, spawnedId);
      },
    );
    return command;
  }

  bool _restoreCompletionSnapshot(TaskItem before, String? spawnedId) {
    final currentIndex = _tasks.indexWhere((task) => task.id == before.id);
    if (currentIndex < 0 || !_tasks[currentIndex].completed) return false;
    if (spawnedId != null) {
      _tasks.removeWhere((task) => task.id == spawnedId);
      unawaited(_reminders.cancel(spawnedId));
    }
    final writeIndex = _tasks.indexWhere((task) => task.id == before.id);
    if (writeIndex < 0) return false;
    _tasks[writeIndex] = before;
    _lastCompletedTaskId = null;
    _lastRecurrenceSpawnId = null;
    _lastCompletedRecurrenceType = null;
    _lastCompletedRecurrenceConfig = null;
    _lastRemovedTaskId = null;
    _lastActionKind = '';
    _setSelectedTaskId(before.id);
    _syncReminderFor(before);
    _schedulePersist();
    _notify();
    return true;
  }

  /// Builds the inverse of a skip action. A skip is intentionally modelled as
  /// its own state transition instead of completion/deletion: undo therefore
  /// removes only the occurrence generated by the skip and restores the
  /// original record with its recurrence rule intact.
  UndoCommand _undoSkipOccurrence(TaskItem before, String spawnedId) {
    late final UndoCommand command;
    command = UndoCommand(
      label: '撤销跳过本周期',
      execute: () {
        if (identical(_lastTaskUndoCommand, command)) {
          _lastTaskUndoCommand = null;
        }
        final originalIndex = _tasks.indexWhere((task) => task.id == before.id);
        if (originalIndex < 0 || !_tasks[originalIndex].isSkipped) {
          return false;
        }
        _tasks.removeWhere((task) => task.id == spawnedId);
        unawaited(_reminders.cancel(spawnedId));
        final restoredIndex = _tasks.indexWhere((task) => task.id == before.id);
        if (restoredIndex < 0) return false;
        _tasks[restoredIndex] = before;
        _lastActionKind = '';
        _lastActionMessage = '';
        _setSelectedTaskId(before.id);
        _syncReminderFor(before);
        _schedulePersist();
        _notify();
        return true;
      },
    );
    return command;
  }

  UndoCommand _undoDeletion(TaskItem before) {
    late final UndoCommand command;
    command = UndoCommand(
      label: '撤销删除',
      execute: () {
        if (identical(_lastTaskUndoCommand, command)) {
          _lastTaskUndoCommand = null;
        }
        return _restoreDeletedSnapshot(before);
      },
    );
    return command;
  }

  bool _restoreDeletedSnapshot(TaskItem before) {
    final index = _tasks.indexWhere((task) => task.id == before.id);
    if (index < 0 || _tasks[index].deletedAt == null) return false;
    _tasks[index] = before;
    _lastRemovedTaskId = null;
    _lastActionKind = '';
    _setSelectedTaskId(before.id);
    _syncReminderFor(before);
    _schedulePersist();
    _notify();
    return true;
  }

  UndoCommand _undoCreation(String taskId) {
    late final UndoCommand command;
    command = UndoCommand(
      label: '撤销添加',
      execute: () {
        if (identical(_lastTaskUndoCommand, command)) {
          _lastTaskUndoCommand = null;
        }
        final index = _tasks.indexWhere((task) => task.id == taskId);
        if (index < 0) return false;
        unawaited(_reminders.cancel(taskId));
        _tasks.removeAt(index);
        if (_selectedTaskId == taskId) _setSelectedTaskId(null);
        _lastActionKind = '';
        _schedulePersist();
        _notify();
        return true;
      },
    );
    return command;
  }

  UndoCommand _undoBulk(_BulkTaskUndo bulk, String label) {
    late final UndoCommand command;
    command = UndoCommand(
      label: label,
      execute: () {
        if (identical(_lastTaskUndoCommand, command)) {
          _lastTaskUndoCommand = null;
        }
        _revertBulkUndo(bulk);
        return true;
      },
    );
    return command;
  }

  TaskActionResult _dispatchTaskAction(String action, Object? payload) {
    switch (action) {
      case 'create':
        if (payload is! TaskDraft) {
          return TaskActionResult.failure('invalid-draft', '无效的任务草稿');
        }
        return _createTaskFromDraft(payload);
      case 'setTitle':
        final (id, title) = payload as (String, String);
        final before = _taskById(id);
        if (before == null) {
          return TaskActionResult.failure('missing-task', '任务不存在');
        }
        if (title.trim().isEmpty) {
          return TaskActionResult.failure('empty-title', '标题不能为空');
        }
        updateTaskTitle(id, title);
        final after = _taskById(id);
        if (after == before || after?.title == before.title) {
          return TaskActionResult.failure('unchanged', '标题没有变化');
        }
        return _taskResult(id, undo: _undoTaskSnapshot(before));
      case 'setDescription':
        final (id, description) = payload as (String, String);
        final before = _taskById(id);
        if (before == null) {
          return TaskActionResult.failure('missing-task', '任务不存在');
        }
        updateTaskDescription(id, description);
        final after = _taskById(id);
        if (after == before ||
            (after?.description ?? after?.note) ==
                (before.description ?? before.note)) {
          return TaskActionResult.failure('unchanged', '备注没有变化');
        }
        return _taskResult(id, undo: _undoTaskSnapshot(before));
      case 'setContent':
        final (id, document, plainText) =
            payload as (String, Map<String, dynamic>, String);
        final before = _taskById(id);
        if (before == null) {
          return TaskActionResult.failure('missing-task', '任务不存在');
        }
        updateTaskRichContent(id, document, plainText);
        final after = _taskById(id);
        if (after == before ||
            jsonEncode(after?.contentJson) == jsonEncode(before.contentJson) &&
                (after?.description ?? after?.note ?? '') ==
                    (before.description ?? before.note ?? '')) {
          return TaskActionResult.failure('unchanged', '正文没有变化');
        }
        return _taskResult(id, undo: _undoTaskSnapshot(before));
      case 'setSourceNote':
        final (id, noteId) = payload as (String, String?);
        final before = _taskById(id);
        if (before == null) {
          return TaskActionResult.failure('missing-task', '任务不存在');
        }
        if (noteId != null &&
            _notes
                .every((note) => note.id != noteId || note.deletedAt != null)) {
          return TaskActionResult.failure('missing-note', '关联笔记不存在');
        }
        if (before.sourceNoteId == noteId) {
          return TaskActionResult.failure('unchanged', '关联笔记没有变化');
        }
        updateTaskSourceNote(id, noteId);
        return _taskResult(id,
            message: noteId == null ? '已取消关联笔记' : '已关联笔记',
            undo: _undoTaskSnapshot(before));
      case 'complete':
        final id = payload as String;
        final task = _taskById(id);
        if (task == null) {
          return TaskActionResult.failure('missing-task', '任务不存在');
        }
        if (task.completed) {
          return TaskActionResult.failure('already-complete', '任务已经完成');
        }
        toggleTask(id);
        final undo = _undoCompletion(task, _lastRecurrenceSpawnId);
        return _taskResult(id, message: _lastActionMessage, undo: undo);
      case 'skipOccurrence':
        final id = payload as String;
        final task = _taskById(id);
        if (task == null) {
          return TaskActionResult.failure('missing-task', '任务不存在');
        }
        if (task.deletedAt != null || task.isSkipped) {
          return TaskActionResult.failure('hidden-task', '任务当前不可跳过');
        }
        if (task.completed) {
          return TaskActionResult.failure('already-complete', '已完成任务不能跳过周期');
        }
        if (task.recurrenceType.toUpperCase() == 'NONE') {
          return TaskActionResult.failure('not-recurring', '只有重复任务可以跳过本周期');
        }
        final now = DateTime.now();
        final next = _spawnNextRecurrence(task, completedAt: now);
        if (next == null) {
          return TaskActionResult.failure(
              'recurrence-not-supported', '无法计算下一周期');
        }
        _taskSequence += 1;
        final skipped = task.copyWith(
          skippedAt: now.toIso8601String(),
          updatedAt: now.toIso8601String(),
          timeLabel: '已跳过 · 刚刚',
        );
        final index = _tasks.indexWhere((item) => item.id == id);
        if (index < 0) {
          return TaskActionResult.failure('missing-task', '任务不存在');
        }
        _tasks[index] = skipped;
        _tasks = [next, ..._tasks];
        _syncReminderFor(skipped);
        _syncReminderFor(next);
        _setSelectedTaskId(next.id);
        _actionVersion += 1;
        _lastActionKind = 'skipOccurrence';
        _lastActionMessage = '已跳过本周期';
        final undo = _undoSkipOccurrence(task, next.id);
        return _taskResult(id,
            message: _lastActionMessage, showFeedback: true, undo: undo);
      case 'restore':
        final id = payload as String;
        final task = _taskById(id);
        if (task == null) {
          return TaskActionResult.failure('missing-task', '任务不存在');
        }
        if (!task.completed) {
          return TaskActionResult.failure('already-active', '任务尚未完成');
        }
        toggleTask(id);
        return _taskResult(id, message: '任务已恢复', undo: _undoTaskSnapshot(task));
      case 'setSchedule':
        final (id, value) = payload as (String, TaskScheduleDraft);
        final before = _taskById(id);
        if (before == null) {
          return TaskActionResult.failure('missing-task', '任务不存在');
        }
        updateTaskDue(id, value.normalizedDueAt, hasTime: value.hasTime);
        final after = _taskById(id);
        final changed = after?.dueAt != before.dueAt ||
            after?.hasDueTime != before.hasDueTime;
        if (!changed) return TaskActionResult.failure('unchanged', '日期没有变化');
        return _taskResult(id,
            message: '日期已更新', undo: _undoTaskSnapshot(before));
      case 'clearSchedule':
        final id = payload as String;
        final task = _taskById(id);
        if (task == null) {
          return TaskActionResult.failure('missing-task', '任务不存在');
        }
        // A damaged/legacy snapshot can carry `hasDueTime: true` without a
        // due date. Clearing the schedule must repair that flag as well, so
        // the all-day/unscheduled invariant is restored in one action.
        if (task.dueAt == null && task.hasDueTime != true)
          return TaskActionResult.failure('unchanged', '任务没有安排日期');
        updateTaskDue(id, null);
        return _taskResult(id,
            message: '已清除安排日期', undo: _undoTaskSnapshot(task));
      case 'setReminder':
        final (id, reminder) = payload as (String, DateTime?);
        final before = _taskById(id);
        if (before == null) {
          return TaskActionResult.failure('missing-task', '任务不存在');
        }
        if (reminder != null && !reminder.isAfter(DateTime.now())) {
          return TaskActionResult.failure('past-reminder', '提醒时间需要晚于现在');
        }
        updateTaskReminder(id, reminder);
        final after = _taskById(id);
        if (after?.reminderAt == before.reminderAt) {
          return TaskActionResult.failure('unchanged', '提醒没有变化');
        }
        return _taskResult(id,
            message: reminder == null ? '已取消提醒' : '提醒已更新',
            undo: _undoTaskSnapshot(before));
      case 'clearReminder':
        final id = payload as String;
        final before = _taskById(id);
        if (before == null) {
          return TaskActionResult.failure('missing-task', '任务不存在');
        }
        if (before.reminderAt == null) {
          return TaskActionResult.failure('unchanged', '任务没有提醒');
        }
        updateTaskReminder(id, null);
        return _taskResult(id,
            message: '已取消提醒', undo: _undoTaskSnapshot(before));
      case 'setRecurrence':
        final (id, recurrence) = payload as (String, RecurrenceDraft);
        final task = _taskById(id);
        if (task == null) {
          return TaskActionResult.failure('missing-task', '任务不存在');
        }
        final normalized = recurrence.normalized();
        updateTaskRecurrence(id, normalized.type, config: normalized.config);
        final after = _taskById(id);
        if (after?.recurrenceType == task.recurrenceType &&
            _mapsEqual(after?.recurrenceConfig, task.recurrenceConfig)) {
          return TaskActionResult.failure('unchanged', '重复规则没有变化');
        }
        return _taskResult(id,
            message: normalized.enabled ? '重复规则已更新' : '已取消重复',
            undo: _undoTaskSnapshot(task));
      case 'clearRecurrence':
        final id = payload as String;
        final before = _taskById(id);
        if (before == null) {
          return TaskActionResult.failure('missing-task', '任务不存在');
        }
        if (before.recurrenceType == 'NONE') {
          return TaskActionResult.failure('unchanged', '任务没有重复规则');
        }
        updateTaskRecurrence(id, 'NONE');
        return _taskResult(id,
            message: '已取消重复', undo: _undoTaskSnapshot(before));
      case 'setPriority':
        final (id, priority) = payload as (String, TaskPriority);
        final before = _taskById(id);
        if (before == null) {
          return TaskActionResult.failure('missing-task', '任务不存在');
        }
        if (before.priority == priority) {
          return TaskActionResult.failure('unchanged', '优先级没有变化');
        }
        updateTaskPriority(id, priority);
        return _taskResult(id,
            message: priority.label, undo: _undoTaskSnapshot(before));
      case 'moveToList':
        final (id, listName) = payload as (String, String);
        final before = _taskById(id);
        if (before == null) {
          return TaskActionResult.failure('missing-task', '任务不存在');
        }
        if (!moveTaskToList(id, listName)) {
          return TaskActionResult.failure('move-failed', '无法移动任务');
        }
        if (_taskById(id)?.listName == before.listName) {
          return TaskActionResult.failure('unchanged', '任务已经在该清单');
        }
        return _taskResult(id,
            message: '已移动到「${listName.trim()}」',
            undo: _undoTaskSnapshot(before));
      case 'setTags':
        final (id, tags) = payload as (String, List<String>);
        final before = _taskById(id);
        if (before == null) {
          return TaskActionResult.failure('missing-task', '任务不存在');
        }
        final normalizedTags = tags
            .map((tag) => tag.trim())
            .where((tag) => tag.isNotEmpty)
            .toSet()
            .toList();
        if (_listEquals(before.tags, normalizedTags)) {
          return TaskActionResult.failure('unchanged', '标签没有变化');
        }
        updateTaskTags(id, tags);
        return _taskResult(id,
            message: normalizedTags.isEmpty ? '已清除标签' : '标签已更新',
            undo: _undoTaskSnapshot(before));
      case 'setDeadline':
        final (id, deadline) = payload as (String, DateTime?);
        final before = _taskById(id);
        if (before == null) {
          return TaskActionResult.failure('missing-task', '任务不存在');
        }
        updateTaskDeadline(id, deadline);
        final after = _taskById(id);
        if (after?.deadlineAt == before.deadlineAt) {
          return TaskActionResult.failure('unchanged', '截止日期没有变化');
        }
        return _taskResult(id,
            message: deadline == null ? '已清除截止日期' : '截止日期已更新',
            undo: _undoTaskSnapshot(before));
      case 'clearDeadline':
        final id = payload as String;
        final before = _taskById(id);
        if (before == null) {
          return TaskActionResult.failure('missing-task', '任务不存在');
        }
        if (before.deadlineAt == null) {
          return TaskActionResult.failure('unchanged', '任务没有截止日期');
        }
        updateTaskDeadline(id, null);
        return _taskResult(id,
            message: '已清除截止日期', undo: _undoTaskSnapshot(before));
      case 'duplicate':
        final id = payload as String;
        final copyId = duplicateTask(id);
        if (copyId == null)
          return TaskActionResult.failure('duplicate-failed', '无法创建副本');
        return _taskResult(copyId, message: '已创建任务副本', showFeedback: true);
      case 'delete':
        final id = payload as String;
        final before = _taskById(id);
        if (before == null)
          return TaskActionResult.failure('missing-task', '任务不存在');
        removeTask(id);
        return _taskResult(id,
            message: _lastActionMessage, undo: _undoDeletion(before));
      case 'undo':
        return undoLastAction()
            ? const TaskActionResult.success(message: '已撤销')
            : TaskActionResult.failure('nothing-to-undo', '没有可撤销的操作');
      case 'bulkComplete':
        final ids = (payload as List<String>);
        final version = _actionVersion;
        _prepareBulkSelection(ids);
        bulkCompleteSelected();
        if (_actionVersion == version) {
          return TaskActionResult.failure('unchanged', '没有可完成的任务');
        }
        final bulk = _lastBulkUndo;
        final undo = bulk == null ? null : _undoBulk(bulk, '撤销批量完成');
        if (undo != null) _lastTaskUndoCommand = undo;
        return TaskActionResult.success(
            message: _lastActionMessage, undo: undo);
      case 'bulkSchedule':
        final (ids, value) = payload as (List<String>, TaskScheduleDraft);
        final version = _actionVersion;
        _prepareBulkSelection(ids);
        bulkRescheduleSelected(value.normalizedDueAt, hasTime: value.hasTime);
        if (_actionVersion == version) {
          return TaskActionResult.failure('unchanged', '没有可更新日期的任务');
        }
        final bulk = _lastBulkUndo;
        final undo = bulk == null ? null : _undoBulk(bulk, '撤销批量日期');
        if (undo != null) _lastTaskUndoCommand = undo;
        return TaskActionResult.success(
            message: _lastActionMessage, undo: undo);
      case 'bulkMove':
        final (ids, listName) = payload as (List<String>, String);
        final version = _actionVersion;
        _prepareBulkSelection(ids);
        bulkMoveSelectedToList(listName);
        if (_actionVersion == version) {
          return TaskActionResult.failure('unchanged', '没有可移动的任务');
        }
        final bulk = _lastBulkUndo;
        final undo = bulk == null ? null : _undoBulk(bulk, '撤销批量移动');
        if (undo != null) _lastTaskUndoCommand = undo;
        return TaskActionResult.success(
            message: _lastActionMessage, undo: undo);
      case 'bulkDelete':
        final ids = (payload as List<String>);
        final version = _actionVersion;
        _prepareBulkSelection(ids);
        bulkDeleteSelected();
        if (_actionVersion == version) {
          return TaskActionResult.failure('unchanged', '没有可删除的任务');
        }
        final bulk = _lastBulkUndo;
        final undo = bulk == null ? null : _undoBulk(bulk, '撤销批量删除');
        if (undo != null) _lastTaskUndoCommand = undo;
        return TaskActionResult.success(
            message: _lastActionMessage, undo: undo);
      default:
        return TaskActionResult.failure('unknown-action', '不支持的任务操作：$action');
    }
  }

  void _prepareBulkSelection(Iterable<String> ids) {
    _multiSelectedTaskIds = ids.toSet();
    _multiSelectAnchorId = ids.firstOrNull;
    taskSelection.clearMulti();
    taskSelection.multiSelectedTaskIds.addAll(_multiSelectedTaskIds);
    taskSelection.anchorTaskId = _multiSelectAnchorId;
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
    _habits = _mergeHabits(bundle.habits, _habits);
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
    _habitSequence = _nextHabitSequence();
    _restoredFromDisk = true;
    if ((_selectedTaskId == null ||
            _tasks.every((task) => task.id != _selectedTaskId)) &&
        _tasks.isNotEmpty) {
      _setSelectedTaskId(_tasks.first.id);
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
    _habits = bundle.habits.map(HabitItem.fromMigration).toList();
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
    _habitSequence = _nextHabitSequence();
    _restoredFromDisk = true;
    _setSelectedTaskId(null);
    _selectedListName = null;
    _selectedTagName = null;
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
    return taskProjection.needsAttentionToday(task, reference: _dateReference);
  }

  bool matrixImportant(TaskItem task) =>
      task.priority == TaskPriority.high ||
      task.priority == TaskPriority.medium;

  bool matrixUrgent(TaskItem task, {DateTime? now}) {
    final due = localDateTimeFromStorage(task.dueAt);
    if (due == null) return false;
    final reference = now ?? DateTime.now();
    final today = DateTime(reference.year, reference.month, reference.day);
    final dueDay = DateTime(due.year, due.month, due.day);
    final horizon = today.add(const Duration(days: 3));
    return !dueDay.isAfter(horizon);
  }

  MatrixQuadrant matrixQuadrantFor(TaskItem task, {DateTime? now}) {
    final important = matrixImportant(task);
    final urgent = matrixUrgent(task, now: now);
    if (important && urgent) return MatrixQuadrant.doNow;
    if (important) return MatrixQuadrant.schedule;
    if (urgent) return MatrixQuadrant.delegate;
    return MatrixQuadrant.later;
  }

  List<TaskItem> matrixTasks({bool includeCompleted = false}) {
    return List.unmodifiable(_tasks.where((task) =>
        task.deletedAt == null &&
        !task.isSkipped &&
        (includeCompleted || !task.completed)));
  }

  /// Returns the active tasks used by the board projection. The grouping is
  /// intentionally a view concern; the task model remains unchanged.
  List<TaskItem> boardTasks({bool includeCompleted = false}) {
    return List.unmodifiable(_tasks.where((task) =>
        task.deletedAt == null &&
        !task.isSkipped &&
        (_selectedListName == null || task.listName == _selectedListName) &&
        (includeCompleted || !task.completed)));
  }

  String boardColumnFor(TaskItem task, BoardGroupBy grouping) {
    if (grouping == BoardGroupBy.priority) return task.priority.name;
    final due = localDateTimeFromStorage(task.dueAt);
    if (due == null) return 'unscheduled';
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final monday = today.subtract(Duration(days: today.weekday - 1));
    final nextMonday = monday.add(const Duration(days: 7));
    final day = DateTime(due.year, due.month, due.day);
    // Keep overdue work visible in the first column: a kanban should not hide
    // tasks merely because their date crossed the current week's boundary.
    if (day.isBefore(nextMonday)) return 'thisWeek';
    if (day.isBefore(nextMonday.add(const Duration(days: 7))) &&
        !day.isBefore(nextMonday)) return 'nextWeek';
    return 'later';
  }

  /// Maps a board drop back to the minimal task field change. Priority drops
  /// preserve dates; date drops preserve the existing clock time.
  void moveTaskToBoardColumn(String id, BoardGroupBy grouping, String column) {
    final task = _tasks.where((item) => item.id == id).firstOrNull;
    if (task == null || task.deletedAt != null || task.isSkipped) return;
    if (grouping == BoardGroupBy.priority) {
      final priority = TaskPriority.values
          .where((value) => value.name == column)
          .firstOrNull;
      if (priority != null) taskActions.setPriority(id, priority);
      return;
    }
    if (column == 'unscheduled') {
      taskActions.clearSchedule(id);
      return;
    }
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final monday = today.subtract(Duration(days: today.weekday - 1));
    final nextMonday = monday.add(const Duration(days: 7));
    final existing = localDateTimeFromStorage(task.dueAt);
    final clockHour = existing?.hour ?? 0;
    final clockMinute = existing?.minute ?? 0;
    DateTime target;
    switch (column) {
      case 'thisWeek':
        target = DateTime(
            today.year, today.month, today.day, clockHour, clockMinute);
      case 'nextWeek':
        target = nextMonday;
        target = DateTime(
            target.year, target.month, target.day, clockHour, clockMinute);
      case 'later':
        target = nextMonday.add(const Duration(days: 7));
        target = DateTime(
            target.year, target.month, target.day, clockHour, clockMinute);
      default:
        return;
    }
    taskActions.setSchedule(
        id, TaskScheduleDraft(dueAt: target, hasTime: task.scheduledWithTime));
  }

  // -------------------------------------------------------------------------
  // Local habits. Records are local calendar keys and are persisted with the
  // same snapshot as tasks and notes.
  // -------------------------------------------------------------------------

  HabitItem? habitById(String id) =>
      _habits.where((habit) => habit.id == id).firstOrNull;

  int habitStreak(String id, {DateTime? from}) =>
      habitById(id)?.streak(from: from) ?? 0;

  bool isHabitComplete(String id, DateTime day) =>
      habitById(id)?.isCompletedOn(day) ?? false;

  bool toggleHabit(String id, {DateTime? day}) {
    final index = _habits.indexWhere((habit) => habit.id == id);
    if (index < 0) return false;
    final date = habitDateKey(day ?? DateTime.now());
    final records = Set<String>.from(_habits[index].records);
    if (!records.add(date)) records.remove(date);
    final now = DateTime.now().toIso8601String();
    _habits[index] = _habits[index].copyWith(
      records: Set.unmodifiable(records),
      updatedAt: now,
    );
    _schedulePersist();
    _notify();
    return true;
  }

  String? addHabit(String rawName,
      {String icon = 'check', String? color, Set<int>? schedule}) {
    final name = rawName.trim();
    if (name.isEmpty || _habits.any((habit) => habit.name == name)) return null;
    final now = DateTime.now().toIso8601String();
    final id = 'habit-${_habitSequence.toString().padLeft(2, '0')}';
    _habitSequence += 1;
    final habit = HabitItem(
      id: id,
      name: name,
      icon: icon,
      color: color,
      schedule: Set.unmodifiable(schedule ?? {1, 2, 3, 4, 5, 6, 7}),
      createdAt: now,
      updatedAt: now,
    );
    _habits = [..._habits, habit];
    _schedulePersist();
    _notify();
    return id;
  }

  bool updateHabit(String id,
      {String? name, String? icon, String? color, Set<int>? schedule}) {
    final index = _habits.indexWhere((habit) => habit.id == id);
    if (index < 0) return false;
    final nextName = name?.trim();
    if (nextName != null &&
        (nextName.isEmpty ||
            _habits.any((habit) => habit.id != id && habit.name == nextName))) {
      return false;
    }
    _habits[index] = _habits[index].copyWith(
      name: nextName,
      icon: icon,
      color: color,
      schedule: schedule == null ? null : Set.unmodifiable(schedule),
      updatedAt: DateTime.now().toIso8601String(),
    );
    _schedulePersist();
    _notify();
    return true;
  }

  bool removeHabit(String id) {
    final index = _habits.indexWhere((habit) => habit.id == id);
    if (index < 0) return false;
    _habits = [..._habits]..removeAt(index);
    _schedulePersist();
    _notify();
    return true;
  }

  /// Adds one completed focus session to a task. A null task keeps the timer
  /// useful as a general focus clock without inventing a task record.
  void recordFocusSession(String? taskId) {
    if (taskId == null) return;
    _replaceTask(
        taskId,
        (task) => task.copyWith(
              focusCount: task.focusCount + 1,
              updatedAt: DateTime.now().toIso8601String(),
            ));
  }

  Future<void> scheduleFocusNotification(String sessionId, DateTime at) async {
    await _reminders.requestPermission();
    await _reminders.schedule(
      taskId: 'focus-$sessionId',
      title: '专注完成',
      body: '这一轮专注结束了，起来活动一下。',
      at: at,
    );
  }

  Future<void> cancelFocusNotification(String sessionId) =>
      _reminders.cancel('focus-$sessionId');

  /// Applies the smallest predictable change when a task crosses a matrix
  /// boundary. Entering “立即做” schedules today; entering an unimportant
  /// quadrant lowers priority while preserving the task's existing date.
  void moveTaskToMatrix(String id, MatrixQuadrant quadrant) {
    final task = _tasks.where((item) => item.id == id).firstOrNull;
    if (task == null || task.deletedAt != null) return;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    switch (quadrant) {
      case MatrixQuadrant.doNow:
        final due = localDateTimeFromStorage(task.dueAt);
        taskActions.setSchedule(
            id,
            TaskScheduleDraft(
                dueAt: DateTime(today.year, today.month, today.day,
                    due?.hour ?? 0, due?.minute ?? 0),
                hasTime: task.scheduledWithTime));
      case MatrixQuadrant.schedule:
        if (matrixUrgent(task, now: now)) {
          final due = localDateTimeFromStorage(task.dueAt);
          taskActions.setSchedule(
              id,
              TaskScheduleDraft(
                  dueAt: today.add(const Duration(days: 7)).add(Duration(
                      hours: due?.hour ?? 0, minutes: due?.minute ?? 0)),
                  hasTime: task.scheduledWithTime));
        }
      case MatrixQuadrant.delegate:
        if (matrixImportant(task))
          taskActions.setPriority(id, TaskPriority.low);
      case MatrixQuadrant.later:
        if (matrixImportant(task))
          taskActions.setPriority(id, TaskPriority.none);
        if (matrixUrgent(task, now: now)) {
          final due = localDateTimeFromStorage(task.dueAt);
          taskActions.setSchedule(
              id,
              TaskScheduleDraft(
                  dueAt: today.add(const Duration(days: 7)).add(Duration(
                      hours: due?.hour ?? 0, minutes: due?.minute ?? 0)),
                  hasTime: task.scheduledWithTime));
        }
    }
  }

  List<TaskItem> get visibleTasks {
    return taskProjection.visible(
      tasks: _tasks,
      view: _view,
      selectedListName: _selectedListName,
      selectedTagName: _selectedTagName,
      reference: _dateReference,
    );
  }

  /// Tasks whose scheduled date falls on [day], independent of the current
  /// navigation filters, so the calendar never borrows another view's list.
  List<TaskItem> tasksForDay(DateTime day) {
    return taskProjection.forDay(_tasks, day);
  }

  int countFor(WorkspaceView destination) {
    return taskProjection.count(
        tasks: _tasks, view: destination, reference: _dateReference);
  }

  int countForList(String listName) =>
      taskProjection.countForList(_tasks, listName);

  bool isListSelected(String listName) =>
      _view == WorkspaceView.all && _selectedListName == listName;

  void selectView(WorkspaceView destination) {
    if (_view == destination &&
        _selectedListName == null &&
        _selectedTagName == null) return;
    _view = destination;
    _selectedListName = null;
    _selectedTagName = null;
    taskSelection.clearMulti();
    _syncLegacySelection();
    _setSelectedTaskId(null);
    _notify();
  }

  void selectList(String listName) {
    final name = listName.trim();
    if (name.isEmpty) return;
    if (_view == WorkspaceView.all && _selectedListName == name) return;
    _view = WorkspaceView.all;
    _selectedListName = name;
    _selectedTagName = null;
    taskSelection.clearMulti();
    _syncLegacySelection();
    _setSelectedTaskId(null);
    _notify();
  }

  void selectBoard({String? listName}) {
    final name = listName?.trim();
    if (_view == WorkspaceView.board && _selectedListName == name) return;
    _view = WorkspaceView.board;
    _selectedListName = name == null || name.isEmpty ? null : name;
    _selectedTagName = null;
    taskSelection.clearMulti();
    _syncLegacySelection();
    _setSelectedTaskId(null);
    _notify();
  }

  void selectTag(String rawName) {
    final name = rawName.trim();
    if (name.isEmpty || !allTags().containsKey(name)) return;
    if (_view == WorkspaceView.all && _selectedTagName == name) return;
    _view = WorkspaceView.all;
    _selectedTagName = name;
    _selectedListName = null;
    taskSelection.clearMulti();
    _syncLegacySelection();
    _setSelectedTaskId(null);
    _notify();
  }

  void clearTagSelection() {
    if (_selectedTagName == null) return;
    _selectedTagName = null;
    _notify();
  }

  void clearTaskSelection() {
    if (_selectedTaskId == null) return;
    _setSelectedTaskId(null);
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
      final label = taskTimeLabelFor(due,
          completed: task.completed, hasTime: task.scheduledWithTime);
      if (bucket == task.bucket && label == task.timeLabel) return task;
      changed = true;
      return task.copyWith(bucket: bucket, timeLabel: label);
    }).toList();
    if (changed) _notify();
  }

  String? duplicateTask(String id) {
    final source = _tasks.where((task) => task.id == id).firstOrNull;
    if (source == null) return null;
    _lastTaskUndoCommand = null;
    _lastBulkUndo = null;
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
    _setSelectedTaskId(copyId);
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
    _setSelectedTaskId(id);
    _notify();
  }

  /// Moves the selection through the currently visible task projection. This
  /// mirrors the arrow-key workflow in desktop task clients while keeping the
  /// controller as the single source of truth for the inspector selection.
  void selectAdjacentTask(String id, int delta) {
    if (delta == 0) return;
    final visible = visibleTasks.toList();
    final selected = taskSelection.adjacent(
        id, delta, visible.map((task) => task.id).toList(growable: false));
    if (selected == null) return;
    _syncLegacySelection();
    _setSelectedTaskId(selected);
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
    taskUiState.markTaskOpened();
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
    _selectedTagName = null;
    _setSelectedTaskId(id);
    _notify();
  }

  /// Opens a note from search: switches to Notes and selects the exact note,
  /// so editing the second result edits that note and not the first one.
  void openNote(String id) {
    if (_notes.every((note) => note.id != id || note.deletedAt != null)) {
      return;
    }
    _selectedNoteId = id;
    taskUiState.markNoteOpened();
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
      timeLabel: taskTimeLabelFor(due,
          completed: task.completed, hasTime: task.scheduledWithTime),
      updatedAt: now.toIso8601String(),
    );
    _view = WorkspaceView.today;
    _setSelectedTaskId(id);
    _schedulePersist();
    _notify();
  }

  void toggleTask(String id) {
    _lastTaskUndoCommand = null;
    _lastBulkUndo = null;
    final index = _tasks.indexWhere((task) => task.id == id);
    if (index < 0) return;
    final task = _tasks[index];
    if (task.isSkipped) return;
    final completing = !task.completed;
    final now = DateTime.now();
    final nowLabel = now.toIso8601String();
    final due = localDateTimeFromStorage(task.dueAt);
    var updated = task.copyWith(
      completed: completing,
      completedAt: completing ? nowLabel : null,
      clearCompletedAt: !completing,
      updatedAt: nowLabel,
      timeLabel: completing
          ? '已完成 · 刚刚'
          : (taskTimeLabelFor(due, hasTime: task.scheduledWithTime) ?? '未安排'),
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
        _setSelectedTaskId(spawn.id);
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
    final due = localDateTimeFromStorage(task.dueAt);
    final nextDue = RecurrenceEngine.nextOccurrence(task,
        from: due, reference: completedAt);
    if (nextDue == null) return null;

    final recurrenceBase =
        due ?? DateTime(completedAt.year, completedAt.month, completedAt.day);
    final recurrenceDelta = nextDue.difference(recurrenceBase);
    DateTime? shiftedReminder;
    if (task.reminderAt != null) {
      final reminder = localDateTimeFromStorage(task.reminderAt);
      if (reminder != null) {
        shiftedReminder = reminder.add(recurrenceDelta);
      }
    }
    final dueEnd = localDateTimeFromStorage(task.dueEndAt);
    final deadline = localDateTimeFromStorage(task.deadlineAt);
    final now = DateTime.now().toIso8601String();
    return TaskItem(
      id: 'task-${_taskSequence.toString().padLeft(2, '0')}',
      title: task.title,
      listName: task.listName,
      bucket: taskBucketForDate(nextDue),
      timeLabel: taskTimeLabelFor(nextDue, hasTime: task.scheduledWithTime),
      dueAt: nextDue.toIso8601String(),
      dueEndAt: dueEnd?.add(recurrenceDelta).toIso8601String(),
      hasDueTime: task.hasDueTime,
      deadlineAt: deadline?.add(recurrenceDelta).toIso8601String(),
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
      focusCount: task.focusCount,
      createdAt: now,
      updatedAt: now,
    );
  }

  bool undoLastCompletion() {
    _lastTaskUndoCommand = null;
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
      timeLabel:
          taskTimeLabelFor(due, hasTime: task.scheduledWithTime) ?? '未安排',
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
      _setSelectedTaskId(id);
    }
    _syncReminderFor(updated);
    _schedulePersist();
    _notify();
    return true;
  }

  /// Soft-deletes a task: it stays in the workspace with a `deletedAt` mark,
  /// so the trash is persistent and the promise in the undo toast is real.
  void removeTask(String id) {
    _lastTaskUndoCommand = null;
    _lastBulkUndo = null;
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
      _setSelectedTaskId(_nextSelectableTaskId(index));
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
    if (_selectedTaskId == id) _setSelectedTaskId(null);
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
    taskSelection.toggleMulti(id);
    _syncLegacySelection();
    _notify();
  }

  void extendMultiSelectTo(String id) {
    final visible = visibleTasks;
    taskSelection.extendTo(id, visible.map((task) => task.id).toList());
    _syncLegacySelection();
    _notify();
  }

  void selectAllVisibleTasks() {
    taskSelection.clearMulti();
    taskSelection.multiSelectedTaskIds
        .addAll(visibleTasks.map((task) => task.id));
    _syncLegacySelection();
    _notify();
  }

  void clearMultiSelect() {
    if (_multiSelectedTaskIds.isEmpty) return;
    taskSelection.clearMulti();
    _syncLegacySelection();
    _notify();
  }

  void bulkCompleteSelected() {
    if (_multiSelectedTaskIds.isEmpty) return;
    _lastTaskUndoCommand = null;
    _lastBulkUndo = null;
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
      if (task.completed || task.deletedAt != null || task.isSkipped) continue;
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
    _lastTaskUndoCommand = null;
    _lastBulkUndo = null;
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
            : taskTimeLabelFor(due,
                completed: task.completed,
                hasTime: hasTime ?? task.scheduledWithTime),
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
    _lastTaskUndoCommand = null;
    _lastBulkUndo = null;
    _ensureList(listName);
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
    _lastTaskUndoCommand = null;
    _lastBulkUndo = null;
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
      _setSelectedTaskId(null);
    }
    _endBulkSelection();
    _schedulePersist();
    _notify();
  }

  void _endBulkSelection() {
    taskSelection.clearMulti();
    _syncLegacySelection();
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
        timeLabel:
            taskTimeLabelFor(due, hasTime: task.scheduledWithTime) ?? '未安排',
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
            : taskTimeLabelFor(due,
                completed: task.completed,
                hasTime: bulk.previousDueTimes[id] ?? task.scheduledWithTime),
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
    taskActions.setSchedule(
      id,
      TaskScheduleDraft(
          dueAt: DateTime(day.year, day.month, day.day, existing?.hour ?? 0,
              existing?.minute ?? 0),
          hasTime: task.scheduledWithTime),
    );
  }

  bool undoLastAction() {
    final taskUndo = _lastTaskUndoCommand;
    if (taskUndo != null) {
      _lastTaskUndoCommand = null;
      final outcome = taskUndo.execute();
      if (outcome is bool) return outcome;
      // The current action boundary is synchronous even when a future
      // persistence side effect is part of the command. The command has been
      // consumed; its completion will still notify the controller.
      unawaited(outcome);
      return true;
    }
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
      _setSelectedTaskId(_lastRemovedTaskId);
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
  TaskActionResult _createTaskFromDraft(TaskDraft rawDraft) {
    final draft = rawDraft.normalized();
    if (!draft.isValid) {
      return TaskActionResult.failure('empty-title', '请输入任务标题');
    }
    final targetList = (draft.listName ?? _creationListName()).trim();
    if (targetList.isEmpty) {
      return TaskActionResult.failure('invalid-list', '请选择任务清单');
    }
    final current = DateTime.now();
    if (draft.reminderAt != null && !draft.reminderAt!.isAfter(current)) {
      return TaskActionResult.failure('past-reminder', '提醒时间需要晚于现在');
    }
    // A manually entered list is allowed to be created, but this mutation is
    // kept inside the same create transaction instead of calling addList and
    // causing a second persistence/notification cycle.
    _ensureList(targetList);
    final due = draft.forceUnscheduled ? null : draft.schedule.normalizedDueAt;
    final now = current.toIso8601String();
    final task = TaskItem(
      id: 'task-${_taskSequence.toString().padLeft(2, '0')}',
      title: draft.title,
      listName: targetList,
      bucket: taskBucketForDate(due),
      timeLabel: taskTimeLabelFor(due, hasTime: draft.schedule.hasTime),
      dueAt: due?.toIso8601String(),
      hasDueTime: due != null && draft.schedule.hasTime,
      reminderAt: draft.reminderAt?.toIso8601String(),
      recurrenceType: draft.recurrence.type,
      recurrenceConfig: draft.recurrence.config,
      tags: List.unmodifiable(draft.tags),
      note: draft.description,
      description: draft.description,
      createdAt: now,
      updatedAt: now,
      priority: draft.priority,
    );
    _taskSequence += 1;
    _tasks = [task, ..._tasks];
    _setSelectedTaskId(null);
    // Creation is an undoable action even when the task remains in the
    // current projection. Bump the same action version used by completion and
    // deletion so the shell can surface one global undo affordance instead of
    // making the result's command unreachable from the keyboard/menu path.
    _actionVersion += 1;
    _lastActionMessage = '已添加到${task.listName}';
    _syncReminderFor(task);
    _schedulePersist();
    _notify();
    return _taskResult(task.id,
        message: '已添加到${task.listName}', undo: _undoCreation(task.id));
  }

  bool addTask(String rawTitle,
      {String? listName,
      DateTime? dueAt,
      bool forceUnscheduled = false,
      bool? hasTime}) {
    final effectiveDue = forceUnscheduled ? null : dueAt ?? _creationDueDate();
    final result = _createTaskFromDraft(TaskDraft(
      title: rawTitle,
      listName: listName,
      schedule: TaskScheduleDraft(
        dueAt: effectiveDue,
        hasTime: hasTime ??
            (effectiveDue != null &&
                (effectiveDue.hour != 0 || effectiveDue.minute != 0)),
      ),
      forceUnscheduled: forceUnscheduled,
    ));
    return result.success;
  }

  /// Global/menu-bar capture always means "remember this for later". It must
  /// not inherit the page currently visible in the main window.
  bool addTaskToInboxUnscheduled(String rawTitle) => addTask(
        rawTitle,
        listName: '收集箱',
        forceUnscheduled: true,
      );

  /// Shared pipeline for the native menu-bar capture and other one-line
  /// entry points. It intentionally lives in the controller so every surface
  /// applies the same date, recurrence, tag, list and priority semantics. The
  /// ActionResult is returned so callers can render the same destination and
  /// error feedback as the in-window Quick Add field.
  TaskActionResult createTaskFromSmartInput(String rawInput,
      {DateTime? now, bool preferInbox = false}) {
    final input = rawInput.trim();
    if (input.isEmpty) {
      return TaskActionResult.failure('empty-title', '请输入任务标题');
    }
    final result = const SmartDateParser().parse(input, now: now);
    final parsedList = result.listName;
    final existingList =
        parsedList != null && _lists.any((list) => list.name == parsedList)
            ? parsedList
            : null;
    final targetList = preferInbox ? (existingList ?? '收集箱') : existingList;
    final title = const SmartDateParser().titleFromSpans(
        input,
        result.spans.where((span) =>
            span.kind != SmartTokenKind.list || existingList != null));
    if (title.trim().isEmpty) {
      return TaskActionResult.failure('empty-title', '请输入任务标题');
    }
    final draft = TaskDraft(
      title: title,
      listName: targetList,
      schedule: TaskScheduleDraft(
        dueAt: result.dueAt,
        hasTime: result.hasTime,
      ),
      reminderAt: result.hasTime ? result.reminderAt : null,
      recurrence: RecurrenceDraft(
          type: result.recurrenceType, config: result.recurrenceConfig),
      priority: result.priority,
      tags: result.tags,
      forceUnscheduled: preferInbox && result.dueAt == null,
    );
    return taskCreator.create(draft);
  }

  /// Compatibility facade for older native callers that only need an
  /// acceptance bit. New surfaces should use [createTaskFromSmartInput].
  bool addTaskFromSmartInput(String rawInput,
          {DateTime? now, bool preferInbox = false}) =>
      createTaskFromSmartInput(rawInput, now: now, preferInbox: preferInbox)
          .success;

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

  /// Public facade for new callers. Legacy addTask/addTaskFromSmartInput stay
  /// available for migration, while new UI code submits one complete Draft.
  TaskActionResult createTask(TaskDraft draft) => taskCreator.create(draft);

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

  /// Persists the Quill document and its plain-text projection together. The
  /// old description mutator remains for compatibility with imported data and
  /// older callers, but the task editor uses this method exclusively.
  void updateTaskRichContent(
      String id, Map<String, dynamic> document, String rawPlainText) {
    final plainText = rawPlainText.trimRight();
    _replaceTask(
      id,
      (task) => plainText.trim().isEmpty
          ? task.copyWith(
              contentJson: document,
              note: null,
              clearNote: true,
              description: null,
              clearDescription: true,
              updatedAt: DateTime.now().toIso8601String(),
            )
          : task.copyWith(
              contentJson: document,
              note: plainText,
              description: plainText,
              updatedAt: DateTime.now().toIso8601String(),
            ),
    );
  }

  bool updateTaskSourceNote(String id, String? noteId) {
    if (noteId != null &&
        _notes.every((note) => note.id != noteId || note.deletedAt != null)) {
      return false;
    }
    return _replaceTask(
      id,
      (task) => noteId == null
          ? task.copyWith(
              sourceNoteId: null,
              clearSourceNoteId: true,
              updatedAt: DateTime.now().toIso8601String(),
            )
          : task.copyWith(
              sourceNoteId: noteId,
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
        // A missing date is always unscheduled. Never persist an orphaned
        // `hasDueTime` flag from a malformed picker/action payload.
        hasDueTime: normalized == null
            ? false
            : hasTime ?? (normalized.hour != 0 || normalized.minute != 0),
        bucket: taskBucketForDate(normalized, completed: task.completed),
        timeLabel: normalized == null
            ? (task.completed ? '已完成' : '未安排')
            : taskTimeLabelFor(normalized,
                completed: task.completed,
                hasTime: hasTime ??
                    (normalized.hour != 0 || normalized.minute != 0)),
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
        !task.isSkipped &&
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
    final recurrence = RecurrenceDraft(type: type, config: config).normalized();
    _replaceTask(
      id,
      (task) => task.copyWith(
        recurrenceType: recurrence.type,
        recurrenceConfig: recurrence.config,
        clearRecurrenceConfig: recurrence.config == null,
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

  bool renameTag(String rawOldName, String rawNewName) {
    final oldName = rawOldName.trim();
    final newName = rawNewName.trim();
    if (oldName.isEmpty || newName.isEmpty || oldName == newName) return false;
    if (!allTags().containsKey(oldName) || allTags().containsKey(newName)) {
      return false;
    }
    _tasks = _tasks
        .map((task) => task.tags.contains(oldName)
            ? task.copyWith(
                tags: task.tags
                    .map((tag) => tag == oldName ? newName : tag)
                    .toSet()
                    .toList(),
                updatedAt: DateTime.now().toIso8601String())
            : task)
        .toList();
    if (_selectedTagName == oldName) _selectedTagName = newName;
    _schedulePersist();
    _notify();
    return true;
  }

  bool deleteTag(String rawName) {
    final name = rawName.trim();
    if (name.isEmpty || !allTags().containsKey(name)) return false;
    _tasks = _tasks
        .map((task) => task.tags.contains(name)
            ? task.copyWith(
                tags: task.tags.where((tag) => tag != name).toList(),
                updatedAt: DateTime.now().toIso8601String())
            : task)
        .toList();
    if (_selectedTagName == name) {
      _selectedTagName = null;
      _view = WorkspaceView.all;
    }
    _schedulePersist();
    _notify();
    return true;
  }

  bool moveTaskToList(String id, String rawListName) {
    final listName = rawListName.trim();
    final index = _tasks.indexWhere((task) => task.id == id);
    if (listName.isEmpty || index < 0) return false;
    if (_tasks[index].listName == listName) return true;
    // Keep list creation and task movement in one transaction. Calling the
    // public addList() here would persist and notify once for the list and a
    // second time for the task, which makes a single Action observable as two
    // changes by the UI.
    _ensureList(listName);
    _tasks[index] = _tasks[index].copyWith(
      listName: listName,
      updatedAt: DateTime.now().toIso8601String(),
    );
    if (_selectedTaskId == id &&
        isTaskView &&
        !visibleTasks.any((task) => task.id == id)) {
      _setSelectedTaskId(null);
    }
    _schedulePersist();
    _notify();
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
    await pickTaskAttachment(taskId);
  }

  /// Picks and copies an attachment for a task, returning the workspace-local
  /// filename so a document editor can insert a matching attachment block.
  Future<String?> pickTaskAttachment(String taskId) async {
    final picked = await _store.platform.pickAttachmentFile();
    if (picked == null || picked.trim().isEmpty) return null;
    final copied = await _copyIntoAttachments(picked);
    if (copied == null) return null;
    _replaceTask(
      taskId,
      (task) => task.copyWith(
        attachments: [...task.attachments, copied],
        updatedAt: DateTime.now().toIso8601String(),
      ),
    );
    return copied;
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
    _setSelectedTaskId(task.id);
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
                color: list.color,
                pinned: list.pinned,
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
    if (name.isEmpty || !_ensureList(name)) return false;
    _schedulePersist();
    _notify();
    return true;
  }

  /// Adds a list without persistence or notification. Callers that already
  /// own a larger task transaction use this helper to avoid split updates.
  bool _ensureList(String name) {
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
    _setSelectedTaskId(draggedId);
    _schedulePersist();
    _notify();
  }

  void _applyBundle(MigrationBundle bundle) {
    _lists = List<MigrationListRecord>.from(bundle.lists);
    _folders = List<MigrationFolderRecord>.from(bundle.folders);
    _habits = bundle.habits.map(HabitItem.fromMigration).toList();
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
    _habitSequence = _nextHabitSequence();
    _setSelectedTaskId(null);
    _selectedListName = null;
    _selectedTagName = null;
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
      habits: _habits.map((habit) => habit.toMigrationRecord()).toList(),
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

  List<HabitItem> _mergeHabits(
      List<MigrationHabitRecord> incoming, List<HabitItem> existing) {
    final merged = List<HabitItem>.from(existing);
    final ids = merged.map((habit) => habit.id).toSet();
    final names = merged.map((habit) => habit.name).toSet();
    for (final record in incoming) {
      if (!ids.add(record.id) || !names.add(record.name)) continue;
      merged.add(HabitItem.fromMigration(record));
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

  int _nextHabitSequence() {
    var highest = 0;
    final pattern = RegExp(r'habit-(\d+)$');
    for (final habit in _habits) {
      final match = pattern.firstMatch(habit.id);
      final value = match == null ? 0 : int.tryParse(match.group(1)!) ?? 0;
      if (value > highest) highest = value;
    }
    return highest + 1;
  }

  bool _replaceTask(String id, TaskItem Function(TaskItem task) update) {
    final index = _tasks.indexWhere((task) => task.id == id);
    if (index < 0) return false;
    _tasks[index] = update(_tasks[index]);
    // Any property mutation may change the current projection (date, list,
    // tag or deadline). Clear an inspector that would otherwise keep showing
    // a task no longer present in the selected view; ActionResult still
    // reports the new destination for an explicit reopen.
    if (_selectedTaskId == id &&
        isTaskView &&
        !visibleTasks.any((task) => task.id == id)) {
      _setSelectedTaskId(null);
    }
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
