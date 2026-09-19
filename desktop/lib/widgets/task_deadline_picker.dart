import 'package:flutter/material.dart';

import 'task_date_picker.dart';

class TaskDeadlinePicker {
  const TaskDeadlinePicker._();

  static Future<TaskDateSelection?> show(BuildContext anchor, {String? value}) {
    return showTaskDatePicker(anchor,
        value: value, title: '截止日期', allowTime: false);
  }
}
