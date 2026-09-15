import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:workfollow_personal/theme/workfollow_theme.dart';
import 'package:workfollow_personal/widgets/desktop_popover.dart';

void main() {
  const entries = [
    DesktopMenuEntry('first', '第一项'),
    DesktopMenuEntry('second', '第二项'),
    DesktopMenuEntry('third', '第三项'),
  ];

  testWidgets('bottom anchored menus open directly above their trigger',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: WorkFollowThemeData.light(),
      home: Scaffold(
        body: Align(
          alignment: Alignment.bottomRight,
          child: Builder(
            builder: (anchor) => IconButton(
              key: const ValueKey('popover-bottom-trigger'),
              onPressed: () =>
                  showDesktopMenu<String>(anchor, entries: entries),
              icon: const Icon(Icons.more_horiz),
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.byKey(const ValueKey('popover-bottom-trigger')));
    await tester.pumpAndSettle();

    final trigger =
        tester.getRect(find.byKey(const ValueKey('popover-bottom-trigger')));
    final lastItem =
        tester.getRect(find.byKey(const ValueKey('menu-option-third')));
    expect(lastItem.bottom, lessThanOrEqualTo(trigger.top));
    expect(trigger.top - lastItem.bottom, lessThan(20));
  });

  testWidgets('top anchored menus remain below their trigger', (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: WorkFollowThemeData.light(),
      home: Scaffold(
        body: Align(
          alignment: Alignment.topLeft,
          child: Builder(
            builder: (anchor) => TextButton(
              key: const ValueKey('popover-top-trigger'),
              onPressed: () =>
                  showDesktopMenu<String>(anchor, entries: entries),
              child: const Text('打开'),
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.byKey(const ValueKey('popover-top-trigger')));
    await tester.pumpAndSettle();

    final trigger =
        tester.getRect(find.byKey(const ValueKey('popover-top-trigger')));
    final firstItem =
        tester.getRect(find.byKey(const ValueKey('menu-option-first')));
    expect(firstItem.top, greaterThanOrEqualTo(trigger.bottom));
    expect(firstItem.top - trigger.bottom, lessThan(20));
  });

  testWidgets('desktop menus support arrow navigation and Enter',
      (tester) async {
    Future<String?>? result;
    await tester.pumpWidget(MaterialApp(
      theme: WorkFollowThemeData.light(),
      home: Scaffold(
        body: Builder(
          builder: (anchor) => TextButton(
            key: const ValueKey('keyboard-menu-trigger'),
            onPressed: () => result = showDesktopMenu<String>(
              anchor,
              entries: entries,
            ),
            child: const Text('打开'),
          ),
        ),
      ),
    ));
    await tester.tap(find.byKey(const ValueKey('keyboard-menu-trigger')));
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();

    expect(await result, 'second');
  });

  testWidgets('Escape closes only the menu and restores trigger focus',
      (tester) async {
    final triggerFocus = FocusNode(debugLabel: 'popover-trigger');
    addTearDown(triggerFocus.dispose);
    Future<String?>? result;
    await tester.pumpWidget(MaterialApp(
      theme: WorkFollowThemeData.light(),
      home: Scaffold(
        body: Builder(
          builder: (anchor) => TextButton(
            key: const ValueKey('escape-menu-trigger'),
            focusNode: triggerFocus,
            onPressed: () => result = showDesktopMenu<String>(
              anchor,
              entries: entries,
            ),
            child: const Text('打开'),
          ),
        ),
      ),
    ));
    triggerFocus.requestFocus();
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('escape-menu-trigger')));
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();

    expect(await result, isNull);
    expect(triggerFocus.hasFocus, isTrue);
  });

  testWidgets('outside click dismisses the menu without selecting an item',
      (tester) async {
    Future<String?>? result;
    await tester.pumpWidget(MaterialApp(
      theme: WorkFollowThemeData.light(),
      home: Scaffold(
        body: Center(
          child: Builder(
            builder: (anchor) => TextButton(
              key: const ValueKey('outside-menu-trigger'),
              onPressed: () => result = showDesktopMenu<String>(
                anchor,
                entries: entries,
              ),
              child: const Text('打开'),
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.byKey(const ValueKey('outside-menu-trigger')));
    await tester.pumpAndSettle();
    await tester.tapAt(const Offset(20, 20));
    await tester.pumpAndSettle();

    expect(await result, isNull);
    expect(find.byKey(const ValueKey('menu-option-first')), findsNothing);
  });
}
