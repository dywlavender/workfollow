import Combine
import SwiftUI

/// Lists and navigation observe data and list presentation, not the selected
/// task. The outline updates the two affected rows through its own subscription.
@MainActor
final class TaskDataObservation: ObservableObject {
    private var subscriptions: Set<AnyCancellable> = []

    init(_ workspace: TaskWorkspaceModel) {
        let changes: [AnyPublisher<Void, Never>] = [
            workspace.$revision.removeDuplicates().dropFirst().map { _ in () }.eraseToAnyPublisher(),
            workspace.$dateRevision.removeDuplicates().dropFirst().map { _ in () }.eraseToAnyPublisher(),
            workspace.$activeList.removeDuplicates().dropFirst().map { _ in () }.eraseToAnyPublisher(),
            workspace.$activeTag.removeDuplicates().dropFirst().map { _ in () }.eraseToAnyPublisher(),
            workspace.$activeFilterID.removeDuplicates().dropFirst().map { _ in () }.eraseToAnyPublisher(),
            workspace.$bulkSelection.removeDuplicates().dropFirst().map { _ in () }.eraseToAnyPublisher(),
            workspace.$collapsedTaskIDs.removeDuplicates().dropFirst().map { _ in () }.eraseToAnyPublisher(),
            workspace.$recentlyCreatedTaskIDs.removeDuplicates().dropFirst().map { _ in () }.eraseToAnyPublisher()
        ]
        Publishers.MergeMany(changes).sink { [weak self] in self?.objectWillChange.send() }
            .store(in: &subscriptions)
    }
}

@propertyWrapper
struct TaskDataObserved: DynamicProperty {
    let wrappedValue: TaskWorkspaceModel
    @ObservedObject private var observation: TaskDataObservation

    init(wrappedValue: TaskWorkspaceModel) {
        self.wrappedValue = wrappedValue
        observation = wrappedValue.dataObservation
    }
}

@MainActor
final class TaskLayoutObservation: ObservableObject {
    private var subscriptions: Set<AnyCancellable> = []
    init(_ workspace: TaskWorkspaceModel) {
        let context: [AnyPublisher<Void, Never>] = [
            workspace.$activeList.removeDuplicates().dropFirst().map { _ in () }.eraseToAnyPublisher(),
            workspace.$activeTag.removeDuplicates().dropFirst().map { _ in () }.eraseToAnyPublisher(),
            workspace.$activeFilterID.removeDuplicates().dropFirst().map { _ in () }.eraseToAnyPublisher(),
            workspace.$bulkSelection.map { !$0.isEmpty }.removeDuplicates().dropFirst().map { _ in () }.eraseToAnyPublisher()
        ]
        Publishers.MergeMany(context).sink { [weak self] in self?.objectWillChange.send() }.store(in: &subscriptions)
        workspace.$selectedTaskID.map { $0 != nil }.removeDuplicates().dropFirst()
            .sink { [weak self] _ in self?.objectWillChange.send() }.store(in: &subscriptions)
        workspace.$taskListPaneWidth.removeDuplicates().dropFirst()
            .sink { [weak self] _ in self?.objectWillChange.send() }.store(in: &subscriptions)
    }
}

@propertyWrapper
struct TaskLayoutObserved: DynamicProperty {
    let wrappedValue: TaskWorkspaceModel
    @ObservedObject private var observation: TaskLayoutObservation
    init(wrappedValue: TaskWorkspaceModel) {
        self.wrappedValue = wrappedValue
        observation = wrappedValue.layoutObservation
    }
}
