import SwiftUI

struct ActivityPageQueryKey: Equatable {
    var taskIDs: [UUID]
    var revision: Int
}

@MainActor
final class TaskActivityPageModel: ObservableObject {
    @Published private(set) var events: [TaskActivityEvent] = []
    @Published private(set) var hasMore = false
    @Published private(set) var isLoading = false
    @Published private(set) var error: String?
    private var generation = 0
    private let pageSize = 50

    func reset(store: TaskActivityStore, taskIDs: [UUID]) async {
        generation += 1
        events = []; hasMore = true; isLoading = false; error = nil
        await loadMore(store: store, taskIDs: taskIDs)
    }

    func loadMore(store: TaskActivityStore, taskIDs: [UUID]) async {
        guard !isLoading, hasMore else { return }
        let request = generation
        isLoading = true; error = nil
        do {
            let page = try await store.page(taskIDs: taskIDs, limit: pageSize + 1, offset: events.count)
            guard request == generation, !_Concurrency.Task.isCancelled else { return }
            hasMore = page.count > pageSize
            events.append(contentsOf: page.prefix(pageSize))
            isLoading = false
        } catch {
            guard request == generation, !_Concurrency.Task.isCancelled else { return }
            self.error = error.localizedDescription
            isLoading = false
        }
    }
}

struct TaskActivityPageControls: View {
    @ObservedObject var history: TaskActivityPageModel
    let load: () async -> Void

    var body: some View {
        if history.isLoading {
            ProgressView().controlSize(.small).padding(8)
        } else if let error = history.error {
            VStack(spacing: 8) {
                Text("读取动态失败：\(error)").font(.caption).foregroundStyle(WFColors.secondaryText)
                Button("重试") { _Concurrency.Task { await load() } }
            }
        } else if history.hasMore {
            Button("加载更多") { _Concurrency.Task { await load() } }
                .buttonStyle(.plain).padding(8)
        }
    }
}
