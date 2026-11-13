import Foundation

private struct AssistantTaskSnapshot: @unchecked Sendable {
    let tasks: [Task]
    let now: Date
    let calendar: Calendar
    func facts() -> AssistantBriefingFacts { .make(tasks: tasks, now: now, calendar: calendar) }
}

extension AppEnvironment {
    func startAIScheduler() {
        guard canSeedWelcomeGuide else { return }
        aiSchedulerStarted = true; aiScheduler.start()
    }
    func checkAIScheduledJobs() { if aiSchedulerStarted { aiScheduler.checkDue() } }
    func runAIScheduledJob(_ id: UUID) throws {
        guard canSeedWelcomeGuide else { throw AIBackendError.failed("工作区尚未就绪。") }
        aiSchedulerStarted = true; try aiScheduler.runNow(id)
    }
    func stopAIScheduler() {
        guard aiSchedulerStarted else { return }
        aiSchedulerStarted = false; aiScheduler.shutdown()
    }
    func openAIScheduledResult(_ id: UUID) {
        guard aiChat.records.contains(where: { $0.id == id }) else {
            feedback.show(FeedbackEvent(kind: .info, message: "这次结果已从对话历史中删除。")); return
        }
        aiChat.select(id); navigation.destination = .aiChat
    }

    func startPersonalAssistant() {
        assistantStarted = true
        refreshAssistantBriefingAutomatically()
    }

    func refreshAssistantBriefingAutomatically() {
        guard assistantStarted else { return }
        refreshAssistantToday()
        refreshAssistantBriefing()
    }

    func refreshAssistantToday() {
        guard canSeedWelcomeGuide else { return }
        let snapshot = AssistantTaskSnapshot(tasks: taskWorkspace.tasksInActiveLists,
            now: taskWorkspace.clock(), calendar: taskWorkspace.calendar)
        assistantBriefing.updateToday { snapshot.facts() }
    }

    func refreshAssistantBriefing(force: Bool = false) {
        guard canSeedWelcomeGuide, force || assistantBriefing.shouldRefreshAutomatically else { return }
        let snapshot = AssistantTaskSnapshot(tasks: taskWorkspace.tasksInActiveLists,
            now: taskWorkspace.clock(), calendar: taskWorkspace.calendar)
        let client = conversationClient()
        assistantBriefing.refresh(force: force) { updates in
            let facts = await _Concurrency.Task.detached(priority: .utility) { snapshot.facts() }.value
            try _Concurrency.Task.checkCancellation()
            if facts.tasks.isEmpty { return (facts, "今天暂时没有需要关注的安排、逾期或临近截止事项。") }
            return (facts, try await client.briefing(facts: facts, updates: updates))
        }
    }
}
