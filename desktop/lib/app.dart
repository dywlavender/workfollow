import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'screens/calendar_screen.dart';
import 'screens/home_screen.dart';
import 'screens/notes_screen.dart';
import 'screens/today_screen.dart';
import 'state/workspace_controller.dart';
import 'theme/workfollow_theme.dart';
import 'widgets/app_icon_button.dart';
import 'widgets/command_palette.dart';
import 'widgets/sidebar.dart';
import 'widgets/settings_panel.dart';

class WorkFollowApp extends StatefulWidget {
  const WorkFollowApp({super.key});

  @override
  State<WorkFollowApp> createState() => _WorkFollowAppState();
}

class _WorkFollowAppState extends State<WorkFollowApp> {
  bool darkMode = false;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '打勾',
      debugShowCheckedModeBanner: false,
      theme: WorkFollowThemeData.light(),
      darkTheme: WorkFollowThemeData.dark(),
      themeMode: darkMode ? ThemeMode.dark : ThemeMode.light,
      home: WorkFollowShell(
          onToggleTheme: () => setState(() => darkMode = !darkMode)),
    );
  }
}

class WorkFollowShell extends StatefulWidget {
  const WorkFollowShell({super.key, required this.onToggleTheme});

  final VoidCallback onToggleTheme;

  @override
  State<WorkFollowShell> createState() => _WorkFollowShellState();
}

class _WorkFollowShellState extends State<WorkFollowShell> {
  late final WorkspaceController controller;
  bool sidebarCollapsed = false;
  bool taskNavigationCollapsed = false;
  bool showUndo = false;
  String undoMessage = '';
  int lastSeenActionVersion = 0;

  @override
  void initState() {
    super.initState();
    controller = WorkspaceController();
    controller.addListener(_observeAction);
    unawaited(controller.restoreFromDisk());
  }

  void _observeAction() {
    if (!mounted || controller.actionVersion == lastSeenActionVersion) return;
    lastSeenActionVersion = controller.actionVersion;
    _showUndo(controller.lastActionMessage);
  }

  @override
  void dispose() {
    controller.removeListener(_observeAction);
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
    controller.selectView(WorkspaceView.today);
    _openCommandPalette();
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

  String get _viewTitle {
    if (controller.isTaskView) return '任务';
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
            SingleActivator(LogicalKeyboardKey.keyK, meta: true):
                SearchIntent(),
            SingleActivator(LogicalKeyboardKey.comma, meta: true):
                ToggleThemeIntent(),
            SingleActivator(LogicalKeyboardKey.digit1, meta: true):
                TodayIntent(),
            SingleActivator(LogicalKeyboardKey.digit2, meta: true):
                InboxIntent(),
            SingleActivator(LogicalKeyboardKey.digit3, meta: true):
                PlanIntent(),
            SingleActivator(LogicalKeyboardKey.digit4, meta: true):
                CalendarIntent(),
            SingleActivator(LogicalKeyboardKey.digit5, meta: true):
                NotesIntent(),
          },
          child: Actions(
            actions: <Type, Action<Intent>>{
              NewTaskIntent: CallbackAction<Intent>(onInvoke: (_) {
                _newTask();
                return null;
              }),
              SearchIntent: CallbackAction<Intent>(onInvoke: (_) {
                _openCommandPalette();
                return null;
              }),
              ToggleThemeIntent: CallbackAction<Intent>(onInvoke: (_) {
                widget.onToggleTheme();
                return null;
              }),
              TodayIntent: CallbackAction<Intent>(onInvoke: (_) {
                controller.selectView(WorkspaceView.today);
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
                            isDark:
                                Theme.of(context).brightness == Brightness.dark,
                            onToggleTheme: widget.onToggleTheme,
                            onOpenSettings: () => showSettingsPanel(
                                context: context,
                                controller: controller,
                                onToggleTheme: widget.onToggleTheme),
                          ),
                        ),
                      ),
                      Expanded(
                        child: Column(
                          children: [
                            _AppToolbar(
                                title: _viewTitle,
                                sidebarCollapsed: sidebarCollapsed,
                                onToggleSidebar: () => setState(
                                    () => sidebarCollapsed = !sidebarCollapsed),
                                onSearch: _openCommandPalette,
                                onNewTask: _newTask),
                            Expanded(
                              child: _WorkspaceContent(
                                controller: controller,
                                taskNavigationCollapsed:
                                    taskNavigationCollapsed,
                                onToggleTaskNavigation: () => setState(() =>
                                    taskNavigationCollapsed =
                                        !taskNavigationCollapsed),
                              ),
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
                                controller.undoLastAction();
                                setState(() => showUndo = false);
                              })),
                    ),
                ],
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
      required this.onNewTask});

  final String title;
  final bool sidebarCollapsed;
  final VoidCallback onToggleSidebar;
  final VoidCallback onSearch;
  final VoidCallback onNewTask;

  @override
  Widget build(BuildContext context) {
    final tokens = WorkFollowTheme.of(context);
    return Container(
      height: 62,
      padding: const EdgeInsets.fromLTRB(11, 11, 16, 9),
      decoration: BoxDecoration(
          color: tokens.content,
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
          Text(title,
              style: TextStyle(
                  color: tokens.textPrimary,
                  fontSize: 14,
                  fontWeight: FontWeight.w700)),
          const Spacer(),
          _ToolbarSearch(onPressed: onSearch),
          const SizedBox(width: 7),
          AppIconButton(
              icon: Icons.tune_rounded,
              tooltip: '筛选与视图',
              onPressed: () {},
              size: 32,
              iconSize: 17),
          const SizedBox(width: 7),
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
  const _WorkspaceContent({
    required this.controller,
    required this.taskNavigationCollapsed,
    required this.onToggleTaskNavigation,
  });

  final WorkspaceController controller;
  final bool taskNavigationCollapsed;
  final VoidCallback onToggleTaskNavigation;

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
        _ => TaskWorkspaceScreen(
            key: ValueKey(controller.view),
            controller: controller,
            navigationCollapsed: taskNavigationCollapsed,
            onToggleNavigation: onToggleTaskNavigation,
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

class SearchIntent extends Intent {
  const SearchIntent();
}

class ToggleThemeIntent extends Intent {
  const ToggleThemeIntent();
}

class TodayIntent extends Intent {
  const TodayIntent();
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
