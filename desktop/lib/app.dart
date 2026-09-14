import 'dart:async';
import 'dart:ui' show AppExitResponse;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_quill/flutter_quill.dart'
    show FlutterQuillLocalizations;

import 'screens/calendar_screen.dart';
import 'screens/board_screen.dart';
import 'screens/habits_screen.dart';
import 'screens/home_screen.dart';
import 'screens/matrix_screen.dart';
import 'screens/notes_screen.dart';
import 'screens/stats_screen.dart';
import 'screens/today_screen.dart';
import 'screens/trash_screen.dart';
import 'models/task.dart';
import 'services/preferences_store.dart';
import 'services/local_workspace_store.dart';
import 'services/focus_timer.dart';
import 'state/workspace_controller.dart';
import 'theme/workfollow_theme.dart';
import 'widgets/app_icon_button.dart';
import 'widgets/command_palette.dart';
import 'widgets/sidebar.dart';
import 'widgets/settings_panel.dart';
import 'widgets/focus_timer_dialog.dart';

class WorkFollowApp extends StatefulWidget {
  const WorkFollowApp(
      {super.key, this.preferencesStore, this.demoMode = false});

  final bool demoMode;

  /// Injectable so tests can point persistence at a temp directory.
  final WorkspacePreferencesStore? preferencesStore;

  @override
  State<WorkFollowApp> createState() => _WorkFollowAppState();
}

class _WorkFollowAppState extends State<WorkFollowApp> {
  ThemeMode _themeMode = ThemeMode.system;
  bool _compactDensity = false;
  // Keep the TickTick-style inspector opt-in. The list remains the primary
  // surface until a task is selected, while power users can pin details on
  // wide windows from Settings.
  // The task inspector is a fixed pane in the macOS task workspace, matching
  // TickTick. Settings can still opt out for a list-only workflow.
  bool _persistentInspector = true;
  late final WorkspacePreferencesStore _preferencesStore;

  @override
  void initState() {
    super.initState();
    _preferencesStore = widget.preferencesStore ??
        WorkspacePreferencesStore(
          platform:
              LocalWorkspaceStore(namespace: widget.demoMode ? 'preview' : null)
                  .platform,
        );
    unawaited(_restoreThemeMode());
  }

  Future<void> _restoreThemeMode() async {
    final preferences = await _preferencesStore.load();
    final saved = preferences['themeMode'];
    if (!mounted) return;
    final mode = saved is String
        ? ThemeMode.values.where((value) => value.name == saved).firstOrNull
        : null;
    final density = preferences['density'];
    final inspector = preferences['inspector'];
    if (mode != null || density is String || inspector is bool) {
      setState(() {
        if (mode != null) _themeMode = mode;
        if (density is String) _compactDensity = density == 'compact';
        if (inspector is bool) _persistentInspector = inspector;
      });
    }
  }

  void _setThemeMode(ThemeMode mode) {
    setState(() => _themeMode = mode);
    unawaited(_preferencesStore.save({
      'themeMode': mode.name,
      'density': _compactDensity ? 'compact' : 'comfortable',
      'inspector': _persistentInspector,
    }));
  }

  void _setDensity(bool compact) {
    setState(() => _compactDensity = compact);
    unawaited(_preferencesStore.save({
      'themeMode': _themeMode.name,
      'density': compact ? 'compact' : 'comfortable',
      'inspector': _persistentInspector,
    }));
  }

  void _setPersistentInspector(bool enabled) {
    setState(() => _persistentInspector = enabled);
    unawaited(_preferencesStore.save({
      'themeMode': _themeMode.name,
      'density': _compactDensity ? 'compact' : 'comfortable',
      'inspector': enabled,
    }));
  }

  void _toggleTheme() {
    // Quick light/dark flip; 跟随系统 stays available in Settings.
    _setThemeMode(
        _themeMode == ThemeMode.dark ? ThemeMode.light : ThemeMode.dark);
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '打勾',
      locale: const Locale('zh', 'CN'),
      supportedLocales: const [Locale('zh', 'CN'), Locale('en', 'US')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        FlutterQuillLocalizations.delegate
      ],
      debugShowCheckedModeBanner: false,
      theme: WorkFollowThemeData.light(),
      darkTheme: WorkFollowThemeData.dark(),
      themeMode: _themeMode,
      home: WorkFollowShell(
        demoMode: widget.demoMode,
        onToggleTheme: _toggleTheme,
        onSetThemeMode: _setThemeMode,
        themeMode: _themeMode,
        compactDensity: _compactDensity,
        onSetDensity: _setDensity,
        persistentInspector: _persistentInspector,
        onSetPersistentInspector: _setPersistentInspector,
      ),
    );
  }
}

class WorkFollowShell extends StatefulWidget {
  const WorkFollowShell({
    super.key,
    required this.onToggleTheme,
    required this.onSetThemeMode,
    required this.themeMode,
    this.compactDensity = false,
    this.onSetDensity,
    this.persistentInspector = true,
    this.onSetPersistentInspector,
    this.demoMode = false,
  });

  final VoidCallback onToggleTheme;
  final ValueChanged<ThemeMode> onSetThemeMode;
  final ThemeMode themeMode;
  final bool compactDensity;
  final ValueChanged<bool>? onSetDensity;
  final bool persistentInspector;
  final ValueChanged<bool>? onSetPersistentInspector;
  final bool demoMode;

  @override
  State<WorkFollowShell> createState() => _WorkFollowShellState();
}

/// Command names sent by the native menu bar over `workfollow/menu`. They map
/// to the same handlers as the in-app keyboard shortcuts.
const _menuChannel = MethodChannel('workfollow/menu');

/// Quick-capture text from the menu bar panel / global hotkey.
const _captureChannel = MethodChannel('workfollow/capture');

class _WorkFollowShellState extends State<WorkFollowShell> {
  late final WorkspaceController controller;
  late final FocusTimerController focusTimer;
  late final AppLifecycleListener _lifecycleListener;
  Timer? _dateRefresh;
  bool sidebarCollapsed = false;
  bool showUndo = false;
  String undoMessage = '';
  int lastSeenActionVersion = 0;

  @override
  void initState() {
    super.initState();
    controller = WorkspaceController(
        seedData: widget.demoMode,
        store:
            LocalWorkspaceStore(namespace: widget.demoMode ? 'preview' : null));
    focusTimer = FocusTimerController(
      scheduleNotification: controller.scheduleFocusNotification,
      cancelNotification: controller.cancelFocusNotification,
      onCompleted: (taskId) {
        controller.recordFocusSession(taskId);
        if (mounted) {
          ScaffoldMessenger.of(context)
              .showSnackBar(const SnackBar(content: Text('这一轮专注完成了，休息一下吧。')));
        }
      },
    );
    if (!widget.demoMode) controller.selectView(WorkspaceView.today);
    if (!widget.demoMode)
      _dateRefresh = Timer.periodic(
          const Duration(minutes: 1), (_) => controller.refreshDates());
    controller.addListener(_observeAction);
    _lifecycleListener = AppLifecycleListener(
      onExitRequested: _handleExitRequested,
      onResume: controller.refreshDates,
    );
    unawaited(controller.restoreFromDisk());
    // The native menu bar routes its command items here.
    _menuChannel.setMethodCallHandler((call) async {
      if (call.method == 'command') {
        _handleMenuCommand(call.arguments as String?);
      }
      return null;
    });
    // Menu bar quick capture is independent of the current page. Explicit
    // smart-entry list markers still win; otherwise it lands in the inbox.
    _captureChannel.setMethodCallHandler((call) async {
      if (call.method == 'quickCapture' && call.arguments is String) {
        // Native quick capture is deliberately independent of the main
        // window's current page and returns an explicit acknowledgement so
        // the native panel only clears text after a successful write request.
        final result = controller.createTaskFromSmartInput(
            call.arguments as String,
            preferInbox: true);
        await controller.waitForPendingSaves();
        return result.success && controller.saveStatus == SaveStatus.saved;
      }
      return null;
    });
  }

  void _handleMenuCommand(String? name) {
    switch (name) {
      case 'newTask':
        _newTask();
      case 'newNote':
        _newNote();
      case 'search':
        _openCommandPalette();
      case 'settings':
        _openSettings();
      case 'toggleSidebar':
        setState(() => sidebarCollapsed = !sidebarCollapsed);
      case 'goToday':
        controller.selectView(WorkspaceView.today);
      case 'goRecent':
        controller.selectView(WorkspaceView.recent);
      case 'goOverdue':
        controller.selectView(WorkspaceView.overdue);
      case 'goAll':
        controller.selectView(WorkspaceView.all);
      case 'goCompleted':
        controller.selectView(WorkspaceView.completed);
      case 'goInbox':
        controller.selectView(WorkspaceView.inbox);
      case 'goPlan':
        controller.selectView(WorkspaceView.plan);
      case 'goCalendar':
        controller.selectView(WorkspaceView.calendar);
      case 'goNotes':
        controller.selectView(WorkspaceView.notes);
      case 'goStats':
        controller.selectView(WorkspaceView.stats);
      case 'goMatrix':
        controller.selectView(WorkspaceView.matrix);
      case 'goBoard':
        controller.selectView(WorkspaceView.board);
      case 'goHabits':
        controller.selectView(WorkspaceView.habits);
      case 'startPomodoro':
        _openFocusTimer();
      case 'completeSelected':
        final id = controller.selectedTaskId;
        if (id != null) {
          final task = controller.selectedTask;
          if (task != null) {
            task.completed
                ? controller.taskActions.restore(id)
                : controller.taskActions.complete(id);
          }
        }
      case 'clearSelectedDate':
        final id = controller.selectedTaskId;
        if (id != null) controller.taskActions.clearSchedule(id);
      case 'priorityHigh':
        final id = controller.selectedTaskId;
        if (id != null)
          controller.taskActions.setPriority(id, TaskPriority.high);
      case 'priorityMedium':
        final id = controller.selectedTaskId;
        if (id != null)
          controller.taskActions.setPriority(id, TaskPriority.medium);
      case 'priorityLow':
        final id = controller.selectedTaskId;
        if (id != null)
          controller.taskActions.setPriority(id, TaskPriority.low);
      case 'priorityNone':
        final id = controller.selectedTaskId;
        if (id != null)
          controller.taskActions.setPriority(id, TaskPriority.none);
    }
  }

  void _observeAction() {
    if (!mounted || controller.actionVersion == lastSeenActionVersion) return;
    lastSeenActionVersion = controller.actionVersion;
    _showUndo(controller.lastActionMessage);
  }

  Future<AppExitResponse> _handleExitRequested() async {
    await controller.waitForPendingSaves();
    return AppExitResponse.exit;
  }

  @override
  void dispose() {
    _dateRefresh?.cancel();
    _lifecycleListener.dispose();
    controller.removeListener(_observeAction);
    focusTimer.dispose();
    controller.dispose();
    super.dispose();
  }

  void _openCommandPalette() {
    showCommandPalette(
        context: context,
        controller: controller,
        onToggleTheme: widget.onToggleTheme);
  }

  void _newTask() {
    // Cmd-N creates in the current context: notes get a note in the shown
    // folder, task views focus their quick add field, and views without an
    // inline field fall back to Today.
    if (controller.view == WorkspaceView.notes) {
      controller.addNoteInCurrentFolder();
      return;
    }
    if (!controller.isTaskView && controller.view != WorkspaceView.home) {
      controller.selectView(WorkspaceView.today);
    }
    controller.requestQuickAddFocus();
  }

  void _newNote() {
    // Cmd-Shift-N always creates a note, wherever the user is.
    if (controller.view != WorkspaceView.notes) {
      controller.selectView(WorkspaceView.notes);
    }
    controller.addNoteInCurrentFolder();
  }

  Future<void> _openSettings() async {
    await showSettingsPanel(
        context: context,
        controller: controller,
        onToggleTheme: widget.onToggleTheme,
        onSetThemeMode: widget.onSetThemeMode,
        themeMode: widget.themeMode,
        compactDensity: widget.compactDensity,
        onSetDensity: widget.onSetDensity,
        persistentInspector: widget.persistentInspector,
        onSetPersistentInspector: widget.onSetPersistentInspector);
  }

  Future<void> _openFocusTimer() => showFocusTimerDialog(
        context: context,
        timer: focusTimer,
        controller: controller,
      );

  Future<void> _openFilters() async {
    final tokens = WorkFollowTheme.of(context);
    final destination = await showModalBottomSheet<WorkspaceView>(
      context: context,
      backgroundColor: tokens.overlay,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text('切换任务视图',
                    style: TextStyle(
                        color: tokens.textPrimary,
                        fontWeight: FontWeight.w700)),
              ),
            ),
            for (final option in const <(WorkspaceView, String)>[
              (WorkspaceView.recent, '最近 7 天'),
              (WorkspaceView.today, '今天'),
              (WorkspaceView.overdue, '过期'),
              (WorkspaceView.inbox, '收集箱'),
              (WorkspaceView.plan, '计划'),
              (WorkspaceView.all, '全部任务'),
              (WorkspaceView.completed, '已完成'),
              (WorkspaceView.matrix, '四象限'),
              (WorkspaceView.board, '看板'),
              (WorkspaceView.habits, '习惯'),
              (WorkspaceView.stats, '统计'),
            ])
              ListTile(
                leading: Icon(
                    option.$1 == controller.view
                        ? Icons.radio_button_checked
                        : Icons.radio_button_off,
                    color: option.$1 == controller.view
                        ? tokens.accent
                        : tokens.textTertiary),
                title: Text(option.$2),
                onTap: () => Navigator.of(sheetContext).pop(option.$1),
              ),
          ],
        ),
      ),
    );
    if (destination != null) controller.selectView(destination);
  }

  void _showUndo(String message) {
    setState(() {
      undoMessage = message;
      showUndo = true;
    });
    Future<void>.delayed(const Duration(seconds: 5), () {
      if (mounted) setState(() => showUndo = false);
    });
  }

  void _handleGlobalEscape() {
    // Nested editors and popovers receive Escape first. Once those surfaces
    // are closed, the shell follows TickTick's predictable unwind order:
    // clear multi-selection, then close the fixed inspector, then release any
    // remaining focus.
    if (controller.multiSelectCount > 0) {
      controller.clearMultiSelect();
      return;
    }
    if (controller.selectedTaskId != null) {
      controller.clearTaskSelection();
      return;
    }
    FocusManager.instance.primaryFocus?.unfocus();
  }

  String get _viewTitle {
    // The task list owns its own TickTick-style title row. Leaving this slot
    // empty avoids rendering a redundant "任务" label above it.
    if (controller.isTaskView) return '';
    return controller.viewTitle;
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final tokens = WorkFollowTheme.of(context);
        return Shortcuts(
          shortcuts: const <ShortcutActivator, Intent>{
            SingleActivator(LogicalKeyboardKey.keyN, meta: true):
                NewTaskIntent(),
            SingleActivator(LogicalKeyboardKey.keyN, meta: true, shift: true):
                NewNoteIntent(),
            SingleActivator(LogicalKeyboardKey.keyK, meta: true):
                SearchIntent(),
            SingleActivator(LogicalKeyboardKey.comma, meta: true):
                SettingsIntent(),
            SingleActivator(LogicalKeyboardKey.digit1, meta: true):
                TodayIntent(),
            SingleActivator(LogicalKeyboardKey.digit9, meta: true):
                RecentIntent(),
            SingleActivator(LogicalKeyboardKey.digit2, meta: true):
                InboxIntent(),
            SingleActivator(LogicalKeyboardKey.digit3, meta: true):
                PlanIntent(),
            SingleActivator(LogicalKeyboardKey.digit4, meta: true):
                CalendarIntent(),
            SingleActivator(LogicalKeyboardKey.digit5, meta: true):
                NotesIntent(),
            SingleActivator(LogicalKeyboardKey.digit6, meta: true):
                MatrixIntent(),
            SingleActivator(LogicalKeyboardKey.digit7, meta: true):
                BoardIntent(),
            SingleActivator(LogicalKeyboardKey.digit8, meta: true):
                HabitsIntent(),
          },
          child: Actions(
            actions: <Type, Action<Intent>>{
              NewTaskIntent: CallbackAction<Intent>(onInvoke: (_) {
                _newTask();
                return null;
              }),
              NewNoteIntent: CallbackAction<Intent>(onInvoke: (_) {
                _newNote();
                return null;
              }),
              SearchIntent: CallbackAction<Intent>(onInvoke: (_) {
                _openCommandPalette();
                return null;
              }),
              SettingsIntent: CallbackAction<Intent>(onInvoke: (_) {
                _openSettings();
                return null;
              }),
              TodayIntent: CallbackAction<Intent>(onInvoke: (_) {
                controller.selectView(WorkspaceView.today);
                return null;
              }),
              RecentIntent: CallbackAction<Intent>(onInvoke: (_) {
                controller.selectView(WorkspaceView.recent);
                return null;
              }),
              InboxIntent: CallbackAction<Intent>(onInvoke: (_) {
                controller.selectView(WorkspaceView.inbox);
                return null;
              }),
              PlanIntent: CallbackAction<Intent>(onInvoke: (_) {
                controller.selectView(WorkspaceView.plan);
                return null;
              }),
              CalendarIntent: CallbackAction<Intent>(onInvoke: (_) {
                controller.selectView(WorkspaceView.calendar);
                return null;
              }),
              NotesIntent: CallbackAction<Intent>(onInvoke: (_) {
                controller.selectView(WorkspaceView.notes);
                return null;
              }),
              MatrixIntent: CallbackAction<Intent>(onInvoke: (_) {
                controller.selectView(WorkspaceView.matrix);
                return null;
              }),
              BoardIntent: CallbackAction<Intent>(onInvoke: (_) {
                controller.selectView(WorkspaceView.board);
                return null;
              }),
              HabitsIntent: CallbackAction<Intent>(onInvoke: (_) {
                controller.selectView(WorkspaceView.habits);
                return null;
              }),
            },
            child: CallbackShortcuts(
              bindings: {
                const SingleActivator(LogicalKeyboardKey.escape):
                    _handleGlobalEscape,
              },
              child: Scaffold(
                backgroundColor: tokens.canvas,
                body: Stack(
                  children: [
                    Row(
                      children: [
                        ClipRect(
                          child: AnimatedAlign(
                            duration: const Duration(milliseconds: 220),
                            curve: Curves.easeOutCubic,
                            alignment: Alignment.centerLeft,
                            widthFactor: sidebarCollapsed ? 0 : 1,
                            child: AppRail(
                              controller: controller,
                              isDark: Theme.of(context).brightness ==
                                  Brightness.dark,
                              onToggleTheme: widget.onToggleTheme,
                              onOpenSettings: () => showSettingsPanel(
                                  context: context,
                                  controller: controller,
                                  onToggleTheme: widget.onToggleTheme,
                                  onSetThemeMode: widget.onSetThemeMode,
                                  themeMode: widget.themeMode,
                                  compactDensity: widget.compactDensity,
                                  onSetDensity: widget.onSetDensity,
                                  persistentInspector:
                                      widget.persistentInspector,
                                  onSetPersistentInspector:
                                      widget.onSetPersistentInspector),
                            ),
                          ),
                        ),
                        Expanded(
                          child: Column(
                            children: [
                              _AppToolbar(
                                  title: _viewTitle,
                                  sidebarCollapsed: sidebarCollapsed,
                                  onToggleSidebar: () => setState(() =>
                                      sidebarCollapsed = !sidebarCollapsed),
                                  onSearch: _openCommandPalette,
                                  onOpenFilters: _openFilters,
                                  focusTimer: focusTimer,
                                  onOpenFocusTimer: _openFocusTimer,
                                  onNewTask:
                                      controller.view == WorkspaceView.notes
                                          ? _newNote
                                          : _newTask),
                              Expanded(
                                child: _WorkspaceContent(
                                    controller: controller,
                                    compactDensity: widget.compactDensity,
                                    persistentInspector:
                                        widget.persistentInspector),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    if (showUndo)
                      Positioned(
                        left: 0,
                        right: 0,
                        bottom: 22,
                        child: Center(
                            child: _UndoToast(
                                message: undoMessage,
                                onUndo: () {
                                  // Keep the global toast on the same action
                                  // boundary as rows, inspectors and menus.
                                  controller.taskActions.undo();
                                  setState(() => showUndo = false);
                                })),
                      ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _AppToolbar extends StatelessWidget {
  const _AppToolbar(
      {required this.title,
      required this.sidebarCollapsed,
      required this.onToggleSidebar,
      required this.onSearch,
      required this.onOpenFilters,
      required this.focusTimer,
      required this.onOpenFocusTimer,
      required this.onNewTask});

  final String title;
  final bool sidebarCollapsed;
  final VoidCallback onToggleSidebar;
  final VoidCallback onSearch;
  final VoidCallback onOpenFilters;
  final FocusTimerController focusTimer;
  final VoidCallback onOpenFocusTimer;
  final VoidCallback onNewTask;

  @override
  Widget build(BuildContext context) {
    final tokens = WorkFollowTheme.of(context);
    return Container(
      height: 50,
      padding: const EdgeInsets.fromLTRB(11, 7, 16, 7),
      decoration: BoxDecoration(
          color: tokens.canvas,
          border: Border(bottom: BorderSide(color: tokens.border))),
      child: Row(
        children: [
          AppIconButton(
              icon: sidebarCollapsed
                  ? Icons.keyboard_double_arrow_right_rounded
                  : Icons.keyboard_double_arrow_left_rounded,
              tooltip: sidebarCollapsed ? '显示侧栏' : '隐藏侧栏',
              onPressed: onToggleSidebar,
              size: 32,
              iconSize: 17),
          const SizedBox(width: 6),
          if (title.isNotEmpty)
            Text(title,
                style: TextStyle(
                    color: tokens.textSecondary,
                    fontSize: 13,
                    fontWeight: FontWeight.w600)),
          const Spacer(),
          _ToolbarSearch(onPressed: onSearch),
          const SizedBox(width: 7),
          FocusTimerButton(timer: focusTimer, onTap: onOpenFocusTimer),
          const SizedBox(width: 6),
          Material(
              color: tokens.accent,
              borderRadius: BorderRadius.circular(8),
              child: InkWell(
                  onTap: onNewTask,
                  borderRadius: BorderRadius.circular(8),
                  child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 8),
                      child: Row(children: [
                        const Icon(Icons.add_rounded,
                            size: 16, color: Colors.white),
                        const SizedBox(width: 5),
                        const Text('新建',
                            style: TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                                fontWeight: FontWeight.w700))
                      ])))),
        ],
      ),
    );
  }
}

class _ToolbarSearch extends StatefulWidget {
  const _ToolbarSearch({required this.onPressed});
  final VoidCallback onPressed;
  @override
  State<_ToolbarSearch> createState() => _ToolbarSearchState();
}

class _ToolbarSearchState extends State<_ToolbarSearch> {
  bool hovering = false;
  @override
  Widget build(BuildContext context) {
    final tokens = WorkFollowTheme.of(context);
    return MouseRegion(
      onEnter: (_) => setState(() => hovering = true),
      onExit: (_) => setState(() => hovering = false),
      child: GestureDetector(
        onTap: widget.onPressed,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          width: 190,
          height: 32,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
              color: hovering ? tokens.accentFaint : tokens.inspector,
              border: Border.all(color: tokens.border),
              borderRadius: BorderRadius.circular(8)),
          child: Row(children: [
            Icon(Icons.search_rounded, size: 16, color: tokens.textTertiary),
            const SizedBox(width: 7),
            Expanded(
                child: Text('搜索',
                    style:
                        TextStyle(color: tokens.textTertiary, fontSize: 12))),
            Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 3),
                decoration: BoxDecoration(
                    color: tokens.content,
                    borderRadius: BorderRadius.circular(4)),
                child: Text('⌘K',
                    style: TextStyle(
                        color: tokens.textTertiary,
                        fontSize: 9,
                        fontWeight: FontWeight.w700)))
          ]),
        ),
      ),
    );
  }
}

class _WorkspaceContent extends StatelessWidget {
  const _WorkspaceContent(
      {required this.controller,
      required this.compactDensity,
      required this.persistentInspector});

  final WorkspaceController controller;
  final bool compactDensity;
  final bool persistentInspector;

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 180),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeIn,
      layoutBuilder: (currentChild, previousChildren) => Stack(children: [
        ...previousChildren,
        if (currentChild != null) currentChild
      ]),
      child: switch (controller.view) {
        WorkspaceView.home =>
          HomeScreen(key: const ValueKey('home'), controller: controller),
        WorkspaceView.calendar => CalendarScreen(
            key: const ValueKey('calendar'), controller: controller),
        WorkspaceView.notes =>
          NotesScreen(key: const ValueKey('notes'), controller: controller),
        WorkspaceView.trash =>
          TrashScreen(key: const ValueKey('trash'), controller: controller),
        WorkspaceView.stats =>
          StatsScreen(key: const ValueKey('stats'), controller: controller),
        WorkspaceView.matrix =>
          MatrixScreen(key: const ValueKey('matrix'), controller: controller),
        WorkspaceView.board =>
          BoardScreen(key: const ValueKey('board'), controller: controller),
        WorkspaceView.habits =>
          HabitsScreen(key: const ValueKey('habits'), controller: controller),
        _ => TodayScreen(
            key: ValueKey(controller.view),
            controller: controller,
            compactDensity: compactDensity,
            persistentInspector: persistentInspector,
          ),
      },
    );
  }
}

class _UndoToast extends StatelessWidget {
  const _UndoToast({required this.message, required this.onUndo});
  final String message;
  final VoidCallback onUndo;
  @override
  Widget build(BuildContext context) {
    final tokens = WorkFollowTheme.of(context);
    return Material(
        color: tokens.overlay,
        borderRadius: BorderRadius.circular(10),
        elevation: 8,
        child: Container(
            padding: const EdgeInsets.fromLTRB(14, 10, 9, 10),
            decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: tokens.borderStrong)),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.check_circle_rounded, size: 16, color: tokens.success),
              const SizedBox(width: 8),
              Text(message,
                  style: TextStyle(
                      color: tokens.textPrimary,
                      fontSize: 12,
                      fontWeight: FontWeight.w600)),
              const SizedBox(width: 14),
              TextButton(
                  onPressed: onUndo,
                  style: TextButton.styleFrom(
                      foregroundColor: tokens.accent,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 3),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap),
                  child: const Text('撤销',
                      style:
                          TextStyle(fontSize: 11, fontWeight: FontWeight.w700)))
            ])));
  }
}

class NewTaskIntent extends Intent {
  const NewTaskIntent();
}

class NewNoteIntent extends Intent {
  const NewNoteIntent();
}

class SearchIntent extends Intent {
  const SearchIntent();
}

class SettingsIntent extends Intent {
  const SettingsIntent();
}

class TodayIntent extends Intent {
  const TodayIntent();
}

class RecentIntent extends Intent {
  const RecentIntent();
}

class InboxIntent extends Intent {
  const InboxIntent();
}

class PlanIntent extends Intent {
  const PlanIntent();
}

class CalendarIntent extends Intent {
  const CalendarIntent();
}

class NotesIntent extends Intent {
  const NotesIntent();
}

class MatrixIntent extends Intent {
  const MatrixIntent();
}

class BoardIntent extends Intent {
  const BoardIntent();
}

class HabitsIntent extends Intent {
  const HabitsIntent();
}
