import SwiftUI

struct AIModelSaveFrameKey: PreferenceKey {
    static let defaultValue = CGRect.zero
    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        let next = nextValue(); if !next.isEmpty { value = next }
    }
}

struct SettingsDirectAIModelView: View {
    @ObservedObject var models: AIModelStore
    @State private var draft = AIModelProfile()
    @State private var key = ""
    @State private var revealKey = false
    @State private var advanced = false
    @State private var loaded = false
    @State private var testing = false
    @State private var result: String?
    @State private var error: String?
    @State private var testTask: _Concurrency.Task<Void, Never>?
    @State private var deleting = false

    var body: some View {
        VStack(spacing: 0) {
            if !models.profiles.isEmpty {
                WFFormRow("已存模型") {
                    HStack(spacing: 10) {
                        BusinessMenu(width: 400, title: "文字模型") {
                            ForEach(models.profiles) { profile in
                                BusinessMenuOption(profile.menuTitle, selected: profile.id == draft.id) { load(profile, activate: true) }
                            }
                        } label: {
                            HStack { Text(draft.title).lineLimit(1); Image(systemName: "chevron.down").font(.system(size: 10)) }
                        }.accessibilityLabel("已存文字模型")
                        Button { newModel() } label: { Image(systemName: "plus") }
                            .buttonStyle(.plain).help("添加模型").accessibilityLabel("添加模型")
                        Button { deleting = true } label: { Image(systemName: "trash") }
                            .buttonStyle(.plain).help("删除模型").accessibilityLabel("删除模型")
                            .disabled(!models.profiles.contains { $0.id == draft.id })
                    }
                }
            }
            WFFormRow("协议") {
                BusinessMenu(width: 260, title: "模型协议") {
                    ForEach(AIModelProtocol.allCases) { item in
                        BusinessMenuOption(item.title, selected: draft.protocolKind == item) { selectProtocol(item) }
                    }
                } label: {
                    HStack { Text(draft.protocolKind.title); Image(systemName: "chevron.down").font(.system(size: 10)) }
                }.accessibilityLabel("模型协议")
            }
            WFFormRow("模型名称") {
                TextField("填写服务商的模型 ID", text: field(\.model))
                    .textFieldStyle(.plain).frame(width: 300).accessibilityIdentifier("ai-model-name")
            }
            WFFormRow("API URL") {
                TextField(draft.protocolKind.defaultURL, text: urlBinding)
                    .textFieldStyle(.plain).frame(width: 300).accessibilityIdentifier("ai-model-url")
            }
            WFFormRow("API Key", showsDivider: false) {
                HStack(spacing: 8) {
                    Group {
                        if revealKey { TextField(draft.requiresKey ? "API Key" : "本地服务可留空", text: keyBinding) }
                        else { SecureField(draft.requiresKey ? "API Key" : "本地服务可留空", text: keyBinding) }
                    }.textFieldStyle(.plain).accessibilityIdentifier("ai-model-key")
                    Button { revealKey.toggle() } label: { Image(systemName: revealKey ? "eye.slash" : "eye") }
                        .buttonStyle(.plain).help(revealKey ? "隐藏 API Key" : "显示 API Key")
                        .accessibilityLabel(revealKey ? "隐藏 API Key" : "显示 API Key")
                }.frame(width: 300)
            }
            DisclosureGroup("高级选项", isExpanded: $advanced) {
                VStack(spacing: 0) {
                    WFFormRow("上下文窗口") {
                        TextField("32768", value: field(\.contextWindow), format: .number.grouping(.never))
                            .textFieldStyle(.plain).frame(width: 110).multilineTextAlignment(.trailing)
                        Text("tokens").foregroundStyle(WFColors.secondaryText)
                    }
                    WFFormRow("最大输出", showsDivider: false) {
                        TextField("2048", value: field(\.maxOutputTokens), format: .number.grouping(.never))
                            .textFieldStyle(.plain).frame(width: 110).multilineTextAlignment(.trailing)
                        Text("tokens").foregroundStyle(WFColors.secondaryText)
                    }

                }
            }.font(WFType.supporting).padding(.horizontal, WFSpace.md).padding(.vertical, 8)
        }
        .disabled(testing)
        .accessibilityIdentifier("ai-direct-model-form")
        HStack {
            if testing {
                ProgressView().controlSize(.small)
                Button("取消测试") { testTask?.cancel() }
            } else {
                Button("测试连接") { test() }.accessibilityIdentifier("ai-test-model")
            }
            Spacer()
            Button("保存") { save() }.disabled(testing).accessibilityIdentifier("ai-save-model")
                .background(GeometryReader { geometry in
                    Color.clear.preference(key: AIModelSaveFrameKey.self, value: geometry.frame(in: .named("ai-model-settings")))
                })
        }.padding(.horizontal, WFSpace.md).padding(.vertical, 10)
        if let error = error ?? models.loadError {
            Text(error).font(WFType.supporting).foregroundStyle(.red)
                .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, WFSpace.md).padding(.bottom, 10)
        } else if let result {
            Text(result).font(WFType.supporting).foregroundStyle(WFColors.secondaryText)
                .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, WFSpace.md).padding(.bottom, 10)
        }
        Color.clear.frame(height: 0)
            .onAppear {
                guard !loaded else { return }; loaded = true
                if let profile = models.profiles.first(where: { $0.id == models.selectedID }) { load(profile, activate: false) }
            }
            .onDisappear { testTask?.cancel() }
            .confirmationDialog("删除此模型配置及保存的 API Key？", isPresented: $deleting) {
                Button("删除模型", role: .destructive) {
                    do {
                        try models.delete(draft.id)
                        if let profile = models.profiles.first { load(profile, activate: false) } else { newModel() }
                    } catch { self.error = error.localizedDescription }
                }
                Button("取消", role: .cancel) {}
            }
    }

    private var keyBinding: Binding<String> {
        Binding(get: { key }, set: { key = $0; clearStatus() })
    }
    private var urlBinding: Binding<String> {
        Binding(get: { draft.baseURL }, set: { value in
            if URLComponents(string: value)?.host != URLComponents(string: draft.baseURL)?.host { key = "" }
            draft.baseURL = value; clearStatus()
        })
    }
    private func field<Value>(_ path: WritableKeyPath<AIModelProfile, Value>) -> Binding<Value> {
        Binding(get: { draft[keyPath: path] }, set: { draft[keyPath: path] = $0; clearStatus() })
    }
    private func clearStatus() { error = nil; result = nil }
    private func selectProtocol(_ item: AIModelProtocol) {
        let old = draft.protocolKind
        if draft.baseURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || draft.baseURL == old.defaultURL {
            draft.baseURL = item.defaultURL
        }
        if draft.protocolKind != item { key = "" }
        draft.protocolKind = item; clearStatus()
    }
    private func load(_ profile: AIModelProfile, activate: Bool) {
        draft = profile; key = ""; revealKey = false; clearStatus()
        do {
            key = try models.key(for: profile.id)
            if activate { try models.select(profile.id) }
        } catch { self.error = error.localizedDescription }
    }
    private func newModel() { draft = AIModelProfile(); key = ""; revealKey = false; clearStatus() }
    private func save() {
        do { draft = try models.save(draft, key: key); error = nil; result = "已保存，用于直接调用的待办、摘要和纪要编写。" }
        catch { self.error = error.localizedDescription; result = nil }
    }
    private func test() {
        clearStatus(); testing = true
        testTask = _Concurrency.Task { @MainActor in
            defer { testing = false; testTask = nil }
            do { try await models.test(draft, key: key); result = "连接成功。" }
            catch is CancellationError { }
            catch { self.error = error.localizedDescription }
        }
    }
}
