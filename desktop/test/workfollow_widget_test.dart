import 'package:flutter_test/flutter_test.dart';

import 'package:workfollow_personal/app.dart';

void main() {
  testWidgets('renders the personal today workspace', (tester) async {
    await tester.pumpWidget(const WorkFollowApp());
    await tester.pumpAndSettle();

    expect(find.text('今天'), findsWidgets);
    expect(find.text('准备季度产品评审演示文稿'), findsOneWidget);
    expect(find.text('记下下一件事…'), findsOneWidget);
  });

  testWidgets('opens the notes view from the sidebar', (tester) async {
    await tester.pumpWidget(const WorkFollowApp());
    await tester.pumpAndSettle();

    await tester.tap(find.text('笔记').first);
    await tester.pumpAndSettle();

    expect(find.text('季度评审 · 叙事结构'), findsWidgets);
    expect(find.text('把想法写下来，任务就有了可以回来的地方。'), findsOneWidget);
  });
}
