import SwiftUI

struct SystemCalendarEventBar: View {
    let event: SystemCalendarEvent
    let onOpen: () -> Void
    var body: some View {
        Button(action: onOpen) {
            Label(event.fields.title, systemImage: "calendar")
                .font(WFType.listMeta).lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 5)
                .frame(height: WFCalendarMetrics.taskBarHeight)
                .foregroundStyle(WFColors.text)
                .background(WFListPalette.swatch(event.colorARGB).opacity(0.18), in: RoundedRectangle(cornerRadius: 3))
        }.buttonStyle(.plain).help(event.calendarTitle + " · " + event.fields.title)
        .accessibilityIdentifier("calendar.system-event.\(event.displayID)")
    }
}

struct SystemCalendarEventDetails: View {
    let event: SystemCalendarEvent
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label(event.fields.title, systemImage: "calendar").font(.title3)
            Text(event.calendarTitle).foregroundStyle(.secondary)
            if event.fields.allDay {
                Text("全天 · " + event.fields.start.formatted(date: .abbreviated, time: .omitted))
            } else {
                Text(event.fields.start.formatted(date: .abbreviated, time: .shortened)
                     + " — " + event.fields.end.formatted(date: .abbreviated, time: .shortened))
            }
            if !event.location.isEmpty { Label(event.location, systemImage: "mappin") }
            Text("这是系统日历中的日程，可在 Apple 日历中编辑。").font(.caption).foregroundStyle(.secondary)
            HStack { Spacer(); Button("关闭") { dismiss() }.keyboardShortcut(.cancelAction) }
        }.padding(24).frame(width: 380)
            .workfollowPopupSurface(fallback: WFColors.canvas)
    }
}
