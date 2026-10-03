# TASK-ACTION-MENU Round 2

Date: 2026-10-03. Reference: user-provided TickTick More Menu screenshots and
explicit ACTION-001 instruction. Editor/Slash/Schedule business logic frozen.

## Sequential delivery gates

| Stage | Deliverable | Acceptance gate |
| --- | --- | --- |
| ACTION-001 | Remove legacy More tail group; neutral delete label; existing action order | Source contract, actual-window action/submenu regressions, main-app screenshot and picker closing |
| ACTION-002 | TaskActivityEvent + store + persisted reverse-time viewer | Record only successful domain transitions, no events for no-op/failure; restart persistence; actual mutations visible in viewer |
| ACTION-003 | Same-task sticky window | Shared TaskWorkspaceModel, no Note conversion or task copy; main/window bidirectional edits; close/reopen position; correct deletion handling |
| ACTION-004 | Printable task projection | Snapshot-based print view, not live NSTextView capture; title/date/body/checklist layout and print cancel flow |

ACTION-002–004 are follow-up deliveries, not placeholder menu entries. Activity
records should be captured at successful mutation boundaries, not from menu
clicks alone, so keyboard/Quick Add actions are not omitted. First version events:
creation, title/date/list/priority/tag changes, completion/restoration/abandonment,
child creation, and successful Focus starts. No body-per-keystroke logging.

Focus estimates remain TASK-FOCUS-GAP-ESTIMATE: no invented UI or fields without
reference evidence. Sticky always-on-top/themes are out of the first scope.

## ACTION-001 implemented structure

```
添加子任务 (root only)
关联主任务
置顶 / 取消置顶
放弃 / 恢复
标签
上传附件
开始专注 >
────────
保存为模板
创建副本
复制链接
转换为笔记
删除
```

Existing parent/closed-task eligibility and Focus submenu lifecycle unchanged.
Deletion text uses the same neutral menu color; execution retains the existing
recoverable trash/undo path. This does not add a new permanent-delete action or
claim a confirmation dialog exists.

## Removed entries and honest capability gaps

- Remove the entire `其他操作` tail group, including `更多属性…`, `截止日期…`,
  `跳过本周期`, and its extra separator. Keep underlying Domain capabilities.
- Current top Schedule edits dueAt/dueEndAt; deadlineAt is a distinct field.
  TASK-ACTION-GAP-DEADLINE-ENTRY: Inspector deadline entry is no longer exposed by
  More; it has NOT been migrated into top Schedule in ACTION-001. Legacy deadline
  panel/attribute state is retained rather than deleting business code.
- Recurrence skip remains available in the task context menu. Moving it into the
  repeat/date context needs a separate verified interaction, not assumed parity.
- Activity/sticky/print are absent until their real implementations exist.
  The complete TickTick-target menu is not yet frozen or fully accepted.

## Acceptance record

- ACTION-001 isolated regression: 19 tests, zero failures. Suites:
  TaskMoreMenuRoundTwoTests, TaskInspectorActionPanelTests, TaskFocusSubmenuTests,
  TaskParentPickerTests, TaskTagPickerInteractionTests, NativeResourceLinkTests.
  Log: `/private/tmp/workfollow-action-round-two-isolated-tests.log`.
- New source contract checks supported row order, removed/unimplemented entries,
  neutral deletion and restore labels. Actual-window regressions retain Focus
  child sizing/Esc hierarchy, parent/tag switching, duplicate creation/close and
  links. These tests are not a complete real-app acceptance of every action.
- The full dirty workspace initially failed to compile in TaskDatePopoverV2.swift
  (extraneous closing brace). Its other uncommitted edits were not overwritten.
  Isolation used the committed baseline plus only ACTION-001 menu hunks and the
  new test file; not the unrelated pending Header/Metrics/Schedule changes.
- Main-app acceptance ran `/private/tmp/WorkFollowActionMenuAcceptance.app` from
  that isolated build. A dedicated task `任务菜单结构验收 1003` was created and
  retained. Inline screenshot confirms all 12 supported rows, one separator,
  no More arrow, removed tail group, and neutral fully visible delete at bottom.
  More → Tags replaces More; Escape closes Tags without applying changes.
- Further main-app clicks were interrupted by repeated external UI-change / tool
  activation errors. No manual pin/restore/delete/Focus-start or narrow/dark
  acceptance is claimed. No user task was mutated during these menu checks.
- Independent app startup took abnormally long in the computer-use tool; no new
  visual evidence was obtained during that wait.
- `git diff --check` passed. No commit/push in ACTION-001; previous editor push
  remains approval-blocked. Full target menu remains pending ACTION-002–004.

## ACTION-002 implementation and latest-worktree acceptance

Task Activity is now the first row after the More separator. Sticky/Print remain
absent rather than showing nonfunctional entries. The viewer is a separate
`AnchoredPropertyPanel`, anchored to the footer More button, with a bounded
scroll area, reverse-time events, close/Escape/outside dismissal, and no arrow.
Opening Activity replaces More; changing the selected task dismisses it.

`TaskActivityStore` owns `modules/task-activity.json`, participates in application
shutdown flushing, and exposes task-filtered events. `WorkspaceStore` publishes
before/after snapshots only after actual commits (one final snapshot per outer
transaction). Workspace undo reports its real reverse transition. Initial load
is deliberately not observed: no fabricated historical creation events. Body
typing, updatedAt-only changes, identical values and tag reordering do not log.
Adjacent title changes within two seconds merge, retaining the original title;
returning to that title removes the merged event. Successful task Focus starts
record their actual timer mode; a rejected start does not record a new event.

Acceptance is based on the complete current `experiment/macos-native` working
tree, including pending Shell/Schedule/Inspector changes, not the earlier
isolated ACTION-001 app. Latest build and 18 selected tests passed, zero failures:
TaskActivityStoreTests (8), TaskActivityIntegrationTests (4),
TaskInspectorActionPanelTests (3), TaskFocusSubmenuTests (3).
Log: `/private/tmp/workfollow-latest-activity-verified.log`.
The integration suite checks real workspace commands, transaction aggregation,
Focus success/rejection, and an actual NSWindow → More → Activity child-window
transition with arrowless style, unchanged parent content and Escape dismissal.
Persistence tests flush to disk and construct a new store to verify reload.

First-pass failures were fixed before this passing run: equal-timestamp ordering
and eager activity-content construction requiring an environment in unrelated
menu render tests. The source-reading XCTest suite stalled in this environment;
a read-only check against the latest actual Inspector source separately passed
row order, removed-entry and neutral-delete checks. It is not reported as a
passing XCTest suite.

Main-app screenshot acceptance is **pending**: computer-use explicitly reported
the Mac was locked and automatic unlock failed. The user was asked to unlock.
The earlier isolated screenshot is not used as evidence for this implementation.
No real-user task was mutated during ACTION-002 automated checks. No commit or
push was performed. ACTION-003 must wait until this screenshot gate is closed.

Additional latest-worktree regressions passed: 64 tests, zero failures across
TaskDomainTests, TaskWorkspaceModelTests, TaskRelationUndoBoundaryTests,
TaskEditorSourceCommitTests and FocusStoreTests. Log:
`/private/tmp/workfollow-latest-activity-regression.log`.
Total verified in these two latest-code runs: 82 tests, zero failures.

## Unlocked main-app acceptance and positioning correction

After unlock, launched the latest full-worktree product directly from
`/private/tmp/workfollow-inspector-align/Build/Products/Debug/WorkFollow.app`.
Created only the dedicated task `任务动态实机验收 1003` and renamed it to
`任务动态实机验收 1003 已改标题`; existing user tasks were not edited.

The first real-app screenshot exposed a missing owner-window constraint:
vertical placement clamped to the screen, so the footer Activity card could
extend past the main window's right edge. Added opt-in `.verticalInOwner` and
used it only for Activity; Schedule/other placements were not changed. Extended
the actual-window integration assertion to require the Activity frame inside
the owner inset, including when the display is larger than the owner window.
Rebuilt the latest worktree and passed 15 tests, zero failures (Activity store,
Activity integration, Focus submenu). Log:
`/private/tmp/workfollow-activity-position-verified.log`.

Restarted the app from that corrected product and obtained inline screenshots:
More contains Activity after the separator, no legacy tail, and fully visible
neutral Delete. Activity replaces More and stays wholly within the main window;
the edited-title event appears above the original creation event. Esc/reopen and
outside-click dismissal were exercised; an outside-click screenshot confirms
the child is gone. Normal quit → relaunch → search/select → More → Activity
retains both events and the edited title, confirmed in the final inline screenshot.

ACTION-002's normal-window main flow is accepted. This does not claim dark-mode,
narrow-window or every event type has manual screenshot coverage; their domain
and selected window behavior are covered by the automated tests above. Sticky
and Print remain unimplemented. No commit/push in this acceptance follow-up.

## Submission packaging verification

Before submission, staged only ACTION-001/002 and Activity's owner-bound placement
from shared files; unrelated pending Schedule, Shell, task-list and editor edits
remain in the working tree. Optional lunar recurrence display reads additive
Codable fields rather than requiring the uncommitted calendar Domain extension.

Latest full-worktree Activity tests passed again: 12 tests, zero failures, log
`/private/tmp/workfollow-activity-latest-submit.log`. Separately exported the exact
index snapshot to a temporary directory and verified independent build/test:
20 tests, zero failures, including the previously stalled source contract, log
`/private/tmp/workfollow-activity-staged-submit.log`. This packaging check does not
replace the latest-app screenshot acceptance recorded above.
