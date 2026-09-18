import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart' as quill;
import 'package:flutter_test/flutter_test.dart';

import 'package:workfollow_personal/features/editor/document_styles.dart';
import 'package:workfollow_personal/theme/workfollow_theme.dart';

void main() {
  testWidgets('ordered and unordered list markers render in accent',
      (tester) async {
    // This is a render-path contract, not a style-object check: quill's
    // _buildLeading copies DefaultStyles.leading and only overrides the color
    // when the line's first operation carries an explicit color attribute, so
    // the accent must survive into the painted marker widgets. If a quill
    // upgrade stops routing leading through DefaultStyles this fails loudly
    // instead of silently regressing to black markers.
    final controller = quill.QuillController(
      document: quill.Document.fromJson([
        {
          'insert': '有序项\n',
          'attributes': {'list': 'ordered'}
        },
        {
          'insert': '无序项\n',
          'attributes': {'list': 'bullet'}
        },
      ]),
      selection: const TextSelection.collapsed(offset: 0),
    );
    addTearDown(controller.dispose);

    await tester.pumpWidget(MaterialApp(
      theme: WorkFollowThemeData.light(),
      home: Scaffold(
        body: quill.QuillEditor(
          controller: controller,
          focusNode: FocusNode(),
          scrollController: ScrollController(),
          config: quill.QuillEditorConfig(
            customStyles: DocumentStyles.build(WorkFollowTheme.light),
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();

    final number = tester.widget<Text>(find.text('1.'));
    expect(number.style?.color, WorkFollowTheme.light.accent,
        reason: '有序列表序号应为 accent 蓝');
    final bullet = tester.widget<Text>(find.text('•'));
    expect(bullet.style?.color, WorkFollowTheme.light.accent,
        reason: '无序列表圆点应为 accent 蓝');

    // The body text keeps the primary colour: only the marker is tinted.
    final bodyRich = tester
        .widgetList<RichText>(find.byType(RichText))
        .firstWhere((rich) => rich.text.toPlainText().contains('有序项'));
    TextSpan? bodySpan;
    void walk(TextSpan span) {
      if (span.text == '有序项') {
        bodySpan = span;
        return;
      }
      for (final child
          in span.children?.whereType<TextSpan>() ?? const <TextSpan>[]) {
        walk(child);
      }
    }

    walk(bodyRich.text as TextSpan);
    // A null span colour means it inherits the paragraph's DefaultTextStyle,
    // which DocumentStyles already pins to textPrimary — either way the body
    // must not take the marker's accent.
    expect(bodySpan?.style?.color, isNot(WorkFollowTheme.light.accent));
  });
}
