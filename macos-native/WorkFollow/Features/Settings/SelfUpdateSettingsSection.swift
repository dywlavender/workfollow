import SwiftUI

/// 设置页「软件更新」分区：本地目录通道的配置与手动检查/安装入口。
/// 检查与安装逻辑在 SelfUpdateModel；落位与回滚在 workfollowctl apply-update。
struct SelfUpdateSettingsSection: View {
    @ObservedObject var model: SelfUpdateModel
    @State private var channelDisplay: String
    @State private var discovered: SelfUpdateModel.Discovery?
    @State private var lastError: String?

    init(model: SelfUpdateModel) {
        self.model = model
        _channelDisplay = State(initialValue: model.channelDirectory?.path ?? "")
    }

    var body: some View {
        Group {
            WFFormRow("当前版本") {
                Text(SelfUpdateModel.versionLabel)
                    .foregroundStyle(WFColors.secondaryText)
            }
            WFFormRow("更新目录") {
                HStack(spacing: 8) {
                    Button(channelDisplay.isEmpty ? "选择目录…" : "更换") { chooseDirectory() }
                    if !channelDisplay.isEmpty {
                        Button("移除") {
                            model.channelDirectory = nil
                            channelDisplay = ""
                            discovered = nil
                        }
                    }
                }
            }
            if !channelDisplay.isEmpty {
                Text(channelDisplay)
                    .font(WFType.caption)
                    .foregroundStyle(WFColors.tertiaryText)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .padding(.horizontal, WFSpace.md)
            }
            WFFormRow("检查更新") {
                Button("检查") { check() }
                    .disabled(model.phase == .handingOff)
            }
            if let discovered {
                Button(discoveryButtonTitle(discovered)) { install(discovered) }
                    .disabled(model.phase == .handingOff)
                    .padding(.horizontal, WFSpace.md)
                if let notes = discovered.manifest.notes, !notes.isEmpty {
                    Text(notes)
                        .font(WFType.caption)
                        .foregroundStyle(WFColors.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, WFSpace.md)
                        .padding(.bottom, 8)
                }
            }
            if case .preparing(let fraction) = model.phase {
                Text("准备中：\(Int(fraction * 100))%")
                    .font(WFType.caption)
                    .foregroundStyle(WFColors.secondaryText)
                    .padding(.horizontal, WFSpace.md)
            }
            if case .handingOff = model.phase {
                Text("正在退出应用并落位更新…")
                    .font(WFType.caption)
                    .foregroundStyle(WFColors.secondaryText)
                    .padding(.horizontal, WFSpace.md)
            }
            WFFormRow("恢复上一版本", showsDivider: false) {
                Button("恢复") { restore() }
                    .disabled(!model.previousRollbackAvailable || model.phase == .handingOff)
            }
            if let message = effectiveMessage {
                Text(message)
                    .font(WFType.caption)
                    .foregroundStyle(message == lastError ? WFColors.danger : WFColors.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, WFSpace.md)
                    .padding(.bottom, 10)
            }
        }
    }

    private func discoveryButtonTitle(_ discovery: SelfUpdateModel.Discovery) -> String {
        discovery.mode == .hot
            ? "立即更新到 \(discovery.title)（热更 \(discovery.sizeHint ?? "")）"
            : "立即更新到 \(discovery.title)（全量）"
    }

    private var effectiveMessage: String? {
        if let lastError { return lastError }
        if case .failed(let message) = model.phase { return message }
        if case .upToDate = model.phase { return "已是最新版本。" }
        return model.lastResult
    }

    private func chooseDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false
        panel.message = "选择包含 manifest.json 的更新目录（可以是同步网盘目录）"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        model.channelDirectory = url
        channelDisplay = url.path
        check()
    }

    private func check() {
        lastError = nil
        discovered = nil
        do {
            discovered = try model.check()
        } catch {
            lastError = error.localizedDescription
        }
    }

    private func install(_ discovery: SelfUpdateModel.Discovery) {
        lastError = nil
        do {
            try model.prepare(discovery)
            try model.handOff()
        } catch {
            lastError = error.localizedDescription
        }
    }

    private func restore() {
        lastError = nil
        do {
            try model.restorePrevious()
        } catch {
            lastError = error.localizedDescription
        }
    }
}
