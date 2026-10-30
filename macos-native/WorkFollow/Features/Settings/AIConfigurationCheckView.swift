import SwiftUI

struct AIConfigurationCheckView: View {
    @EnvironmentObject private var environment: AppEnvironment
    @State private var checks: [AIConfigurationCheck] = []
    @State private var running = false
    @State private var error: String?
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Button("检查本机 AI 配置") {
                    running = true; checks = []; error = nil
                    _Concurrency.Task {
                        defer { running = false }
                        do { checks = try await environment.conversationClient().checkConfiguration() }
                        catch { self.error = error.localizedDescription }
                    }
                }.disabled(running)
                if running { ProgressView().controlSize(.small) }
            }
            ForEach(checks) { check in
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: check.ok ? "checkmark.circle.fill" : "exclamationmark.circle")
                        .foregroundStyle(check.ok ? WFColors.accent : WFColors.danger)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(check.name).font(WFType.section)
                        Text(check.message).font(WFType.supporting).foregroundStyle(WFColors.secondaryText).textSelection(.enabled)
                    }
                }
            }
            if let error { Text(error).foregroundStyle(WFColors.danger) }
        }.font(WFType.body).padding(.horizontal, WFSpace.md)
    }
}
