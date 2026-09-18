import 'package:flutter/material.dart';

import '../../../theme/workfollow_icons.dart';
import '../../../theme/workfollow_theme.dart';
import '../../../widgets/app_icon_button.dart';
import '../document_keys.dart';

/// The single formatting-toolbar trigger shared by task and note editors.
class DocumentFormattingToggle extends StatelessWidget {
  const DocumentFormattingToggle({
    super.key,
    required this.active,
    required this.onPressed,
  });

  final bool active;
  final void Function(BuildContext anchor) onPressed;

  @override
  Widget build(BuildContext context) {
    final tokens = WorkFollowTheme.of(context);
    return Builder(
      builder: (anchor) => AppIconButton(
        key: documentFormattingToggleKey,
        icon: WorkFollowIcons.format,
        tooltip: active ? '格式工具已打开' : '显示格式工具',
        active: active,
        activeBackgroundColor: tokens.canvas,
        iconColor: tokens.textSecondary,
        onPressed: () => onPressed(anchor),
        size: WorkFollowMetrics.iconHitTarget,
        iconSize: WorkFollowMetrics.toolbarIcon,
      ),
    );
  }
}
