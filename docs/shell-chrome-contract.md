# SHELL-CHROME-001 — Main window full-size content

## Scope and implementation

Only the main WindowGroup adopts hiddenTitleBar at creation. MainWindowChromeConfiguration independently applies fullSizeContentView, a transparent titlebar, hidden title and no titlebar separator. It does not replace the window delegate or change Settings/child panels.

RootShell ignores the top container safe area. Backgrounds and vertical dividers reach the window top; existing module header padding, font sizes, column widths and breakpoints remain unchanged. Rail controls alone receive a measured top inset.

The rail is 52pt, narrower than the default native traffic-light arrangement. Native button sizes are preserved; gaps are compacted within the rail. Reserve space is measured in content coordinates from the buttons' bottom plus 8pt, recalculated after layout/resize and fullscreen changes. Fullscreen uses system controls instead of repositioning them.

Do not enable background dragging across editable content. Native titlebar dragging remains enabled. Do not add blanket top padding to all columns or hide system window controls.

## Regression coverage

- MainWindowChromeContractTests: six tests, including real NSWindow attachment and three resize widths; native button frames stay inside the rail, and the inset clears their bottom.
- ScheduleAnchorGeometryTests: seven tests.
- SchedulePanelWindowFlowTests: six tests.
- FocusLayoutMetricsTests: five tests.
- TaskInspectorShellContractTests: four tests.

Build-for-testing succeeded; all 28 tests passed on 2026-10-02. The static inset assertion was corrected to check its layout application, not count the environment property's spelling.

## UI acceptance on 2026-10-02

An independently identified temporary copy of the latest build was used because the UI tool repeatedly resolved the same bundle identifier to an older build. The copy does not register workfollow links. No task/document edits were committed during the flows.

| Check | Result |
| --- | --- |
| Wide task page, light and dark | Screenshot inspected: all column dividers reach top; no full-width titlebar band; headers visible |
| Select task | Passed: list remains visible, Inspector updates |
| Countdown, light | Screenshot inspected: title directly below window top; rail divider extends to top |
| Settings isolation | Passed: Settings retains its own standard window chrome |
| Fullscreen entry/exit | Flow executed using green button and View menu; return to normal screenshot is correct |
| Fullscreen top-edge visual | Pending: captured top strip contains corrupted/duplicated pixels; cause not established, do not mark passed |
| Native traffic-light geometry | Automated real-window test passed; screenshot control area obscured by system capture indicator |
| Narrow window and actual dragging | Pending: UI resize attempts did not change the frame; do not substitute automated resize tests for manual flow acceptance |
| Minimize/close pointer interaction | Pending manual acceptance; capabilities preserved by automated test |

This is implementation complete with partial UI acceptance, not a declaration that every window mode has passed. Keep earlier unaccepted date changes separate from this scope.
