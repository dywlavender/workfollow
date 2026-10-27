import SwiftUI

struct SettingsAIModelsView: View {
    @ObservedObject var store: MeetingStore
    @StateObject private var catalog: PiModelCatalog
    @State private var refresh = 0
    @State private var advanced = false
    @State private var executableDraft: String
    @State private var speechSearch = ""
    @State private var textSearch = ""

    init(store: MeetingStore, catalog: PiModelCatalog? = nil) {
        self.store = store
        _catalog = StateObject(wrappedValue: catalog ?? PiModelCatalog())
        _executableDraft = State(initialValue: store.configuration.executable)
    }

    private var speechBusy: Bool { store.recordingID != nil || store.transcribing || store.requestingPermission }

    var body: some View {
        SettingsPage {
            WFFormSection {
                modelRow(speech: true)
                modelRow(speech: false)
                if speechBusy { WFFormNote("正在录音或转写，结束后可以更换语音模型。") }
                HStack(spacing: 8) {
                    if catalog.loading {
                        ProgressView().controlSize(.small)
                        Text("正在读取模型…")
                    }
                    Spacer()
                    Button("刷新模型") { refresh += 1 }.disabled(catalog.loading)
                }.font(WFType.supporting).padding(.horizontal, WFSpace.md)
                if let error = catalog.error {
                    Text(error).font(WFType.supporting).foregroundStyle(.red).padding(.horizontal, WFSpace.md)
                } else if !catalog.loading && catalog.models.isEmpty {
                    WFFormNote("请先在 Pi 配置模型并完成登录，再刷新列表。")
                }
            }
            DisclosureGroup("高级选项", isExpanded: $advanced) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Pi 程序")
                    HStack {
                        TextField("Pi 可执行文件路径", text: $executableDraft).textFieldStyle(.roundedBorder)
                            .onSubmit { applyExecutable() }
                        Button("应用") { applyExecutable() }
                            .disabled(executableDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || executableDraft == store.configuration.executable)
                    }
                    Text("音频扩展")
                    TextField("留空使用内置转写通道", text: $store.configuration.audioExtension).textFieldStyle(.roundedBorder)
                    Text("模型与登录信息在 Pi 中管理。")
                        .foregroundStyle(WFColors.secondaryText)
                }.padding(.top, 10).disabled(speechBusy)
            }.font(WFType.body).padding(.horizontal, WFSpace.md)
        }
        .task(id: store.configuration.executable + "#\(refresh)") { await catalog.refresh(executable: store.configuration.executable) }
    }

    private func modelRow(speech: Bool) -> some View {
        let title = speech ? "语音转写" : "文字处理"
        let saved = speech ? store.configuration.resolvedTranscriptionModel : store.configuration.resolvedMinutesModel
        let current = catalog.model(for: saved)
        let customAudio = !store.configuration.audioExtension.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let available = catalog.models.filter { speech ? (customAudio || $0.supportsTranscription) : $0.supportsText }
        let search = speech ? $speechSearch : $textSearch
        let matches = available.filter { search.wrappedValue.isEmpty || ($0.menuTitle + " " + $0.modelID).localizedStandardContains(search.wrappedValue) }
        return VStack(alignment: .leading, spacing: 2) {
            WFFormRow(title, showsDivider: speech) {
                BusinessMenu(width: 360, title: title + "模型", search: available.count > 8 ? search : nil) {
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
                .accessibilityLabel(title + "模型")
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
        guard !speechBusy, !path.isEmpty else { return }
        store.configuration.executable = path
    }
}
