import Foundation

/// 笔记内置模板只在内存里组装，不写进 modules/templates.json；与任务内置模板
/// 用不同的固定 UUID 段，并以 kind = "note" 精确过滤，避免互相串味。
enum BuiltInNoteTemplates {
    static let all: [TaskTemplate] = [
        meetingNotes,
        weeklyReport,
        dailyLog,
        readingNotes,
        projectRetrospective
    ]

    private static let createdAt = Date(timeIntervalSince1970: 1_704_067_200)

    private static var meetingNotes: TaskTemplate {
        TaskTemplate(
            id: UUID(uuidString: "30000000-0000-4000-8000-000000000001")!,
            name: "会议纪要",
            title: "会议纪要",
            document: document([
                (.heading(2), "会议信息"),
                (.paragraph, "主题："),
                (.paragraph, "时间 / 地点："),
                (.paragraph, "参会人员："),
                (.heading(2), "议题与讨论要点"),
                (.bullet, "记录讨论中的关键信息"),
                (.heading(2), "结论与待办"),
                (.checklist(false), "写清负责人和截止日期；行内日期可直接设提醒")
            ]),
            createdAt: createdAt,
            kind: "note")
    }

    /// 周报：本周完成 / 下周计划用清单块，周五整理时直接勾选；数据与风险留段落。
    private static var weeklyReport: TaskTemplate {
        TaskTemplate(
            id: UUID(uuidString: "30000000-0000-4000-8000-000000000004")!,
            name: "周报",
            title: "周报",
            document: document([
                (.heading(2), "本周完成"),
                (.checklist(false), "挑关键产出，别写成流水账"),
                (.heading(2), "下周计划"),
                (.checklist(false), "写上日期可以直接设提醒"),
                (.heading(2), "数据与进展"),
                (.paragraph, "关键指标 / 里程碑："),
                (.heading(2), "风险与需要的支持"),
                (.paragraph, "卡在哪里、需要谁拍板：")
            ]),
            createdAt: createdAt,
            kind: "note")
    }

    private static var dailyLog: TaskTemplate {
        TaskTemplate(
            id: UUID(uuidString: "30000000-0000-4000-8000-000000000002")!,
            name: "每日记录",
            title: "每日记录",
            document: document([
                (.heading(2), "今日完成"),
                (.checklist(false), "列出今天完成的事"),
                (.heading(2), "值得记录的事"),
                (.paragraph, "今天发生了哪些美好或值得关注的事？"),
                (.heading(2), "问题与感想"),
                (.paragraph, "遇到了哪些问题？有什么感想或总结？")
            ]),
            createdAt: createdAt,
            kind: "note")
    }

    private static var projectRetrospective: TaskTemplate {
        TaskTemplate(
            id: UUID(uuidString: "30000000-0000-4000-8000-000000000003")!,
            name: "项目复盘",
            title: "项目复盘",
            document: document([
                (.heading(2), "项目概况"),
                (.paragraph, "目标与范围："),
                (.heading(2), "做得好的地方"),
                (.bullet, "值得延续的做法"),
                (.heading(2), "可以改进的地方"),
                (.bullet, "下次要避开的坑"),
                (.heading(2), "后续行动"),
                (.checklist(false), "沉淀成可执行的改进项")
            ]),
            createdAt: createdAt,
            kind: "note")
    }

    /// 读书笔记：一篇一本书，标题即书名；行动清单块收尾。
    private static var readingNotes: TaskTemplate {
        TaskTemplate(
            id: UUID(uuidString: "30000000-0000-4000-8000-000000000005")!,
            name: "读书笔记",
            title: "书名（作者）",
            document: document([
                (.heading(2), "基本信息"),
                (.paragraph, "书名 / 作者 / 出版年："),
                (.paragraph, "评分：⭐⭐⭐⭐☆"),
                (.heading(2), "摘录"),
                (.bullet, "值得记住的原句（标注页码）"),
                (.heading(2), "我的想法"),
                (.paragraph, "不同意什么？联想到什么？"),
                (.heading(2), "行动"),
                (.checklist(false), "读完后想做的一件事")
            ]),
            createdAt: createdAt,
            kind: "note")
    }

    private static func document(_ entries: [(DocumentBlockKind, String)]) -> NativeDocument {
        NativeDocument(blocks: entries.map { kind, text in
            DocumentBlock(kind: kind, runs: [DocumentRun(text: text)])
        })
    }
}
