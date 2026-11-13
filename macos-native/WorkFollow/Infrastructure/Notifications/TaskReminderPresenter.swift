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
        // 与编辑器弹层同一套玻璃卡语言：无标题栏的圆角悬浮卡。非激活面板
        // 不抢键盘焦点（用户正在输入不该被打断），按钮点击照常送达。
        let panel = NSPanel(contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isReleasedWhenClosed = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .floating
        panel.becomesKeyOnlyIfNeeded = true
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        let host = NSHostingView(rootView: TaskReminderPanel(delivery: delivery,
            defaultMinutes: preferences.snoozeMinutes, onSnooze: onSnooze, onStop: onStop, onOpen: onOpen)
            .workfollowNativeTheme())
        host.sizingOptions = [.intrinsicContentSize]
        panel.contentView = host
        host.layoutSubtreeIfNeeded()
        let size = host.fittingSize
        if size.width > 0, size.height > 0 { panel.setContentSize(size) }
        panel.center()
        panel.orderFrontRegardless()
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
    @Environment(\.workfollowBackgroundTheme) private var backgroundTheme
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 7) {
                Image(systemName: "bell.badge")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(WFColors.accent)
                Text("任务提醒")
                    .font(WFType.supporting)
                    .foregroundStyle(WFColors.secondaryText)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)

            Text(delivery.title)
                .font(WFType.controlLabelStrong)
                .foregroundStyle(WFColors.text)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 16)
                .padding(.top, 8)

            Text(delivery.body)
                .font(WFType.supporting)
                .foregroundStyle(WFColors.secondaryText)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 16)
                .padding(.top, 4)

            Divider()
                .padding(.top, 14)

            HStack(spacing: 8) {
                footerButton(delivery.kind == .task || delivery.kind == .checklistItem ? "打开任务" : "查看提醒",
                             filled: true, action: onOpen)
                BusinessMenu(title: "稍后提醒") {
                    ForEach(Array(Set([5, defaultMinutes, 10, 30])).sorted(), id: \.self) { minutes in
                        Button("\(minutes) 分钟后") { onSnooze(minutes) }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text("稍后提醒")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(WFColors.text)
                            .lineLimit(1)
                        Image(systemName: "chevron.down")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(WFColors.secondaryText)
                    }
                    .frame(maxWidth: .infinity, minHeight: 26)
                    .background(WFColors.content, in: RoundedRectangle(cornerRadius: PopupMetrics.buttonCornerRadius))
                    .overlay(RoundedRectangle(cornerRadius: PopupMetrics.buttonCornerRadius)
                        .stroke(WFColors.border))
                    .contentShape(Rectangle())
                }
                footerButton("停止", filled: false, action: onStop)
                    .frame(width: 64)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 12)
        }
        .frame(width: 352)
        .background {
            WFGlassSurface(shape: RoundedRectangle(cornerRadius: PopupMetrics.cornerRadius),
                           fallback: backgroundTheme.popupFill(for: colorScheme))
        }
        .clipShape(RoundedRectangle(cornerRadius: PopupMetrics.cornerRadius))
        .hidesSystemFocusEffect()
    }

    /// 与检查项提醒面板同一套页脚按钮：主操作强调色实底，次操作描边幽灵。
    private func footerButton(_ title: String, filled: Bool,
                              action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12, weight: filled ? .semibold : .medium))
                .foregroundStyle(filled ? WFColors.onAccent : WFColors.text)
                .frame(maxWidth: .infinity, minHeight: 26)
                .background(filled ? WFColors.accent : WFColors.content,
                            in: RoundedRectangle(cornerRadius: PopupMetrics.buttonCornerRadius))
                .overlay(RoundedRectangle(cornerRadius: PopupMetrics.buttonCornerRadius)
                    .stroke(filled ? Color.clear : WFColors.border))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
