import XCTest
@testable import WorkFollow

final class TaskTagPickerSessionTests: XCTestCase {
    func testInitializationNormalizesSelectionAndRetainsInitialTagsInCatalog() {
        let session = TaskTagPickerSession(initialTags: [" #work# ", "学习", "work", " ## "])

        XCTAssertEqual(session.selectedTags, ["work", "学习"])
        XCTAssertEqual(session.allTags(availableTags: ["已有", "学习", "已有"]), ["已有", "学习", "work"].sorted())
    }

    func testMatchingTagsSearchesCaseInsensitivelyAndNormalizesQuery() {
        var session = TaskTagPickerSession(initialTags: ["Project Notes"])
        session.query = " #pRoJ "

        XCTAssertEqual(session.matchingTags(availableTags: ["Plan", "Planning", "Other"]),
                       ["Project Notes"])

        session.query = "PLAn"
        XCTAssertEqual(session.matchingTags(availableTags: ["Plan", "Planning", "Other"]),
                       ["Plan", "Planning"])
    }

    func testCreateNormalizesDeduplicatesAndSkipsExistingTags() {
        var session = TaskTagPickerSession(initialTags: ["已有", "保留"])
        session.query = " ##新标签##, 新标签， 已有 , # 带空格 #,, ### "

        XCTAssertEqual(session.creatableTags(availableTags: ["目录标签"]), ["新标签", "带空格"])

        session.createFromQuery(availableTags: ["目录标签"])

        XCTAssertEqual(session.selectedTags, ["已有", "保留", "新标签", "带空格"])
        XCTAssertEqual(session.allTags(availableTags: ["目录标签"]),
                       ["目录标签", "已有", "保留", "新标签", "带空格"].sorted())
        XCTAssertEqual(session.query, "")
    }

    func testTagIdentityRemainsCaseSensitiveWhenCreating() {
        var session = TaskTagPickerSession(initialTags: ["Work"])
        session.query = "work"

        XCTAssertEqual(session.creatableTags(availableTags: []), ["work"])
        session.createFromQuery(availableTags: [])
        XCTAssertEqual(session.selectedTags, ["Work", "work"])
    }

    func testDeselectingInitialUnsavedTagKeepsItAvailableForReselection() {
        var session = TaskTagPickerSession(initialTags: ["#尚未保存#"])

        session.toggle("尚未保存")
        XCTAssertTrue(session.selectedTags.isEmpty)
        XCTAssertEqual(session.allTags(availableTags: []), ["尚未保存"])

        session.toggle(" #尚未保存 ")
        XCTAssertEqual(session.selectedTags, ["尚未保存"])
    }

    func testDeselectingCreatedTagKeepsItAvailableForReselection() {
        var session = TaskTagPickerSession(initialTags: [])
        session.query = "新建标签"
        session.createFromQuery(availableTags: [])
        XCTAssertEqual(session.selectedTags, ["新建标签"])

        session.toggle("新建标签")
        XCTAssertTrue(session.selectedTags.isEmpty)
        XCTAssertEqual(session.allTags(availableTags: []), ["新建标签"])

        session.toggle("新建标签")
        XCTAssertEqual(session.selectedTags, ["新建标签"])
    }

    func testIndependentDraftSessionsDoNotMutateAvailableOrOtherSessionTags() {
        let availableTags = ["全局标签"]
        var cancelledDraft = TaskTagPickerSession(initialTags: ["Quick Add"])
        let nextSession = TaskTagPickerSession(initialTags: ["Quick Add"])
        cancelledDraft.toggle("Quick Add")
        cancelledDraft.query = "本地创建"
        cancelledDraft.createFromQuery(availableTags: availableTags)

        XCTAssertEqual(availableTags, ["全局标签"])
        XCTAssertEqual(nextSession.selectedTags, ["Quick Add"])
        XCTAssertEqual(nextSession.allTags(availableTags: availableTags), ["全局标签", "Quick Add"].sorted())
    }
}
