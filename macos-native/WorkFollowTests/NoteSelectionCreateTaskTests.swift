import Foundation
import XCTest
@testable import WorkFollow

/// 选中文字建任务（滴答笔记编辑器行为）：多行拆分、任务侧 sourceNoteID 回链、
/// 整批一个事务（一次撤销全部消失）。对应 `NoteEditorHostActions.createTaskFromSelection`。
@MainActor
final class NoteSelectionCreateTaskTests: XCTestCase {
    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(secondsFromGMT: 28_800)!
        return value
    }
    private var now: Date {
        calendar.date(from: DateComponents(year: 2026, month: 11, day: 5, hour: 12))!
    }

    private func workspace() -> TaskWorkspaceModel {
        TaskWorkspaceModel(clock: { self.now }, calendar: calendar, seedDemoData: false)
    }

    func testMultiLineSelectionCreatesOneTaskPerLineWithSourceBacklink() throws {
        let tasks = workspace()
        let noteID = try XCTUnwrap(tasks.createNote(title: "风控评审agent问题"))
        let ids = tasks.createTasksFromSelection(" 1、表述风格不一致 \n\n2、误判语义相反\n", noteID: noteID)
        XCTAssertEqual(ids.count, 2, "空行丢弃、首尾空白裁掉，每行一条")
        XCTAssertEqual(tasks.allTasks.filter { $0.sourceNoteID == noteID }.count, 2)
        XCTAssertEqual(tasks.allTasks.first { $0.id == ids[0] }?.title, "1、表述风格不一致")
        XCTAssertEqual(tasks.allTasks.first { $0.id == ids[1] }?.title, "2、误判语义相反")
        for id in ids {
            let task = try XCTUnwrap(tasks.task(for: id))
            XCTAssertEqual(task.list, .inbox)
            XCTAssertTrue(task.document.blocks.flatMap(\.runs).contains {
                $0.marks.contains(.link(NativeResourceLink.note(noteID).url.absoluteString))
            }, "任务正文要带可点回笔记的来源链接（与 AI 提取待办同款惯例）")
        }
    }

    func testSelectionBatchIsOneUndoStep() throws {
        let tasks = workspace()
        let noteID = try XCTUnwrap(tasks.createNote(title: "笔记"))
        _ = tasks.createTasksFromSelection("甲\n乙\n丙", noteID: noteID)
        XCTAssertEqual(tasks.allTasks.filter { !$0.isNoteTask && $0.deletedAt == nil }.count, 3)
        tasks.undo()
        XCTAssertTrue(tasks.allTasks.filter { !$0.isNoteTask && $0.deletedAt == nil }.isEmpty,
                      "整批一个撤销帧，一次撤销全部消失")
        XCTAssertNotNil(tasks.task(for: noteID), "撤销只回退任务批，不动笔记本体")
    }

    func testBlankSelectionCreatesNothing() throws {
        let tasks = workspace()
        let noteID = try XCTUnwrap(tasks.createNote(title: "笔记"))
        XCTAssertTrue(tasks.createTasksFromSelection("  \n \n", noteID: noteID).isEmpty)
        XCTAssertEqual(tasks.allTasks.filter { !$0.isNoteTask }.count, 0)
    }

    func testNoteHostActionRoutesThroughWorkspace() throws {
        let tasks = workspace()
        let notes = NotesWorkspaceModel(taskWorkspace: tasks)
        let noteID = notes.create()
        let host = NoteEditorHostActions.make(noteID: noteID, tasks: tasks, notes: notes)
        host.createTaskFromSelection("甲\n乙")
        XCTAssertEqual(tasks.allTasks.filter { $0.sourceNoteID == noteID }.count, 2)
        let note = try XCTUnwrap(notes.notes.first { $0.id == noteID })
        XCTAssertTrue(note.linkedTaskIDs.isEmpty,
                      "回链只走任务侧 sourceNoteID，不再写笔记 linkedTaskIDs")
    }
}
