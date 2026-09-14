import 'package:flutter_test/flutter_test.dart';

import 'package:workfollow_personal/services/focus_timer.dart';

void main() {
  test('focus timer schedules and cancels the native notification', () async {
    final scheduled = <String>[];
    final cancelled = <String>[];
    String? completedTask;
    final timer = FocusTimerController(
      scheduleNotification: (id, _) async => scheduled.add(id),
      cancelNotification: (id) async => cancelled.add(id),
      onCompleted: (taskId) => completedTask = taskId,
    );
    addTearDown(timer.dispose);

    timer.setDuration(15);
    timer.setTask('task-01');
    expect(timer.display, '15:00');
    timer.start();
    await Future<void>.delayed(Duration.zero);
    expect(timer.isRunning, isTrue);
    expect(timer.hasStarted, isTrue);
    expect(scheduled, hasLength(1));
    expect(completedTask, isNull);

    timer.pause();
    await Future<void>.delayed(Duration.zero);
    expect(timer.isRunning, isFalse);
    expect(cancelled, hasLength(1));

    timer.reset();
    expect(timer.hasStarted, isFalse);
    expect(timer.display, '15:00');
  });
}
