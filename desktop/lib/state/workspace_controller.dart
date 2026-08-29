import 'package:flutter/foundation.dart';

import '../models/task.dart';

enum WorkspaceView {
  today,
  inbox,
  plan,
  all,
  completed,
  calendar,
  notes,
  work,
  personal,
}

class WorkspaceController extends ChangeNotifier {
  WorkspaceController()
      : _tasks = [
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
        _notes = const [
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
        ];

  List<TaskItem> _tasks;
  final List<NoteItem> _notes;
  WorkspaceView _view = WorkspaceView.today;
  String? _selectedTaskId = 'task-01';
  String? _lastCompletedTaskId;
  TaskItem? _lastRemovedTask;
  int? _lastRemovedIndex;
  int _completionVersion = 0;
  int _actionVersion = 0;
  String _lastActionMessage = '';
  String _lastActionKind = '';
  int _taskSequence = 8;

  WorkspaceView get view => _view;
  String? get selectedTaskId => _selectedTaskId;
  int get completionVersion => _completionVersion;
  int get actionVersion => _actionVersion;
  String get lastActionMessage => _lastActionMessage;
  List<TaskItem> get tasks => List.unmodifiable(_tasks);
  List<NoteItem> get notes => List.unmodifiable(_notes);

  TaskItem? get selectedTask {
    for (final task in _tasks) {
      if (task.id == _selectedTaskId) return task;
    }
    return null;
  }

  List<TaskItem> get visibleTasks {
    final filtered = switch (_view) {
      WorkspaceView.today => _tasks.where((task) => task.bucket != TaskBucket.later),
      WorkspaceView.inbox => _tasks.where((task) => task.listName == '收集箱'),
      WorkspaceView.plan => _tasks.where((task) => task.bucket == TaskBucket.later),
      WorkspaceView.all => _tasks,
      WorkspaceView.completed => _tasks.where((task) => task.completed),
      WorkspaceView.work => _tasks.where((task) => task.listName == '工作'),
      WorkspaceView.personal => _tasks.where((task) => task.listName == '个人'),
      WorkspaceView.calendar || WorkspaceView.notes => const <TaskItem>[],
    };
    return List.unmodifiable(filtered);
  }

  int countFor(WorkspaceView destination) {
    return switch (destination) {
      WorkspaceView.today => _tasks.where((task) => !task.completed && task.bucket != TaskBucket.later).length,
      WorkspaceView.inbox => _tasks.where((task) => task.listName == '收集箱' && !task.completed).length,
      WorkspaceView.plan => _tasks.where((task) => task.bucket == TaskBucket.later && !task.completed).length,
      WorkspaceView.all => _tasks.where((task) => !task.completed).length,
      WorkspaceView.completed => _tasks.where((task) => task.completed).length,
      WorkspaceView.work => _tasks.where((task) => task.listName == '工作' && !task.completed).length,
      WorkspaceView.personal => _tasks.where((task) => task.listName == '个人' && !task.completed).length,
      WorkspaceView.calendar || WorkspaceView.notes => 0,
    };
  }

  void selectView(WorkspaceView destination) {
    if (_view == destination) return;
    _view = destination;
    final available = visibleTasks;
    if (available.isNotEmpty && !available.any((task) => task.id == _selectedTaskId)) {
      _selectedTaskId = available.first.id;
    }
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
      _selectedTaskId = _tasks.isEmpty ? null : _tasks[index.clamp(0, _tasks.length - 1).toInt()].id;
    }
    notifyListeners();
  }

  bool undoLastAction() {
    if (_lastActionKind == 'completion') return undoLastCompletion();
    if (_lastActionKind != 'removal' || _lastRemovedTask == null || _lastRemovedIndex == null) return false;
    final index = _lastRemovedIndex!.clamp(0, _tasks.length).toInt();
    _tasks.insert(index, _lastRemovedTask!);
    _selectedTaskId = _lastRemovedTask!.id;
    _lastRemovedTask = null;
    _lastRemovedIndex = null;
    _lastActionKind = '';
    notifyListeners();
    return true;
  }

  bool addTask(String rawTitle, {TaskBucket bucket = TaskBucket.today, String listName = '收集箱'}) {
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
    notifyListeners();
    return true;
  }

  void updateSelectedTitle(String title) {
    final id = _selectedTaskId;
    if (id == null || title.trim().isEmpty) return;
    final index = _tasks.indexWhere((task) => task.id == id);
    if (index < 0) return;
    _tasks[index] = _tasks[index].copyWith(title: title.trim());
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
    notifyListeners();
  }
}
