import 'package:flutter/material.dart';

import 'workfollow_theme.dart';

/// The interaction state vocabulary used by desktop controls.
///
/// The enum is intentionally small. A selected row is not a focused row, and
/// a destructive action is a semantic intent rather than a red background.
enum WorkFollowInteractionState {
  defaultState,
  hover,
  pressed,
  selected,
  focused,
  disabled,
  destructive,
}

/// Shared state resolution for rows, menus and controls.
///
/// This class only consumes existing semantic theme roles. It does not define
/// a new palette, geometry, or animation. Callers can use [fill] for custom
/// painted rows and [overlay] for Material controls so the same precedence is
/// used for pointer, keyboard and disabled states.
class WorkFollowInteractionStyles {
  const WorkFollowInteractionStyles._();

  /// Resolves a Material state set using one stable precedence order.
  ///
  /// Disabled wins over every other state. Pressed wins over selection and
  /// hover. Focus is kept separate from fill states so a keyboard focus ring
  /// can be added without changing the selected surface.
  static WorkFollowInteractionState resolve(
    Set<WidgetState> states, {
    bool selected = false,
    bool destructive = false,
  }) {
    if (states.contains(WidgetState.disabled)) {
      return WorkFollowInteractionState.disabled;
    }
    if (states.contains(WidgetState.pressed)) {
      return WorkFollowInteractionState.pressed;
    }
    if (selected) {
      return WorkFollowInteractionState.selected;
    }
    if (states.contains(WidgetState.focused)) {
      return WorkFollowInteractionState.focused;
    }
    if (states.contains(WidgetState.hovered)) {
      return WorkFollowInteractionState.hover;
    }
    if (destructive) {
      return WorkFollowInteractionState.destructive;
    }
    return WorkFollowInteractionState.defaultState;
  }

  /// Fill for a custom row or surface.
  ///
  /// Focus deliberately has no fill. The caller can use [focusBorder] to
  /// render an independent focus ring. Destructive controls remain neutral in
  /// their default state and receive a restrained danger tint only while the
  /// pointer is over or pressing them.
  static Color? fill(
    WorkFollowTheme tokens, {
    bool selected = false,
    bool hovered = false,
    bool pressed = false,
    bool focused = false,
    bool enabled = true,
    bool destructive = false,
    bool menu = false,
  }) {
    if (!enabled) return null;
    if (destructive && (hovered || pressed)) {
      return tokens.danger.withValues(alpha: .12);
    }
    if (pressed) return tokens.listRowSelected;
    if (selected) return menu ? tokens.menuSelected : tokens.listRowSelected;
    if (hovered) return menu ? tokens.menuSelected : tokens.listRowHover;
    // Focus is represented by a ring, rather than turning focus into a
    // second selected state.
    if (focused) return null;
    return null;
  }

  /// Resolves a custom shell's state without replacing its existing semantic
  /// colors. Navigation rails and user-colored list entries can provide their
  /// own selected/hover fills while sharing the same precedence and pressed
  /// behavior as menus.
  static Color customFill({
    required Color defaultColor,
    required Color hoverColor,
    required Color selectedColor,
    Color? pressedColor,
    bool selected = false,
    bool hovered = false,
    bool pressed = false,
    bool enabled = true,
  }) {
    if (!enabled) return defaultColor;
    if (pressed) return pressedColor ?? selectedColor;
    if (selected) return selectedColor;
    if (hovered) return hoverColor;
    return defaultColor;
  }

  static Color foreground(
    WorkFollowTheme tokens, {
    bool enabled = true,
    bool destructive = false,
  }) {
    if (!enabled) return tokens.textDisabled;
    if (destructive) return tokens.danger;
    return tokens.textPrimary;
  }

  /// Focus is a border concern, independent from hover and selection fills.
  static BorderSide focusBorder(
    WorkFollowTheme tokens, {
    required bool focused,
    double width = 1,
  }) {
    return focused
        ? BorderSide(color: tokens.focusRing, width: width)
        : BorderSide.none;
  }

  /// Fallback focus treatment for Material ink controls whose decoration is
  /// owned by a parent. It is deliberately subtle and does not replace a
  /// selected fill.
  static Color focusColor(WorkFollowTheme tokens) =>
      tokens.focusRing.withValues(alpha: .12);

  /// State overlay for Material controls. A focused control does not get a
  /// second selected background; Material focus is left for the control's
  /// focus ring or focus border.
  static WidgetStateProperty<Color?> overlay(
    WorkFollowTheme tokens, {
    bool destructive = false,
    bool menu = false,
  }) {
    return WidgetStateProperty.resolveWith<Color?>((states) {
      if (states.contains(WidgetState.disabled)) return null;
      // Pointer feedback is independent from a selected fill. This lets an
      // already-selected control still show pressed feedback while keeping
      // the selected surface itself stable.
      if (states.contains(WidgetState.pressed)) {
        return destructive
            ? tokens.danger.withValues(alpha: .14)
            : tokens.listRowSelected;
      }
      if (states.contains(WidgetState.hovered)) {
        return destructive
            ? tokens.danger.withValues(alpha: .10)
            : (menu ? tokens.menuSelected : tokens.listRowHover);
      }
      // Selected surfaces are painted by the control itself. Focus receives a
      // separate, low-alpha ring tint rather than reusing the selected fill.
      if (states.contains(WidgetState.focused)) {
        return focusColor(tokens);
      }
      return null;
    });
  }
}
