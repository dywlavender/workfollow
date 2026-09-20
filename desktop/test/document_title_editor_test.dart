import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:workfollow_personal/features/editor/presentation/document_title_editor.dart';
import 'package:workfollow_personal/theme/workfollow_theme.dart';

void main() {
  testWidgets('shared title editor delegates input and title metrics',
      (tester) async {
    final controller = TextEditingController(text: '旧标题');
    final focusNode = FocusNode();
    addTearDown(() {
      controller.dispose();
      focusNode.dispose();
    });
    String? changed;

    await tester.pumpWidget(MaterialApp(
      theme: WorkFollowThemeData.light(),
      home: Scaffold(
        body: DocumentTitleEditor(
          fieldKey: const ValueKey('shared-title-field'),
          controller: controller,
          focusNode: focusNode,
          placeholder: '标题占位符',
          maxLines: 3,
          fontSize: WorkFollowMacTypography.detailTitle,
          onChanged: (value) => changed = value,
        ),
      ),
    ));

    final field = tester
        .widget<TextField>(find.byKey(const ValueKey('shared-title-field')));
    expect(field.controller, same(controller));
    expect(field.focusNode, same(focusNode));
    expect(field.minLines, 1);
    expect(field.maxLines, 3);
    expect(field.style?.fontSize, WorkFollowMacTypography.detailTitle);
    expect(field.decoration?.hintText, '标题占位符');

    await tester.enterText(
        find.byKey(const ValueKey('shared-title-field')), '新标题');
    expect(changed, '新标题');
  });

  testWidgets('a title field reads at full ink and never carries a rule',
      (tester) async {
    final controller = TextEditingController();
    final focusNode = FocusNode();
    addTearDown(() {
      controller.dispose();
      focusNode.dispose();
    });

    await tester.pumpWidget(MaterialApp(
      theme: WorkFollowThemeData.light(),
      home: Scaffold(
        body: DocumentTitleEditor(
          fieldKey: const ValueKey('title-field'),
          controller: controller,
          focusNode: focusNode,
          placeholder: '任务标题',
          fontSize: WorkFollowMacTypography.detailTitle,
          onChanged: (_) {},
        ),
      ),
    ));

    // A title field names a document, and it names it the same way in every
    // state the document can be in. Two parameters used to be reachable from
    // here — a strike, then a grey — and both were passed by the task
    // inspector for a finished task, which made the one field where a task's
    // name is fully readable the one place that name looked wrong.
    final field =
        tester.widget<TextField>(find.byKey(const ValueKey('title-field')));
    expect(field.style?.color, WorkFollowTheme.light.textPrimary,
        reason: 'the editor shows a task as itself, finished or not');
    expect(field.style?.decoration, isNull,
        reason: 'completion never lines through a title');
    expect(field.style?.fontSize, WorkFollowMacTypography.detailTitle);
  });
}
