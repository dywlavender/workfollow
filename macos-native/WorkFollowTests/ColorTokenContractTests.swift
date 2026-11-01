import XCTest
@testable import WorkFollow

/// 颜色令牌契约：`Features/` 不得手写颜色构造（`Color(red:)` /
/// `NSColor(red:)` / `NSColor(srgbRed:)` / `Color(hex:)`），界面语义色一律
/// 收进 `DesignSystem/Colors.swift` 的 `WFColors`——它自 2026-10 起就是
/// 全 App 界面色的唯一色源，裸值散进各功能页必然漂移（同一语义色两处取值）。
///
/// 白名单只收**不是界面语义色**的三类，新增例外必须在这里写明理由：
/// 1. 插画 / 吉祥物的作画色——内容，不是界面（skill 口径：imagery 是内容）；
/// 2. ARGB / hex → Color 的解析器——值来自数据或外部色板，不是手调；
/// 3. 有固定外部参照的色板（如 `WFPlanningPalette` 的象限四色、滴答 CSS
///    角色色）——它们的"唯一色源"就是那张外部色表。
final class ColorTokenContractTests: XCTestCase {
    private let allowlistedFiles: Set<String> = [
        // 插画 / 吉祥物作画色：内容色，留在各自文件里。
        "FocusCompletionPane.swift",
        "FocusEmptyRecordsIllustration.swift",
        "CompanionDockView.swift",
        // ARGB / hex 解析器：颜色来自数据或外部色表。
        "FocusOverviewPane.swift",
        "TaskManagementViews.swift",
        "CodeSyntaxHighlighter.swift",
        // 固定外部参照的色板：象限四色对齐 WorkFollowColorTokens。
        "PlanningMetrics.swift",
    ]

    private let rawColorPatterns = [
        "Color(red:",
        "NSColor(red:",
        "NSColor(srgbRed:",
        "Color(srgbRed:",
        "Color(hex:",
    ]

    func testFeatureSourcesDoNotHandRollColors() throws {
        let violations = try featureSourceFiles().compactMap { file -> String? in
            guard !allowlistedFiles.contains(file.lastPathComponent) else { return nil }
            let source = try String(contentsOf: file, encoding: .utf8)
            let hits = rawColorPatterns.filter { source.contains($0) }
            guard !hits.isEmpty else { return nil }
            return "\(relativePath(of: file)): \(hits.joined(separator: ", "))"
        }
        XCTAssertTrue(violations.isEmpty, """
            界面色必须走 WFColors（DesignSystem/Colors.swift），不要手写颜色构造。
            若新增的裸色属于界面语义色：进 Colors.swift 对应的 MARK 组再引用；
            若确认是插画色 / 解析器 / 外部色板：在 ColorTokenContractTests 的
            allowlistedFiles 里写明理由后加入。违规：
            \(violations.joined(separator: "\n"))
            """)
    }

    // 与 ArrowlessTaskPopupContractTests 同一套：从测试文件自身定位源码根，
    // 不依赖测试运行器的 cwd；枚举残缺必须响亮失败而不是给出空转绿灯。
    private var featuresRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("WorkFollow", isDirectory: true)
            .appendingPathComponent("Features", isDirectory: true)
    }

    private func featureSourceFiles() throws -> [URL] {
        let enumerator = try XCTUnwrap(
            FileManager.default.enumerator(
                at: featuresRoot,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            ),
            "Could not enumerate Features at \(featuresRoot.path)"
        )
        let files = enumerator.compactMap { $0 as? URL }
            .filter { $0.pathExtension == "swift" }
            .sorted { $0.path < $1.path }
        try XCTUnwrap(!files.isEmpty,
                      "Features enumeration returned no files; contract would pass vacuously")
        try XCTUnwrap(files.contains { $0.lastPathComponent == "RootShellView.swift" },
                      "Enumeration missed RootShellView.swift; source scan is incomplete")
        return files
    }

    private func relativePath(of file: URL) -> String {
        String(file.path.dropFirst(featuresRoot.path.count + 1))
    }
}
