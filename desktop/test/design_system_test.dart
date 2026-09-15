import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_quill/flutter_quill.dart' as quill;

import 'package:workfollow_personal/theme/workfollow_theme.dart';
import 'package:workfollow_personal/widgets/app_icon_button.dart';
import 'package:workfollow_personal/widgets/desktop_popover.dart';
import 'package:workfollow_personal/widgets/task_editor_toolbar.dart';
import 'package:workfollow_personal/theme/workfollow_icons.dart';

void main() {
  test('TickTick-inspired design tokens stay stable', () {
    final theme = WorkFollowThemeData.light();

    expect(WorkFollowMetrics.iconHitTarget, 32);
    expect(WorkFollowMetrics.toolbarIcon, 16);
    expect(WorkFollowMetrics.menuRowHeight, 40);
    expect(WorkFollowMetrics.editorToolbarHeight, 40);
    expect(theme.textTheme.displaySmall?.fontSize, 26);
    expect(theme.textTheme.bodyLarge?.fontSize, 14);
    expect(theme.textTheme.bodyMedium?.fontSize, 13);
    expect(
        theme.textTheme.bodyLarge?.fontFamilyFallback, contains('PingFang SC'));
  });

  testWidgets('shared icon controls use the compact desktop geometry',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: WorkFollowThemeData.light(),
      home: const Scaffold(
        body: Center(
          child: AppIconButton(
            icon: Icons.more_horiz,
            tooltip: '更多',
          ),
        ),
      ),
    ));

    expect(tester.getSize(find.byType(AppIconButton)), const Size(32, 32));
    expect(tester.widget<Icon>(find.byIcon(Icons.more_horiz)).size, 16);
  });

  testWidgets('document formatting strip keeps a 40 point toolbar height',
      (tester) async {
    final controller = quill.QuillController.basic();
    addTearDown(controller.dispose);

    await tester.pumpWidget(MaterialApp(
      theme: WorkFollowThemeData.light(),
      home: Scaffold(
        body: TaskEditorToolbar(
          controller: controller,
          onAttach: () {},
          onInsertSlash: () {},
          onInsertDivider: () {},
          onLink: () {},
        ),
      ),
    ));

    expect(
      tester.getSize(find.byKey(const ValueKey('task-editor-toolbar'))).height,
      WorkFollowMetrics.editorToolbarHeight,
    );
  });

  testWidgets('field controls use explicit semantic icon size and color',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: WorkFollowThemeData.light(),
      home: Scaffold(
        body: PropertyButton(
          icon: WorkFollowIcons.calendar,
          label: '昨天',
          active: true,
          onPressed: (_) {},
        ),
      ),
    ));

    final icon = tester.widget<AppIcon>(find.byType(AppIcon));
    expect(icon.size, WorkFollowMetrics.compactFieldIcon);
    expect(icon.color, WorkFollowTheme.light.accent);
  });
}
