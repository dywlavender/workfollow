# Editor list marker stability

## Reproduced issue — 2026-10-03

Entering `plp` in a list, pressing Return to continue the list, then Return
to exit the empty list item moved the preceding marker 16pt left. A further
Return restored its position. Bullet, ordered and checklist blocks reproduced
the same failure in a real NSWindow render test.

## Rule

Decorations for existing characters must use character-range geometry, not
zero-length insertion geometry. TextKit can resolve the latter using the current
typing paragraph's indent after leaving a trailing list. Only the characterless
final paragraph uses insertion geometry.

This is a drawing-only correction: it must not change stored list indentation,
Return semantics, content or selection.

## Verification

- Regression checks the first item's x-coordinate before Return, after list
  continuation, after exiting the empty item and after a further newline.
- Before the fix: all three list kinds failed, with x changing from 41pt to 25pt.
- After the fix: 38 content, decoration-render and format-style tests passed.
- Actual NSWindow capture inspected: `/tmp/render_list_double_return.png`.
- This render workflow does not claim a separate manual Inspector typing check.

## Follow-up: drawing and hit testing share geometry

- Reproduced a second failure: after exiting a checklist, a mouse click inside
  the visible checkbox's right edge did not toggle it. Drawing used character
  geometry but hit testing still queried zero-length insertion geometry.
- Checklist hit testing and the empty-line plus now use `viewRect` too. The
  original hit-area sizes and document behavior are preserved. Caret-following
  Slash positioning and selection popups intentionally retain their own range
  queries; these follow the caret/selection, not an earlier paragraph.
- Added real-window mouse-event regression for the visible checkbox edge,
  H1/H2/H3 and quote geometry under trailing format changes, and plus-menu
  activation immediately after leaving each list kind without inserting text.
- The plus regression also reproduced a trailing-empty-line failure: gutter
  insertion lookup resolved the previous paragraph. Hit testing now uses the
  active paragraph, matching the plus's active-line-only drawing policy.
- Final run: 42 decoration-render, content, format-style and editor-state tests
  passed; updated list-exit screenshot inspected. This is real NSWindow test
  coverage, not a separate manual typing acceptance in the Inspector.
