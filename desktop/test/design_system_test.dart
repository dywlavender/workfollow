import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_quill/flutter_quill.dart' as quill;

import 'package:workfollow_personal/theme/workfollow_theme.dart';
import 'package:workfollow_personal/widgets/app_icon_button.dart';
import 'package:workfollow_personal/widgets/desktop_popover.dart';
import 'package:workfollow_personal/features/editor/document_editor_toolbar.dart';
import 'package:workfollow_personal/widgets/task_editor_popover.dart';
import 'package:workfollow_personal/theme/workfollow_icons.dart';

void main() {
  test('TickTick-inspired design tokens stay stable', () {
    final theme = WorkFollowThemeData.light();

    expect(WorkFollowMetrics.iconHitTarget, 32);
    expect(WorkFollowMetrics.railIcon, 22);
    expect(WorkFollowMetrics.navigationIcon, 20);
    expect(WorkFollowMetrics.toolbarIcon, 18);
    expect(WorkFollowMetrics.fieldIcon, 20);
    expect(WorkFollowMetrics.compactFieldIcon, 17);
    expect(WorkFollowMetrics.menuRowHeight, 40);
    expect(WorkFollowMetrics.editorToolbarHeight, 42);
    expect(WorkFollowMetrics.listItemMaxWidth, 172);
    // The light workspace follows the reference's four-plane hierarchy:
    // turquoise rail, mint navigation, cool-gray list canvas and white detail.
    expect(WorkFollowTheme.light.rail, const Color(0xFF42C8A8));
    expect(WorkFollowTheme.light.railActive, Colors.white);
    expect(WorkFollowTheme.light.sidebarGradient.colors.first,
        const Color(0xFFDDF5EE));
    // One primary for the whole product. The light shell used to carry a teal
    // accent next to the navigation column's indigo, which is what made the
    // notes page read as two products sharing a window: the compose button,
    // the sort control and the folder chips were green while the navigation
    // selection beside them was blue. Green now means "completed / succeeded"
    // only.
    expect(WorkFollowTheme.light.accent, const Color(0xFF5B5CEB));
    expect(theme.textTheme.displaySmall?.fontSize, WorkFollowMacTypography.pageTitle);
    expect(theme.textTheme.displaySmall?.fontWeight,
        WorkFollowMacWeight.semibold);
    expect(theme.textTheme.displaySmall?.letterSpacing,
        WorkFollowMacTracking.none);
    expect(theme.textTheme.bodyLarge?.fontSize, WorkFollowMacTypography.body);
    expect(theme.textTheme.bodyMedium?.fontSize, WorkFollowMacTypography.control);
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
    expect(tester.widget<Icon>(find.byIcon(Icons.more_horiz)).size,
        WorkFollowMetrics.toolbarIcon);
  });

  testWidgets('document formatting strip uses the reference popover height',
      (tester) async {
    final controller = quill.QuillController.basic();
    addTearDown(controller.dispose);

    await tester.pumpWidget(MaterialApp(
      theme: WorkFollowThemeData.light(),
      home: Scaffold(
        body: DocumentEditorToolbar(
          controller: controller,
          onAttach: () {},
          onInsertSlash: () {},
          onInsertDivider: () {},
          onLink: () {},
        ),
      ),
    ));

    expect(
      tester.getSize(find.byKey(const ValueKey('document-editor-toolbar'))).height,
      TaskEditorPopoverStyle.toolbarHeight,
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
