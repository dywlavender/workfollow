import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:workfollow_personal/theme/workfollow_motion.dart';
import 'package:workfollow_personal/theme/workfollow_theme.dart';

void main() {
  test('motion roles resolve to the shared timing primitives', () {
    expect(
      WorkFollowMotionTokens.durationFor(WorkFollowMotionRole.hoverTransition),
      WorkFollowMotion.instant,
    );
    expect(
      WorkFollowMotionTokens.durationFor(
          WorkFollowMotionRole.selectionTransition),
      WorkFollowMotion.fast,
    );
    expect(
      WorkFollowMotionTokens.durationFor(WorkFollowMotionRole.panelTransition),
      WorkFollowMotion.normal,
    );
    expect(
      WorkFollowMotionTokens.durationFor(WorkFollowMotionRole.taskComplete),
      const Duration(milliseconds: 200),
    );
    expect(
      WorkFollowMotionTokens.curveFor(WorkFollowMotionRole.popoverEnter),
      WorkFollowMotion.standard,
    );
    expect(
      WorkFollowMotionTokens.curveFor(WorkFollowMotionRole.popoverExit),
      WorkFollowMotionTokens.exit,
    );
    expect(
      WorkFollowMotionTokens.feedbackSpring.damping,
      greaterThan(WorkFollowMotionTokens.feedbackSpring.mass),
    );
  });

  testWidgets('reduced motion keeps a short linear transition and no spring',
      (tester) async {
    Duration? duration;
    Curve? curve;
    final reduced = <SpringDescription?>[];
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(disableAnimations: true),
        child: Builder(
          builder: (context) {
            duration = WorkFollowMotionPolicy.duration(
                context, WorkFollowMotionRole.panelTransition);
            curve = WorkFollowMotionPolicy.curve(
                context, WorkFollowMotionRole.panelTransition);
            reduced.add(WorkFollowMotionPolicy.spring(
                context, WorkFollowMotionRole.taskComplete));
            return const SizedBox.shrink();
          },
        ),
      ),
    );

    expect(duration, WorkFollowMotionTokens.instant);
    expect(curve, WorkFollowMotionTokens.reduced);
    expect(reduced.single, isNull);
  });

  testWidgets('normal motion exposes the completion spring', (tester) async {
    SpringDescription? spring;
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(disableAnimations: false),
        child: Builder(
          builder: (context) {
            spring = WorkFollowMotionPolicy.spring(
                context, WorkFollowMotionRole.feedbackToastEnter);
            return const SizedBox.shrink();
          },
        ),
      ),
    );

    expect(spring, WorkFollowMotionTokens.feedbackSpring);
  });
}
