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
import 'features/feedback/feedback_controller.dart';
import 'features/feedback/feedback_event.dart';
import 'features/feedback/feedback_host.dart';
import 'features/feedback/feedback_scope.dart';
import 'features/tasks/application/task_actions.dart';
import 'features/tasks/presentation/task_feedback_mapper.dart';
import 'models/task.dart';
import 'services/preferences_store.dart';
import 'services/local_workspace_store.dart';
import 'services/focus_timer.dart';
import 'state/workspace_controller.dart';
import 'theme/workfollow_motion.dart';
import 'theme/workfollow_theme.dart';
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

  /// 完成任务时播放提示音. On by default: the tone is the only signal that
  /// survives the user looking somewhere else when a task is ticked off.
  bool _completionSound = true;

  /// 动态反馈. Off keeps every result HUD but uses the short fade path instead
  /// of springing it, which is what a reduce-motion preference asks for.
  bool _animatedFeedback = true;

  late final WorkspacePreferencesStore _preferencesStore;

  /// The app's only transient-result channel.
  ///
  /// Created here rather than in the shell so it outlives page switches, and
  /// mounted above the [Navigator] so dialogs and the task inspector can report
  /// results too.
  final FeedbackController _feedback = FeedbackController();

  @override
  void initState() {
    super.initState();
    _preferencesStore = widget.preferencesStore ??
        WorkspacePreferencesStore(
          platform:
              LocalWorkspaceStore(namespace: widget.demoMode ? 'preview' : null)
                  .platform,
        );
    _syncFeedbackSettings();
    unawaited(_restoreThemeMode());
  }

  @override
  void dispose() {
    _feedback.dispose();
    super.dispose();
  }

  /// The controller is what reads these two preferences; the bools above are
  /// the source of truth that Settings edits, so every write goes through here.
  void _syncFeedbackSettings() {
    _feedback
      ..completionSoundEnabled = _completionSound
      ..animatedFeedback = _animatedFeedback;
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
    final completionSound = preferences['completionSound'];
    final animatedFeedback = preferences['animatedFeedback'];
    if (mode != null ||
        density is String ||
        inspector is bool ||
        completionSound is bool ||
        animatedFeedback is bool) {
      setState(() {
        if (mode != null) _themeMode = mode;
        if (density is String) _compactDensity = density == 'compact';
        if (inspector is bool) _persistentInspector = inspector;
        if (completionSound is bool) _completionSound = completionSound;
        if (animatedFeedback is bool) _animatedFeedback = animatedFeedback;
      });
      _syncFeedbackSettings();
    }
  }

  /// Every preference is written together. The store replaces the whole map,
  /// so saving one key alone would drop the others.
  void _savePreferences() {
    unawaited(_preferencesStore.save({
      'themeMode': _themeMode.name,
      'density': _compactDensity ? 'compact' : 'comfortable',
      'inspector': _persistentInspector,
      'completionSound': _completionSound,
      'animatedFeedback': _animatedFeedback,
    }));
  }

  void _setThemeMode(ThemeMode mode) {
    setState(() => _themeMode = mode);
    _savePreferences();
  }

  void _setDensity(bool compact) {
    setState(() => _compactDensity = compact);
    _savePreferences();
  }

  void _setPersistentInspector(bool enabled) {
    setState(() => _persistentInspector = enabled);
    _savePreferences();
  }

  void _setCompletionSound(bool enabled) {
    setState(() => _completionSound = enabled);
    _syncFeedbackSettings();
    _savePreferences();
  }

  void _setAnimatedFeedback(bool enabled) {
    setState(() => _animatedFeedback = enabled);
    _syncFeedbackSettings();
    _savePreferences();
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
      // Deliberately above the Navigator rather than inside the shell's page
      // stack: `showDialog` / `showGeneralDialog` build their routes as
      // siblings of `home`, so a scope placed inside the shell would be
      // invisible to Settings, the command palette and every confirmation
      // sheet. `builder` is inside AnimatedTheme, so Theme.of still resolves to
      // the app theme.
      builder: (context, child) => FeedbackScope(
          controller: _feedback,
          child: Stack(fit: StackFit.expand, children: [
            if (child != null) child,
            WorkFollowFeedbackHost(
                controller: _feedback, animate: _animatedFeedback),
          ])),
      home: WorkFollowShell(
        demoMode: widget.demoMode,
        onToggleTheme: _toggleTheme,
        onSetThemeMode: _setThemeMode,
        themeMode: _themeMode,
        compactDensity: _compactDensity,
        onSetDensity: _setDensity,
        persistentInspector: _persistentInspector,
        onSetPersistentInspector: _setPersistentInspector,
        completionSound: _completionSound,
        onSetCompletionSound: _setCompletionSound,
        animatedFeedback: _animatedFeedback,
        onSetAnimatedFeedback: _setAnimatedFeedback,
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
    this.completionSound = true,
    this.onSetCompletionSound,
    this.animatedFeedback = true,
    this.onSetAnimatedFeedback,
  });

  final VoidCallback onToggleTheme;
  final ValueChanged<ThemeMode> onSetThemeMode;
  final ThemeMode themeMode;
  final bool compactDensity;
  final ValueChanged<bool>? onSetDensity;
  final bool persistentInspector;
  final ValueChanged<bool>? onSetPersistentInspector;
  final bool demoMode;

  /// 完成任务时播放提示音.
  final bool completionSound;
  final ValueChanged<bool>? onSetCompletionSound;

  /// 动态反馈 — the result HUD springs in when on and uses a short fade when off.
  final bool animatedFeedback;
  final ValueChanged<bool>? onSetAnimatedFeedback;

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

  /// Resolved in [didChangeDependencies] rather than looked up on demand: the
  /// action watcher runs from a listener callback, where an inherited-widget
  /// lookup could land inside another widget's build.
  FeedbackController? _feedback;
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
        // A round running out is its own kind of finished: the same HUD, its
        // own tone, and nothing to undo.
        _feedback?.show(const WorkFollowFeedback(
            kind: WorkFollowFeedbackKind.success,
            message: '这一轮专注完成了，休息一下吧。',
            sound: WorkFollowFeedbackSound.focus,
            duration: Duration(seconds: 3)));
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
            final result = task.completed
                ? controller.taskActions.restore(id)
                : controller.taskActions.complete(id);
            // The menu bar reports through the same channel as a row, so a
            // completion driven from the menu keeps its tone and its undo.
            presentTaskResultIn(context, result,
                actionVersion: controller.actionVersion);
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
    // Deferred by one microtask on purpose. The entry point that ran the
    // command presents its own, richer result immediately after the command
    // returns — still inside the synchronous block that notified us — so
    // checking on the next turn is what lets `wasActionPresented` see that
    // claim. Checking here would race it, and the entry point's completion
    // would lose to this generic one.
    scheduleMicrotask(_reportUnclaimedAction);
  }

  /// Reports an action that no entry point claimed: a note going to the trash,
  /// a bulk edit from the selection bar, a menu-bar command.
  void _reportUnclaimedAction() {
    if (!mounted) return;
    final version = lastSeenActionVersion;
    final feedback = _feedback;
    if (feedback == null || feedback.wasActionPresented(version)) return;
    final message = controller.lastActionMessage;
    if (message.isEmpty) return;
    // No intent is known on this path, so the result is offered as undoable:
    // that is exactly what the previous single global undo tooltip did.
    presentTaskResult(
        feedback,
        TaskActionResult.success(
            message: message,
            undo: UndoCommand(label: '撤销', execute: _undoLastAction)),
        actionVersion: version);
  }

  /// Bridges the global undo back into a callback shape. `taskActions.undo`
  /// reports whether anything was actually taken back, which the HUD does not
  /// need — it has already dismissed itself.
  Future<bool> _undoLastAction() async =>
      controller.taskActions.undo().success;

  Future<AppExitResponse> _handleExitRequested() async {
    await controller.waitForPendingSaves();
    return AppExitResponse.exit;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Null when the shell is mounted on its own (widget tests, previews): the
    // shell then simply reports nothing instead of throwing.
    _feedback = FeedbackScope.maybeOf(context);
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
        onSetPersistentInspector: widget.onSetPersistentInspector,
        completionSound: widget.completionSound,
        onSetCompletionSound: widget.onSetCompletionSound,
        animatedFeedback: widget.animatedFeedback,
        onSetAnimatedFeedback: widget.onSetAnimatedFeedback);
  }

  Future<void> _openFocusTimer() => showFocusTimerDialog(
        context: context,
        timer: focusTimer,
        controller: controller,
      );

  void _handleGlobalEscape() {
    // Nested editors and popovers receive Escape first. Once those surfaces
    // are closed, the shell clears multi-selection or releases focus.
    // The inspector owns dismissal for inline and narrow presentations;
    // a fixed detail pane remains selected when focus is elsewhere.
    if (controller.multiSelectCount > 0) {
      controller.clearMultiSelect();
      return;
    }
    FocusManager.instance.primaryFocus?.unfocus();
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
                body: Row(
                  children: [
                    ClipRect(
                      child: AnimatedAlign(
                        duration: WorkFollowMotionPolicy.duration(
                            context, WorkFollowMotionRole.panelTransition),
                        curve: WorkFollowMotionPolicy.curve(
                            context, WorkFollowMotionRole.panelTransition),
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
                                    widget.onSetPersistentInspector,
                                completionSound: widget.completionSound,
                                onSetCompletionSound:
                                    widget.onSetCompletionSound,
                                animatedFeedback: widget.animatedFeedback,
                                onSetAnimatedFeedback:
                                    widget.onSetAnimatedFeedback),
                        ),
                      ),
                    ),
                    Expanded(
                      child: _WorkspaceContent(
                          controller: controller,
                          compactDensity: widget.compactDensity,
                          persistentInspector: widget.persistentInspector,
                          onOpenFocusTimer: _openFocusTimer),
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

class _WorkspaceContent extends StatelessWidget {
  const _WorkspaceContent(
      {required this.controller,
      required this.compactDensity,
      required this.persistentInspector,
      this.onOpenFocusTimer});

  final WorkspaceController controller;
  final bool compactDensity;
  final bool persistentInspector;
  final VoidCallback? onOpenFocusTimer;

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: WorkFollowMotionPolicy.duration(
          context, WorkFollowMotionRole.panelTransition),
      switchInCurve: WorkFollowMotionPolicy.curve(
          context, WorkFollowMotionRole.panelTransition),
      switchOutCurve: WorkFollowMotionPolicy.curve(
          context, WorkFollowMotionRole.popoverExit),
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
            onOpenFocusTimer: onOpenFocusTimer,
          ),
      },
    );
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
