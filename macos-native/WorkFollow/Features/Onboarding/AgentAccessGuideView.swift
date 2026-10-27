import AppKit
import SwiftUI

struct AgentAccessGuideView: View {
    var guide = AgentAccessGuide()
    var copyText: (String) -> Void = { text in
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    private enum Copied { case instructions, command }
    @State private var agent = AgentAccessGuide.Agent.workbuddy
    @State private var copied: Copied?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Button {
                copyText(guide.aiInstructions)
                copied = .instructions
            } label: {
                Label(copied == .instructions ? "已复制" : "复制给 AI",
                      systemImage: copied == .instructions ? "checkmark" : "doc.on.doc")
            }
            .buttonStyle(.borderedProminent)
            .inspectorRenderAnchor(.agentCopyInstructions)

            Divider()

            Text("手动执行").font(WFType.sectionSemibold)
            Picker("AI 助手", selection: $agent) {
                ForEach(AgentAccessGuide.Agent.allCases) { agent in
                    Text(agent.title).tag(agent)
                }
            }
            .labelsHidden()
            .pickerStyle(.segmented)
            .frame(width: 210)

            ScrollView([.horizontal, .vertical]) {
                Text(guide.manualCommand(for: agent))
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(WFColors.text)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: true, vertical: true)
                    .padding(12)
            }
            .background(WFColors.canvas, in: RoundedRectangle(cornerRadius: 8))
            .frame(height: 104)

            Button {
                copyText(guide.manualCommand(for: agent))
                copied = .command
            } label: {
                Label(copied == .command ? "已复制" : "复制命令",
                      systemImage: copied == .command ? "checkmark" : "doc.on.doc")
            }
            .buttonStyle(.bordered)
            .inspectorRenderAnchor(.agentCopyCommand)
        }
        .padding(16)
        .background(WFColors.secondarySurface, in: RoundedRectangle(cornerRadius: 10))
        .onChange(of: agent) { _, _ in
            if copied == .command { copied = nil }
        }
    }
}
