import 'package:flutter/material.dart';

import 'task_date_picker.dart';

class TaskReminderPicker {
  const TaskReminderPicker._();

  static Future<TaskDateSelection?> show(BuildContext anchor,
      {String? value}) {
    return showTaskDatePicker(anchor,
        value: value, title: '提醒我', reminder: true, allowTime: true);
  }
}
