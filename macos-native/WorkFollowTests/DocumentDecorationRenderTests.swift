import XCTest
@testable import WorkFollow

/// 活动行标记（标题角标 / 空行"+"）的离屏渲染验收。
///
/// 把 `NativeTextView` 挂到真实窗口、设好选区后抓取真实渲染结果
/// （`drawViewHierarchy`；TextKit 2 的文本不走 `draw(_:)`，
/// `cacheDisplay` 抓不到）：
/// - 沟槽（视图左侧 20pt）里的非白像素只可能来自行首装饰——
///   正文与光标都画在 x≥25，所以"沟槽有墨"⇔"标记画出来了"。
/// - 同时把 PNG 落到 /tmp 供人工目检几何位置。
final class DocumentDecorationRenderTests: XCTestCase {
    private let sample = NativeDocument(blocks: [
        DocumentBlock(kind: .heading(2), runs: [DocumentRun(text: "标题行")]),
        DocumentBlock(kind: .paragraph, runs: [DocumentRun(text: "正文")]),
        DocumentBlock(kind: .paragraph, runs: [DocumentRun(text: "")]),
    ])

    @MainActor
    private func renderedGutter(caret: Int, dump name: String,
                                typingKind: DocumentBlockKind? = nil) throws -> (rep: NSBitmapImageRep, scale: CGFloat) {
        let width: CGFloat = 600
        let height: CGFloat = 300
        let view = NativeTextView(frame: NSRect(x: 0, y: 0, width: width, height: height), textContainer: nil)
        let window = NSWindow(contentRect: view.frame, styleMask: [.borderless],
                              backing: .buffered, defer: false)
        window.backgroundColor = .white
        window.hasShadow = false
        // 装饰用的是动态系统色（tertiaryLabelColor 等）：系统切到深色模式后，
        // 它们变成近白色，"白底 + 非白像素"的断言会整片失效（实测踩过）。
        // 测试把外观钉在浅色，颜色可预期，与断言口径一致。
        window.appearance = NSAppearance(named: .aqua)
        window.contentView = view
        window.orderFrontRegardless()
        window.makeFirstResponder(view)
        view.textStorage?.setAttributedString(DocumentTextCodec.render(sample))
        if let typingKind {
            view.typingAttributes = DocumentTextCodec.attributes(kind: typingKind, marks: [])
            // 装饰层读取模型同步的文末级别（测试里没有协调器，手动给值）。
            view.displayedTrailingBlock = typingKind
        }
        view.setSelectedRange(NSRange(location: caret, length: 0))
        view.displayIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.2))

        // 直接抓窗口合成结果：TextKit 2 的文本不走 draw(_)，位图重绘抓不到；
        // 窗口镜像才是用户看到的真实画面。
        let cgImage = try XCTUnwrap(CGWindowListCreateImage(
            .null, .optionIncludingWindow, CGWindowID(window.windowNumber), [.bestResolution]))
        let rep = NSBitmapImageRep(cgImage: cgImage)
        let png = try XCTUnwrap(rep.representation(using: .png, properties: [:]))
        try png.write(to: URL(fileURLWithPath: "/tmp/render_\(name).png"))
        let scale = CGFloat(rep.pixelsWide) / width
        return (rep, scale)
    }

    /// 沟槽区域内是否存在非白的不透明像素。
    /// 窗口底为白，正文/光标都在 x≥25pt；捕获图两侧有透明黑边（alpha=0），
    /// 必须按 alpha 过滤，否则透明黑会被误判成墨迹。
    private func gutterHasInk(_ rep: NSBitmapImageRep, scale: CGFloat) -> Bool {
        let columnLimit = min(Int(20.0 * scale), rep.pixelsWide)
        var y = 0
        while y < rep.pixelsHigh {
            var x = 0
            while x < columnLimit {
                if let color = rep.colorAt(x: x, y: y), color.alphaComponent > 0.5 {
                    let isBackground = color.redComponent > 0.95
                        && color.greenComponent > 0.95 && color.blueComponent > 0.95
                    if !isBackground { return true }
                }
                x += 1
            }
            y += 1
        }
        return false
    }

    /// 光标在标题行：行首沟槽应出现 H2 角标。
    @MainActor
    func testHeadingBadgeDrawsInGutterForActiveHeadingLine() throws {
        let (rep, scale) = try renderedGutter(caret: 0, dump: "badge")
        XCTAssertTrue(gutterHasInk(rep, scale: scale),
                      "H2 角标应画在标题行左侧的沟槽里")
    }

    /// 光标在文末空行：行首沟槽应出现 "+"。
    @MainActor
    func testEmptyLinePlusDrawsInGutterForActiveEmptyLine() throws {
        let (rep, scale) = try renderedGutter(caret: sample.plainText.count, dump: "plus")
        XCTAssertTrue(gutterHasInk(rep, scale: scale),
                      "空行活动时沟槽里应画出 +")
    }

    /// 光标在非空正文行：沟槽应保持干净（普通段落没有行首标记）。
    @MainActor
    func testPlainBodyLineLeavesGutterEmpty() throws {
        let (rep, scale) = try renderedGutter(caret: 5, dump: "plain")
        XCTAssertFalse(gutterHasInk(rep, scale: scale), "普通非空段落不应在沟槽里画任何标记")
    }

    /// 两个渲染在指定横向区间（pt）内，B 相对 A 新出现的非白像素数。
    /// 捕获图存在垂直翻转/底部锚定的不确定性与透明边缘，逐列差分比
    /// 固定坐标区域更稳。
    private func newInkCount(base: NSBitmapImageRep, other: NSBitmapImageRep,
                             scale: CGFloat, ptColumn: NSRange) -> Int {
        let x0 = Int(Double(ptColumn.location) * scale)
        let x1 = min(Int(Double(ptColumn.location + ptColumn.length) * scale), other.pixelsWide)
        func isInk(_ color: NSColor?) -> Bool {
            guard let color, color.alphaComponent > 0.5 else { return false }
            return !(color.redComponent > 0.95 && color.greenComponent > 0.95 && color.blueComponent > 0.95)
        }
        var count = 0
        var y = 0
        while y < min(base.pixelsHigh, other.pixelsHigh) {
            var x = x0
            while x < x1 {
                if !isInk(base.colorAt(x: x, y: y)), isInk(other.colorAt(x: x, y: y)) { count += 1 }
                x += 1
            }
            y += 1
        }
        return count
    }

    /// 光标在文末空段且待定级别是列表：列表缩进区应画出项目符号
    /// （无字符的段落主循环看不到，由活动行绘制补上）。
    /// 基线是同一位置的"+"（画在沟槽 0..15pt），列表符号画在缩进区 25..45pt，
    /// 对比两者在符号区的新增墨迹。
    @MainActor
    func testTrailingEmptyLineWithPendingListKindDrawsMarker() throws {
        let baseline = try renderedGutter(caret: sample.plainText.count, dump: "pending_plus",
                                          typingKind: nil)
        let pending = try renderedGutter(caret: sample.plainText.count, dump: "pending_list",
                                         typingKind: .bullet)
        let delta = newInkCount(base: baseline.rep, other: pending.rep,
                                scale: pending.scale, ptColumn: NSRange(location: 16, length: 44))
        XCTAssertGreaterThan(delta, 10, "文末空段的待定列表应画出项目符号")
    }
}
