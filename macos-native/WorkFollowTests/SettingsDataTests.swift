import XCTest
@testable import WorkFollow

final class SettingsDataTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("SettingsDataTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory.appendingPathComponent("modules", isDirectory: true),
            withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    // MARK: Helpers

    private let formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter
    }()

    private func write(_ text: String, to relativePath: String) throws {
        let url = directory.appendingPathComponent(relativePath)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: url)
    }

    // MARK: DataInventory

    func testInventoryListsWorkspaceAndKnownModuleFilesMarkingMissingOnes() throws {
        try write(#"{"version":1,"tasks":[]}"#, to: "workspace.json")
        try write(#"{"streak":3}"#, to: "modules/focus.json")

        let entries = DataInventory.entries(directory: directory, dateFormatter: formatter)

        XCTAssertEqual(entries.map(\.name),
                       ["workspace.json", "modules/focus.json", "modules/habits.json",
                        "modules/summary.json", "modules/filters.json", "modules/templates.json"])
        XCTAssertEqual(entries.filter(\.exists).map(\.name), ["workspace.json", "modules/focus.json"])
        let missing = try XCTUnwrap(entries.first { $0.name == "modules/habits.json" })
        XCTAssertFalse(missing.exists)
        XCTAssertNil(missing.sizeText)
        XCTAssertNil(missing.modifiedText)
    }

    func testInventoryReadsFileSizeAndModificationTime() throws {
        try write(String(repeating: "x", count: 2048), to: "workspace.json")
        let modified = formatter.date(from: "2026-09-26 14:30")!
        try FileManager.default.setAttributes([.modificationDate: modified],
                                              ofItemAtPath: directory.appendingPathComponent("workspace.json").path)

        let entry = DataInventory.entry(named: "workspace.json", in: directory, dateFormatter: formatter)

        XCTAssertTrue(entry.exists)
        XCTAssertEqual(entry.sizeText, "2.0 KB")
        XCTAssertEqual(entry.modifiedText, "2026-09-26 14:30")
    }

    func testSizeTextFormatsBytesKilobytesMegabytesAndGigabytes() {
        XCTAssertEqual(DataInventory.sizeText(forBytes: 512), "512 B")
        XCTAssertEqual(DataInventory.sizeText(forBytes: 1536), "1.5 KB")
        XCTAssertEqual(DataInventory.sizeText(forBytes: 2 * 1024 * 1024), "2.0 MB")
        XCTAssertEqual(DataInventory.sizeText(forBytes: 3 * 1024 * 1024 * 1024), "3.0 GB")
    }

    func testInventoryAppendsExtraModuleJsonSortedAndSkipsOtherFiles() throws {
        try write("{}", to: "modules/zz-extra.json")
        try write("{}", to: "modules/aa-extra.json")
        try write("text", to: "modules/notes.txt")
        try write("{}", to: "modules/.hidden.json")
        try FileManager.default.createDirectory(
            at: directory.appendingPathComponent("modules/subfolder.json", isDirectory: true),
            withIntermediateDirectories: true)

        let entries = DataInventory.entries(directory: directory, dateFormatter: formatter)

        XCTAssertEqual(Array(entries.map(\.name).suffix(2)),
                       ["modules/aa-extra.json", "modules/zz-extra.json"])
        XCTAssertFalse(entries.map(\.name).contains("modules/notes.txt"))
        XCTAssertFalse(entries.map(\.name).contains("modules/.hidden.json"))
        XCTAssertFalse(entries.map(\.name).contains("modules/subfolder.json"))
    }

    // MARK: DataExporter

    func testCombinedExportMergesWorkspaceAndExistingModulesSkippingMissing() throws {
        try write(#"{"version":1,"tasks":["整理桌面"]}"#, to: "workspace.json")
        try write(#"{"streak":3}"#, to: "modules/focus.json")

        let now = formatter.date(from: "2026-09-26 14:30")!
        let data = try DataExporter.combinedExport(directory: directory, now: now)
        let object = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])

        XCTAssertEqual(object["version"] as? Int, 1)
        XCTAssertEqual(object["exportedAt"] as? String, ISO8601DateFormatter().string(from: now))
        let workspace = try XCTUnwrap(object["workspace"] as? [String: Any])
        XCTAssertEqual(workspace["tasks"] as? [String], ["整理桌面"])
        let modules = try XCTUnwrap(object["modules"] as? [String: Any])
        XCTAssertEqual(Set(modules.keys), ["focus.json"])
        let focus = try XCTUnwrap(modules["focus.json"] as? [String: Any])
        XCTAssertEqual(focus["streak"] as? Int, 3)
    }

    func testCombinedExportKeepsOriginalValuesWithoutReencoding() throws {
        try write(#"{"ratio":1.5,"count":3,"title":"专注"}"#, to: "modules/habits.json")

        let data = try DataExporter.combinedExport(directory: directory)
        let object = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let habits = try XCTUnwrap(
            (object["modules"] as? [String: Any])?["habits.json"] as? [String: Any])

        XCTAssertEqual((habits["ratio"] as? NSNumber)?.doubleValue, 1.5)
        XCTAssertEqual(habits["count"] as? Int, 3)
        XCTAssertEqual(habits["title"] as? String, "专注")
        XCTAssertTrue(String(decoding: data, as: UTF8.self).contains("1.5"))
    }

    func testCombinedExportWithoutDataYieldsNullWorkspaceAndEmptyModules() throws {
        let empty = FileManager.default.temporaryDirectory
            .appendingPathComponent("SettingsDataTests-empty-\(UUID().uuidString)", isDirectory: true)

        let data = try DataExporter.combinedExport(directory: empty)
        let object = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])

        XCTAssertTrue(object["workspace"] is NSNull)
        XCTAssertEqual((object["modules"] as? [String: Any])?.count, 0)
    }

    func testCombinedExportThrowsWhenWorkspaceFileIsCorrupt() throws {
        try write("not json", to: "workspace.json")

        XCTAssertThrowsError(try DataExporter.combinedExport(directory: directory))
    }

    func testSuggestedExportFileNameUsesInjectedFormatter() {
        let dayFormatter = DateFormatter()
        dayFormatter.locale = Locale(identifier: "en_US_POSIX")
        dayFormatter.dateFormat = "yyyy-MM-dd"
        let day = dayFormatter.date(from: "2026-09-26")!

        XCTAssertEqual(DataExporter.suggestedFileName(for: day, formatter: dayFormatter),
                       "WorkFollow导出 2026-09-26.json")
    }

    // MARK: DataBackup

    func testBackupDirectoryNameUsesInjectedFormatter() {
        let stampFormatter = DateFormatter()
        stampFormatter.locale = Locale(identifier: "en_US_POSIX")
        stampFormatter.dateFormat = "yyyy-MM-dd HH-mm"
        let instant = stampFormatter.date(from: "2026-09-26 14-30")!

        XCTAssertEqual(DataBackup.directoryName(for: instant, formatter: stampFormatter),
                       "备份 2026-09-26 14-30")
    }

    func testPerformBackupCopiesAllFilesAndReplacesSameNameTarget() throws {
        try write(#"{"version":1}"#, to: "workspace.json")
        try write(#"{"streak":3}"#, to: "modules/focus.json")
        try write("附件内容", to: "Attachments/note.txt")

        let stampFormatter = DateFormatter()
        stampFormatter.locale = Locale(identifier: "en_US_POSIX")
        stampFormatter.dateFormat = "yyyy-MM-dd HH-mm"
        let instant = stampFormatter.date(from: "2026-09-26 14-30")!

        let target = try DataBackup.performBackup(directory: directory, date: instant)
        XCTAssertEqual(target.lastPathComponent, "备份 2026-09-26 14-30")
        XCTAssertEqual(try String(contentsOf: target.appendingPathComponent("workspace.json"), encoding: .utf8),
                       #"{"version":1}"#)
        XCTAssertTrue(FileManager.default.fileExists(atPath: target.appendingPathComponent("modules/focus.json").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: target.appendingPathComponent("Attachments/note.txt").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: target.appendingPathComponent("backups").path))

        // 同名备份先删除再整体重拷，不遗留旧文件，也不把 backups/ 拷进自己。
        try write(#"{"version":2}"#, to: "workspace.json")
        try FileManager.default.removeItem(at: target.appendingPathComponent("modules"))
        try DataBackup.performBackup(directory: directory, date: instant)

        XCTAssertEqual(try String(contentsOf: target.appendingPathComponent("workspace.json"), encoding: .utf8),
                       #"{"version":2}"#)
        XCTAssertEqual(Set(try FileManager.default.contentsOfDirectory(
            atPath: target.appendingPathComponent("modules").path)), ["focus.json"])
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(
            atPath: directory.appendingPathComponent("backups").path).count, 1)
    }

    func testLatestBackupNameReturnsNewestAndNilWithoutBackups() throws {
        XCTAssertNil(DataBackup.latestBackupName(in: directory))

        let backups = directory.appendingPathComponent("backups", isDirectory: true)
        try FileManager.default.createDirectory(
            at: backups.appendingPathComponent("备份 2026-09-25 09-00"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(
            at: backups.appendingPathComponent("备份 2026-09-26 14-30"), withIntermediateDirectories: true)

        XCTAssertEqual(DataBackup.latestBackupName(in: directory), "备份 2026-09-26 14-30")
    }
}
