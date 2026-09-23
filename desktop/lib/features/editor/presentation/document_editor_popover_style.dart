import 'package:flutter/material.dart';

import '../../../theme/workfollow_theme.dart';
import '../../../widgets/task_menu_style.dart';

/// Theme extension used by floating controls shared across document surfaces.
class DocumentEditorPopoverStyle {
  const DocumentEditorPopoverStyle._();

  static ThemeData theme(BuildContext context) {
    final base = Theme.of(context);
    final colors = TaskMenuStyle.colors(context);
    return base.copyWith(extensions: [
      ...base.extensions.values
          .where((extension) => extension is! WorkFollowTheme),
      colors,
    ]);
  }
}
