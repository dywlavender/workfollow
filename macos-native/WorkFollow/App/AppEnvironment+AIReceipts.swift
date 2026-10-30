import Foundation

extension AppEnvironment {
    func recordAIAction(_ request: AutomationRequest, data: AutomationValue) {
        if let token = data["undoneID"]?.string.flatMap(UUID.init(uuidString:)) {
            aiChat.markUndone(token); AIConversationRegistry.shared.markUndone(token); return
        }
        guard let conversation = request.conversationID, NativeAutomationService.writes(request.operation) else { return }
        let title = data["title"]?.string ?? data["name"]?.string ?? request.arguments["name"] ?? "已完成操作"
        var details: [String] = []
        for (key, label) in [("date", "安排"), ("due", "截止"), ("reminder", "提醒")] {
            if let raw = data[key]?.string, let date = ISO8601DateFormatter().date(from: raw) {
                details.append(label + " " + date.formatted(.dateTime.month().day().hour().minute()))
            }
        }
        if let list = data["list"]?.string { details.append(list) }
        if let priority = data["priority"]?.string, priority != "none" { details.append(["high":"高重要性", "medium":"中重要性", "low":"低重要性"][priority] ?? priority) }
        if let repeatValue = data["repeat"]?.string, let value = TaskRepeat(rawValue: repeatValue), value != .never { details.append(value.title) }
        if case let .array(offsets)? = data["reminderOffsets"], !offsets.isEmpty {
            let values = offsets.compactMap { value -> String? in
                guard case let .number(minutes) = value else { return nil }
                return minutes == 0 ? "准时提醒" : "提前\(Int(-minutes))分钟提醒"
            }
            details += values
        }
        if case let .array(days)? = data["repeatWeekdays"], !days.isEmpty {
            let names = ["周日", "周一", "周二", "周三", "周四", "周五", "周六"]
            details.append(days.compactMap { value -> String? in
                guard case let .number(day) = value, (1...7).contains(Int(day)) else { return nil }
                return names[Int(day) - 1]
            }.joined(separator: "、"))
        }
        if details.isEmpty { details.append(request.operation.hasPrefix("note.") ? "笔记已保存" : "已保存") }
        let receipt = AIActionReceipt(title: title, url: data["url"]?.string, details: details.joined(separator: " · "),
            undoID: data["undoID"]?.string.flatMap(UUID.init(uuidString:)))
        if !AIConversationRegistry.shared.append(receipt, id: conversation) { aiChat.recordAction(receipt, conversationID: conversation) }
    }
    func undoAIAction(_ receipt: AIActionReceipt) {
        guard let token = receipt.undoID, taskWorkspace.undoAutomation(token) else {
            feedback.show(FeedbackEvent(kind: .info, message: "请先撤销更新的操作，再撤销这一项。")); return
        }
        aiChat.markUndone(token)
        AIConversationRegistry.shared.markUndone(token)
        feedback.show(FeedbackEvent(kind: .info, message: "已撤销「\(receipt.title)」"))
    }
}
