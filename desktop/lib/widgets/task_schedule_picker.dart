import 'package:flutter/material.dart';

import 'task_date_picker.dart';

class TaskSchedulePicker {
  const TaskSchedulePicker._();

  static Future<TaskDateSelection?> show(BuildContext anchor,
      {String? value, bool? hasTime}) {
    return showTaskDatePicker(anchor, value: value, hasTime: hasTime);
  }
}
