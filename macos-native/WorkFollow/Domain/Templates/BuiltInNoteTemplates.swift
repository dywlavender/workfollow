import Foundation

/// 笔记内置模板只在内存里组装，不写进 modules/templates.json；与任务内置模板
/// 用不同的固定 UUID 段，并以 kind = "note" 精确过滤，避免互相串味。
enum BuiltInNoteTemplates {
    static let all: [TaskTemplate] = [
        meetingNotes,
        dailyLog,
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
                (.checklist(false), "明确负责人与截止时间")
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

    private static func document(_ entries: [(DocumentBlockKind, String)]) -> NativeDocument {
        NativeDocument(blocks: entries.map { kind, text in
            DocumentBlock(kind: kind, runs: [DocumentRun(text: text)])
        })
    }
}
