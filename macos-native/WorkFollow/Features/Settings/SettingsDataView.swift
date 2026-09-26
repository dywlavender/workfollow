import AppKit
import SwiftUI
import UniformTypeIdentifiers

// MARK: - Testable logic (covered by WorkFollowTests/SettingsDataTests.swift)

/// Builds the file inventory shown on the settings "数据" page: workspace.json
/// plus every known module file (missing ones are reported, not hidden) and any
/// extra JSON files that exist under modules/.
enum DataInventory {
    struct Entry: Equatable {
        /// Path relative to the data directory, e.g. "modules/focus.json".
        let name: String
        let exists: Bool
        let sizeText: String?
        let modifiedText: String?
    }

    static let workspaceFileName = "workspace.json"
    static let modulesDirectoryName = "modules"
    /// Files owned by the module stores, in canonical display order.
    static let moduleFileNames = ["focus.json", "habits.json", "summary.json", "filters.json", "templates.json"]

    static let defaultDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter
    }()

    static func entries(directory: URL,
                        dateFormatter: DateFormatter = DataInventory.defaultDateFormatter) -> [Entry] {
        let modulesDirectory = directory.appendingPathComponent(modulesDirectoryName, isDirectory: true)
        var present: Set<String> = []
        if let names = try? FileManager.default.contentsOfDirectory(atPath: modulesDirectory.path) {
            for name in names where !name.hasPrefix(".") {
                var isDirectory: ObjCBool = false
                let url = modulesDirectory.appendingPathComponent(name)
                if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory),
                   !isDirectory.boolValue, name.lowercased().hasSuffix(".json") {
                    present.insert(name)
                }
            }
        }
        var names = [workspaceFileName]
        names.append(contentsOf: moduleFileNames.map { modulesDirectoryName + "/" + $0 })
        names.append(contentsOf: present.subtracting(moduleFileNames)
            .sorted()
            .map { modulesDirectoryName + "/" + $0 })
        return names.map { entry(named: $0, in: directory, dateFormatter: dateFormatter) }
    }

    static func entry(named relativePath: String,
                      in directory: URL,
                      dateFormatter: DateFormatter = DataInventory.defaultDateFormatter) -> Entry {
        let url = directory.appendingPathComponent(relativePath)
        guard let values = try? url.resourceValues(
                  forKeys: [.isRegularFileKey, .fileSizeKey, .contentModificationDateKey]),
              values.isRegularFile == true, let bytes = values.fileSize else {
            return Entry(name: relativePath, exists: false, sizeText: nil, modifiedText: nil)
        }
        return Entry(name: relativePath, exists: true,
                     sizeText: sizeText(forBytes: bytes),
                     modifiedText: dateFormatter.string(from: values.contentModificationDate ?? .distantPast))
    }

    /// Deterministic, locale-independent sizes: "512 B", "1.5 KB", "2.0 MB", "3.0 GB".
    static func sizeText(forBytes bytes: Int) -> String {
        if bytes < 1024 { return "\(bytes) B" }
        let kilobytes = Double(bytes) / 1024
        if kilobytes < 1024 { return String(format: "%.1f KB", kilobytes) }
        let megabytes = kilobytes / 1024
        if megabytes < 1024 { return String(format: "%.1f MB", megabytes) }
        return String(format: "%.1f GB", megabytes / 1024)
    }
}

/// Whole-directory backup into `数据目录/backups/备份 yyyy-MM-dd HH-mm/`.
/// 旧版整目录备份仍在"恢复备份"列表里可选；workspace.json 的每日快照备份
/// 由 NativePreviewRepository 维护（workspace-YYYY-MM-DD.json，保留 7 天）。
enum DataBackup {
    static let backupsDirectoryName = "backups"
    static let namePrefix = "备份 "

    static let timestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH-mm"
        return formatter
    }()

    static func directoryName(for date: Date,
                              formatter: DateFormatter = DataBackup.timestampFormatter) -> String {
        namePrefix + formatter.string(from: date)
    }

    static func destinationURL(in directory: URL,
                               date: Date,
                               formatter: DateFormatter = DataBackup.timestampFormatter) -> URL {
        directory.appendingPathComponent(backupsDirectoryName, isDirectory: true)
            .appendingPathComponent(directoryName(for: date, formatter: formatter), isDirectory: true)
    }

    /// Copies every top-level item except `backups/` itself (copying a directory
    /// into its own descendant would recurse forever). An existing same-name
    /// target is removed first, so the backup always mirrors the current data.
    @discardableResult
    static func performBackup(directory: URL,
                              date: Date,
                              formatter: DateFormatter = DataBackup.timestampFormatter) throws -> URL {
        let fileManager = FileManager.default
        let target = destinationURL(in: directory, date: date, formatter: formatter)
        if fileManager.fileExists(atPath: target.path) {
            try fileManager.removeItem(at: target)
        }
        try fileManager.createDirectory(at: target, withIntermediateDirectories: true)
        let children = try fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        for child in children where child.lastPathComponent != backupsDirectoryName {
            try fileManager.copyItem(at: child, to: target.appendingPathComponent(child.lastPathComponent))
        }
        return target
    }

    /// Newest backup directory name; zero-padded names sort chronologically.
    static func latestBackupName(in directory: URL) -> String? {
        let backups = directory.appendingPathComponent(backupsDirectoryName, isDirectory: true)
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: backups.path) else { return nil }
        return names.filter { $0.hasPrefix(namePrefix) }.sorted().last
    }

    /// 所有旧版整目录备份（含 workspace.json 的才能恢复）。
    static func directoryBackups(in directory: URL) -> [URL] {
        let backups = directory.appendingPathComponent(backupsDirectoryName, isDirectory: true)
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: backups.path) else { return [] }
        return names
            .filter { $0.hasPrefix(namePrefix) }
            .sorted()
            .compactMap { name -> URL? in
                let candidate = backups.appendingPathComponent(name, isDirectory: true)
                var isDirectory: ObjCBool = false
                guard FileManager.default.fileExists(atPath: candidate.path, isDirectory: &isDirectory),
                      isDirectory.boolValue,
                      FileManager.default.fileExists(
                          atPath: candidate.appendingPathComponent(DataInventory.workspaceFileName).path)
                else { return nil }
                return candidate
            }
    }
}

/// Merges workspace.json and modules/*.json into one export payload, keeping the
/// parsed original values untouched (no re-encoding through Codable models).
enum DataExporter {
    static let version = 1

    static let exportFileNameFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    static func suggestedFileName(for date: Date,
                                  formatter: DateFormatter = DataExporter.exportFileNameFormatter) -> String {
        "WorkFollow导出 \(formatter.string(from: date)).json"
    }

    /// Shape: `{"exportedAt": ISO8601, "version": 1, "workspace": <原始JSON>,
    /// "modules": {"focus.json": <原始JSON>, ...}}`. Missing workspace.json becomes
    /// null; missing or unreadable module files are skipped; a corrupt
    /// workspace.json throws.
    static func combinedExport(directory: URL, now: Date = Date()) throws -> Data {
        var payload: [String: Any] = [
            "exportedAt": ISO8601DateFormatter().string(from: now),
            "version": version,
        ]

        let workspaceURL = directory.appendingPathComponent(DataInventory.workspaceFileName)
        if FileManager.default.fileExists(atPath: workspaceURL.path) {
            do {
                let raw = try Data(contentsOf: workspaceURL)
                payload["workspace"] = try JSONSerialization.jsonObject(with: raw, options: [.fragmentsAllowed])
            } catch {
                throw NSError(domain: "DataExporter", code: 1, userInfo: [NSLocalizedDescriptionKey:
                    "workspace.json 读取失败：\(error.localizedDescription)"])
            }
        } else {
            payload["workspace"] = NSNull()
        }

        var modules: [String: Any] = [:]
        let modulesDirectory = directory.appendingPathComponent(DataInventory.modulesDirectoryName, isDirectory: true)
        if let names = try? FileManager.default.contentsOfDirectory(atPath: modulesDirectory.path).sorted() {
            for name in names where !name.hasPrefix(".") && name.lowercased().hasSuffix(".json") {
                if let raw = try? Data(contentsOf: modulesDirectory.appendingPathComponent(name)),
                   let object = try? JSONSerialization.jsonObject(with: raw, options: [.fragmentsAllowed]) {
                    modules[name] = object
                }
            }
        }
        payload["modules"] = modules

        return try JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys])
    }
}

// MARK: - View

struct SettingsDataView: View {
    private enum FeedbackKind { case copiedPath, backup, restore, export, importData }
    private enum ImportMode { case merge, replace }

    /// "恢复备份"列表里的一项：每日快照文件或旧版整目录备份。
    struct SnapshotRestoreEntry: Identifiable, Equatable {
        let id: String
        let name: String
        let url: URL
        let isLegacyDirectoryBackup: Bool
    }

    @State private var entries: [DataInventory.Entry] = []
    @State private var attachmentDirectoryExists = false
    @State private var backupInfo: SnapshotBackupInfo?
    @State private var feedbackKind: FeedbackKind?
    @State private var feedbackText = ""
    @State private var feedbackIsError = false

    @State private var pendingImport: MigrationBundle?
    @State private var importBusy = false
    @State private var confirmReplaceImport = false
    @State private var showingRestoreSheet = false
    @State private var restoreEntries: [SnapshotRestoreEntry] = []
    @State private var restoreCandidate: SnapshotRestoreEntry?

    private var dataDirectory: URL { NativePreviewRepository.directory }
    private var attachmentDirectory: URL { NativeAttachmentFiles.directory }
    private var repository: NativePreviewRepository { NativePreviewRepository() }

    var body: some View {
        Form {
            Section("存储位置") {
                directoryRow(title: "数据目录", url: dataDirectory)
                if attachmentDirectoryExists {
                    directoryRow(title: "附件目录", url: attachmentDirectory)
                }
                inventoryRows
                HStack {
                    Button {
                        refresh()
                    } label: {
                        Label("刷新", systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    Spacer()
                }
                feedbackLine(.copiedPath)
            }
            Section("导入与导出") {
                HStack {
                    Button {
                        pickImportFile()
                    } label: {
                        Label("导入…（打勾备份）", systemImage: "square.and.arrow.down")
                    }
                    .buttonStyle(.bordered)
                    .disabled(importBusy)

                    Button {
                        runMigrationExport()
                    } label: {
                        Label("导出全部数据…", systemImage: "square.and.arrow.up")
                    }
                    .buttonStyle(.bordered)
                    .disabled(importBusy)
                }
                if let pendingImport {
                    importPreview(pendingImport)
                }
                Text("导出文件包含任务、笔记、清单和本地附件（base64 内嵌），可在打勾个人版与本机之间互相迁移。")
                    .font(WFType.supporting)
                    .foregroundStyle(WFColors.tertiaryText)
                HStack {
                    Button("导出工作区快照…") { runExport() }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    Text("旧入口：仅合并 workspace.json 与模块 JSON，不含附件。")
                        .font(WFType.supporting)
                        .foregroundStyle(WFColors.tertiaryText)
                }
                feedbackLine(.export)
                feedbackLine(.importData)
            }
            Section("备份") {
                HStack(alignment: .firstTextBaseline) {
                    Button("立即备份") { runBackup() }
                        .buttonStyle(.bordered)
                        .disabled(importBusy)
                    Button("恢复备份…") { openRestoreSheet() }
                        .buttonStyle(.bordered)
                        .disabled(importBusy)
                    Spacer()
                    Text(backupSummaryText)
                        .font(WFType.supporting)
                        .foregroundStyle(WFColors.secondaryText)
                }
                Text("每天首次修改会自动把 workspace.json 快照到 backups/，保留最近 7 天；恢复前会先备份当前内容。")
                    .font(WFType.supporting)
                    .foregroundStyle(WFColors.tertiaryText)
                feedbackLine(.backup)
                feedbackLine(.restore)
            }
        }
        .formStyle(.grouped)
        .safeAreaInset(edge: .bottom) {
            Text("数据仅保存在本机。导入或恢复备份后需重启应用才会重新加载；执行前都会先自动备份当前内容。")
                .font(WFType.supporting)
                .foregroundStyle(WFColors.tertiaryText)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, WFSpace.lg)
                .padding(.bottom, WFSpace.md)
        }
        .sheet(isPresented: $showingRestoreSheet) {
            restoreSheet
        }
        .confirmationDialog("清空本机后导入？", isPresented: $confirmReplaceImport, titleVisibility: .visible) {
            Button("清空并导入", role: .destructive) { performImport(mode: .replace) }
            Button("取消", role: .cancel) {}
        } message: {
            Text("以文件内容为准，本机当前任务和笔记会被清空。执行前会先自动备份当前数据。")
        }
        .confirmationDialog("恢复这份备份？", isPresented: Binding(
            get: { restoreCandidate != nil },
            set: { if !$0 { restoreCandidate = nil } }), titleVisibility: .visible) {
            Button("恢复") { if let candidate = restoreCandidate { performRestore(candidate) } }
            Button("取消", role: .cancel) {}
        } message: {
            Text("任务和笔记将恢复到备份时的状态。恢复前会先备份当前内容。")
        }
        .onAppear(perform: refresh)
    }

    // MARK: 导入预览

    @ViewBuilder
    private func importPreview(_ bundle: MigrationBundle) -> some View {
        VStack(alignment: .leading, spacing: WFSpace.xs) {
            Text("文件来自打勾个人版，包含：")
                .font(WFType.supporting)
                .foregroundStyle(WFColors.secondaryText)
            Text("任务 \(bundle.tasks.count) · 笔记 \(bundle.notes.count) · 清单 \(bundle.lists.count) · 文件夹 \(bundle.folders.count) · 附件 \(bundle.attachmentCount)")
                .font(WFType.supporting)
                .monospacedDigit()
            HStack {
                Button("合并到本机") { performImport(mode: .merge) }
                    .buttonStyle(.borderedProminent)
                    .disabled(importBusy)
                Button("清空后导入", role: .destructive) { confirmReplaceImport = true }
                    .buttonStyle(.bordered)
                    .disabled(importBusy)
                Button("取消") { pendingImport = nil }
                    .buttonStyle(.bordered)
                    .disabled(importBusy)
                if importBusy {
                    Text("处理中…")
                        .font(WFType.supporting)
                        .foregroundStyle(WFColors.tertiaryText)
                }
            }
            Text("合并会保留本地已有内容，相同 ID 的记录跳过；清空后导入以文件内容为准。")
                .font(WFType.supporting)
                .foregroundStyle(WFColors.tertiaryText)
        }
        .padding(.vertical, WFSpace.xs)
    }

    @ViewBuilder
    private var restoreSheet: some View {
        NavigationStack {
            List {
                Section("每日快照备份") {
                    let snapshots = restoreEntries.filter { !$0.isLegacyDirectoryBackup }
                    if snapshots.isEmpty {
                        Text("还没有可恢复的快照备份。")
                            .font(WFType.supporting)
                            .foregroundStyle(WFColors.tertiaryText)
                    }
                    ForEach(snapshots) { entry in
                        Button(entry.name) { choose(entry) }
                            .buttonStyle(.plain)
                            .font(WFType.supporting)
                    }
                }
                Section("旧版整目录备份") {
                    let legacy = restoreEntries.filter(\.isLegacyDirectoryBackup)
                    if legacy.isEmpty {
                        Text("暂无。")
                            .font(WFType.supporting)
                            .foregroundStyle(WFColors.tertiaryText)
                    }
                    ForEach(legacy) { entry in
                        Button(entry.name) { choose(entry) }
                            .buttonStyle(.plain)
                            .font(WFType.supporting)
                    }
                }
            }
            .navigationTitle("选择要恢复的备份")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { showingRestoreSheet = false }
                }
            }
        }
        .frame(width: 420, height: 380)
    }

    private func choose(_ entry: SnapshotRestoreEntry) {
        showingRestoreSheet = false
        restoreCandidate = entry
    }

    @ViewBuilder
    private var inventoryRows: some View {
        ForEach(entries, id: \.name) { entry in
            HStack(alignment: .firstTextBaseline) {
                Text(entry.name)
                    .font(WFType.supporting)
                    .foregroundStyle(WFColors.text)
                Spacer()
                if entry.exists, let sizeText = entry.sizeText, let modifiedText = entry.modifiedText {
                    Text("\(modifiedText) · \(sizeText)")
                        .font(WFType.supporting)
                        .monospacedDigit()
                        .foregroundStyle(WFColors.tertiaryText)
                } else {
                    Text("尚未生成")
                        .font(WFType.supporting)
                        .foregroundStyle(WFColors.tertiaryText)
                }
            }
        }
    }

    private func directoryRow(title: String, url: URL) -> some View {
        VStack(alignment: .leading, spacing: WFSpace.xs) {
            HStack(spacing: WFSpace.sm) {
                Text(title)
                    .font(WFType.section)
                Spacer()
                Button {
                    copyPath(of: url, title: title)
                } label: {
                    Label("复制路径", systemImage: "doc.on.doc")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                Button {
                    NSWorkspace.shared.open(url)
                } label: {
                    Label("在访达中打开", systemImage: "folder")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            Text(url.path)
                .font(WFType.supporting)
                .foregroundStyle(WFColors.secondaryText)
                .lineLimit(1)
                .truncationMode(.middle)
                .textSelection(.enabled)
                .help(url.path)
        }
    }

    @ViewBuilder
    private func feedbackLine(_ kind: FeedbackKind) -> some View {
        if feedbackKind == kind {
            Text(feedbackText)
                .font(WFType.supporting)
                .foregroundStyle(feedbackIsError ? Color.red : WFColors.secondaryText)
        }
    }

    private var backupSummaryText: String {
        guard let info = backupInfo, info.count > 0, let name = info.latestName else { return "每日自动备份：暂无" }
        return "每日自动备份：\(info.count) 份，最新 \(name)"
    }

    // MARK: Actions

    private func refresh() {
        entries = DataInventory.entries(directory: dataDirectory)
        attachmentDirectoryExists = FileManager.default.fileExists(atPath: attachmentDirectory.path)
        backupInfo = repository.backupInfo()
    }

    private func copyPath(of url: URL, title: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(url.path, forType: .string)
        showFeedback(.copiedPath, "已复制「\(title)」路径", isError: false)
    }

    // MARK: 导入

    private func pickImportFile() {
        let panel = NSOpenPanel()
        panel.title = "选择打勾个人版数据文件"
        panel.prompt = "导入"
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        var types: [UTType] = [.json]
        if let custom = UTType(filenameExtension: "workfollow") { types.append(custom) }
        panel.allowedContentTypes = types
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            importBusy = true
            DispatchQueue.global(qos: .userInitiated).async {
                var bundle: MigrationBundle?
                var failure: String?
                do {
                    bundle = try MigrationSnapshot.parse(Data(contentsOf: url))
                } catch let error as MigrationFormatError {
                    failure = error.localizedDescription
                } catch {
                    failure = "无法读取这个文件，请重新导出后再试。"
                }
                DispatchQueue.main.async {
                    importBusy = false
                    if let bundle {
                        pendingImport = bundle
                        refresh()
                    } else if let failure {
                        pendingImport = nil
                        showFeedback(.importData, failure, isError: true)
                    }
                }
            }
        }
    }

    private func performImport(mode: ImportMode) {
        guard let bundle = pendingImport else { return }
        importBusy = true
        let repository = repository
        DispatchQueue.global(qos: .userInitiated).async {
            var message: String?
            var failure: String?
            do {
                // 与 Flutter 一致：导入（合并或清空）前先自动备份当前内容。
                _ = try repository.backupNow()
                let restored = try MigrationSnapshot.restoreEmbeddedFiles(bundle.embeddedFiles,
                                                                         into: NativeAttachmentFiles.directory)
                let attachmentNames = MigrationSnapshot.attachmentNames(in: NativeAttachmentFiles.directory)

                let result: (snapshot: NativeWorkspaceSnapshot, summary: MigrationImportSummary)
                switch mode {
                case .merge:
                    let local: NativeWorkspaceSnapshot
                    do {
                        local = try repository.load() ?? NativeWorkspaceSnapshot(tasks: [], notes: [], taskLists: nil)
                    } catch {
                        throw NSError(domain: "MigrationImport", code: 2, userInfo: [NSLocalizedDescriptionKey:
                            "本地 workspace.json 无法读取（可能已损坏），请改用「清空后导入」。"])
                    }
                    result = MigrationSnapshot.merged(bundle, into: local, attachmentNames: attachmentNames)
                case .replace:
                    result = MigrationSnapshot.replaced(bundle, attachmentNames: attachmentNames)
                }
                try repository.save(result.snapshot)

                let summary = result.summary
                let skipped = summary.skippedTasks + summary.skippedNotes
                var text = mode == .replace
                    ? "已清空本机并导入 \(summary.importedTasks) 个任务、\(summary.importedNotes) 条笔记。"
                    : "已导入 \(summary.importedTasks) 个任务、\(summary.importedNotes) 条笔记（跳过 \(skipped) 条同 ID）。"
                if summary.importedLists > 0 { text += " 新建清单 \(summary.importedLists) 个。" }
                if summary.importedLegacyChildren > 0 { text += " 展开旧版子任务 \(summary.importedLegacyChildren) 条。" }
                if restored > 0 { text += " 还原附件 \(restored) 个。" }
                text += "重启应用后生效。"
                message = text
            } catch {
                failure = "导入失败：\(error.localizedDescription)"
            }
            DispatchQueue.main.async {
                importBusy = false
                if let message {
                    pendingImport = nil
                    showFeedback(.importData, message, isError: false)
                    refresh()
                } else if let failure {
                    showFeedback(.importData, failure, isError: true)
                }
            }
        }
    }

    // MARK: 导出

    /// 新入口：workfollow-personal-migration v3，含附件 base64。
    private func runMigrationExport() {
        let now = Date()
        importBusy = true
        let repository = repository
        DispatchQueue.global(qos: .userInitiated).async {
            var data: Data?
            var failure: String?
            do {
                let snapshot = try repository.load() ?? NativeWorkspaceSnapshot(tasks: [], notes: [], taskLists: nil)
                data = try MigrationSnapshot.exportJSON(from: snapshot,
                                                        attachmentDirectory: NativeAttachmentFiles.directory,
                                                        now: now)
            } catch {
                failure = "导出失败：workspace.json 读取失败，请先修复本机数据。"
            }
            DispatchQueue.main.async {
                importBusy = false
                if let data {
                    presentMigrationSavePanel(data, now: now)
                } else if let failure {
                    showFeedback(.export, failure, isError: true)
                }
            }
        }
    }

    private func presentMigrationSavePanel(_ data: Data, now: Date) {
        let panel = NSSavePanel()
        panel.title = "导出全部数据"
        panel.prompt = "导出"
        panel.nameFieldStringValue = DataExporter.suggestedFileName(for: now)
        panel.allowedContentTypes = [.json]
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            DispatchQueue.global(qos: .userInitiated).async {
                var failure: String?
                do {
                    try data.write(to: url, options: .atomic)
                } catch {
                    failure = "导出失败：\(error.localizedDescription)"
                }
                DispatchQueue.main.async {
                    if let failure {
                        showFeedback(.export, failure, isError: true)
                    } else {
                        showFeedback(.export, "已导出任务、笔记和本地附件到 \(url.lastPathComponent)", isError: false)
                    }
                }
            }
        }
    }

    /// 旧入口：合并 workspace.json 与模块 JSON（不含附件）。
    private func runExport() {
        let now = Date()
        DispatchQueue.global(qos: .userInitiated).async {
            var data: Data?
            var failure: String?
            do {
                data = try DataExporter.combinedExport(directory: dataDirectory, now: now)
            } catch {
                failure = "导出失败：\(error.localizedDescription)"
            }
            DispatchQueue.main.async {
                if let data {
                    let panel = NSSavePanel()
                    panel.title = "导出工作区快照"
                    panel.prompt = "导出"
                    panel.nameFieldStringValue = DataExporter.suggestedFileName(for: now)
                    panel.allowedContentTypes = [.json]
                    panel.begin { response in
                        guard response == .OK, let url = panel.url else { return }
                        do {
                            try data.write(to: url, options: .atomic)
                            showFeedback(.export, "已导出到 \(url.lastPathComponent)", isError: false)
                        } catch {
                            showFeedback(.export, "导出失败：\(error.localizedDescription)", isError: true)
                        }
                    }
                } else if let failure {
                    showFeedback(.export, failure, isError: true)
                }
            }
        }
    }

    // MARK: 备份与恢复

    private func runBackup() {
        let repository = repository
        DispatchQueue.global(qos: .userInitiated).async {
            var message: String?
            var failure: String?
            do {
                if let target = try repository.backupNow() {
                    message = "已创建备份：\(target.lastPathComponent)"
                } else {
                    message = "还没有 workspace.json，先使用应用产生数据后再备份。"
                }
            } catch {
                failure = "备份失败：\(error.localizedDescription)"
            }
            DispatchQueue.main.async {
                if let message { showFeedback(.backup, message, isError: false) }
                if let failure { showFeedback(.backup, failure, isError: true) }
                refresh()
            }
        }
    }

    private func openRestoreSheet() {
        let snapshots = repository.listBackups().reversed().map { url in
            SnapshotRestoreEntry(id: url.path, name: url.lastPathComponent, url: url,
                                 isLegacyDirectoryBackup: false)
        }
        let legacy = DataBackup.directoryBackups(in: dataDirectory).reversed().map { url in
            SnapshotRestoreEntry(id: url.path, name: url.lastPathComponent, url: url,
                                 isLegacyDirectoryBackup: true)
        }
        restoreEntries = Array(snapshots) + Array(legacy)
        showingRestoreSheet = true
    }

    private func performRestore(_ entry: SnapshotRestoreEntry) {
        let repository = repository
        let url = entry.url
        DispatchQueue.global(qos: .userInitiated).async {
            var failure: String?
            do {
                try repository.restoreBackup(at: url)
            } catch {
                failure = "无法恢复这份备份：\(error.localizedDescription)"
            }
            DispatchQueue.main.async {
                restoreCandidate = nil
                if let failure {
                    showFeedback(.restore, failure, isError: true)
                } else {
                    showFeedback(.restore, "已恢复所选备份。重启应用后生效。", isError: false)
                }
                refresh()
            }
        }
    }

    private func showFeedback(_ kind: FeedbackKind, _ text: String, isError: Bool) {
        feedbackKind = kind
        feedbackText = text
        feedbackIsError = isError
    }
}
