import SwiftUI

/// Geometry reported only in Debug builds so render tests can verify real SwiftUI layout.
enum FocusRenderAnchor: Hashable {
    case rail
    case railSelectedHitArea
    case railSelectedBackground
    case divider
    case timerRing
    case primaryButton
    case overviewFirstCard
    case recordsHeader
    case emptyRecordsIllustration
    case emptyRecordsContent
    case emptyRecordsRegion
    case activeTimeline
    case activeTimelineTick0
    case activeTimelineTick1
    case activeTimelineTick2
    case activeTimelineTick3
    case activeTimelineTick4
    case activeTimelineCurrentLine
    case activeTimelineCurrentDot
    case activeTimelineFocusFill
    case activeFocusNoteHeader
    case activeFocusNote
    case focusPauseButton
    case focusResumeButton
    case focusEndButton
    case focusDurationTrigger
    case focusDurationPopover
    case focusModeSegment
    case focusAddTimerButton
    case focusRunningStatus
    case focusPausedTimerLabel
    case activeSessionTomatoIcon

    static let coordinateSpaceName = "focus-render-contract"
}

struct FocusRenderFramesPreferenceKey: PreferenceKey {
    static let defaultValue: [FocusRenderAnchor: CGRect] = [:]

    static func reduce(value: inout [FocusRenderAnchor: CGRect],
                       nextValue: () -> [FocusRenderAnchor: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, latest in latest })
    }
}

extension View {
    @ViewBuilder
    func focusRenderAnchor(_ anchor: FocusRenderAnchor) -> some View {
        #if DEBUG
        background {
            GeometryReader { geometry in
                Color.clear.preference(
                    key: FocusRenderFramesPreferenceKey.self,
                    value: [anchor: geometry.frame(in: .named(FocusRenderAnchor.coordinateSpaceName))]
                )
            }
        }
        #else
        self
        #endif
    }
}
