import 'package:flutter/material.dart';

import 'workfollow_theme.dart';

/// The material roles used by desktop surfaces.
///
/// A role describes the complete material treatment (corner shape, border and
/// shadow). It deliberately does not describe interaction colors; those remain
/// in [WorkFollowTheme] and are applied by the owning widget.
enum WorkFollowSurfaceRole { surface, input, card, popover, dialog, toast }

/// Shared shadow levels for desktop surfaces.
///
/// The values mirror the Web design-token levels while keeping the existing
/// theme shadow color. Widgets should select a role instead of inventing a
/// blur/offset pair at the call site.
class WorkFollowShadows {
  const WorkFollowShadows._();

  static const double level0Elevation = 0;
  static const double level1Elevation = 1;
  static const double level2Elevation = 6;
  static const double level3Elevation = 16;
  static const double level4Elevation = 24;

  static List<BoxShadow> level1(WorkFollowTheme tokens) => _single(
        tokens,
        blurRadius: 2,
        offset: const Offset(0, 1),
      );

  static List<BoxShadow> level2(WorkFollowTheme tokens) => _single(
        tokens,
        blurRadius: 18,
        offset: const Offset(0, 6),
      );

  static List<BoxShadow> level3(WorkFollowTheme tokens) => _single(
        tokens,
        blurRadius: 64,
        offset: const Offset(0, 24),
      );

  static List<BoxShadow> level4(WorkFollowTheme tokens) => _single(
        tokens,
        blurRadius: 28,
        offset: const Offset(0, 10),
      );

  static List<BoxShadow> detail(WorkFollowTheme tokens) => _single(
        tokens,
        blurRadius: WorkFollowComponentTokens.detailShadowBlur,
        offset: const Offset(WorkFollowComponentTokens.detailShadowOffset, 0),
      );

  static List<BoxShadow> _single(
    WorkFollowTheme tokens, {
    required double blurRadius,
    required Offset offset,
  }) =>
      [
        BoxShadow(
          color: tokens.shadow,
          blurRadius: blurRadius,
          offset: offset,
        ),
      ];
}

/// Material specifications for the shared surface roles.
///
/// This is the single place where a surface's corner, border and shadow are
/// paired. A caller may override the fill or border color for content-specific
/// states, but it cannot silently create a new material tier.
class WorkFollowSurfaceTokens {
  const WorkFollowSurfaceTokens._();

  /// Small geometry exceptions with a semantic owner. These are used by
  /// custom painted markers, rather than becoming anonymous
  /// `BorderRadius.circular(...)` values in feature widgets.
  ///
  /// A completion box is not one of them. Its corner is a fraction of its own
  /// side — `taskCompletionBoxRadius` — because the box is drawn at four
  /// different sizes and has to be the same shape at all of them.
  static const double markerRadius = WorkFollowRadii.marker;

  static BorderRadius radius(WorkFollowSurfaceRole role) =>
      BorderRadius.circular(switch (role) {
        WorkFollowSurfaceRole.surface => WorkFollowRadii.surface,
        WorkFollowSurfaceRole.input => WorkFollowRadii.control,
        WorkFollowSurfaceRole.card => WorkFollowRadii.card,
        WorkFollowSurfaceRole.popover => WorkFollowRadii.popover,
        WorkFollowSurfaceRole.dialog => WorkFollowRadii.popover,
        WorkFollowSurfaceRole.toast => WorkFollowRadii.card,
      });

  static List<BoxShadow>? shadows(
          WorkFollowSurfaceRole role, WorkFollowTheme tokens) =>
      switch (role) {
        WorkFollowSurfaceRole.surface || WorkFollowSurfaceRole.input => null,
        WorkFollowSurfaceRole.card => WorkFollowShadows.level1(tokens),
        WorkFollowSurfaceRole.popover => WorkFollowShadows.level2(tokens),
        WorkFollowSurfaceRole.dialog => WorkFollowShadows.level3(tokens),
        WorkFollowSurfaceRole.toast => WorkFollowShadows.level4(tokens),
      };

  static Color fill(WorkFollowSurfaceRole role, WorkFollowTheme tokens) =>
      switch (role) {
        WorkFollowSurfaceRole.surface ||
        WorkFollowSurfaceRole.input ||
        WorkFollowSurfaceRole.card =>
          tokens.content,
        WorkFollowSurfaceRole.popover ||
        WorkFollowSurfaceRole.dialog =>
          tokens.overlay,
        WorkFollowSurfaceRole.toast => tokens.feedbackSurface,
      };

  static bool hasBorder(WorkFollowSurfaceRole role) => switch (role) {
        WorkFollowSurfaceRole.surface || WorkFollowSurfaceRole.toast => false,
        WorkFollowSurfaceRole.input ||
        WorkFollowSurfaceRole.card ||
        WorkFollowSurfaceRole.popover ||
        WorkFollowSurfaceRole.dialog =>
          true,
      };

  static BoxDecoration decoration(
    WorkFollowSurfaceRole role,
    WorkFollowTheme tokens, {
    Color? color,
    BorderSide? border,
    BorderRadius? customRadius,
    bool withShadow = true,
  }) {
    final showBorder = hasBorder(role) && border != BorderSide.none;
    return BoxDecoration(
      color: color ?? fill(role, tokens),
      borderRadius: customRadius ?? radius(role),
      border: showBorder
          ? Border.fromBorderSide(border ?? BorderSide(color: tokens.border))
          : null,
      boxShadow: withShadow ? shadows(role, tokens) : null,
    );
  }

  static BoxDecoration card(
    WorkFollowTheme tokens, {
    Color? color,
    Color? borderColor,
    bool elevated = false,
  }) =>
      decoration(
        WorkFollowSurfaceRole.card,
        tokens,
        color: color,
        border: BorderSide(color: borderColor ?? tokens.border),
        withShadow: elevated,
      );

  static BoxDecoration input(WorkFollowTheme tokens,
          {Color? color, Color? borderColor}) =>
      decoration(
        WorkFollowSurfaceRole.input,
        tokens,
        color: color,
        border: BorderSide(color: borderColor ?? tokens.border),
        withShadow: false,
      );

  static BoxDecoration popover(
    WorkFollowTheme tokens, {
    BorderRadius? radius,
    Color? color,
    bool withShadow = true,
  }) =>
      decoration(
        WorkFollowSurfaceRole.popover,
        tokens,
        color: color,
        customRadius: radius,
        withShadow: withShadow,
      );

  static BoxDecoration dialog(WorkFollowTheme tokens) =>
      decoration(WorkFollowSurfaceRole.dialog, tokens);

  static BoxDecoration toast(WorkFollowTheme tokens) =>
      decoration(WorkFollowSurfaceRole.toast, tokens);
}
