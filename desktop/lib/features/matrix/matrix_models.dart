import 'package:flutter/material.dart';

import '../../models/task.dart';
import '../../state/workspace_controller.dart';
import '../../theme/workfollow_color_tokens.dart';

/// The small, fixed visual vocabulary used by the four matrix quadrants.
///
/// This is deliberately separate from [TaskItem]. A task only stores the
/// properties from which a quadrant is derived; the matrix owns the label and
/// colour that make that derived value legible.
@immutable
class MatrixQuadrantStyle {
  const MatrixQuadrantStyle({
    required this.quadrant,
    required this.numeral,
    required this.title,
    required this.color,
  });

  final MatrixQuadrant quadrant;
  final String numeral;
  final String title;
  final Color color;

  static MatrixQuadrantStyle forQuadrant(MatrixQuadrant quadrant) {
    return switch (quadrant) {
      MatrixQuadrant.doNow => const MatrixQuadrantStyle(
          quadrant: MatrixQuadrant.doNow,
          numeral: 'I',
          title: '重要且紧急',
          color: WorkFollowColorTokens.matrixDoNow),
      MatrixQuadrant.schedule => const MatrixQuadrantStyle(
          quadrant: MatrixQuadrant.schedule,
          numeral: 'II',
          title: '重要不紧急',
          color: WorkFollowColorTokens.matrixSchedule),
      MatrixQuadrant.delegate => const MatrixQuadrantStyle(
          quadrant: MatrixQuadrant.delegate,
          numeral: 'III',
          title: '不重要但紧急',
          color: WorkFollowColorTokens.matrixDelegate),
      MatrixQuadrant.later => const MatrixQuadrantStyle(
          quadrant: MatrixQuadrant.later,
          numeral: 'IV',
          title: '不重要不紧急',
          color: WorkFollowColorTokens.matrixLater),
    };
  }
}

@immutable
class MatrixTaskViewModel {
  const MatrixTaskViewModel({
    required this.task,
    required this.listName,
    required this.dateLabel,
    required this.overdue,
    required this.hasNote,
    required this.hasSubtasks,
    required this.hasReminder,
    required this.recurring,
  });

  final TaskItem task;
  final String listName;
  final String? dateLabel;
  final bool overdue;
  final bool hasNote;
  final bool hasSubtasks;
  final bool hasReminder;
  final bool recurring;
}

@immutable
class MatrixGroupViewModel {
  const MatrixGroupViewModel({
    required this.id,
    required this.title,
    required this.count,
    required this.completedGroup,
    required this.tasks,
  });

  final String id;
  final String title;
  final int count;
  final bool completedGroup;
  final List<MatrixTaskViewModel> tasks;
}

@immutable
class MatrixQuadrantViewModel {
  const MatrixQuadrantViewModel({
    required this.quadrant,
    required this.groups,
  });

  final MatrixQuadrant quadrant;
  final List<MatrixGroupViewModel> groups;

  MatrixQuadrantStyle get style => MatrixQuadrantStyle.forQuadrant(quadrant);

  int get taskCount => groups.fold(0, (total, group) => total + group.count);
}
