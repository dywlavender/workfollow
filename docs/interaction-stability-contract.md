# Interaction Stability / Responsiveness

## Architectural boundaries

- UI revisions invalidate presentation. They are not domain events and must not trigger every downstream service.
- WorkspaceStore publishes a committed TaskChangeSet once per outer transaction, including undo. It is the common input for field-aware consumers; commands do not maintain parallel activity or reminder logic.
- TaskActivityStore handles changed entries only. Editor body changes do not produce activity events. Title coalescing and existing persistence semantics remain unchanged.
- Reminders consume only relevant domain changes and coalesce a typing burst before computing signatures. Title/list still update notification copy; body-only changes do not schedule reconciliation. Initial load and countdown reconciliation remain explicit.
- Inspector action panels use the shared borderless child-window presenter. Outside dismissal returns the original mouse event to the owner. A transparent full-pane dismissal shield is forbidden for these nonmodal menus.
- Each action panel owns a fresh picker draft and focus lifecycle. Focus submenu remains an independent child of More; Escape closes child before parent.

## Acceptance

1. Latest complete worktree must build; do not validate a stale app bundle.
2. More → date opens date with one physical click, without mutating the draft on cancel.
3. More → title/body and task selection must deliver the same outside click to the target.
4. Parent/tag picker cancellation discards drafts; apply and undo retain previous semantics.
5. Child clicks keep More alive; Escape is hierarchical; outside click closes the action family.
6. Change-set tests cover no-op, document/title, reminder-relevant changes, creation/deletion, transaction, and undo.
7. Document-only edits must not request reminder reconciliation. Title notification copy must not be permanently stale.

## Scope and limits

This round does not replace the document codec, undo snapshot model, or all list invalidation. Store snapshot diffing still has linear cost; removing redundant downstream work is not a claim that all input paths are constant-time. Actual latency improvement requires matched before/after sampling. Background snapshot persistence already coalesces writes and is preserved.

Verification results are recorded after the latest build and window-flow tests, not inferred from source inspection alone.

## Verification — 2026-10-03

Built and tested the current complete worktree, including its existing unrelated
changes. This is not verification of a previously installed app.

- Selected regression run: 84 test cases; 83 passed without an expected failure.
  One strict expected failure remains: `INTERACTION-FOCUS-001` below. The test
  runner's successful exit is not a full interaction acceptance pass.
- More → date: one physical click opens the date panel; Escape cancels it and
  leaves the task date unchanged. Automated flow repeats this 20 times.
- More → title: one physical click closes More and focuses the title field.
- More → another task: one physical click selects that task and closes More.
- Parent picker, tag draft cancel/reopen/apply/undo, activity viewer and duplicate
  entry pass their actual child-window tests.
- Focus submenu: independent geometry, child clicks retain More, Escape closes
  child before parent, and an outside date click closes the action family.
- Domain publication: no-op, document/title changes, reminder eligibility,
  insertion/deletion, transaction and undo tests pass.
- Reminder stream: document/selection changes produce no delivery; a title burst
  produces one delivery reading the latest committed task; reminder undo delivers
  again. Preview saving remains wired to revision.
- Final regression log: `/private/tmp/workfollow-stability-final-test.log`.
- Latest tested app: `/private/tmp/workfollow-inspector-align/Build/Products/Debug/WorkFollow.app`.

### Historical failed acceptance: INTERACTION-FOCUS-001

Reproduction: focus the title of an empty-body task → open More → click the
visible empty paragraph once. More closes, but the body does not consistently
become first responder. Reproduced both in the window-flow test and with physical
clicks on the final app.

The isolated content-sized editor had a visible native hit area. An initial
Inspector hit-test observation suggested the outer SwiftUI container, but that
observation used the wrong coordinate space: NSView.hitTest requires superview
coordinates. It must not be treated as proof of the root cause. Experimental
SwiftUI gesture/focus compensation was removed after failing acceptance.
The original strict expected failure is superseded by the IS-001 tests below.

Next acceptance gate: repair the Inspector/native editor input boundary, then
verify first-click body focus, caret placement, text selection/drag, decoration
clicks and scrolling without changing document codec or undo semantics. No
overall responsiveness or latency percentage is claimed by this round.

## INTERACTION-STABILITY-001 stage gates

Execute IS-001 → IS-002 → IS-003 → IS-004. No new features. A stage's passing
tests do not imply the later stages have passed.

### IS-001 implementation

- Inspector action panels retain the shared borderless child-window presenter;
  outside dismissal observes and returns the original mouse event. There is no
  pane-sized transparent dismissal shield.
- Content-sized DocumentEditor now hosts NativeTextView directly; only the host
  scroll container owns scrolling. Full-height standalone editors retain their
  own native NSScrollView.
- The content-sized native view has a 48pt minimum hit area and host-managed
  height. Native editable mouseDown explicitly acquires first responder before
  normal selection/drag handling.
- Scroll-range and caret-follow requests use the host's document coordinates.
  Growth, selection retention and scrolling are regression-tested together.
- The former expected-failure test has been replaced by explicit host-hit and
  native mouseDown tests. Synthetic NSApplication dispatch in this harness did
  not reach NSTextView.mouseDown; the integrated single-click focus gate is
  therefore checked with physical UI input, not inferred from those unit tests.

### Remaining stages

- IS-002: audit popup families across Inspector, Quick Add, Schedule, Focus,
  Context and navigation. Freeze inside/outside ownership, deepest-first Escape
  and application/owner-window focus loss without closing a parent when its
  child takes key focus. Add actual-window tests before broad changes.
- IS-003: remove title Button + row tap duplicate selection ownership; preserve
  completion, disclosure, date and right-click/drag/drop routes. Verify counts
  per action and single-click behavior before applying globally.
- IS-004: extend the existing committed TaskChangeSet boundary rather than emit
  parallel command-specific events that can omit transactions or undo. Keep
  activity field-aware and persistence coalesced; measure projection costs before
  changing invalidation. Title/list changes still need debounced reminder-copy
  updates; only document-only edits may categorically skip reminder work.

IS-002–004 and the full-round completion/restore and Quick Add repetitions are
not accepted by the IS-001 gate alone.

### IS-001 final acceptance — 2026-10-03

Result: IS-001 passed for the latest isolated build of the current worktree.
The earlier INTERACTION-FOCUS-001 failure is no longer reproduced in this gate.

- Automated selected regression: 77 tests, zero failures, no expected-failure
  exemptions. Covers native hit targets and first responder, long-document
  growth/selection/host scrolling, Inspector hierarchy, tags, Focus submenu,
  decorations, document state/profile/transactions and formatting.
- Physical UI input, with fresh accessibility observations after each action:
  title/body switching 30 times; More → body 20 times; More → title 10 times;
  Tag → body 20 times; More → date → Escape 20 times; More → another task
  30 times. Every counted target action succeeded on its first click.
- Date drafts were cancelled and original dates remained unchanged. Task-switch
  samples were the visible existing tasks “测试1” and “编辑器流程验收 1003”.
  These repetitions did not edit task contents, tags or completion status.
- A shared build directory was overwritten during an earlier physical run.
  That interrupted run was excluded; all counts above were rerun against the
  isolated app, without subsequent production-code edits.
- Tested app: `/private/tmp/workfollow-is001-acceptance.YyF8ZF/Build/Products/Debug/WorkFollow.app`.
- Regression log: `/private/tmp/workfollow-is001-isolated.log`.
- Test result: `/private/tmp/workfollow-is001-acceptance.YyF8ZF/Logs/Test/Test-WorkFollow-2026.10.03_21-42-18-+0800.xcresult`.

This establishes the sampled first-click gate, not a quantified latency claim
or full-project acceptance. IS-002–004 remain pending, including global focus-loss
ownership, row gesture consolidation, mutation/projection profiling, and the
full-round completion/restore and Quick Add repetitions.

## IS-002 shared popup interaction ownership

`PopupInteractionRegistry` is the shared presentation-only boundary for outside
mouse-down and window/application focus loss. It has one application-local mouse
monitor, one global mouse observer and shared focus notifications, rather than
duplicated monitors in the context-menu presenter.

- A panel and its descendant windows own inside clicks. An ancestor click closes
  only the child unless it targets that child's trigger. Other controls retain
  the original event, including left, right and middle mouse-down.
- Application deactivation and another window family taking key focus dismiss
  transient panels. A child or parent taking key focus does not dismiss the family.
  Resign-key handling examines the resulting key window on the next main-loop
  turn, avoiding a transient nil during parent/child transfer.
- AnchoredPropertyPanel consumers (Inspector, Quick Add, Schedule, Focus picker/
  scope, Context and navigation) inherit this boundary without content changes.
- Focus Duration and Add Timer inline cards use the same registry. Add Timer's
  transparent interception shield is removed. Inline cards also register Escape.
- Existing PopupEscapeRegistry remains the sole layered Escape router; IME
  composition and attached-sheet handling are unchanged.

Actual-window regressions cover descendant clicks, unrelated-window event
identity, key-family transfer, application deactivation and registration cleanup,
in addition to the existing schedule, Inspector and Focus window flows. Final
build and physical results are recorded separately below.

### IS-002 verification — 2026-10-03

- Latest selected regression: 65 tests, zero failures or expected-failure
  exemptions. Includes real-window interaction ownership, layered Escape,
  Context, Focus picker/scope, Focus inline observation, Schedule, tags and
  IS-001 native editor regression tests; also checks arrowless source contracts.
- Build: `/private/tmp/workfollow-is002-acceptance/Build/Products/Debug/WorkFollow.app`.
- Log: `/private/tmp/workfollow-is002-final-tests.log`.
- Physical single-click checks: More → empty body 10 repetitions; More → date
  → Escape 10 repetitions. Target focus/open succeeded without a second click.
- Application switching through the computer-control tool stalled. A later
  screenshot shows the application inactive with More closed, but this does not
  establish timely dismissal; the interrupted switch is not counted as a pass.
- Focus has an existing paused session. It was not ended or replaced to expose
  Duration/Add Timer. Rhythm was visually observed opening and closing on an
  outside click, but note focus was not established by the returned accessibility
  state and is not claimed as a passing first-click focus gate.

Status: shared implementation and automated gate complete; full physical IS-002
acceptance still pending (timely app switching, inline Focus cards, and remaining
popup-family walkthroughs). Do not proceed as if IS-002 was fully accepted or
reuse IS-001 repetitions as evidence for this new build.

### IS-002 isolated physical follow-up — 2026-10-03

Two running preview apps shared one bundle identity. To remove that ambiguity,
the follow-up uses `com.workfollow.native.acceptance` and a separate scratch
store. A Debug-only `WorkFollowAcceptanceStorageRoot` Info.plist override routes
the repository and its derived module stores to that directory. Normal builds
keep their original storage location; the existing paused Focus session was not
ended or replaced.

- App: `/private/tmp/workfollow-is002-distinct/Build/Products/Debug/WorkFollow.app`.
- Scratch data: `/private/tmp/workfollow-is002-sandbox.TB1y1S`.
- Latest selected regression rerun: 65 tests, zero failures or expected failures.
  Log: `/private/tmp/workfollow-is002-current-tests.log`.
  Result: `/private/tmp/workfollow-is002-regression/Logs/Test/Test-WorkFollow-2026.10.03_23-16-48-+0800.xcresult`.
- Coordinate mouse input: Duration → Add Timer → Duration, ten complete rounds
  with fresh full accessibility observations after every click. Each transition
  closes the previous card and opens the target card with one click.
- Escape closes Duration and Add Timer independently without starting a session.
- Quick Add properties opened visually; one outside click returns to its title
  input with the properties card gone. This is a walkthrough sample, not the
  required twenty-round Quick Add acceptance.
- Task context menu opened with a physical secondary click; one click on
  “准备季度复盘材料” closes the menu and selects that task in the Inspector.
- More opened, then a physical click on the already-running TickTick window's
  title whitespace left WorkFollow's More closed in the following screenshot.
  No measured dismissal latency is claimed.

Accessibility button actions are not substituted for physical mouse-down in
outside-click acceptance. Child-window screenshots and main-window coordinate
input did not consistently address the same window; unsuccessful submenu input
attempts are excluded, not classified as proven product failures.

Status: Focus inline physical gate and the latest automated gate pass. Full
IS-002 acceptance remains pending for child-picker walkthroughs, navigation and
the repeated Quick Add gate. IS-003 is not started by this follow-up.

### IS-002 child focus handoff — 2026-10-04

The expanded Quick Add real-window suite exposed a regression omitted from the
earlier 65-test selection: closing a focused list/tag child could also dismiss
its parent. Making the fixture's owner key-capable did not resolve it. The panel
close path detached the key child before returning focus, allowing AppKit to
choose an unrelated window and the shared registry to dismiss the parent.

`AnchoredPropertyPanel.Coordinator.close()` now returns key ownership to the
visible parent before detaching a focused child, only while the app is active.
Outside mouse events remain unconsumed, and application deactivation does not
reactivate the owner. No picker content or draft semantics were changed.

Quick Add acceptance now includes twenty real-window mouse-down/up rounds,
alternating list and tag children. Each outside target click must close both
panels, execute the target exactly once, and apply neither draft. Existing tests
retain strict assertions for search focus, child-only cancellation, parent frame,
confirmation callback and two-level Escape. These are automated native-window
flows, not twenty physical mouse repetitions.

The test host could not read source files under Documents (NSCocoaErrorDomain
257). The entire selected suite was therefore rerun against a temporary copy of
the current macos-native source, without changing system permissions or skipping
the source contracts. Log: `/private/tmp/workfollow-is002-oct04-verified.log`.
Final result: 71 tests, zero failures or expected failures. The repaired presenter
and Quick Add test sources match the tested copy.

The pre-fix physical app built earlier today is excluded from acceptance of this
repair. Full IS-002 physical acceptance, especially narrow-window navigation and
child-window mouse walkthroughs, is still pending; IS-003 remains unstarted.

### IS-002 physical follow-up — 2026-10-04

The repaired acceptance app was opened from the verified build above. One
continuous Focus task-picker sequence showed the scope child closing on the
first keyboard Escape while the searchable parent remained; the second Escape
returned to the main window. Scope was opened through its accessibility action,
so this is a keyboard-layer check, not child mouse-target acceptance.

A separated attempt returned to the main window on the first Escape, but the
control tool also reported intervening application changes. That attempt is
inconclusive, not a confirmed product regression. A five-round repeat stopped
before its first round: the observed window changed from `WorkFollowNativeMain`
to `main-AppWindow-1`, and the expected Focus entry was absent. No five-round
pass is claimed.

Window zoom changed the observed size, but edge dragging did not resize it.
Narrow-window navigation therefore remains unverified. The current presenter
matches the tested copy; the current Escape router additionally declares named
rank constants, so the verified build must not be described as the entire latest
working tree. Full acceptance remains open pending a stable app/window target
and the remaining coordinate-based child and narrow-navigation walkthroughs.

### IS-002 latest-build narrow-navigation acceptance — 2026-10-04

The selected 71-test regression suite was rerun against a fresh copy of the
current workspace and passed with zero failures. The initial sandboxed build
failed to start Swift macro services; the successful run used normal Xcode
execution without skipping tests. Log:
`/private/tmp/workfollow-is002-latest-13ANyJ/test-verified.log`.

The corresponding acceptance app is
`/private/tmp/workfollow-is002-latest-13ANyJ/build/Build/Products/Debug/WorkFollow.app`,
with independent bundle identity and temporary storage. The presenter, Escape
router and TaskListView match this tested source copy at the final check.

Using the system Window → Move & Resize → Left command succeeded where edge
dragging did not. The narrow window exposes the navigation button. The latest
build was then checked through actual coordinate input and fresh UI observations:

- Navigation opens beside its trigger; selecting Inbox closes it and changes
  the displayed list. Selecting Today returns to the expected task rows.
- Navigation open → one click on the visible quarterly-task date opens Schedule.
  Escape returns to the main window without leaving the navigation panel visible.
  This sequence passed twenty consecutive coordinate-input rounds; every date
  opening was checked for the Schedule confirmation control, and each dismissal
  was checked for the main window. No second click or latency measurement is claimed.
- Quick Add list child opened through a coordinate click. Escape closed the
  child while retaining the priority/list/tag parent panel.
- The tag child opened, then its Cancel accessibility action closed only that
  child and retained the parent. This is not counted as a coordinate Cancel check.

Two attempted root-shell native-window tests had no accessible controls in
their test host, so never reached mouse dispatch. Their experimental source was
removed; their failures are not classified as production navigation failures.
An outside-date attempt after a child-only screenshot landed in main-window
whitespace because the tool changed coordinate origins; it is excluded.

Narrow navigation is no longer blocked. Overall IS-002 still has the repeated
Quick Add physical gate and coordinate-based tag confirmation/cancellation
walkthrough remaining. The twenty automated Quick Add rounds are not relabeled
as physical rounds. IS-003 remains unstarted by this follow-up.

### IS-002 remaining physical gates — 2026-10-04

The same latest-source acceptance build completed the remaining walkthroughs:

- Quick Add input → property menu → one coordinate click on the visible
  quarterly-task date opened Schedule. Escape returned to the main window.
  Twenty consecutive rounds passed, with fresh accessibility observations
  after every action and confirmation/main-window checks in every round.
  The property menu and first Schedule opening were also visually inspected.
  These are additional physical coordinate-input rounds, not the earlier
  automated native-window rounds.
- Tag Cancel was clicked at its observed child-window button position. Only
  the tag child closed; the priority/list/tag parent remained visible.
- The tag child was reopened and Confirm was clicked at the previously
  observed child-window button position. Again only the child closed and the
  parent remained visible. The draft contained no tags, so this checks actual
  mouse dismissal/ownership, not a new-tag persistence transaction.

The capture tool intermittently rendered a scaled whole-window image in the
child-sized screenshot buffer. The Confirm coordinate used the earlier clear
child screenshot rather than guessing from that scaled image; the resulting
parent state was checked through both accessibility and screenshot output.

TaskListView, AnchoredPropertyPanel and PopupEscapeRouter were compared with
the tested source copy after these checks and remained identical. No production
code changed in this follow-up. The selected IS-002 popup acceptance gates are
now complete; this does not claim measured latency or the later task-row and
mutation-performance gates. IS-003 inspection still finds a title Button and
an enclosing row tap handler sharing selection ownership; implementation and
its task-selection/completion walkthrough belong to the next stage.

### IS-003 task-row selection ownership — 2026-10-04

Implementation is limited to the task-row input boundary:

- Removed the nested title Button. Title and preview are ordinary views; an
  assistive default action still selects the task without owning a mouse surface.
- The row has one exclusive selection gesture: Command, then Shift, then plain
  click. Each recognizer reads its own modifiers, not delayed NSApp.currentEvent
  or a timestamp heuristic. Existing bulk/range domain callbacks remain intact.
- Completion/restore, disclosure and date retain independent buttons.
- On macOS 15 and newer the row explicitly allows window-activation clicks.
  The macOS 14 fallback preserves platform behavior; it is not a physical
  macOS 14 acceptance result.
- Added DEBUG-only title/date/row frame probes and five TaskRowInteractionTests.
  The shared window-event helper now optionally accepts mouse modifier flags.

Latest source copy and build:
`/private/tmp/workfollow-is003-0qUwRL/source` and
`/private/tmp/workfollow-is003-0qUwRL/build/Build/Products/Debug/WorkFollow.app`.
The selected 96-test suite passed with zero failures. Log:
`/private/tmp/workfollow-is003-0qUwRL/regression-final.log`.
The production source directory matches the tested copy at the final check.

The strict new tests verify thirty title/preview/padding clicks, exactly one
selection each; completion/disclosure callbacks never also select; completed
checkbox restores; date opens independently and Escape leaves selection usable;
Command/Shift/plain click callbacks are mutually exclusive. An early test host
did not receive activation clicks. A temporary acceptsFirstMouse override was
removed; the final suite uses an ordinary NSHostingView and the production
activation policy. No test failure is waived.

After restarting the final build, actual coordinate-input walkthroughs passed:

- Thirty task switches across title, padding and non-button metadata, checking
  the Inspector title after each click; no second click was used.
- Twenty completion/restore cycles on the quarterly task, checking both row
  lifecycle controls and the unchanged reading-task Inspector after each step.
- Twenty date open/Escape cycles, checking Schedule confirmation on opening
  and the unchanged Inspector title after dismissal.
- Parent collapse/expand leaves the other task selected. Row right-click opens
  the context card, verified visually.

Earlier background-launch coordinate clicks entered bulk selection on both the
pre-activation-policy build and the intermediate gesture build. Escape restored
ordinary routing. These attempts are recorded, not used to prove a specific
product root cause. The final continuous counts above were performed after
explicitly bringing the acceptance window forward through keyboard input.
No latency number is inferred from computer-use tool runtime.

Open compatibility gate: coordinate drag from quarterly task to reading task did
not change order, despite the final build being in manual-sort mode. A second
attempt from row whitespace after collapsing children also did not reorder.
The same title-drag attempt on the prior IS-002 build likewise did not reorder.
This is not evidence that the new gesture introduced the problem, nor proof
that drag/drop works. Do not freeze all IS-003 behavior or start IS-004 until
drag initiation/drop delivery is checked separately. No reorder implementation
or domain mutation was changed in this round.

At walkthrough cleanup, Escape after the non-key context card also removed the
Inspector controls from the observed accessibility tree. A subsequent single
row click restored the expected Inspector. Context Escape propagation therefore
needs a targeted repeat alongside the drag gate; context opening alone is not
claimed as complete keyboard-dismissal acceptance.

### IS-003 closure plan — 2026-10-04

1. Reproduce context Escape on a current isolated build and observe event-window,
   key-window and routing result. Add a regression covering the failed delivery
   path, then ensure one Escape dismisses only the deepest menu.
2. Observe drag mouse events, drag initiation, drop targeting, decoded payload,
   reorder action and list projection. Compare the prior behavior where needed;
   change only the first broken boundary, preserving the reorder domain.
3. Verify native-window tests and actual UI sequences on the final build: context
   Escape twenty times, upward/downward reorder and undo, post-drag click,
   selection, completion/restore and Schedule regressions.
4. Record passed and unresolved gates separately. No IS-004 changes, new features,
   visual changes or automatic commit/push are included in this implementation.

### IS-003 closure evidence — 2026-10-04

- Added a native-window Context regression: twenty open/Escape cycles never
  reach the presenter responder; after the final menu closes, a subsequent
  Escape reaches that responder normally. Context child/parent dismissal now
  uses dispatched key events rather than direct registry calls.
- Added twenty upward/downward reorder operations with undo. Store-backed list
  projection updates correctly and the selected task remains unchanged. This
  verifies the action/projection boundary, not drag initiation or drop delivery.
- The current uninstrumented source snapshot passed 100 selected interaction
  regressions with zero failures, including Schedule, Quick Add, Focus, task
  rows, popup ownership, tags and completed presentation. Production sources
  were compared with the tested snapshot and had no differences.
  Log: `/private/tmp/workfollow-is003-closure-HQfku9/regression-final.log`.
- A separate diagnostic build, with temporary event logging only, passed twenty
  More/Escape cycles through accessibility activation and keyboard input. Each
  Escape was consumed by the popup registry; the same Inspector stayed visible.
  Earlier attempts with concurrent test/acceptance windows produced inconsistent
  results and are not counted as passing final-build acceptance.
- Coordinate left/right clicks and drag did not enter the diagnostic app's
  local mouse-event monitor, even after re-binding the bundle and raising its
  window. Accessibility activation and key events did arrive. Therefore the
  current unchanged order cannot identify a production drag/drop defect.
  Log: `/private/tmp/workfollow-is003-closure-HQfku9/events.log`.
- Open gate: restore native pointer delivery and repeat Context opening/Escape,
  drag up/down, undo and post-drag selection on the final uninstrumented app.
  The physical closure gate has **not** passed; no speculative production
  fallback or reorder rewrite was added. No commit/push was performed.

### IS-003 resumed physical verification — 2026-10-04

The repository had advanced since the prior build. A new isolated snapshot at
`/private/tmp/workfollow-is003-latest-O8eENb/source` passed 40 targeted tests with
zero failures (Context, task row, Escape registry, Schedule and bulk selection).
Log: `/private/tmp/workfollow-is003-latest-O8eENb/regression.log`.

Native pointer input resumed. On the uninstrumented latest build, twenty actual
right-click / Escape cycles preserved the reading task Inspector. The twentieth
open and closed states were captured in the conversation. Manual sort was
confirmed in its menu. **The Context Escape physical gate now passes.**

The drag gate remains open. Pointer events reached the diagnostic window with
zero modifier flags, but upward drag did not reorder. A scratch simultaneous
selection gesture candidate failed checkbox/disclosure/date selection-isolation
tests and was rejected. A scratch `onDrag` provider candidate was invoked by
the drag, but no drop target callback or reordered projection was observed;
it was also not adopted. This narrows observation to initiation/drop delivery,
but does not establish that changing either API fixes the product.

All diagnostic and candidate code was removed from the isolated source. The
restored production source matches the repository. Before rewriting the drag
shell, manually drag the quarterly task above the reading task in this isolated
app to distinguish native user behavior from computer-use drag delivery. This
round does not claim completed drag/undo/post-drag physical acceptance, does not
change production drag behavior, and does not enter IS-004 or commit/push.
