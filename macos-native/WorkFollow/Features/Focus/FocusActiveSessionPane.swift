import SwiftUI

/// Running/paused focus presentation. Break phases continue to use FocusOverviewPane.
struct FocusActiveSessionPane: View {
    @ObservedObject var store: FocusStore
    @Environment(\.colorScheme) private var colorScheme

    private var theme: FocusTheme { FocusTheme(colorScheme) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                FocusTomatoIcon(color: theme.accent)
                    .focusRenderAnchor(.activeSessionTomatoIcon)
                Text("番茄计时")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(theme.text)
                Spacer()
                Image(systemName: "link")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(theme.text2)
                    .help("任务关联")
            }
            .frame(height: FocusLayoutMetrics.timelineHeaderHeight)

            FocusTimelineView(store: store, theme: theme)
                .padding(.top, FocusLayoutMetrics.timelineTopPadding)

            VStack(alignment: .leading, spacing: 8) {
                Text("专注笔记")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(theme.text)
                    .focusRenderAnchor(.activeFocusNoteHeader)

                ZStack(alignment: .topLeading) {
                    if store.currentSessionNote.isEmpty {
                        Text("记录你的想法...")
                            .font(.system(size: 14))
                            .foregroundStyle(theme.text3)
                            .padding(.horizontal, 9)
                            .padding(.top, 8)
                            .allowsHitTesting(false)
                    }
                    TextEditor(text: Binding(
                        get: { store.currentSessionNote },
                        set: { store.updateCurrentSessionNote($0) }
                    ))
                    .font(.system(size: 14))
                    .foregroundStyle(theme.text)
                    .scrollContentBackground(.hidden)
                    .background(.clear)
                    .accessibilityIdentifier("focus-session-note-editor")
                }
                .frame(height: FocusLayoutMetrics.focusNoteHeight)
                .background(theme.chipBackground,
                            in: RoundedRectangle(cornerRadius: FocusLayoutMetrics.focusNoteRadius))
                .overlay(RoundedRectangle(cornerRadius: FocusLayoutMetrics.focusNoteRadius)
                    .stroke(theme.hairline, lineWidth: 1))
                .focusRenderAnchor(.activeFocusNote)
            }
            .padding(.top, FocusLayoutMetrics.focusNoteTopGap)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, FocusLayoutMetrics.timelineHorizontalPadding)
        .padding(.top, FocusLayoutMetrics.timelineTopPadding)
        .padding(.bottom, FocusLayoutMetrics.timelineHorizontalPadding)
        .frame(minWidth: FocusLayoutMetrics.overviewPaneMinWidth, maxWidth: .infinity,
               maxHeight: .infinity, alignment: .topLeading)
        .background(theme.canvas)
    }
}
