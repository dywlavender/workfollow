import SwiftUI

struct AIWorkflowFailureView: View {
    let message: String
    let retryAt: Date?
    var retry: () -> Void
    @EnvironmentObject private var environment: AppEnvironment
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(message).foregroundStyle(WFColors.danger).textSelection(.enabled)
            TimelineView(.periodic(from: .now, by: 1)) { context in
                let remaining = max(0, Int(ceil(retryAt?.timeIntervalSince(context.date) ?? 0)))
                HStack {
                    Button(remaining > 0 ? "\(remaining) 秒后重试" : "重试", action: retry).disabled(remaining > 0)
                    Button("AI 模型设置…") { environment.settingsSection = .ai; openSettings() }
                }
            }
        }
    }
}
