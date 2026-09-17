import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart' as quill;
import 'package:flutter_test/flutter_test.dart';

import 'package:workfollow_personal/theme/workfollow_theme.dart';
import 'package:workfollow_personal/widgets/task_document_styles.dart';

void main() {
  test('task document blocks use the WorkFollow type scale', () {
    final styles = TaskDocumentStyles.build(WorkFollowTheme.light);
    final body = styles.paragraph!.style;

    expect(body.fontSize, WorkFollowMacTypography.body);
    expect(body.fontWeight, WorkFollowMacWeight.regular);
    expect(body.height, WorkFollowMacTypography.lineBody);
    expect(body.color, WorkFollowTheme.light.textPrimary);

    expect(styles.h1!.style.fontSize, WorkFollowMacTypography.documentH1);
    expect(styles.h1!.style.fontWeight, WorkFollowMacWeight.semibold);
    expect(
        styles.h1!.style.height, WorkFollowMacTypography.documentHeadingLine);
    expect(styles.h1!.style.color, WorkFollowTheme.light.textPrimary);

    expect(styles.h2!.style.fontSize, WorkFollowMacTypography.documentH2);
    expect(styles.h2!.style.fontWeight, WorkFollowMacWeight.semibold);
    expect(
        styles.h2!.style.height, WorkFollowMacTypography.documentHeadingLine);

    expect(styles.h3!.style.fontSize, WorkFollowMacTypography.documentH3);
    expect(styles.h3!.style.fontWeight, WorkFollowMacWeight.semibold);
    expect(
        styles.h3!.style.height, WorkFollowMacTypography.documentHeading3Line);

    expect(styles.lists!.style, body);
    expect(styles.leading!.style, body);
    expect(styles.quote!.style, body);
    expect(styles.quote!.horizontalSpacing.left, 12);
    final quoteBorder = styles.quote!.decoration?.border;
    expect(quoteBorder, isA<Border>());
    expect((quoteBorder! as Border).left.color,
        WorkFollowTheme.light.borderStrong);

    expect(styles.link!.fontSize, WorkFollowMacTypography.body);
    expect(styles.link!.color, WorkFollowTheme.light.accent);
    expect(styles.link!.decoration, TextDecoration.underline);
    expect(styles.inlineCode!.style.fontFamily, WorkFollowMacTypeFamily.code);
    expect(styles.inlineCode!.backgroundColor, WorkFollowTheme.light.canvas);
    expect(styles.code!.style.fontFamily, WorkFollowMacTypeFamily.code);
    final codeDecoration = styles.code!.decoration;
    expect(codeDecoration, isA<BoxDecoration>());
    expect((codeDecoration! as BoxDecoration).color,
        WorkFollowTheme.light.canvas);
  });

  test('block defaults retain the base face while inline colours stay explicit',
      () {
    const base = TextStyle(
      fontFamily: 'Test Document Face',
      color: Colors.purple,
    );
    final h1 = TaskDocumentStyles.h1(WorkFollowTheme.dark, base: base);
    final styles = TaskDocumentStyles.build(WorkFollowTheme.dark, base: base);

    expect(h1.fontFamily, 'Test Document Face');
    expect(h1.color, WorkFollowTheme.dark.textPrimary);
    expect(styles.color, WorkFollowTheme.dark.textPrimary);
    // A user-set color is an inline Delta attribute; the block defaults do
    // not add one and therefore cannot erase it during a heading change.
    final document = quill.Document.fromJson([
      {
        'insert': '彩色',
        'attributes': {'color': '#ff0000'},
      },
      {
        'insert': '\n',
        'attributes': {'header': 1},
      },
    ]);
    final attributes = document.toDelta().toJson().first['attributes'] as Map;
    expect(attributes['color'], '#ff0000');
    expect(attributes.containsKey('font'), isFalse);
    expect(attributes.containsKey('size'), isFalse);
  });

  test('checklist styles use a shared marker builder and completed text role',
      () {
    final tokens = WorkFollowTheme.light;
    final styles = TaskDocumentStyles.build(tokens);
    final marker = styles.lists!.checkboxUIBuilder;
    expect(marker, isA<TaskDocumentCheckboxBuilder>());

    final completed =
        TaskDocumentStyles.customStyleBuilder(tokens)(quill.Attribute.checked);
    expect(completed.color, tokens.textSecondary);
    expect(completed.decoration, TextDecoration.lineThrough);
    expect(completed.decorationColor, tokens.textSecondary);
    expect(completed.decorationThickness, 1);
    final normal = TaskDocumentStyles.customStyleBuilder(tokens)(
        quill.Attribute.unchecked);
    expect(normal, const TextStyle());
    expect(
        TaskDocumentStyles.checklistCheckedFill(
            WorkFollowTheme.dark, Brightness.dark),
        WorkFollowTheme.dark.borderStrong);
  });

  testWidgets('checklist marker stays neutral and exposes its checked state',
      (tester) async {
    var changed = false;
    await tester.pumpWidget(MaterialApp(
      theme: WorkFollowThemeData.light(),
      home: Builder(
        builder: (context) => TaskDocumentCheckboxBuilder(WorkFollowTheme.light)
            .build(
              context: context,
              isChecked: true,
              onChanged: (_) => changed = true,
            ),
      ),
    ));

    expect(find.bySemanticsLabel('已完成检查项'), findsOneWidget);
    final material = tester.widget<Material>(find.byType(Material).last);
    expect(material.color, WorkFollowTheme.light.textSecondary);

    await tester.tap(find.descendant(
        of: find.bySemanticsLabel('已完成检查项'),
        matching: find.byType(InkWell)));
    expect(changed, isTrue);
  });

  testWidgets('Quill keeps existing checklist states and toggles their Delta',
      (tester) async {
    final document = quill.Document.fromJson([
      {'insert': '已完成'},
      {
        'insert': '\n',
        'attributes': {'list': 'checked'},
      },
      {'insert': '待办'},
      {
        'insert': '\n',
        'attributes': {'list': 'unchecked'},
      },
    ]);
    final editor = quill.QuillController(
      document: document,
      selection: const TextSelection.collapsed(offset: 0),
    );
    final focus = FocusNode();
    final scroll = ScrollController();
    addTearDown(() {
      editor.dispose();
      focus.dispose();
      scroll.dispose();
    });

    await tester.pumpWidget(MaterialApp(
      theme: WorkFollowThemeData.light(),
      home: SizedBox(
        width: 360,
        height: 140,
        child: quill.QuillEditor(
          controller: editor,
          focusNode: focus,
          scrollController: scroll,
          config: quill.QuillEditorConfig(
            scrollable: false,
            minHeight: 120,
            customStyles: TaskDocumentStyles.build(
              WorkFollowTheme.light,
            ),
            customStyleBuilder:
                TaskDocumentStyles.customStyleBuilder(WorkFollowTheme.light),
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.bySemanticsLabel('已完成检查项'), findsOneWidget);
    expect(find.bySemanticsLabel('未完成检查项'), findsOneWidget);

    await tester.tap(find.descendant(
        of: find.bySemanticsLabel('已完成检查项'),
        matching: find.byType(InkWell)));
    await tester.pumpAndSettle();
    final uncheckedLines = document.toDelta().toJson().where((op) {
      final attributes = op['attributes'];
      return attributes is Map && attributes['list'] == 'unchecked';
    });
    expect(uncheckedLines, isNotEmpty);
    expect(
        document.toDelta().toJson().any((op) =>
            op['attributes'] is Map && op['attributes']['list'] == 'checked'),
        isFalse);
    expect(document.toPlainText(), '已完成\n待办\n');

    await tester.tap(find.bySemanticsLabel('未完成检查项').first);
    await tester.pumpAndSettle();
    expect(
        document.toDelta().toJson().any((op) =>
            op['attributes'] is Map && op['attributes']['list'] == 'checked'),
        isTrue);
  });
}
