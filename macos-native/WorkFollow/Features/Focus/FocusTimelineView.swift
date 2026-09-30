import SwiftUI

/// Fixed-window time axis for an active focus session.
struct FocusTimelineView: View {
    @ObservedObject var store: FocusStore
    let theme: FocusTheme

    var body: some View {
        GeometryReader { geometry in
            if let timing = store.sessionTiming {
                let projection = FocusTimelineProjection.make(
                    timing: timing, now: store.currentTime, calendar: .current
                )
                let currentY = projection.currentYRatio * geometry.size.height
                let axisWidth = max(0, geometry.size.width - FocusLayoutMetrics.timelineLabelWidth)
                let layoutFrames = activeLayoutFrames(
                    origin: geometry.frame(in: .named(FocusRenderAnchor.coordinateSpaceName)).origin,
                    size: geometry.size, projection: projection
                )

                ZStack(alignment: .topLeading) {
                    if let endRatio = projection.endYRatio {
                        Rectangle()
                            .fill(theme.accent.opacity(FocusLayoutMetrics.timelineFocusFillOpacity))
                            .frame(width: axisWidth,
                                   height: max(0, (endRatio - projection.currentYRatio) * geometry.size.height))
                            .offset(x: FocusLayoutMetrics.timelineLabelWidth, y: currentY)
                    }

                    ForEach(Array(projection.ticks.enumerated()), id: \.offset) { index, tick in
                        tickRow(tick, axisWidth: axisWidth)
                            .frame(height: 20)
                            .offset(y: CGFloat(index) * geometry.size.height / 4 - 10)
                    }

                    Rectangle()
                        .fill(theme.warn)
                        .frame(width: axisWidth,
                               height: FocusLayoutMetrics.timelineCurrentLineWidth)
                        .offset(x: FocusLayoutMetrics.timelineLabelWidth,
                                y: currentY - FocusLayoutMetrics.timelineCurrentLineWidth / 2)

                    Circle()
                        .fill(theme.warn)
                        .frame(width: FocusLayoutMetrics.timelineCurrentDotSize,
                               height: FocusLayoutMetrics.timelineCurrentDotSize)
                        .offset(x: FocusLayoutMetrics.timelineLabelWidth
                                - FocusLayoutMetrics.timelineCurrentDotSize / 2,
                                y: currentY - FocusLayoutMetrics.timelineCurrentDotSize / 2)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .preference(key: FocusRenderFramesPreferenceKey.self, value: layoutFrames)
            } else {
                Color.clear
            }
        }
        .frame(height: FocusLayoutMetrics.timelineHeight)
    }

    private func tickRow(_ date: Date, axisWidth: CGFloat) -> some View {
        HStack(spacing: 0) {
            Text("\(Calendar.current.component(.hour, from: date))")
                .font(.system(size: 13))
                .monospacedDigit()
                .foregroundStyle(theme.text3)
                .frame(width: FocusLayoutMetrics.timelineLabelWidth, alignment: .leading)

            Rectangle()
                .fill(theme.hairline)
                .frame(width: axisWidth, height: FocusLayoutMetrics.timelineGridLineWidth)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func tickAnchor(_ index: Int) -> FocusRenderAnchor {
        switch index {
        case 0: .activeTimelineTick0
        case 1: .activeTimelineTick1
        case 2: .activeTimelineTick2
        case 3: .activeTimelineTick3
        default: .activeTimelineTick4
        }
    }

    private func activeLayoutFrames(origin: CGPoint, size: CGSize,
                                    projection: FocusTimelineProjection) -> [FocusRenderAnchor: CGRect] {
        let labelWidth = FocusLayoutMetrics.timelineLabelWidth
        let axisWidth = max(0, size.width - labelWidth)
        let currentY = projection.currentYRatio * size.height
        var frames: [FocusRenderAnchor: CGRect] = [
            .activeTimeline: CGRect(origin: origin, size: size),
            .activeTimelineCurrentLine: CGRect(
                x: origin.x + labelWidth,
                y: origin.y + currentY - FocusLayoutMetrics.timelineCurrentLineWidth / 2,
                width: axisWidth,
                height: FocusLayoutMetrics.timelineCurrentLineWidth
            ),
            .activeTimelineCurrentDot: CGRect(
                x: origin.x + labelWidth - FocusLayoutMetrics.timelineCurrentDotSize / 2,
                y: origin.y + currentY - FocusLayoutMetrics.timelineCurrentDotSize / 2,
                width: FocusLayoutMetrics.timelineCurrentDotSize,
                height: FocusLayoutMetrics.timelineCurrentDotSize
            )
        ]

        if let endRatio = projection.endYRatio {
            frames[.activeTimelineFocusFill] = CGRect(
                x: origin.x + labelWidth,
                y: origin.y + currentY,
                width: axisWidth,
                height: max(0, (endRatio - projection.currentYRatio) * size.height)
            )
        }

        for index in projection.ticks.indices {
            frames[tickAnchor(index)] = CGRect(
                x: origin.x,
                y: origin.y + CGFloat(index) * size.height / 4 - 10,
                width: size.width,
                height: 20
            )
        }
        return frames
    }
}
