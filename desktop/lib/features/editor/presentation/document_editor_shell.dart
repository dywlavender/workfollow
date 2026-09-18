import 'package:flutter/material.dart';

/// The shared outer layout for editable task and note documents.
///
/// The shell owns only the surface and the header/body/footer slots. The
/// slots retain their own content sizing, scrolling, focus, and lifecycle so
/// task and note editors can use different document-height models.
class DocumentEditorShell extends StatelessWidget {
  const DocumentEditorShell({
    super.key,
    required this.body,
    this.header,
    this.footer,
    this.backgroundColor,
    this.mainAxisSize = MainAxisSize.max,
  });

  final Widget? header;
  final Widget body;
  final Widget? footer;
  final Color? backgroundColor;
  final MainAxisSize mainAxisSize;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: backgroundColor,
      child: Column(
        mainAxisSize: mainAxisSize,
        children: [
          if (header != null) header!,
          body,
          if (footer != null) footer!,
        ],
      ),
    );
  }
}
