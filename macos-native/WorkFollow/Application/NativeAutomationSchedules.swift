import Foundation

extension NativeAutomationService {
    func executeSchedule(_ request: AutomationRequest) throws -> AutomationValue? {
        guard request.operation.hasPrefix("schedule.") else { return nil }
        let args = request.arguments
        func value(_ job: AIScheduledJob, body: Bool = true) -> AutomationValue {
            var fields: [String: AutomationValue] = ["id": .string(job.id.uuidString), "title": .string(job.title),
                "version": .string(String(job.version)), "enabled": .bool(job.isEnabled),
                "deliverResult": .bool(job.deliverResult == true),
                "at": .string(ISO8601DateFormatter().string(from: job.schedule.firstRunAt)),
                "repeat": .string(job.schedule.frequency.rawValue), "timeZone": .string(job.schedule.timeZoneID),
                "schedule": .string(job.schedule.summary),
                "nextRunAt": job.nextRunAt.map { .string(ISO8601DateFormatter().string(from: $0)) } ?? .null]
            if body { fields["content"] = .string(job.instruction) }
            if let run = job.lastRun {
                fields["lastRun"] = .object(["state": .string(run.state.rawValue),
                    "conversationID": .string(run.conversationID.uuidString),
                    "startedAt": .string(ISO8601DateFormatter().string(from: run.startedAt)),
                    "error": run.error.map(AutomationValue.string) ?? .null])
            }
            return .object(fields)
        }
        func schedule(_ base: AIJobSchedule? = nil) throws -> AIJobSchedule {
            let frequency = args["repeat"] ?? base?.frequency.rawValue ?? "once"
            guard let kind = AIJobSchedule.Frequency(rawValue: frequency) else {
                throw AutomationFailure.argument("AI 定时任务支持 once、daily、weekdays 和 weekly。")
            }
            let first: Date
            if let raw = args["at"] {
                guard raw.contains("T") else { throw AutomationFailure.argument("at 需要包含时刻和时区的 ISO8601 时间。") }
                first = try date(raw)
            } else if let base { first = base.firstRunAt }
            else { throw AutomationFailure.argument("请提供 --at 执行时间。") }
            return AIJobSchedule(frequency: kind, firstRunAt: first,
                timeZoneID: args["time-zone"] ?? base?.timeZoneID ?? tasks.calendar.timeZone.identifier)
        }
        if let error = scheduledJobs.storageError { throw AutomationFailure(code: "storage_unavailable", message: error) }
        if request.operation == "schedule.list" {
            let jobs = scheduledJobs.jobs.filter { job in
                guard let query = args["query"], !query.isEmpty else { return true }
                return job.title.localizedStandardContains(query) || job.instruction.localizedStandardContains(query)
            }
            return try page(jobs, args: args) { value($0, body: false) }
        }
        if request.operation == "schedule.add" {
            return value(try scheduledJobs.add(title: args["title"] ?? "", instruction: args["content"] ?? "",
                schedule: schedule(), enabled: boolean(args["enabled"]) ?? true,
                deliverResult: boolean(args["deliver-result"]) ?? false))
        }
        guard let raw = args["id"], let id = UUID(uuidString: raw), let current = scheduledJobs.job(id) else {
            throw AutomationFailure(code: "not_found", message: "定时任务已不存在。")
        }
        if request.operation == "schedule.get" { return value(current) }
        if request.operation == "schedule.run" {
            guard let runScheduledJob else { throw AutomationFailure.argument("当前 App 尚未启动定时任务执行器。") }
            try runScheduledJob(id)
            guard case var .object(fields) = value(scheduledJobs.job(id) ?? current) else { return nil }
            fields["queued"] = .bool(true); return .object(fields)
        }
        guard let version = args["version"].flatMap(Int.init) else { throw AutomationFailure.argument("请先 schedule get，再传入其 version。") }
        if request.operation == "schedule.delete" {
            try scheduledJobs.delete(id, version: version); return value(current)
        }
        if request.operation == "schedule.update" {
            let changedSchedule = !Set(args.keys).isDisjoint(with: ["at", "repeat", "time-zone"])
            return value(try scheduledJobs.update(id, version: version, title: args["title"], instruction: args["content"],
                schedule: changedSchedule ? schedule(current.schedule) : nil, enabled: boolean(args["enabled"]),
                deliverResult: boolean(args["deliver-result"])))
        }
        throw AutomationFailure.argument("未知 AI 定时任务操作。")
    }
}
