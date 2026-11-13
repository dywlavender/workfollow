import Foundation
import XCTest
@testable import WorkFollow

final class NoteFolderTreeTests: XCTestCase {
    private func record(_ id: String, _ name: String, _ parent: String?,
                        _ order: Int) -> NoteFolderMeta {
        NoteFolderMeta(id: id, parentID: parent, name: name, sortOrder: order,
                       createdAt: nil, updatedAt: nil)
    }

    func testSanitizedDropsDanglingParent() {
        let records = [record("a", "A", "missing", 0)]
        XCTAssertNil(NoteFolderTree.sanitized(records)[0].parentID)
    }

    func testSanitizedBreaksCycleIntoRoots() {
        let records = [record("a", "A", "b", 0), record("b", "B", "a", 1)]
        let cleaned = NoteFolderTree.sanitized(records)
        XCTAssertNil(cleaned[0].parentID)
        XCTAssertNil(cleaned[1].parentID)
        XCTAssertEqual(NoteFolderTree.nodes(from: records).count, 2)
    }

    func testNodesAreDepthFirstWithCorrectDepth() {
        let records = [
            record("a", "A", nil, 0),
            record("b", "B", "a", 1),
            record("c", "C", nil, 2),
            record("d", "D", "b", 3)
        ]
        let nodes = NoteFolderTree.nodes(from: records)
        XCTAssertEqual(nodes.map(\.name), ["A", "B", "D", "C"])
        XCTAssertEqual(nodes.map(\.depth), [0, 1, 2, 0])
    }

    func testCannotMoveFolderUnderSelfOrDescendant() {
        let records = [
            record("a", "A", nil, 0),
            record("b", "B", "a", 1),
            record("c", "C", "b", 2)
        ]
        XCTAssertFalse(NoteFolderTree.canMove(folderID: "a", under: "a", in: records))
        XCTAssertFalse(NoteFolderTree.canMove(folderID: "a", under: "b", in: records))
        XCTAssertFalse(NoteFolderTree.canMove(folderID: "a", under: "c", in: records))
        XCTAssertTrue(NoteFolderTree.canMove(folderID: "c", under: "a", in: records))
        XCTAssertTrue(NoteFolderTree.canMove(folderID: "a", under: nil, in: records))
    }

    func testPathReturnsAncestorsFromRoot() {
        let records = [
            record("a", "工作", nil, 0),
            record("b", "2026", "a", 1),
            record("c", "周报", "b", 2)
        ]
        XCTAssertEqual(NoteFolderTree.path(toID: "c", in: records), ["工作", "2026"])
        XCTAssertEqual(NoteFolderTree.path(toID: "a", in: records), [])
    }

    func testNameColorHexFlowsIntoNodesAndSurvivesCoding() throws {
        var meta = record("a", "工作", nil, 0)
        meta.nameColorHex = "#0b7bff"
        let nodes = NoteFolderTree.nodes(from: [meta])
        XCTAssertEqual(nodes.first?.nameColorHex, "#0b7bff")

        let data = try JSONEncoder().encode([meta])
        let restored = try JSONDecoder().decode([NoteFolderMeta].self, from: data)
        XCTAssertEqual(restored.first?.nameColorHex, "#0b7bff")

        // 旧快照没有 nameColorHex 键：解码为 nil，不影响其余字段。
        let legacy = try JSONDecoder().decode([NoteFolderMeta].self, from: Data(
            #"[{"id":"a","name":"工作","sortOrder":0}]"#.utf8))
        XCTAssertNil(legacy.first?.nameColorHex)
        XCTAssertEqual(legacy.first?.name, "工作")
    }
}

@MainActor
final class NoteFolderTreeModelTests: XCTestCase {
    func testSubfolderPathAndMoveToRoot() throws {
        let model = NotesWorkspaceModel()
        let parent = try XCTUnwrap(model.addFolder("工作", parentID: nil))
        let child = try XCTUnwrap(model.addFolder("周报", parentID: parent))
        XCTAssertEqual(model.folderPath(named: "周报"), ["工作", "周报"])
        // 父不能挂到自己的后代下
        XCTAssertFalse(model.moveFolder(id: parent, under: child))
        XCTAssertTrue(model.moveFolder(id: child, under: nil))
        XCTAssertEqual(model.folderPath(named: "周报"), ["周报"])
    }

    func testRemoveFolderPromotesChildrenInsteadOfOrphaningThem() throws {
        let model = NotesWorkspaceModel()
        let parent = try XCTUnwrap(model.addFolder("工作", parentID: nil))
        _ = model.addFolder("周报", parentID: parent)
        model.create(folder: "周报")
        model.removeFolder("工作")
        XCTAssertEqual(model.folderPath(named: "周报"), ["周报"])
        XCTAssertEqual(model.selected?.folder, "周报")
    }

    func testFolderNameStaysGloballyUniqueAcrossLevels() throws {
        let model = NotesWorkspaceModel()
        let parent = try XCTUnwrap(model.addFolder("工作", parentID: nil))
        XCTAssertTrue(model.addFolder("周报", parentID: parent) != nil)
        XCTAssertNil(model.addFolder("周报", parentID: nil))
        XCTAssertEqual(model.folders, ["工作", "周报"])
    }

    /// 展开态不能走 revision：AppEnvironment 订阅 $revision 写盘，
    /// 折叠一次触发一次 SQLite 写是不可接受的。
    func testExpandingDoesNotBumpRevision() {
        let model = NotesWorkspaceModel()
        let before = model.revision
        model.setFolderExpanded("x", true)
        XCTAssertTrue(model.isFolderExpanded("x"))
        XCTAssertEqual(model.revision, before)
        model.setFolderExpanded("x", false)
        XCTAssertEqual(model.revision, before)
    }

    func testExpandAncestorsOpensWholeChain() throws {
        let model = NotesWorkspaceModel()
        let root = try XCTUnwrap(model.addFolder("工作", parentID: nil))
        let middle = try XCTUnwrap(model.addFolder("2026", parentID: root))
        let leaf = try XCTUnwrap(model.addFolder("周报", parentID: middle))
        model.expandAncestors(ofFolderNamed: "周报")
        XCTAssertTrue(model.isFolderExpanded(root))
        XCTAssertTrue(model.isFolderExpanded(middle))
        XCTAssertTrue(model.isFolderExpanded(leaf))
    }
}
