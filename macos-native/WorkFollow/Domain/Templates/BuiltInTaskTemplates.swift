import Foundation

enum BuiltInTaskTemplates {
    static let all: [TaskTemplate] = [
        TaskTemplate(
            id: UUID(uuidString: "10000000-0000-4000-8000-000000000001")!,
            name: "每天工作前要做的几件事",
            title: "每天工作前要做的几件事",
            document: checklistDocument([
                "简单回顾昨天的情况",
                "花点时间处理邮件和未读消息",
                "查看智能清单“今天”中的任务",
                "确定今天最重要的1~3件事，排好优先级",
                "Break the most difficult one into small check items",
                "给自己倒一杯水（或咖啡）",
                "休息5分钟，将状态调整到最佳"
            ]),
            listName: nil,
            schedule: .today,
            childTitles: [],
            createdAt: createdAt),
        TaskTemplate(
            id: UUID(uuidString: "10000000-0000-4000-8000-000000000002")!,
            name: "每日记录",
            title: "每日记录",
            document: paragraphDocument([
                "今天完成了什么？",
                "今天发生了哪些美好或值得关注的事？",
                "今天遇到了哪些突发问题？",
                "今天心情如何？",
                "今天有哪些感想或总结？"
            ]),
            listName: nil,
            schedule: nil,
            childTitles: [],
            createdAt: createdAt),
        TaskTemplate(
            id: UUID(uuidString: "10000000-0000-4000-8000-000000000003")!,
            name: "旅行必备物品",
            title: "旅行必备物品",
            document: checklistDocument([
                "身份证 / 护照 / 学生证",
                "充电器 / 数据线",
                "晴雨伞",
                "易于携带的小背包",
                "衣物：上衣 / 下装",
                "衣物：换洗内衣裤",
                "鞋袜"
            ]),
            listName: nil,
            schedule: nil,
            childTitles: [],
            createdAt: createdAt)
    ]

    private static let createdAt = Date(timeIntervalSince1970: 1_704_067_200)

    private static func checklistDocument(_ items: [String]) -> NativeDocument {
        NativeDocument(blocks: items.map {
            DocumentBlock(kind: .checklist(false), runs: [DocumentRun(text: $0)])
        })
    }

    private static func paragraphDocument(_ prompts: [String]) -> NativeDocument {
        NativeDocument(blocks: prompts.map {
            DocumentBlock(kind: .paragraph, runs: [DocumentRun(text: $0)])
        })
    }
}
