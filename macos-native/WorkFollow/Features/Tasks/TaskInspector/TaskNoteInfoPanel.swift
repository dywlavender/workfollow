import SwiftUI

/// 笔记信息（TI2-15，对齐滴答 `TTTaskDetailNoteInfoViewController` 的
/// count / create / modify 三行）。只在任务有正文时从顶栏查看，纯只读。
struct TaskNoteInfo: Equatable {
    let characterCount: Int
    let createdAt: Date
    let updatedAt: Date

    init(task: Task) {
        characterCount = task.document.plainText.reduce(into: 0) { count, character in
            if !character.isWhitespace { count += 1 }
        }
        createdAt = task.createdAt
        updatedAt = task.updatedAt
    }

    var characterCountText: String { "\(characterCount)" }
}

struct TaskNoteInfoPanel: View {
    let info: TaskNoteInfo
    var calendar: Calendar = .current

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            row("字数", info.characterCountText)
            row("创建", Self.dateText(info.createdAt, calendar: calendar))
            row("修改", Self.dateText(info.updatedAt, calendar: calendar))
        }
        .padding(14)
        .frame(width: PopupMetrics.noteInfoWidth)
    }

    private func row(_ title: String, _ value: String) -> some View {
        HStack(spacing: 12) {
            Text(title)
                .font(WFType.supporting)
                .foregroundStyle(WFColors.secondaryText)
                .frame(width: 36, alignment: .leading)
            Text(value)
                .font(WFType.body)
                .foregroundStyle(WFColors.text)
                .lineLimit(1)
            Spacer(minLength: 0)
        }
    }

    static func dateText(_ date: Date, calendar: Calendar) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy/M/d HH:mm"
        return formatter.string(from: date)
    }
}
