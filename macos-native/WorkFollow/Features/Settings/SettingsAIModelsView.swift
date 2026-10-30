import SwiftUI

struct SettingsAIModelsView: View {
    @ObservedObject var store: MeetingStore
    @ObservedObject var models: AIModelStore
    @StateObject private var catalog: PiModelCatalog
    @State private var refresh = 0
    @State private var advanced = false
    @State private var executableDraft: String
    @State private var speechSearch = ""
    @State private var textSearch = ""
    @State private var textEngine: AITextEngine
    @State private var configurationError: String?

    init(store: MeetingStore, models: AIModelStore, catalog: PiModelCatalog? = nil) {
        self.store = store
        self.models = models
        _textEngine = State(initialValue: models.engine)
        _catalog = StateObject(wrappedValue: catalog ?? PiModelCatalog())
        let executable = store.configuration.executable
        _executableDraft = State(initialValue: ["/opt/homebrew/bin/pi", "/usr/local/bin/pi"].contains(executable) ? "" : executable)
    }

    private var speechBusy: Bool { store.recordingID != nil || store.transcribing || store.requestingPermission }

    var body: some View {
        SettingsPage {
            WFFormSection {
                WFFormRow("文字处理", showsDivider: true) {
                    BusinessMenu(width: 220, title: "调用方式") {
                        BusinessMenuOption("直接调用", selected: textEngine == .langchain) {
                            do { try models.useLangchain(); textEngine = .langchain; configurationError = nil }
                            catch { configurationError = error.localizedDescription }
                        }
                        BusinessMenuOption("Pi", selected: textEngine == .pi) {
                            do { try models.usePi(); textEngine = .pi; configurationError = nil }
                            catch { configurationError = error.localizedDescription }
                        }
                    } label: {
                        HStack { Text(textEngine == .langchain ? "直接调用" : "Pi"); Image(systemName: "chevron.down").font(.system(size: 10)) }
                    }.accessibilityLabel("文字处理调用方式")
                }
                if textEngine == .langchain {
                    SettingsDirectAIModelView(models: models)
                    modelRow(speech: false, chatOnly: true)
                    WFFormNote("独立对话和选区浮窗使用 Pi；其他文字处理使用上方的直接调用配置。")
                }
                else { modelRow(speech: false) }
                if let configurationError { WFFormNote(configurationError) }
            }
            WFFormSection {
                modelRow(speech: true)
                if speechBusy { WFFormNote("正在录音或转写，结束后可以更换语音模型。") }
                HStack(spacing: 8) {
                    if catalog.loading {
                        ProgressView().controlSize(.small)
                        Text("正在读取模型…")
                    }
                    Spacer()
                    Button("刷新 Pi 模型") { refresh += 1 }.disabled(catalog.loading)
                }.font(WFType.supporting).padding(.horizontal, WFSpace.md)
                if let error = catalog.error {
                    Text(error).font(WFType.supporting).foregroundStyle(.red).padding(.horizontal, WFSpace.md)
                } else if !catalog.loading && catalog.models.isEmpty {
                    WFFormNote("请先按欢迎清单的“AI 配置说明”配置本机 Pi，再刷新模型列表。")
                }
            }
            DisclosureGroup("Pi 高级选项", isExpanded: $advanced) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("本机 Pi 程序")
                    HStack {
                        TextField("留空自动查找本机 Pi", text: $executableDraft).textFieldStyle(.roundedBorder)
                            .onSubmit { applyExecutable() }
                        Button("应用") { applyExecutable() }
                            .disabled(executableDraft == store.configuration.executable)
                    }
                    Text("音频扩展")
                    TextField("留空使用内置转写通道", text: $store.configuration.audioExtension).textFieldStyle(.roundedBorder)
                    Text("Pi 和 Node.js 使用本机安装；模型列表读取本机 Pi 配置。安装命令与模型文件示例见欢迎清单中的「AI 配置说明」。")
                        .foregroundStyle(WFColors.secondaryText)
                }.padding(.top, 10).disabled(speechBusy)
            }.font(WFType.body).padding(.horizontal, WFSpace.md)
            AIConfigurationCheckView()
        }
        .coordinateSpace(name: "ai-model-settings")
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("ai-model-settings")
        .task(id: store.configuration.executable + "#\(refresh)") { await catalog.refresh(executable: store.configuration.executable) }
        .onChange(of: models.engine) { _, value in textEngine = value }
    }

    private func modelRow(speech: Bool, chatOnly: Bool = false) -> some View {
        let title = speech ? "语音转写" : chatOnly ? "Pi 对话模型" : "Pi 文字模型"
        let modelTitle = speech ? "语音转写模型" : "Pi 文字模型"
        let saved = speech ? store.configuration.resolvedTranscriptionModel : store.configuration.resolvedMinutesModel
        let current = catalog.model(for: saved)
        let customAudio = !store.configuration.audioExtension.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let available = catalog.models.filter { speech ? (customAudio || $0.supportsTranscription) : $0.supportsText }
        let search = speech ? $speechSearch : $textSearch
        let matches = available.filter { search.wrappedValue.isEmpty || ($0.menuTitle + " " + $0.modelID).localizedStandardContains(search.wrappedValue) }
        return VStack(alignment: .leading, spacing: 2) {
            WFFormRow(title, showsDivider: speech) {
                BusinessMenu(width: 360, title: modelTitle, search: available.count > 8 ? search : nil) {
                    if !speech {
                        BusinessMenuOption("跟随 Pi 默认模型", selected: saved.isEmpty) { store.configuration.minutesModel = "" }
                        if !matches.isEmpty { Divider() }
                    }
                    ForEach(matches) { model in
                        BusinessMenuOption(model.menuTitle, selected: current?.id == model.id) {
                            if speech { store.configuration.transcriptionModel = model.id }
                            else { store.configuration.minutesModel = model.id }
                        }
                    }
                    if matches.isEmpty { Text(available.isEmpty ? "暂无适用模型，请刷新列表" : "没有匹配的模型").font(WFType.supporting).padding(10) }
                } label: {
                    HStack(spacing: 8) {
                        Text(saved.isEmpty ? "跟随 Pi 默认模型" : current?.title ?? saved)
                            .lineLimit(1).truncationMode(.middle)
                        Image(systemName: "chevron.down").font(.system(size: 10))
                    }.frame(maxWidth: 310, alignment: .trailing).contentShape(Rectangle())
                }
                .accessibilityLabel(modelTitle)
                .help(current?.menuTitle ?? title + "模型")
                .disabled(catalog.loading || (speech && (speechBusy || available.isEmpty)))
            }
            if !saved.isEmpty && !catalog.loading && catalog.error == nil && !catalog.models.isEmpty && !available.contains(where: { $0.id == current?.id }) {
                WFFormNote(current == nil ? "当前模型不在 Pi 列表中，请重新选择。" : "当前模型不适用于此场景，请重新选择。")
            }
        }
    }

    private func applyExecutable() {
        let path = executableDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !speechBusy else { return }
        store.configuration.executable = path
    }
}
