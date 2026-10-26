import AppKit
import SwiftUI

enum ReminderAudio {
    static func filename(_ name: String) -> String { "WorkFollowReminder\(name).wav" }
    static func sound(_ name: String) -> NSSound? {
        guard let url = Bundle.main.url(forResource: "WorkFollowReminder\(name)", withExtension: "wav") else { return NSSound(named: name) }
        return NSSound(contentsOf: url, byReference: true)
    }
}

@MainActor
final class TaskReminderPresenter {
    private var panel: NSPanel?
    private var sound: NSSound?
    private(set) var activeID: String?

    @discardableResult
    func show(_ delivery: ReminderDelivery, preferences: TaskReminderPreferences,
              playSound: Bool, onSnooze: @escaping (Int) -> Void,
              onStop: @escaping () -> Void, onOpen: @escaping () -> Void) -> Bool {
        if activeID == delivery.id { return sound?.isPlaying == true }
        stop()
        activeID = delivery.id
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 350, height: 190),
            styleMask: [.titled, .utilityWindow], backing: .buffered, defer: false)
        panel.title = "任务提醒"; panel.level = .floating
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        panel.contentView = NSHostingView(rootView: TaskReminderPanel(delivery: delivery,
            defaultMinutes: preferences.snoozeMinutes, onSnooze: onSnooze, onStop: onStop, onOpen: onOpen))
        panel.center()
        if NSApp.isActive { panel.makeKeyAndOrderFront(nil) }
        else { panel.orderFrontRegardless() }
        self.panel = panel
        if playSound, preferences.soundEnabled, let tone = ReminderAudio.sound(preferences.bell) {
            tone.loops = true; tone.volume = 0.5; tone.play(); sound = tone
        }
        NativeAcceptanceInteractionTrace.record("reminder.present", ["kind": delivery.kind.rawValue,
            "audioPlaying": sound?.isPlaying == true, "active": NSApp.isActive,
            "keyWindow": panel.isKeyWindow, "visible": panel.isVisible])
        return sound?.isPlaying == true
    }
    func stop(id: String? = nil) {
        guard id == nil || id == activeID else { return }
        sound?.stop(); sound = nil; panel?.close(); panel = nil; activeID = nil
        NativeAcceptanceInteractionTrace.record("reminder.stop", ["stopped": true])
    }
}

private struct TaskReminderPanel: View {
    let delivery: ReminderDelivery
    let defaultMinutes: Int
    let onSnooze: (Int) -> Void
    let onStop: () -> Void
    let onOpen: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label(delivery.title, systemImage: "bell.badge").font(.headline).lineLimit(2)
            Text(delivery.body).font(.subheadline).foregroundStyle(.secondary)
            HStack {
                Button(delivery.kind == .task || delivery.kind == .checklistItem ? "打开任务" : "查看提醒",
                       action: onOpen)
                Spacer()
                BusinessMenu("稍后提醒") {
                    ForEach(Array(Set([5, defaultMinutes, 10, 30])).sorted(), id: \.self) { minutes in
                        Button("\(minutes) 分钟后") { onSnooze(minutes) }
                    }
                }
                Button("停止", action: onStop).keyboardShortcut(.cancelAction)
            }
        }.padding(20).frame(width: 350, height: 160, alignment: .topLeading)
    }
}
