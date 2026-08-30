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
  work,
  study,
  personal,
}

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
        _tasks = [
          const TaskItem(
            id: 'task-01',
            title: '准备季度产品评审演示文稿',
            listName: '工作',
            bucket: TaskBucket.today,
            timeLabel: '今天 14:00',
            note: '把核心指标、用户反馈和下季度优先级整理成一份清晰的演示。',
            priority: TaskPriority.high,
            subtaskTotal: 3,
            subtaskCompleted: 2,
          ),
          const TaskItem(
            id: 'task-02',
            title: '整理用户反馈：移动端适配问题清单',
            listName: '工作',
            bucket: TaskBucket.today,
            timeLabel: '今天 18:00',
            priority: TaskPriority.medium,
          ),
          const TaskItem(
            id: 'task-03',
            title: '给设计顾问发一封确认邮件',
            listName: '收集箱',
            bucket: TaskBucket.today,
            timeLabel: '今天',
            priority: TaskPriority.low,
          ),
          const TaskItem(
            id: 'task-04',
            title: '核对报销单据并提交财务系统',
            listName: '工作',
            bucket: TaskBucket.overdue,
            timeLabel: '昨天',
            priority: TaskPriority.high,
          ),
          const TaskItem(
            id: 'task-05',
            title: '阅读《设计心理学》第 4 章并做摘录',
            listName: '学习',
            bucket: TaskBucket.later,
            timeLabel: '周日',
            note: '记录三个可以应用到任务列表的交互细节。',
          ),
          const TaskItem(
            id: 'task-06',
            title: '为周末徒步准备一份轻量清单',
            listName: '个人',
            bucket: TaskBucket.later,
            timeLabel: '周六',
            hasAttachment: true,
          ),
          const TaskItem(
            id: 'task-07',
            title: '整理五月份的项目复盘资料',
            listName: '工作',
            bucket: TaskBucket.today,
            completed: true,
            timeLabel: '已完成 09:42',
          ),
        ],
        _notes = [
          NoteItem(
            id: 'note-01',
            title: '季度评审 · 叙事结构',
            preview: '先讲变化，再解释原因，最后把决策留给下一步。',
            updatedLabel: '刚刚',
            folder: '工作笔记',
            accent: ColorValue(0xFFC23377),
          ),
          NoteItem(
            id: 'note-02',
            title: '灵感收集 · 好的空状态',
            preview: '空白不是结束，它应该告诉用户下一步可以做什么。',
            updatedLabel: '昨天',
            folder: '灵感',
            accent: ColorValue(0xFF4F46E5),
          ),
          NoteItem(
            id: 'note-03',
            title: '读书摘录 · 设计心理学',
            preview: '熟悉感来自稳定的反馈，而不是重复的装饰。',
            updatedLabel: '8 月 24 日',
            folder: '学习',
            accent: ColorValue(0xFF0F766E),
          ),
        ],
        _lists = _defaultLists(),
        _folders = _defaultFolders();

  final LocalWorkspaceStore _store;
  List<TaskItem> _tasks;
  List<NoteItem> _notes;
  List<MigrationListRecord> _lists;
  List<MigrationFolderRecord> _folders;
  WorkspaceView _view = WorkspaceView.home;
  String? _selectedListName;
  String? _selectedTaskId = 'task-01';
  String? _lastCompletedTaskId;
  TaskItem? _lastRemovedTask;
  int? _lastRemovedIndex;
  int _completionVersion = 0;
  int _actionVersion = 0;
  String _lastActionMessage = '';
  String _lastActionKind = '';
  int _taskSequence = 8;
  bool _restoredFromDisk = false;

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
        WorkspaceView.notes =>
          false,
      };
  String? get selectedTaskId => _selectedTaskId;
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
      };
  List<TaskItem> get tasks => List.unmodifiable(_tasks);
  List<NoteItem> get notes => List.unmodifiable(_notes);
  List<MigrationListRecord> get lists => List.unmodifiable(_lists);
  List<MigrationFolderRecord> get folders => List.unmodifiable(_folders);
  bool get restoredFromDisk => _restoredFromDisk;

  Future<void> restoreFromDisk() async {
    final snapshot = await _store.load();
    if (snapshot == null) return;
    _applyBundle(snapshot);
    _restoredFromDisk = true;
    notifyListeners();
  }

  Future<MigrationImportSummary> importMigration(MigrationBundle bundle) async {
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
    _restoredFromDisk = true;
    if ((_selectedTaskId == null ||
            _tasks.every((task) => task.id != _selectedTaskId)) &&
        _tasks.isNotEmpty) {
      _selectedTaskId = _tasks.first.id;
    }
    await _store.save(_snapshot());
    notifyListeners();
    return MigrationImportSummary(
      importedTasks: importedTasks.length,
      skippedTasks: bundle.tasks.length - importedTasks.length,
      importedNotes: importedNotes.length,
      skippedNotes: bundle.notes.length - importedNotes.length,
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
    if (_selectedListName != null && _view == WorkspaceView.all) {
      return List.unmodifiable(
          _tasks.where((task) => task.listName == _selectedListName));
    }
    final filtered = switch (_view) {
      WorkspaceView.home => _tasks,
      WorkspaceView.today =>
        _tasks.where((task) => task.bucket != TaskBucket.later),
      WorkspaceView.inbox => _tasks.where((task) => task.listName == '收集箱'),
      WorkspaceView.plan =>
        _tasks.where((task) => task.bucket == TaskBucket.later),
      WorkspaceView.all => _tasks,
      WorkspaceView.completed => _tasks.where((task) => task.completed),
      WorkspaceView.work => _tasks.where((task) => task.listName == '工作'),
      WorkspaceView.study => _tasks.where((task) => task.listName == '学习'),
      WorkspaceView.personal => _tasks.where((task) => task.listName == '个人'),
      WorkspaceView.calendar || WorkspaceView.notes => const <TaskItem>[],
    };
    return List.unmodifiable(filtered);
  }

  int countFor(WorkspaceView destination) {
    return switch (destination) {
      WorkspaceView.home => _tasks
          .where((task) => !task.completed && task.bucket != TaskBucket.later)
          .length,
      WorkspaceView.today => _tasks
          .where((task) => !task.completed && task.bucket != TaskBucket.later)
          .length,
      WorkspaceView.inbox => _tasks
          .where((task) => task.listName == '收集箱' && !task.completed)
          .length,
      WorkspaceView.plan => _tasks
          .where((task) => task.bucket == TaskBucket.later && !task.completed)
          .length,
      WorkspaceView.all => _tasks.where((task) => !task.completed).length,
      WorkspaceView.completed => _tasks.where((task) => task.completed).length,
      WorkspaceView.work =>
        _tasks.where((task) => task.listName == '工作' && !task.completed).length,
      WorkspaceView.study =>
        _tasks.where((task) => task.listName == '学习' && !task.completed).length,
      WorkspaceView.personal =>
        _tasks.where((task) => task.listName == '个人' && !task.completed).length,
      WorkspaceView.calendar || WorkspaceView.notes => 0,
    };
  }

  int countForList(String listName) => _tasks
      .where((task) => task.listName == listName && !task.completed)
      .length;

  bool isListSelected(String listName) =>
      _view == WorkspaceView.all && _selectedListName == listName;

  void selectView(WorkspaceView destination) {
    if (_view == destination && _selectedListName == null) return;
    _view = destination;
    _selectedListName = null;
    final available = visibleTasks;
    if (available.isNotEmpty &&
        !available.any((task) => task.id == _selectedTaskId)) {
      _selectedTaskId = available.first.id;
    }
    notifyListeners();
  }

  void selectList(String listName) {
    final name = listName.trim();
    if (name.isEmpty) return;
    if (_view == WorkspaceView.all && _selectedListName == name) return;
    _view = WorkspaceView.all;
    _selectedListName = name;
    final available = visibleTasks;
    if (available.isNotEmpty) _selectedTaskId = available.first.id;
    notifyListeners();
  }

  void selectTask(String id) {
    if (_selectedTaskId == id) return;
    if (_tasks.every((task) => task.id != id)) return;
    _selectedTaskId = id;
    notifyListeners();
  }

  void moveTaskToToday(String id) {
    final index = _tasks.indexWhere((task) => task.id == id);
    if (index < 0) return;
    final task = _tasks[index];
    _tasks[index] = task.copyWith(
      bucket: TaskBucket.today,
      timeLabel: task.completed ? task.timeLabel : '今天',
    );
    _view = WorkspaceView.today;
    _selectedTaskId = id;
    _schedulePersist();
    notifyListeners();
  }

  void toggleTask(String id) {
    final index = _tasks.indexWhere((task) => task.id == id);
    if (index < 0) return;
    final task = _tasks[index];
    final completing = !task.completed;
    _tasks[index] = task.copyWith(
      completed: completing,
      timeLabel: completing ? '已完成 · 刚刚' : task.timeLabel,
    );
    if (completing) {
      _completionVersion += 1;
      _actionVersion += 1;
      _lastActionKind = 'completion';
      _lastActionMessage = '任务已完成';
    }
    _lastCompletedTaskId = completing ? id : null;
    _schedulePersist();
    notifyListeners();
  }

  bool undoLastCompletion() {
    final id = _lastCompletedTaskId;
    if (id == null) return false;
    final index = _tasks.indexWhere((task) => task.id == id);
    if (index < 0) return false;
    final task = _tasks[index];
    _tasks[index] = task.copyWith(completed: false, timeLabel: '今天');
    _lastCompletedTaskId = null;
    _lastActionKind = '';
    _selectedTaskId = id;
    _schedulePersist();
    notifyListeners();
    return true;
  }

  void removeTask(String id) {
    final index = _tasks.indexWhere((task) => task.id == id);
    if (index < 0) return;
    _lastRemovedTask = _tasks.removeAt(index);
    _lastRemovedIndex = index;
    _lastCompletedTaskId = null;
    _actionVersion += 1;
    _lastActionKind = 'removal';
    _lastActionMessage = '任务已移到废纸篓';
    if (_selectedTaskId == id) {
      _selectedTaskId = _tasks.isEmpty
          ? null
          : _tasks[index.clamp(0, _tasks.length - 1).toInt()].id;
    }
    _schedulePersist();
    notifyListeners();
  }

  bool undoLastAction() {
    if (_lastActionKind == 'completion') return undoLastCompletion();
    if (_lastActionKind != 'removal' ||
        _lastRemovedTask == null ||
        _lastRemovedIndex == null) return false;
    final index = _lastRemovedIndex!.clamp(0, _tasks.length).toInt();
    _tasks.insert(index, _lastRemovedTask!);
    _selectedTaskId = _lastRemovedTask!.id;
    _lastRemovedTask = null;
    _lastRemovedIndex = null;
    _lastActionKind = '';
    _schedulePersist();
    notifyListeners();
    return true;
  }

  bool addTask(String rawTitle,
      {TaskBucket bucket = TaskBucket.today, String listName = '收集箱'}) {
    final title = rawTitle.trim();
    if (title.isEmpty) return false;
    final task = TaskItem(
      id: 'task-${_taskSequence.toString().padLeft(2, '0')}',
      title: title,
      listName: listName,
      bucket: bucket,
      timeLabel: bucket == TaskBucket.today ? '今天' : '稍后',
    );
    _taskSequence += 1;
    _tasks = [task, ..._tasks];
    _selectedTaskId = task.id;
    _schedulePersist();
    notifyListeners();
    return true;
  }

  void updateSelectedTitle(String title) {
    final id = _selectedTaskId;
    if (id == null || title.trim().isEmpty) return;
    final index = _tasks.indexWhere((task) => task.id == id);
    if (index < 0) return;
    _tasks[index] = _tasks[index].copyWith(title: title.trim());
    _schedulePersist();
    notifyListeners();
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
    notifyListeners();
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
    _selectedTaskId = _tasks.isEmpty ? null : _tasks.first.id;
    _selectedListName = null;
    _lastCompletedTaskId = null;
    _lastRemovedTask = null;
    _lastRemovedIndex = null;
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
    unawaited(_store.save(_snapshot()));
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
}
