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
    private enum FeedbackKind { case copiedPath, backup, export }

    @State private var entries: [DataInventory.Entry] = []
    @State private var attachmentDirectoryExists = false
    @State private var latestBackupName: String?
    @State private var feedbackKind: FeedbackKind?
    @State private var feedbackText = ""
    @State private var feedbackIsError = false

    private var dataDirectory: URL { NativePreviewRepository.directory }
    private var attachmentDirectory: URL { NativeAttachmentFiles.directory }

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
            Section("备份") {
                HStack(alignment: .firstTextBaseline) {
                    Button("立即备份") { runBackup() }
                        .buttonStyle(.bordered)
                    Spacer()
                    Text("最近备份：\(latestBackupName ?? "暂无")")
                        .font(WFType.supporting)
                        .foregroundStyle(WFColors.secondaryText)
                }
                Text("备份保存到数据目录的 backups 子文件夹，同名备份会被替换。")
                    .font(WFType.supporting)
                    .foregroundStyle(WFColors.tertiaryText)
                feedbackLine(.backup)
            }
            Section("导出") {
                HStack {
                    Button("导出 JSON…") { runExport() }
                        .buttonStyle(.bordered)
                    Spacer()
                }
                feedbackLine(.export)
            }
        }
        .formStyle(.grouped)
        .safeAreaInset(edge: .bottom) {
            Text("数据仅保存在本机。恢复备份时请退出应用后用备份目录中的文件替换数据目录中的同名文件。")
                .font(WFType.supporting)
                .foregroundStyle(WFColors.tertiaryText)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, WFSpace.lg)
                .padding(.bottom, WFSpace.md)
        }
        .onAppear(perform: refresh)
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

    // MARK: Actions

    private func refresh() {
        entries = DataInventory.entries(directory: dataDirectory)
        attachmentDirectoryExists = FileManager.default.fileExists(atPath: attachmentDirectory.path)
        latestBackupName = DataBackup.latestBackupName(in: dataDirectory)
    }

    private func copyPath(of url: URL, title: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(url.path, forType: .string)
        showFeedback(.copiedPath, "已复制「\(title)」路径", isError: false)
    }

    private func runBackup() {
        do {
            let target = try DataBackup.performBackup(directory: dataDirectory, date: Date())
            refresh()
            showFeedback(.backup, "备份完成：\(target.lastPathComponent)", isError: false)
        } catch {
            showFeedback(.backup, "备份失败：\(error.localizedDescription)", isError: true)
        }
    }

    private func runExport() {
        let now = Date()
        let data: Data
        do {
            data = try DataExporter.combinedExport(directory: dataDirectory, now: now)
        } catch {
            showFeedback(.export, "导出失败：\(error.localizedDescription)", isError: true)
            return
        }
        let panel = NSSavePanel()
        panel.title = "导出 JSON"
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
    }

    private func showFeedback(_ kind: FeedbackKind, _ text: String, isError: Bool) {
        feedbackKind = kind
        feedbackText = text
        feedbackIsError = isError
    }
}
