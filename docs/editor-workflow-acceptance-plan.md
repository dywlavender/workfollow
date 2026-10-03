# Native editor workflow acceptance

Date: 2026-10-03. Scope: Task Inspector and Note editor, shared Native editor.
No new commands, Slash redesign, popup migration or unrelated visual changes.

## Execution order and gates

| Stage | Cases | Pass criteria | Evidence |
| --- | --- | --- | --- |
| 1. Paragraph interaction | Bullet, ordered, checklist: input → Return → Return exit → another newline; H1/H2/H3 and quote format switches; empty-line plus | Earlier markers do not move; visible checkbox toggles; plus opens on its displayed line without inserting text; content origin remains stable | Real-window regression tests plus Task/Note main-app screenshots |
| 2. Inline formatting | Bold, italic, underline, strikethrough, highlight, inline code; link; selected and caret-only input; mixed selection | Applied/cancelled marks match text and toolbar state; selection/content preserved; insertion follows defined current engine behavior | Lifecycle tests plus main-app toolbar checks |
| 3. Undo and persistence | Apply/cancel, checkbox toggle, replacement/reference; undo/redo; switch document and reopen | Undo/redo republishes correct model; no cross-document undo; saved text, block kinds, marks and links survive reload | Transaction/state/JSON tests and main-app document reopen |
| 4. Closeout | Integrate confirmed fixes only, rerun affected suites, inspect screenshots | Each stage records automatic vs manual evidence separately; unverified cases remain pending | Final status below and linked defect contracts |

## Operating rules

- Use dedicated acceptance task/note; do not edit existing user content.
- Existing-character geometry and characterless trailing-line geometry are distinct.
- Display and hit testing share the same origin; caret/selection-following panels
  intentionally query the caret/selection rather than previous paragraphs.
- No visual result is inferred solely from a model test. Main-app actions and
  rendered test-window actions are explicitly distinguished.
- A failed case is reproduced first, fixed narrowly, rerun, then marked passed.
- Preserve current production semantics unless reference evidence authorizes a change.

## Execution record

### Stage 1 — regression gate passed

Real-window tests cover marker stability, checklist-edge hit testing, trailing
plus activation, and H1/H2/H3/quote geometry. Main-app Task and Note checks
confirmed list exit, checklist clicking, and continuous quote rendering.
Task plus opened the Slash menu on the displayed empty line without inserting
text. Note plus was visually inspected; its activation is covered by the shared
real-window test, not a separate main-app click.

The main-app workflow exposed checked-checklist presentation leaking into a new
heading. Completion strike is now marked as presentation-only, excluded from
decoded user marks, and normalized out of non-checklist display runs. Explicit
user strikethrough on ordinary text remains intact. Latest Note screenshot and
Task reopen both show the new heading without a strike.

### Stage 2 — regression gate passed

One gpt-6-luna/max owner added inline lifecycle/serialization tests and the exact
attribute replacement fix in DocumentFormatCommand.swift. Main agent integrated
and checked the actual toolbar workflow. Native attributed insertion retained
omitted old attributes, causing underline/strike/highlight/code cancellation to
fail. Rendered attributes are now reapplied exactly while retaining links and
attachments, selection, and the existing undo path.

Selected-text application/cancellation of all six marks was exercised in the
Note main app. Bold/italic/underline/strike were confirmed through AX changes;
highlight through unselected screenshots; code through toolbar state and saved
marks because Chinese glyphs provide little visible monospace distinction.
Caret-only input and mixed selections have automated coverage, not separate
main-app screenshot coverage.

### Stage 3 — regression gate passed

Actual saving exposed a second defect missed by storage-only tests: insertText
published before the final attribute correction, leaving removed marks in the
saved model. Inline formatting now republishes after final storage/selection
correction. A coordinator-callback regression tests cancellation, link retention,
undo and redo for underline/strike/highlight/code.

Latest main-app verification: cancel highlight on linked text → inspect saved
marks (link only) → quit → relaunch → reopen Note. Highlight stays removed, link
and block kinds survive. Task checked state and clean heading also survived an
earlier quit/relaunch. Cross-document undo isolation, reference/replacement and
checkbox replay are covered by the transaction/state suites, not all repeated
manually.

### Stage 4 — scoped closeout complete

74 tests passed, zero failures, in these selected suites:
DocumentDecorationRenderTests, DocumentContentTests, DocumentFormatStyleTests,
DocumentEditorStateTests, DocumentContentTransactionTests, NativeDocumentTests,
DocumentProfileTests. Log: `/private/tmp/workfollow-editor-acceptance-integrated.log`.
`git diff --check` passed. At the acceptance closeout, no commit or push had been performed.

Before the requested remote submission, the staged files were exported into an
isolated checkout and the same 74 tests passed with zero failures. This excludes
uncommitted Schedule, shell configuration and task-list changes. The existing
tracked sidebar required the uncommitted `mainWindowRailInset` definition; that
definition was extracted to MainWindowRailInset.swift as a minimal build
dependency, leaving window chrome activation/configuration uncommitted.
Isolated log: `/private/tmp/workfollow-staged-editor-tests.log`.

## Case evidence matrix

| Case | Automated evidence | Main-app evidence | Result |
| --- | --- | --- | --- |
| Bullet / ordered double Return exit | Real-window geometry and content tests | Task and Note screenshots, markers remain aligned | Passed |
| Visible checklist edge hit | Actual mouse event test | Task and Note checkbox toggles | Passed |
| Empty-line plus | Shared real-window activation test | Task menu opens; Note plus visible and unclipped | Passed; Note activation not separately clicked |
| H1/H2/H3 switching and content origin | Real-window heading geometry | Task H1/H2/H3; Note H1 | Passed; Note H2/H3 automated only |
| Consecutive quote rows | Decoration/content coverage | Task and Note continuous rule screenshot | Passed |
| Checked row → new heading | Decode/display regression tests | Latest Note clean H1; Task reopen clean H1 | Passed |
| Six inline marks apply/cancel | Exact-mark lifecycle tests | Note selected text toggled through toolbar | Passed |
| Caret marks across newline / mixed selection | Lifecycle and active-style tests | Not separately replayed | Automated pass |
| Link retention during style removal | Link/attachment selection test and callback test | Note linked text retains URL after highlight removal | Passed |
| Attribute correction reaches save callback | New transaction regression | Saved Note has link only after highlight cancellation | Passed |
| Undo / redo | Transaction tests, including final callback marks | Note Edit menu restores code mark then removes it; saved marks inspected | Passed |
| JSON / codec / document rebind | Serialization/state/profile tests | Task and Note quit/relaunch/reopen | Passed |

## Evidence boundaries and retained fixtures

- Main-app screenshots are displayed inline in this conversation, not exported
  image artifacts. This is not a full UI automation suite.
- Main-app acceptance used light mode and the current wide window. Dark/narrow
  windows, IME composition and every Task/Note toolbar permutation were not
  separately accepted here; no global all-editor/all-theme claim is made.
- Quote double Return currently continues quote blocks; this run did not change
  that pre-existing behavior or establish new TickTick parity for it.
- Explicit strikethrough on a checked checklist remains filtered by the existing
  codec contract. Independent strike persistence inside checked items was not
  changed or accepted in this stage.
- Dedicated fixtures retained: `编辑器流程验收 1003`, `编辑器格式隔离验收 1003`,
  `编辑器检查项复验 1003`, `笔记编辑器流程验收 1003`. Earlier reproduction fixtures
  may intentionally contain pre-fix output; no existing user document was edited.
