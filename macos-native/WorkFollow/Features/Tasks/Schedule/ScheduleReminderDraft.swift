import Foundation

/// Local selection; Confirm writes only the schedule draft, never the task.
struct ScheduleReminderDraft {
    var offsets: Set<Int>

    mutating func toggle(_ minutes: Int) {
        if !offsets.insert(minutes).inserted { offsets.remove(minutes) }
    }

    @MainActor
    func confirm(into model: TaskDateDraftModel, customAmount: String? = nil, unit: Int = 1) -> Bool {
        var selected = offsets
        if let customAmount {
            guard let amount = Int(customAmount.trimmingCharacters(in: .whitespaces)), amount > 0 else { return false }
            let value = amount.multipliedReportingOverflow(by: unit)
            guard !value.overflow else { return false }
            selected.insert(-value.partialValue)
        }
        model.setReminderOffsets(selected)
        return true
    }
}
