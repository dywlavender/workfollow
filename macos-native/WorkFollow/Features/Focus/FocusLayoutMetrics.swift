import CoreGraphics

/// Focus 页面的布局基线。三栏由 RootShell 的全局 Icon Rail、Focus Pane 和 Overview Pane 组成。
/// 本轮先锁定 pane 几何；其余值供后续逐项对齐时复用，避免继续散落布局魔数。
enum FocusLayoutMetrics {
    // Pane
    static let focusPaneMinWidth: CGFloat = 430
    static let focusPaneIdealWidth: CGFloat = 650
    static let focusPaneMaxWidth: CGFloat = 680
    static let focusPaneWidthRatio: CGFloat = 0.37
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
    static let ringSize: CGFloat = 236
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
    static let primaryButtonWidth: CGFloat = 120
    static let primaryButtonHeight: CGFloat = 42
    static let footerHeight: CGFloat = 180

    // Preset row stays below the header without shifting the timer stage's absolute position.
    static let presetChipsRowTop: CGFloat = 12
    static let presetChipsRowHeight: CGFloat = 44

    // Overview
    static let overviewHorizontalPadding: CGFloat = 24
    static let overviewVerticalPadding: CGFloat = 24
    static let overviewTitleFontSize: CGFloat = 18
    static let overviewTitleBottom: CGFloat = 16
    static let overviewCardGap: CGFloat = 12
    static let overviewCardHeight: CGFloat = 76
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

    // Records
    static let recordHeaderTop: CGFloat = 26
    static let recordHeaderFontSize: CGFloat = 17
    static let recordHeaderButtonSize: CGFloat = 28
    static let recordHeaderIconSize: CGFloat = 16
    static let recordHeaderBottom: CGFloat = 8
    static let recordGroupTop: CGFloat = 12
    static let recordGroupBottom: CGFloat = 4
    static let recordRowHeight: CGFloat = 48
    static let recordTimeFontSize: CGFloat = 13
    static let recordTitleFontSize: CGFloat = 14
    static let recordMinutesFontSize: CGFloat = 13
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

    /// Focus Pane 按可用内容宽度的 37% 取值，同时为 Overview 保留最低宽度。
    static func focusPaneWidth(availableWidth: CGFloat) -> CGFloat {
        let overviewBoundedMaximum = availableWidth - dividerWidth - overviewPaneMinWidth
        guard overviewBoundedMaximum >= focusPaneMinWidth else {
            return focusPaneMinWidth
        }
        return min(max(availableWidth * focusPaneWidthRatio, focusPaneMinWidth),
                   min(focusPaneMaxWidth, overviewBoundedMaximum))
    }
}
