import XCTest
@testable import WorkFollow

/// 滴答 Markdown 行为规格（2026-10-16 对滴答清单 8.0.80 编辑栏运行时探针的固化）。
///
/// 每条断言的来源：
/// - 块级：`#` 后必须有空格；`#`~`######` 六级；`* `/`- ` 无序；`1. ` 有序；`- [ ]`/`- [x]` 任务；`> ` 引用（不支持嵌套）；``` 围栏代码块；`---` 分割线。
/// - 行内：`**` 加粗、`*` 斜体、`~~` 删除线、`~` 下划线（滴答扩展）、`::` 高亮（滴答扩展）、`` ` `` 行内代码、`[字](url)` 链接。
/// - 边缘：未闭合标记保持字面；表格/HTML/数学/`==` 原样；多空行合并；嵌套引用第二个 `>` 保留为字面。
/// - 工具条（已实测）：加粗插 `**`、斜体插 `*`、下划线插 `~`、删除线插 `~~`、高亮插 `::`、代码插 `` ` ``、
///   任务插 `- [ ] `、无序插 `* `、有序插 `1. `、分割线插独立行 `---`。
final class MarkdownSyntaxTests: XCTestCase {

    // MARK: - 块级

    func testHeadingsRequireSpaceAndSupportSixLevels() {
        let doc = MarkdownSyntax.parse("# H1\n##无空格\n###### H6\n####### 七个井号\n")
        XCTAssertEqual(doc.blocks.count, 4)
        XCTAssertEqual(doc.blocks[0].kind, .heading(level: 1))
        XCTAssertEqual(doc.blocks[1].kind, .paragraph, "`#` 后无空格不解析为标题")
        XCTAssertEqual(doc.blocks[2].kind, .heading(level: 6))
        XCTAssertEqual(doc.blocks[3].kind, .paragraph, "七个 # 超出六级，按段落")
    }

    func testHeadingMarkerRangeCoversHashesAndSpace() {
        let doc = MarkdownSyntax.parse("## 标题\n")
        XCTAssertEqual(doc.blocks[0].markerRange, NSRange(location: 0, length: 3))
        XCTAssertEqual(doc.blocks[0].contentRange, NSRange(location: 3, length: 2))
    }

    func testBulletAcceptsStarAndHyphen() {
        let doc = MarkdownSyntax.parse("* 星号\n- 连字符\n+ 加号\n")
        XCTAssertEqual(doc.blocks.map(\.kind), [.bullet, .bullet, .bullet])
        XCTAssertEqual(doc.blocks[0].markerRange, NSRange(location: 0, length: 2))
    }

    func testOrderedList() {
        let doc = MarkdownSyntax.parse("1. 第一\n12. 第十二\n1.无空格\n")
        XCTAssertEqual(doc.blocks[0].kind, .ordered)
        XCTAssertEqual(doc.blocks[1].kind, .ordered)
        XCTAssertEqual(doc.blocks[2].kind, .paragraph, "`1.` 后必须有空格")
    }

    func testChecklistStates() {
        let doc = MarkdownSyntax.parse("- [ ] 未完成\n- [x] 已完成\n- [X] 大写\n* [ ] 星号任务\n- [] 缺空格\n")
        XCTAssertEqual(doc.blocks[0].kind, .checklist(checked: false))
        XCTAssertEqual(doc.blocks[1].kind, .checklist(checked: true))
        XCTAssertEqual(doc.blocks[2].kind, .checklist(checked: true))
        XCTAssertEqual(doc.blocks[3].kind, .checklist(checked: false))
        XCTAssertEqual(doc.blocks[4].kind, .bullet, "`[]` 缺空格退化为无序列表")
        XCTAssertEqual(doc.blocks[0].markerRange, NSRange(location: 0, length: 6))
    }

    func testQuoteKeepsNestedMarkerAsLiteral() {
        // 滴答不支持嵌套引用：`> > x` 渲染为引用块 + 字面 `> x`
        let doc = MarkdownSyntax.parse("> 单层\n> > 双层\n")
        XCTAssertEqual(doc.blocks[0].kind, .quote)
        XCTAssertEqual(doc.blocks[1].kind, .quote)
        XCTAssertEqual(doc.blocks[1].inlines.map(\.text).joined(), "> 双层")
    }

    func testCodeBlockWithFence() {
        let doc = MarkdownSyntax.parse("```\n第一行\n第二行\n```\n")
        XCTAssertEqual(doc.blocks.count, 1)
        XCTAssertEqual(doc.blocks[0].kind, .codeBlock)
        XCTAssertEqual(doc.blocks[0].inlines.map(\.text), ["第一行", "第二行"])
        XCTAssertEqual(doc.blocks[0].codeLines.count, 2)
    }

    func testDivider() {
        let doc = MarkdownSyntax.parse("正文\n\n---\n\n后面\n")
        XCTAssertEqual(doc.blocks.map(\.kind), [.paragraph, .divider, .paragraph])
    }

    func testFenceLineJudgeForTypedInput() {
        // 输入期整行围栏判定：3+ 反引号（行首最多 3 空格）成立；
        // 带语言标记、行内位置、不足 3 个都不成立（2026-10-16 口径）。
        XCTAssertTrue(MarkdownSyntax.isFenceLine("```"))
        XCTAssertTrue(MarkdownSyntax.isFenceLine("  ```"))
        XCTAssertTrue(MarkdownSyntax.isFenceLine("`````"))
        XCTAssertFalse(MarkdownSyntax.isFenceLine("``"))
        XCTAssertFalse(MarkdownSyntax.isFenceLine("```swift"))
        XCTAssertFalse(MarkdownSyntax.isFenceLine("abc```"))
        XCTAssertFalse(MarkdownSyntax.isFenceLine("``` "))
    }

    func testParagraphMergesConsecutiveLines() {
        let doc = MarkdownSyntax.parse("第一行\n第二行\n\n新段落\n")
        XCTAssertEqual(doc.blocks.count, 2)
        XCTAssertEqual(doc.blocks[0].inlines.count, 2)
        XCTAssertEqual(doc.blocks[0].inlines.map(\.text), ["第一行", "\n第二行"])
    }

    func testBlankLinesCollapse() {
        let doc = MarkdownSyntax.parse("前\n\n\n\n后\n")
        XCTAssertEqual(doc.blocks.count, 2, "多个空行合并为一个段落间隔")
    }

    // MARK: - 行内（滴答扩展语法）

    func testTickTickExtendedInlineMarks() {
        let doc = MarkdownSyntax.parse("::高亮::\n")
        XCTAssertEqual(doc.blocks[0].inlines.first?.marks, [.highlight])

        let strike = MarkdownSyntax.parse("~~删除线~~\n")
        XCTAssertEqual(strike.blocks[0].inlines.first?.marks, [.strikethrough])

        // 单个波浪线是滴答的下划线，不是删除线
        let underline = MarkdownSyntax.parse("~下划线~\n")
        XCTAssertEqual(underline.blocks[0].inlines.first?.marks, [.underline])
    }

    func testStandardInlineMarks() {
        let doc = MarkdownSyntax.parse("**粗体** *斜体* `代码` [链接](https://ticktick.com)\n")
        let marks = doc.blocks[0].inlines.map(\.marks)
        XCTAssertTrue(marks.contains([.bold]))
        XCTAssertTrue(marks.contains([.italic]))
        XCTAssertTrue(marks.contains([.code]))
        XCTAssertTrue(marks.contains([.link(url: "https://ticktick.com")]))
    }

    func testSingleTildeIsUnderlineNotStrikethrough() {
        // 探针：`H~2~O` 渲染为无波浪线的 “H2O”，证明 `~x~` 被解析为下划线并移除标记
        let doc = MarkdownSyntax.parse("H~2~O\n")
        let underlined = doc.blocks[0].inlines.first { $0.marks == [.underline] }
        XCTAssertEqual(underlined?.text, "2")
    }

    func testDoubleCharacterMarkerInteriorsStayLiteral() {
        // 防抢跑守卫（2026-10-16 行内输入期口径）：双写标记的中间态不产生单字符标记。
        let strike = MarkdownSyntax.parse("~~删~\n")
        XCTAssertTrue(strike.blocks[0].inlines.allSatisfy { $0.marks.isEmpty },
                      "`~~删~` 不解析出下划线（`~删~`）")
        let bold = MarkdownSyntax.parse("**粗*\n")
        XCTAssertTrue(bold.blocks[0].inlines.allSatisfy { $0.marks.isEmpty },
                      "`**粗*` 不解析出斜体（`*粗*`）")
        // 前一字符是刚结束片段的闭标记时不误伤：`~a~` 紧接 `~b~` 仍是两段下划线。
        let chained = MarkdownSyntax.parse("~a~~b~\n")
        XCTAssertEqual(chained.blocks[0].inlines.filter { $0.marks == [.underline] }.count, 2)
    }

    func testUnclosedMarkersStayLiteral() {
        let doc = MarkdownSyntax.parse("**未闭合\n*未闭合\n`未闭合\n~未闭合\n::未闭合\n")
        for block in doc.blocks {
            XCTAssertTrue(block.inlines.allSatisfy { $0.marks.isEmpty }, "未闭合标记不产生样式")
        }
        let joined = doc.blocks.map { block in block.inlines.map(\.text).joined() }.joined(separator: "\n")
        XCTAssertTrue(joined.contains("**未闭合"))
        XCTAssertTrue(joined.contains("`未闭合"))
        XCTAssertTrue(joined.contains("::未闭合"))
    }

    func testUnsupportedSyntaxStaysLiteral() {
        let doc = MarkdownSyntax.parse("| 甲 | 乙 |\n<u>下划线</u>\n$x^2$ 公式\n==高亮==\n++插入++\n")
        XCTAssertTrue(doc.blocks.allSatisfy { $0.kind == .paragraph })
        XCTAssertTrue(doc.blocks.allSatisfy { $0.inlines.allSatisfy { $0.marks.isEmpty } })
    }

    // MARK: - 渲染支持信息

    func testMarkerRangesExposeSymbolsForHiding() {
        let doc = MarkdownSyntax.parse("前 **粗** 后\n")
        let bold = doc.blocks[0].inlines.first { $0.marks == [.bold] }
        XCTAssertEqual(bold?.markerRanges.count, 2, "开闭两个标记都要暴露给渲染层隐藏")
        XCTAssertEqual(bold?.contentRange.length, 1)
        XCTAssertEqual(bold?.text, "粗")
    }

    func testLinkMarkersCoverBracketsAndURL() {
        let doc = MarkdownSyntax.parse("[文字](https://x.com)\n")
        let link = doc.blocks[0].inlines.first
        XCTAssertEqual(link?.text, "文字")
        XCTAssertEqual(link?.markerRanges.count, 3, "`[`、`]`、`](url)` 三段标记")
    }
}
