import AppKit
import SwiftUI

struct AIConfigurationGuideView: View {
    let prepareSettings: () -> Void
    @Environment(\.openSettings) private var openSettings
    @State private var copied: String?
    @State private var showPi = false
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Button("打开 AI 模型设置") { prepareSettings(); openSettings() }
                    .buttonStyle(.borderedProminent)
                Link("下载 Node.js", destination: AIConfigurationGuide.nodeDownloadURL)
            }
            Text("已有 Homebrew 时，可在终端执行：").font(WFType.supporting)
            code(AIConfigurationGuide.nodeInstallCommand)
            Button(copied == "node" ? "已复制" : "复制安装命令") {
                copy(AIConfigurationGuide.nodeInstallCommand, kind: "node")
            }.buttonStyle(.bordered)

            Text("安装本机 Pi").font(WFType.sectionSemibold)
            code(AIConfigurationGuide.piInstallCommand)
            Button(copied == "pi-install" ? "已复制" : "复制 Pi 安装命令") {
                copy(AIConfigurationGuide.piInstallCommand, kind: "pi-install")
            }.buttonStyle(.bordered)

            DisclosureGroup("Pi 模型配置", isExpanded: $showPi) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("打开 models.json，填写服务商的地址、Key 和模型 ID。示例包含文字与百炼语音两项，删除不需要的示例。Responses 服务将 api 改为 openai-responses。已有配置保持原样打开。")
                        .font(WFType.supporting).foregroundStyle(WFColors.secondaryText)
                    HStack {
                        Button("打开 Pi 配置") {
                            do { NSWorkspace.shared.open(try AIConfigurationGuide.preparePiModels()); error = nil }
                            catch { self.error = error.localizedDescription }
                        }
                        Button(copied == "pi-models" ? "已复制" : "复制配置示例") {
                            copy(AIConfigurationGuide.piModelsTemplate, kind: "pi-models")
                        }
                    }.buttonStyle(.bordered)
                    code(AIConfigurationGuide.piModelsTemplate)
                    if let error { Text(error).font(WFType.supporting).foregroundStyle(.red) }
                }.padding(.top, 10)
            }.font(WFType.body)

        }
        .padding(16)
        .background(WFColors.secondarySurface, in: RoundedRectangle(cornerRadius: 10))
    }

    private func code(_ value: String) -> some View {
        ScrollView(.horizontal) {
            Text(value).font(.system(size: 11, design: .monospaced))
                .textSelection(.enabled).fixedSize(horizontal: true, vertical: false).padding(10)
        }.background(WFColors.canvas, in: RoundedRectangle(cornerRadius: 6))
        .compactScrollbars()
    }

    private func copy(_ value: String, kind: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(value, forType: .string)
        copied = kind
    }
}
