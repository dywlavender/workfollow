import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:workfollow_personal/models/task.dart';
import 'package:workfollow_personal/state/workspace_controller.dart';
import 'package:workfollow_personal/theme/workfollow_icons.dart';
import 'package:workfollow_personal/theme/workfollow_theme.dart';
import 'package:workfollow_personal/widgets/task_completion_box.dart';
import 'package:workfollow_personal/widgets/task_inspector.dart';

const _tokens = WorkFollowTheme.light;

/// One shape for the completion box, wherever a task appears.
///
/// A task is marked by the same box in a task row, on a board card, beside a
/// note, in the inspector's header, in a month cell's bar and in a week column.
/// Those are four different sizes, and the box has to be recognisably the same
/// thing at all of them — so its corner is a fraction of its own side rather
/// than a number each screen picked, and the fraction is the task row's: an
/// 18pt box with a 4.5pt corner.
///
/// Drawing it is what keeps that true. An icon arrives with its own corner, its
/// own stroke and its own idea of a tick, and two places that each reach for
/// one come out with two different boxes without anyone deciding to.
void main() {
  /// Every size the product draws the box at, named for the surface that owns
  /// it, so a size that quietly grows a corner of its own is named here too.
  const sizes = <String, double>{
    'a month cell\'s bar and a week column\'s item':
        CalendarMetrics.taskBarCheckboxSize,
    "the inspector's header and a quadrant row":
        WorkFollowMetrics.completionBoxSize,
    'a task row': TaskListMetrics.checkboxSize,
    'a board card': BoardMetrics.taskCheckboxSize,
  };

  Future<BoxDecoration> _paint(
      WidgetTester tester, double size, bool completed) async {
    await tester.pumpWidget(MaterialApp(
      theme: WorkFollowThemeData.light(),
      home: Scaffold(
          body: TaskCompletionBox(size: size, completed: completed)),
    ));
    return tester
            .widget<DecoratedBox>(find
                .descendant(
                    of: find.byType(TaskCompletionBox),
                    matching: find.byType(DecoratedBox))
                .first)
            .decoration as BoxDecoration;
  }

  test('the corner is the same fraction of the side at every size', () {
    // The task row's box is the one the rest of the product matches, so at its
    // own size the helper has to hand back exactly the row's corner.
    expect(taskCompletionBoxRadius(TaskListMetrics.checkboxSize),
        WorkFollowRadii.checkbox);

    for (final size in sizes.values) {
      expect(taskCompletionBoxRadius(size) / size,
          WorkFollowRadii.checkbox / TaskListMetrics.checkboxSize,
          reason: 'a box drawn at $size is the same shape as the row\'s, '
              'scaled — not a corner someone picked for that screen');
    }
  });

  test('one side for the product, and the control Flutter caps is scaled to it',
      () {
    // Flutter's own Checkbox paints a side of its own and takes no argument
    // for it, so a surface built on that control reaches the product's side by
    // scaling. The row's slot is that control's own side, and it is also what
    // the corner fraction above is quoted against.
    expect(
        TaskListMetrics.checkboxSize, WorkFollowMetrics.platformCheckboxSize);
    expect(WorkFollowMetrics.completionBoxScale,
        WorkFollowMetrics.completionBoxSize /
            WorkFollowMetrics.platformCheckboxSize);
    expect(WorkFollowMetrics.completionBoxScale, lessThan(1),
        reason: 'Flutter paints the control larger than the product draws it, '
            'so the scale is a shrink — a scale of one or more means the two '
            'have drifted apart');

    // The sides the product picks are the product's, not a page's own idea.
    expect(MatrixMetrics.taskRowCheckboxSize,
        WorkFollowMetrics.completionBoxSize);
    expect(
        taskCompletionBoxRadius(WorkFollowMetrics.completionBoxSize) /
            WorkFollowMetrics.completionBoxSize,
        .25,
        reason: "the product's box is the row's shape, so its corner is the "
            'same fraction of its own side');

    // Every surface that keeps Flutter's control has to scale it. One that
    // forgets draws at the control's own side instead, which is how the same
    // task ends up two different sizes in two places.
    for (final path in const [
      'lib/widgets/task_row.dart',
      'lib/screens/notes_screen.dart',
      'lib/widgets/task_date_picker.dart',
    ]) {
      final source = File(path).readAsStringSync();
      expect(source, contains('Transform.scale'),
          reason: '$path keeps Flutter\'s own Checkbox, so it has to scale it '
              'to the side the product draws its boxes at');
      expect(source, contains('WorkFollowMetrics.completionBoxScale'),
          reason: '$path has to scale by the product\'s factor rather than a '
              'number of its own');
    }
  });

  testWidgets('an open box is an outline and a done one is a filled tick',
      (tester) async {
    final open = await _paint(tester, TaskListMetrics.checkboxSize, false);
    final done = await _paint(tester, TaskListMetrics.checkboxSize, true);

    // Open: an edge and nothing inside it.
    expect(open.color, isNull);
    expect(open.border, isNotNull);
    expect((open.border! as Border).top.color, _tokens.textSecondary);

    // Done: filled with the completed neutral a finished task takes
    // everywhere, and carrying a tick rather than being one.
    expect(done.color, taskCompletionFill(_tokens));
    expect(done.border, isNull);
    expect(find.byIcon(WorkFollowIcons.check), findsOneWidget);

    // Both corners, so the two states cannot drift apart in shape.
    for (final decoration in [open, done]) {
      expect((decoration.borderRadius! as BorderRadius).topLeft.x,
          taskCompletionBoxRadius(TaskListMetrics.checkboxSize));
    }
  });

  testWidgets('the box is square at every size it is drawn at', (tester) async {
    for (final size in sizes.values) {
      await tester.pumpWidget(MaterialApp(
        theme: WorkFollowThemeData.light(),
        home: Scaffold(body: TaskCompletionBox(size: size, completed: false)),
      ));
      final box = tester.getRect(find.byType(TaskCompletionBox));
      expect(box.width, size);
      expect(box.height, size);
    }
  });

  test('no completion box is taken from the icon set', () {
    // The box used to be `check_box_outline_blank_rounded` / `check_box_rounded`
    // in two places under two names, which is how the calendar's box and the
    // editor's came to be different shapes. There is no glyph for it now: if
    // one is added back, this is where the argument for it has to be made.
    //
    // `checklist` is not one of them — it is the document editor's own list
    // marker, an icon in a formatting toolbar, and shares nothing with a
    // task's completion state.
    const glyphs = <String>[
      'Icons.check_box_rounded',
      'Icons.check_box_outline_blank_rounded',
    ];
    final offenders = <String>[];
    for (final entity in Directory('lib').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final source = entity.readAsStringSync();
      if (glyphs.any(source.contains)) offenders.add(entity.path);
    }
    expect(offenders, isEmpty,
        reason: 'a completion box is drawn by TaskCompletionBox; an icon brings '
            'its own corner and undoes the one-shape rule');
  });

  test('the open edge carries priority through one shared mapping', () {
    // A task's priority lives on its completion box while the task is open,
    // because a collapsed row has nowhere else to put it. That is exactly why
    // the mapping cannot be written out per surface: the same task is drawn in
    // the list and in its editor's header, and it was a red box in one and a
    // grey one in the other until both started reading this.
    expect(taskPriorityColor(TaskPriority.high, _tokens), _tokens.danger);
    expect(taskPriorityColor(TaskPriority.medium, _tokens), _tokens.warning);
    expect(taskPriorityColor(TaskPriority.low, _tokens), _tokens.accent);
    expect(taskPriorityColor(TaskPriority.none, _tokens), _tokens.borderStrong);

    // Both surfaces that draw this box for a task take its edge from the same
    // place. The inspector also colours its priority property button off the
    // priority, but that is an emphasis rule with its own colours, so this
    // checks the box's own wiring rather than the file as a whole.
    for (final path in const [
      'lib/widgets/task_row.dart',
      'lib/widgets/task_inspector.dart',
    ]) {
      expect(File(path).readAsStringSync(), contains('taskPriorityColor('),
          reason: '$path draws a completion box, so its edge has to come from '
              'the shared mapping rather than a colour picked here');
    }
    expect(File('lib/widgets/task_inspector.dart').readAsStringSync(),
        contains('openColor: taskPriorityColor('),
        reason: "the editor's header box went back to a fixed ink, which is "
            'what left a high-priority task red in the list and grey here');
  });

  test('a finished task is the same box on both sides of the window', () {
    // The editor's header and the editor's child rows each filled their box
    // with success green while the list filled the same task's box with
    // graphite — one task, two answers. The fill comes from one role now, and
    // the surfaces that used to override it take the default again.
    expect(taskCompletionFill(_tokens), _tokens.taskCompletedCheckbox);
    expect(taskCompletionFill(WorkFollowTheme.dark),
        WorkFollowTheme.dark.taskCompletedCheckbox);

    // The box is the last rung of the finished-row ladder and not a value of
    // its own; where the ladder is asserted is
    // `completion_style_contract_test.dart`, beside the rest of the rule.

    for (final path in const [
      'lib/widgets/task_inspector.dart',
      'lib/widgets/task_children_panel.dart',
    ]) {
      expect(File(path).readAsStringSync(), isNot(contains('doneColor:')),
          reason: '$path fills a completion box with a colour of its own, so '
              'the same task is two different boxes on the two sides');
    }
  });

  test('no completion box raises Material ink around itself', () {
    // Material answers a pointer with ink drawn around the control. For a
    // checkbox that ink is a circle the radius of a fingertip in
    // `ThemeData.hoverColor` — which this app sets to an opaque grey — so
    // hovering a task's box raised a grey disc around it: the one round thing
    // in a row built from rectangles, and it read as a second, smaller target
    // inside the row's own. For a button it is a plate the size of the whole
    // control, which put a grey slab under the box in the editor's header.
    //
    // Every control that draws this box clears its overlay. That is where both
    // the hover halo and the press ripple are painted from, and this product
    // answers a pointer with a row fill that switches on the frame rather than
    // ink that eases in under it.
    for (final path in const [
      'lib/widgets/task_row.dart',
      'lib/screens/notes_screen.dart',
      'lib/widgets/matrix/matrix_task_row.dart',
      'lib/widgets/task_inspector.dart',
    ]) {
      final source = File(path).readAsStringSync();
      expect(source, contains('overlayColor'),
          reason: '$path leaves Material\'s ink on its completion box');
      expect(source, contains('Colors.transparent'),
          reason: '$path has to clear the overlay, not just mention it');
    }
  });

  testWidgets('the editor\'s box declares no pointer ink', (tester) async {
    // The source scan above keeps the declaration in the file; this checks the
    // declaration the widget really resolves, so a style that names the overlay
    // but hands back something else does not pass as a clear.
    final controller = WorkspaceController(seedData: false);
    addTearDown(controller.dispose);
    controller.addTask('声明的任务');

    await tester.pumpWidget(MaterialApp(
      theme: WorkFollowThemeData.light(),
      home: Scaffold(
          body: TaskInspector(
              task: controller.tasks.single, controller: controller)),
    ));
    await tester.pumpAndSettle();

    final button = tester.widget<TextButton>(find.descendant(
        of: find.byKey(const ValueKey('task-complete')),
        matching: find.byType(TextButton)));
    final overlay = button.style?.overlayColor;
    expect(overlay, isNotNull,
        reason: "the editor's completion control leaves Material's default "
            'overlay in place, which paints a plate under the box on hover');
    for (final state in const [
      WidgetState.hovered,
      WidgetState.pressed,
      WidgetState.focused,
    ]) {
      expect(overlay!.resolve({state}), Colors.transparent,
          reason: 'the control has to answer $state with no ink at all');
    }
  });
}
