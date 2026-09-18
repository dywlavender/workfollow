import 'dart:math' as math;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

import '../../theme/workfollow_theme.dart';

/// Measures the title before giving the document the remaining viewport.
/// Both children grow within the inspector's single scroll view.
class DocumentEditorViewport extends MultiChildRenderObjectWidget {
  DocumentEditorViewport({
    super.key,
    required this.minHeight,
    required Widget title,
    required Widget document,
  }) : super(children: [title, document]);

  final double minHeight;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderDocumentEditorViewport(minHeight);

  @override
  void updateRenderObject(
      BuildContext context, covariant _RenderDocumentEditorViewport renderObject) {
    renderObject.minHeight = minHeight;
  }
}

class _ViewportParentData extends ContainerBoxParentData<RenderBox> {}

class _RenderDocumentEditorViewport extends RenderBox
    with
        ContainerRenderObjectMixin<RenderBox, _ViewportParentData>,
        RenderBoxContainerDefaultsMixin<RenderBox, _ViewportParentData> {
  _RenderDocumentEditorViewport(this._minHeight);

  double _minHeight;
  static const gap = WorkFollowSpacing.controlGap;

  set minHeight(double value) {
    if (_minHeight == value) return;
    _minHeight = value;
    markNeedsLayout();
  }

  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! _ViewportParentData) {
      child.parentData = _ViewportParentData();
    }
  }

  @override
  void performLayout() {
    final title = firstChild!;
    final document = lastChild!;
    final width = constraints.maxWidth;
    title.layout(BoxConstraints.tightFor(width: width), parentUsesSize: true);
    final documentTop = title.size.height + gap;
    document.layout(
      BoxConstraints(
        minWidth: width,
        maxWidth: width,
        minHeight: math.max(0, _minHeight - documentTop),
      ),
      parentUsesSize: true,
    );
    (title.parentData! as _ViewportParentData).offset = Offset.zero;
    (document.parentData! as _ViewportParentData).offset =
        Offset(0, documentTop);
    size =
        constraints.constrain(Size(width, documentTop + document.size.height));
  }

  @override
  void paint(PaintingContext context, Offset offset) =>
      defaultPaint(context, offset);

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) =>
      defaultHitTestChildren(result, position: position);
}
