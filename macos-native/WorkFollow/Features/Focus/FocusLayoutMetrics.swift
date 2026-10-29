import CoreGraphics

/// Focus 页面的布局基线。三栏由 RootShell 的全局 Icon Rail、Focus Pane 和 Overview Pane 组成。
/// 2026-10-14 同版本 8.0.80、1512×859 窗口观察：timer pane约558pt、ring约238pt、按钮123×48pt。
/// 其余尚未测量的值保留项目基线。
enum FocusLayoutMetrics {
    // Pane
    static let focusPaneMinWidth: CGFloat = 430
    static let focusPaneIdealWidth: CGFloat = 650
    static let focusPaneMaxWidth: CGFloat = 680
    static let focusPaneWidthRatio: CGFloat = 0.385
    static let completionPaneWidthRatio: CGFloat = 567 / 1450
    static let overviewPaneMinWidth: CGFloat = 620
    static let dividerWidth: CGFloat = 1
    static var minimumWorkspaceWidth: CGFloat {
        focusPaneMinWidth + dividerWidth + overviewPaneMinWidth
    }

    // Page
    static let horizontalPadding: CGFloat = 24
    static let topPadding: CGFloat = 20

    // Header
    static let headerHeight: CGFloat = 36
    static let titleFontSize: CGFloat = 18
    static let headerIconSize: CGFloat = 16
    static let headerButtonSize: CGFloat = 28
    static let headerButtonSpacing: CGFloat = 9

    // Mode switch
    static let segmentWidth: CGFloat = 150
    static let segmentHeight: CGFloat = 30
    static let segmentTrackInset: CGFloat = 2
    static let segmentFontSize: CGFloat = 13

    // Timer
    static let focusLabelTop: CGFloat = 185
    static let focusLabelHeight: CGFloat = 24
    static let ringTopGap: CGFloat = 110
    static let ringSize: CGFloat = 238
    static let ringLineWidth: CGFloat = 2.5
    static let progressRingLineWidth: CGFloat = 3
    static let stopwatchTickCount = 96
    static let stopwatchTickLength: CGFloat = 10
    static let stopwatchTickLineWidth: CGFloat = 1
    static let timerFontSize: CGFloat = 42
    static let phaseFontSize: CGFloat = 14
    static let ringCenterSpacing: CGFloat = 10
    static let ringShadowRadius: CGFloat = 30
    static let statusTopGap: CGFloat = 18
    static let statusSpacing: CGFloat = 10
    static let statusDotSize: CGFloat = 7

    // Primary action
    static let primaryButtonWidth: CGFloat = 123
    static let primaryButtonHeight: CGFloat = 48
    static let footerHeight: CGFloat = 180

    // Preset row stays below the header without shifting the timer stage's absolute position.
    static let presetChipsRowTop: CGFloat = 12
    static let presetChipsRowHeight: CGFloat = 44

    // Overview
    static let overviewHorizontalPadding: CGFloat = 21
    static let overviewVerticalPadding: CGFloat = 24
    static let overviewTitleFontSize: CGFloat = 18
    static let overviewTitleBottom: CGFloat = 16
    static let overviewCardGap: CGFloat = 12
    static let overviewCardHeight: CGFloat = 72
    static let overviewCardRadius: CGFloat = 10
    static let overviewCardHorizontalPadding: CGFloat = 14
    static let overviewCardVerticalPadding: CGFloat = 12
    static let overviewCardTextGap: CGFloat = 4
    static let overviewLabelFontSize: CGFloat = 12
    static let overviewValueFontSize: CGFloat = 24
    static let overviewUnitFontSize: CGFloat = 12
    static let overviewGoalTop: CGFloat = 16
    static let overviewGoalFontSize: CGFloat = 12
    static let overviewGoalContentGap: CGFloat = 13
    static let overviewGoalProgressHeight: CGFloat = 3

    // Records: 补记面板为同版本运行时观察尺寸。
    static let recordEditorWidth: CGFloat = 440
    static let recordEditorHeight: CGFloat = 446
    static let recordHeaderTop: CGFloat = 26
    static let recordHeaderFontSize: CGFloat = 18
    static let recordHeaderButtonSize: CGFloat = 28
    static let recordHeaderIconSize: CGFloat = 16
    static let recordHeaderBottom: CGFloat = 8
    static let recordGroupTop: CGFloat = 12
    static let recordGroupBottom: CGFloat = 4
    static let recordRowHeight: CGFloat = 48
    static let recordTimeFontSize: CGFloat = 12
    static let recordTitleFontSize: CGFloat = 14
    static let recordMinutesFontSize: CGFloat = 12
    static let recordStatusDotSize: CGFloat = 5
    static let recordEmptyFontSize: CGFloat = 13
    static let recordEmptyIllustrationWidth: CGFloat = 110
    static let recordEmptyIllustrationHeight: CGFloat = 90
    static let recordEmptyContentGap: CGFloat = 12
    static let recordEmptyVerticalOffset: CGFloat = 20

    // Active session
    static let timelineHorizontalPadding: CGFloat = 24
    static let timelineTopPadding: CGFloat = 24
    static let timelineHeaderHeight: CGFloat = 32
    static let timelineHeight: CGFloat = 500
    static let timelineLabelWidth: CGFloat = 26
    static let timelineGridLineWidth: CGFloat = 1
    static let timelineCurrentLineWidth: CGFloat = 1.5
    static let timelineCurrentDotSize: CGFloat = 16
    static let timelineFocusFillOpacity: CGFloat = 0.16
    static let focusNoteTopGap: CGFloat = 28
    static let focusNoteHeight: CGFloat = 122
    static let focusNoteRadius: CGFloat = 6

    // 同版本 8.0.80、1512×859 的自然完成页与追加后完成页运行截图。
    static let completionHeaderTop: CGFloat = 18
    static let completionFigureCenterY: CGFloat = 280
    static let completionFigureSize: CGFloat = 180
    static let completionTomatoSize: CGFloat = 132
    static let completionClockFontSize: CGFloat = 32
    static let completionTitleTop: CGFloat = 425
    static let completionTitleFontSize: CGFloat = 24
    static let completionSubtitleFontSize: CGFloat = 16
    static let completionActionsTop: CGFloat = 525
    static let completionActionGap: CGFloat = 16
    static let completionPopoverWidth: CGFloat = 240
    static let completionTimelineHorizontalPadding: CGFloat = 20
    static let completionTimelineTop: CGFloat = 46
    static let completionTimelineHeaderGap: CGFloat = 53
    static let completionTimelineHeight: CGFloat = 410
    static let completionNoteTopGap: CGFloat = 60
    static let completionNoteHeight: CGFloat = 106

    // 常用库：8.0.80、1512×859 的运行截图；与完成页共用约567pt左栏。
    static let libraryHeaderHeight: CGFloat = 58
    static let libraryRowHeight: CGFloat = 54
    static let libraryAvatarSize: CGFloat = 30
    static let libraryTimerBarHeight: CGFloat = 64
    static let libraryListInset: CGFloat = 10
    static let presetDetailHorizontalPadding: CGFloat = 20
    static let presetDetailCardHeight: CGFloat = 72
    static let presetDetailChartHeight: CGFloat = 136

    static var ringTop: CGFloat {
        focusLabelTop + focusLabelHeight + ringTopGap
    }

    static func selectorTopPadding(hasPresetChips: Bool) -> CGFloat {
        let presetBlockHeight = hasPresetChips ? presetChipsRowTop + presetChipsRowHeight : 0
        return max(0, focusLabelTop - topPadding - headerHeight - presetBlockHeight)
    }

    static func footerTop(paneHeight: CGFloat) -> CGFloat {
        max(0, paneHeight - footerHeight)
    }

    /// Focus Pane 按参考窗口校准后的比例 取值，同时为 Overview 保留最低宽度。
    static func focusPaneWidth(availableWidth: CGFloat, isCompleted: Bool = false) -> CGFloat {
        let overviewBoundedMaximum = availableWidth - dividerWidth - overviewPaneMinWidth
        guard overviewBoundedMaximum >= focusPaneMinWidth else {
            return focusPaneMinWidth
        }
        let ratio = isCompleted ? completionPaneWidthRatio : focusPaneWidthRatio
        return min(max(availableWidth * ratio, focusPaneMinWidth),
                   min(focusPaneMaxWidth, overviewBoundedMaximum))
    }
}
