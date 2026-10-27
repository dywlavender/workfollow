import SwiftUI

struct WelcomeGuideWelcomeView: View {
    let onStart: () -> Void
    let onSkip: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: WFSpace.sm) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 40, weight: .semibold))
                    .foregroundStyle(WFColors.accent)
                Text("欢迎使用 WorkFollow")
                    .font(.system(size: 22, weight: .semibold))
                Text("把想法写下来，安排到时间，再专注做完。")
                    .font(WFType.body)
                    .foregroundStyle(WFColors.secondaryText)
            }
            .padding(.top, 32)

            VStack(alignment: .leading, spacing: 16) {
                feature(icon: "checklist", title: "待办与清单",
                        detail: "快速记下任务，按清单、日期和四象限整理。")
                feature(icon: "timer", title: "专注与统计",
                        detail: "给重要任务开一个番茄钟，回看时间花在哪。")
                feature(icon: "note.text", title: "笔记与会议",
                        detail: "想法、纪要和任务放在一起，搜索一次就找到。")
            }
            .padding(.horizontal, 36)
            .padding(.top, 30)

            Spacer(minLength: WFSpace.xxl)

            HStack {
                Button("稍后再说", action: onSkip)
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("开始使用", action: onStart)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .tint(WFColors.accent)
                    .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 36)
            .padding(.bottom, 28)
        }
        .frame(width: 520, height: 420)
        .background(WFColors.content)
    }

    private func feature(icon: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: WFSpace.md) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(WFColors.accent)
                .frame(width: 30, height: 30)
                .background(WFColors.accent.opacity(0.12),
                            in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            VStack(alignment: .leading, spacing: WFSpace.xs) {
                Text(title).font(WFType.body.weight(.medium))
                Text(detail)
                    .font(WFType.supporting)
                    .foregroundStyle(WFColors.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
    }
}
