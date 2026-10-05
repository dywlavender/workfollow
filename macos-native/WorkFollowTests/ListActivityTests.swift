import XCTest
@testable import WorkFollow

/// 清单动态：按清单聚合任务变更时间线（事件模型与任务动态共用 `TaskActivityStore`）。
@MainActor
final class ListActivityTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_790_000_000)

    /// 活动存储会从模块目录读盘（默认指向真实数据），测试必须用隔离目录。
    private func makeActivity() -> TaskActivityStore {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ListActivityTests-\(UUID().uuidString)", isDirectory: true)
        return TaskActivityStore(clock: { self.now }, directory: directory)
    }

    func testEventsForListAggregatesOnlyThatList() {
        let activity = makeActivity()
        let inList = UUID()
        let other = UUID()
        activity.recordFocusStart(taskID: inList, stopwatch: false)
        activity.recordFocusStart(taskID: other, stopwatch: false)

        let mapping: (UUID) -> String? = { id in id == inList ? "工作" : "生活" }
        XCTAssertEqual(activity.events(forList: "工作", listNameOfTask: mapping).map(\.taskID), [inList])
        XCTAssertEqual(activity.events(forList: "生活", listNameOfTask: mapping).map(\.taskID), [other])
        XCTAssertTrue(activity.events(forList: "不存在", listNameOfTask: mapping).isEmpty)
    }

    func testEventsForListSkipsTasksWithoutList() {
        let activity = makeActivity()
        let gone = UUID()
        activity.recordFocusStart(taskID: gone, stopwatch: false)
        XCTAssertTrue(activity.events(forList: "工作", listNameOfTask: { _ in nil }).isEmpty,
                      "任务被删掉后不再归属任何清单（当前口径，已登记）")
    }
}
