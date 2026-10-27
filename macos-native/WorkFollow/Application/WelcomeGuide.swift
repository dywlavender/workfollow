import Foundation

/// 滴答式新手引导：一个普通清单 + 三个分组 + 可勾选任务。
/// 任务正文只负责讲清楚「为什么 / 怎么做」，动作放在 `guideAction`，
/// 由任务详情里的「开始使用」按钮跳到真实功能。
enum WelcomeGuide {
    static let listName = "👋欢迎"
    static let sectionTitles = ["新手入门", "功能模块", "探索更多"]
    static let version = 3

    enum Section: Int, CaseIterable {
        case start, modules, explore
        var title: String { sectionTitles[rawValue] }
    }

    enum Action: String, CaseIterable {
        case quickAdd = "quick-add"
        case schedule
        case complete
        case list
        case matrix
        case calendar
        case focus
        case meetings
        case notes
        case floatingNote = "floating-note"
        case allTasks = "all-tasks"
        case summary
        case commandPalette = "command-palette"
        case agentAccess = "agent-access"

        var title: String {
            switch self {
            case .quickAdd: return "去创建任务"
            case .schedule: return "去安排日期"
            case .complete: return "去完成任务"
            case .list: return "查看欢迎清单"
            case .matrix: return "打开四象限"
            case .calendar: return "打开日历"
            case .focus: return "打开专注"
            case .meetings: return "打开会议纪要"
            case .notes: return "打开笔记"
            case .floatingNote: return "新建悬浮笔记"
            case .allTasks: return "打开所有任务"
            case .summary: return "打开摘要"
            case .commandPalette: return "快速打开"
            case .agentAccess: return "查看 AI 接入说明"
            }
        }

        var url: URL {
            URL(string: "workfollow://guide/\(rawValue)")!
        }

        init?(url: URL) {
            guard url.scheme?.lowercased() == "workfollow",
                  url.host?.lowercased() == "guide",
                  url.pathComponents.count == 2 else { return nil }
            self.init(rawValue: url.lastPathComponent)
        }
    }

    struct Item {
        let section: Section
        let title: String
        let action: Action
        let summary: String
        let steps: [String]
    }

    static let items: [Item] = [
        Item(section: .start,
             title: "✅ 点击输入框，创建任务",
             action: .quickAdd,
             summary: "把脑子里的事情先写下来，大脑用来思考，不用来记事。",
             steps: [
                "在清单顶部的输入框点击「+」，输入标题后回车，任务就建好了。",
                "标题尽量写成能直接执行的动作，例如「晚上 8 点读《小王子》30 分钟」。",
                "想补充细节时，点开任务右侧的详情面板。"
             ]),
        Item(section: .start,
             title: "📅 设置日期和提醒",
             action: .schedule,
             summary: "给任务一个时间，它才会在该出现的时候出现。",
             steps: [
                "打开任务详情，点击日期区域，选择今天、明天或具体日期。",
                "担心忘记就加上提醒时间；固定发生的事情可以设置重复。",
                "设置后，任务会自动进入「今天」「最近 7 天」等智能清单。"
             ]),
        Item(section: .start,
             title: "✔️ 完成任务，收进「今天」",
             action: .complete,
             summary: "完成的事情及时打勾，今天的清单才会越做越轻。",
             steps: [
                "点击任务左侧的圆圈即可完成，再点一次可以恢复。",
                "「今天」汇总今天到期的任务，「最近 7 天」帮你提前安排。",
                "做完的任务可以在侧栏「已完成」里回看。"
             ]),
        Item(section: .modules,
             title: "📋 用清单和分组管理任务",
             action: .list,
             summary: "任务多起来后，用清单按项目或场景分类；清单内还能再分「分组」。",
             steps: [
                "在侧栏新建清单，例如「工作」「生活」「学习」。",
                "在清单标题上右键可以新建分组，把任务拖进对应分组。",
                "看板视图会把分组显示成列，适合推进多阶段项目。"
             ]),
        Item(section: .modules,
             title: "🎯 四象限：先做重要的事",
             action: .matrix,
             summary: "每天事情很多时，先按「重要 / 紧急」把任务放进四个象限。",
             steps: [
                "打开四象限，把任务拖到对应象限；拖动会同步修改优先级和安排日。",
                "优先处理重要且紧急的事，给重要不紧急的事留出固定时间。",
                "每个象限可以单独折叠、排序，长列表不会挤乱其他象限。"
             ]),
        Item(section: .modules,
             title: "🗓 日历：把任务排进日程",
             action: .calendar,
             summary: "有明确时间的任务，放到日历里看更直观。",
             steps: [
                "打开日历，切换日 / 周 / 月视图查看安排。",
                "拖动任务可以改期，跨天任务可以拉长时间范围。",
                "任务和日程同屏显示，冲突一眼可见。"
             ]),
        Item(section: .modules,
             title: "🍅 专注：一次只做一件事",
             action: .focus,
             summary: "给重要任务开一个专注计时，减少切换。",
             steps: [
                "在任务详情点击「专注」，或在专注页选择任务开始。",
                "番茄时长和休息节奏可以在设置里调整。",
                "专注记录会累计到任务和统计里，回头能看到时间花在哪。"
             ]),
        Item(section: .modules,
             title: "🎙 会议纪要：开完会就有待办",
             action: .meetings,
             summary: "会议纪要里的行动项可以直接转成任务，不用再抄一遍。",
             steps: [
                "打开「会议纪要」，左侧是会议列表，右侧是对话记录和可编辑的纪要。",
                "点「提取待办」，把结论里的行动项转成任务。",
                "会议和任务互相关联，回看时能追到出处。"
             ]),
        Item(section: .modules,
             title: "📝 笔记：想法和任务放在一起",
             action: .notes,
             summary: "想法先记成笔记，需要行动时再转成任务。",
             steps: [
                "打开笔记页，新建笔记，支持富文本、清单和附件。",
                "选中一段文字，可以直接「用所选文字创建任务」。",
                "笔记和任务可以互相引用，搜索时一起出现。"
             ]),
        Item(section: .explore,
             title: "🪟 悬浮笔记：边看资料边记",
             action: .floatingNote,
             summary: "把笔记固定在桌面最上层，一边看 PDF 一边记录。",
             steps: [
                "菜单「文件 → 新建悬浮笔记」，或按 ⌥⌘N。",
                "点击笔记输入内容；鼠标移到 PDF 上滚轮翻页，键盘输入仍在笔记里。",
                "点「在主页打开」可以把内容交回主页继续编辑。"
             ]),
        Item(section: .explore,
             title: "🏷 标签与过滤器：按场景找任务",
             action: .allTasks,
             summary: "用标签跨清单找任务，用过滤器保存常用筛选。",
             steps: [
                "给任务加标签，例如「#深度工作」「#等反馈」。",
                "在侧栏新建过滤器，按清单、标签、优先级组合条件。",
                "过滤器会记住条件，下次点开就是同一批任务。"
             ]),
        Item(section: .explore,
             title: "📑 摘要：回看一周的产出",
             action: .summary,
             summary: "把一周完成的任务收成一份摘要，复盘和汇报都省事。",
             steps: [
                "打开「摘要」，选择本周范围。",
                "生成后可以复制为纯文本 / 富文本 / Markdown，或直接发邮件。",
                "常用格式可以存成摘要模板，下次一键复用。"
             ]),
        Item(section: .explore,
             title: "🤖 让 AI 操作任务和笔记",
             action: .agentAccess,
             summary: "把接入说明交给本机 AI 助手，之后用一句话管理 WorkFollow。",
             steps: [
                "点击「复制给 AI」，把说明粘贴到 WorkBuddy、Codex 等本机 AI 助手，让它完成配置。",
                "也可以在下方选择助手，复制命令到终端手动执行。",
                "接入后试着说：「把这段讨论保存成笔记，再建一个明天下午三点跟进的待办。」"
             ]),
        Item(section: .explore,
             title: "💡 帮助与快捷键",
             action: .commandPalette,
             summary: "记住几个快捷键，日常操作会快很多。",
             steps: [
                "⌘K 快速打开；⌘N 新建任务；⌥⌘N 新建悬浮笔记。",
                "⌘F 在正文里查找；⌘Z / ⇧⌘Z 撤销和重做。",
                "这份引导被删了，可以在「帮助 → 重置新手引导」重新生成。"
             ])
    ]

    static func document(for item: Item) -> NativeDocument {
        var blocks = [DocumentBlock(kind: .paragraph,
                                    runs: [DocumentRun(text: item.summary)])]
        blocks += item.steps.map { step in
            DocumentBlock(kind: .bullet, runs: [DocumentRun(text: step)])
        }
        return NativeDocument(blocks: blocks)
    }

    static func action(for task: Task) -> Action? {
        guard let raw = task.guideAction else { return nil }
        return Action(rawValue: raw)
    }

    /// 文档每次生成都会换 block UUID，升级比较必须忽略 id，只看内容结构。
    static func documentMatches(_ document: NativeDocument, item: Item) -> Bool {
        let reference = self.document(for: item)
        guard document.blocks.count == reference.blocks.count else { return false }
        return zip(document.blocks, reference.blocks).allSatisfy { lhs, rhs in
            lhs.kind == rhs.kind
                && lhs.indentLevel == rhs.indentLevel
                && lhs.runs.map(\.text) == rhs.runs.map(\.text)
                && lhs.runs.map(\.marks) == rhs.runs.map(\.marks)
        }
    }

    /// 演示 GIF 按动作命名放在 `Resources/WelcomeGuide`，构建后摊平进
    /// app bundle 根目录；新增演示只要补同名文件，不必改代码。
    static func mediaResourceName(for action: Action) -> String {
        "guide-" + action.rawValue
    }

    static func mediaURL(for action: Action, bundle: Bundle = .main) -> URL? {
        bundle.url(forResource: mediaResourceName(for: action), withExtension: "gif")
    }
}
