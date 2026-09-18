import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:workfollow_personal/state/workspace_controller.dart';
import 'package:workfollow_personal/theme/workfollow_theme.dart';
import 'package:workfollow_personal/widgets/quick_add.dart';

/// Focus contract for the list add row.
///
/// Flutter unfocuses an [EditableText] on every pointer-down that lands outside
/// its tap region on desktop (editable_text.dart, `_EditableTextTapOutsideAction`
/// → `focusNode.unfocus()` for macOS). The add row's own controls — the date
/// chip and the properties disclosure — sit outside that region, so without the
/// shared tap group every one of them reads as "outside" and drops the caret.
/// These tests pin the intended behaviour: the caret stays in the field while
/// the user sets properties.
void main() {
  testWidgets('list quick add names its target and keeps the shortcut visible',
      (tester) async {
    tester.view.physicalSize = const Size(560, 240);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final controller = WorkspaceController(seedData: false);
    addTearDown(controller.dispose);
    controller.selectView(WorkspaceView.inbox);
    await tester.pumpWidget(MaterialApp(
      theme: WorkFollowThemeData.light(),
      home: Scaffold(
        body: QuickAddField(controller: controller, listStyle: true),
      ),
    ));
    await tester.pumpAndSettle();

    final field =
        tester.widget<TextField>(find.byKey(const ValueKey('quick-add-title')));
    expect(field.decoration?.hintText, '添加任务至“收集箱”');
    expect(find.text('⌘N'), findsOneWidget);
  });

  Future<void> pumpAddRow(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final controller = WorkspaceController(seedData: false);
    addTearDown(controller.dispose);
    await tester.pumpWidget(MaterialApp(
      theme: WorkFollowThemeData.light(),
      home: Scaffold(
        body: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: 560,
            child: QuickAddField(controller: controller, listStyle: true),
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();

    // The two slots only show while the row is selected, so focus it first.
    await tester.tap(find.byKey(const ValueKey('quick-add-title')));
    await tester.pumpAndSettle();
  }

  bool caretInField(WidgetTester tester) => tester
      .widget<TextField>(find.byKey(const ValueKey('quick-add-title')))
      .focusNode!
      .hasFocus;

  testWidgets('tapping the date chip keeps the caret in the add field',
      (tester) async {
    await pumpAddRow(tester);
    expect(caretInField(tester), isTrue);

    await tester.tap(find.byKey(const ValueKey('quick-add-schedule')));
    await tester.pumpAndSettle();

    expect(caretInField(tester), isTrue,
        reason: 'the date chip belongs to the field, not outside it');
  });

  testWidgets('tapping the properties disclosure keeps the caret',
      (tester) async {
    await pumpAddRow(tester);

    await tester.tap(find.byKey(const ValueKey('quick-add-properties')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('quick-add-properties-panel')),
        findsOneWidget);
    expect(caretInField(tester), isTrue,
        reason: 'the disclosure belongs to the field, not outside it');

    // Picking a priority commits and closes the panel; the caret should come
    // back to the field so the user can keep typing the title.
    await tester
        .tap(find.byKey(const ValueKey('quick-add-priority-flag-high')));
    await tester.pumpAndSettle();
    expect(
        find.byKey(const ValueKey('quick-add-properties-panel')), findsNothing);
    expect(caretInField(tester), isTrue);
  });
}
