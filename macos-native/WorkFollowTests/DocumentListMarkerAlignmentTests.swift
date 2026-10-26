import XCTest
@testable import WorkFollow

/// 列表标记与引用竖条的横向对齐：滴答实测（2026-10-16，截图 1px = 1pt）。
///
/// 滴答同一段内容里的墨迹位置：正文与标题文字起于 x19，圆点 x19..24，
/// 有序编号 x19..28.5，列表文字 x34，引用竖条 x22..23.5。也就是说**标记与文字左缘
/// 对齐**、不是右对齐成一列；引用竖条落在文字左缘右侧 3pt。
///
/// 断言用**相对**位置（相对标题文字墨迹左缘）——宿主给的内容起点不同不影响结论。
final class DocumentListMarkerAlignmentTests: XCTestCase {
    private struct Band {
        var segments: [(start: CGFloat, end: CGFloat)]
    }

    /// 离屏渲染五行内容（标题 / 无序 / 有序 / 复选 / 引用），返回每行的墨水列段（pt）。
    @MainActor
    private func measuredBands() throws -> [Band] {
        let width: CGFloat = 400, height: CGFloat = 220
        let view = NativeTextView(frame: NSRect(x: 0, y: 0, width: width, height: height), textContainer: nil)
        view.profile = DocumentProfile(taskSlash: true)
        view.textContainerInset = NSSize(width: 20, height: 8)
        // 固定浅色外观：动态色在深色宿主里会失真，墨迹阈值就失去基准。
        view.appearance = NSAppearance(named: .aqua)
        view.backgroundColor = .white
        view.drawsBackground = true
        let document = NativeDocument(blocks: [
            DocumentBlock(kind: .heading(1), runs: [DocumentRun(text: "H1")]),
            DocumentBlock(kind: .bullet, runs: [DocumentRun(text: "无")]),
            DocumentBlock(kind: .ordered, runs: [DocumentRun(text: "有")]),
            DocumentBlock(kind: .checklist(false), runs: [DocumentRun(text: "点")]),
            DocumentBlock(kind: .quote, runs: [DocumentRun(text: "引")])
        ])
        view.textStorage?.setAttributedString(DocumentTextCodec.render(document))

        let window = NSWindow(contentRect: view.frame, styleMask: [.borderless],
                              backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: .aqua)
        window.backgroundColor = .white
        window.isReleasedWhenClosed = false
        window.contentView = view
        window.orderFrontRegardless()
        RunLoop.current.run(until: Date().addingTimeInterval(0.4))
        view.layoutManager?.ensureLayout(for: view.textContainer!)

        let rep = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: rep)
        let scale = CGFloat(rep.pixelsWide) / view.bounds.width

        func isInk(_ x: Int, _ y: Int) -> Bool {
            guard let c = rep.colorAt(x: x, y: y) else { return false }
            return (c.redComponent + c.greenComponent + c.blueComponent) / 3 < 0.9
        }

        var bands: [(Int, Int)] = []
        var current: (Int, Int)?
        for y in 0..<rep.pixelsHigh {
            var count = 0
            for x in 0..<rep.pixelsWide where isInk(x, y) { count += 1 }
            if count > 0 { current = current.map { ($0.0, y) } ?? (y, y) }
            else if let c = current { bands.append(c); current = nil }
        }
        if let c = current { bands.append(c) }

        return bands.map { band in
            var columns = [Bool](repeating: false, count: rep.pixelsWide)
            for y in band.0...band.1 {
                for x in 0..<rep.pixelsWide where isInk(x, y) { columns[x] = true }
            }
            var segments: [(CGFloat, CGFloat)] = []
            var start: Int?
            for (x, inked) in columns.enumerated() {
                if inked { start = start ?? x }
                else if let s = start {
                    segments.append((CGFloat(s) / scale, CGFloat(x) / scale))
                    start = nil
                }
            }
            if let s = start { segments.append((CGFloat(s) / scale, CGFloat(rep.pixelsWide) / scale)) }
            return Band(segments: segments)
        }
    }

    @MainActor
    func testMarkersAndQuoteRuleAlignToTheTextLeftEdge() throws {
        let bands = try measuredBands()
        XCTAssertEqual(bands.count, 5, "五行内容应各成一条墨水带")

        // 基准：标题文字（H1）的墨迹左缘。
        let reference = try XCTUnwrap(bands[0].segments.first?.start)

        // 无序项：圆点左缘贴文字左缘，右缘 +5.5；列表文字 +15 上下。
        let bullet = bands[1].segments
        XCTAssertEqual(bullet.count, 2, "无序行应是「圆点 + 文字」两段")
        XCTAssertEqual(bullet[0].start - reference, 0, accuracy: 1, "圆点左缘与正文文字左缘对齐（滴答 x19）")
        XCTAssertEqual(bullet[0].end - reference, 5.5, accuracy: 1, "圆点右缘 ≈ +5.5（滴答 x24）")
        XCTAssertEqual(bullet[1].start - reference, 15, accuracy: 1.5, "列表文字 ≈ +15（滴答 x34）")

        // 有序项：编号「1.」从文字左缘起排，不再是右对齐到文字左侧 7pt。
        let ordered = bands[2].segments
        XCTAssertEqual(ordered.count, 3, "有序行应是「1 + . + 文字」三段")
        XCTAssertEqual(ordered[0].start - reference, 0.5, accuracy: 1, "编号左缘 ≈ +0.5（滴答 x19）")
        XCTAssertEqual(ordered[1].end - reference, 9, accuracy: 1.5, "编号右缘 ≈ +9（滴答 x28.5）")
        XCTAssertEqual(ordered[2].start - reference, 15, accuracy: 1.5, "列表文字 ≈ +15")

        // 复选款：17pt 命中区里画 15pt 可见框（滴答截图实测），左缘与其余标记一致，
        // 文字比普通列表再多让 8pt。
        let checklist = bands[3].segments
        XCTAssertGreaterThanOrEqual(checklist.count, 2, "复选行应是「复选框 + 文字」")
        XCTAssertEqual(checklist[0].start - reference, 0, accuracy: 1.5, "复选框左缘与文字左缘对齐")
        XCTAssertEqual(checklist[0].end - checklist[0].start, 15, accuracy: 1.5, "复选框可见框 15pt 宽")
        XCTAssertEqual(checklist.last!.start - reference, 23, accuracy: 1.5, "复选文字 ≈ +23")

        // 引用：竖条 2pt 宽，落在文字左缘右侧 3pt。
        let quote = bands[4].segments
        XCTAssertGreaterThanOrEqual(quote.count, 2, "引用行应有「竖条 + 文字」")
        XCTAssertEqual(quote[0].start - reference, 3, accuracy: 1, "竖条左缘 ≈ +3（滴答 x22）")
        XCTAssertEqual(quote[0].end - quote[0].start, 2, accuracy: 0.5, "竖条 2pt 宽（滴答 x22..23）")
    }
}
