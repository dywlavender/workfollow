# Editor toolbar: live TickTick comparison

Reference inspected in the installed TickTick macOS app on 2026-10-02.
This is a local presentation correction, not an Editor Platform or Slash redesign.

## Contract

- Time insertion order: Chinese date + time, Chinese date, slash date, time.
- Labels show current values; the corresponding format is passed to the existing TextKit insertion command.
- Heading picker preserves Paragraph plus H1/H2/H3. H₁/H₂/H₃ badges are decorative only, never inserted into document content.
- Keep command order, active formatting feedback, and 26 × 28 hit areas.
- Format toolbar component metrics centralize glyph size, card outline and shadow. Existing theme colors remain the source of truth.
- Do not invent the purpose of TickTick's four-corner toolbar entry; it remains unimplemented pending reference verification.

## Verification

- 15 DocumentProfileTests / DocumentEditorStateTests passed.
- Includes all four format strings, menu height, heading badges and stable hit areas.
- Each date/time menu value was tested against actual NativeTextView insertion with the same fixed date.
- Fresh build was opened: title picker shows H₁/H₂/H₃ and Paragraph; time picker shows four formats in reference order.
- Switching Heading → Time replaces the child picker; screenshot shows no parent toolbar resizing.
- Existing task body was not edited during screenshot checks.
- Escape workflow is **not accepted**: during key dispatch the observed window changed navigation, appearance and size; the computer-use tool also reported external state changes. Re-test in a stable single-instance session before attributing this to application code.
- Dark/narrow-window visual equivalence and exact pixel parity are not claimed by this verification.

## Text-style glyph refinement — 2026-10-03

- Use 14pt symbols (13pt inline code), preserving 26 × 28pt hit areas and 444 × 38pt toolbar geometry.
- Checklist, bullet, ordered list, quote and divider reuse the shared editor glyphs. Checklist is a single checked box; divider uses dashed outer rules; quote uses paired quotation marks.
- Time uses `clock.arrow.circlepath`; group dividers have 5pt side insets. Card radius is 8pt with no hard outline.
- Highlight preview uses the document engine's yellow at 45% opacity, not a visually similar color that differs from inserted text.
- 31 DocumentProfileTests / DocumentFormatStyleTests passed, including rendered button order, hit-area geometry and a real Bold-button click preserving selection.
- Light and dark component screenshots inspected: `/tmp/render_text_style_toolbar_light.png`, `/tmp/render_text_style_toolbar_dark.png`.
- Fresh build opened in the actual task inspector: clicking “正文格式” displayed all 15 controls in dark mode, above the footer without clipping. Existing task content was not edited.
- This check does not establish narrow-window fit or new Escape acceptance; those remain separate from this glyph-only change.
