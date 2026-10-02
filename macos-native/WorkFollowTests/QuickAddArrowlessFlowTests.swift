import AppKit
import SwiftUI
import XCTest
@testable import WorkFollow

@MainActor
final class QuickAddArrowlessFlowTests: XCTestCase {
    private final class State: ObservableObject {
        @Published var showsProperties = true
        var listSelections: [String] = []
        var tagSelections: [[String]] = []
        var quickAddFrames: [QuickAddRenderAnchor: CGRect] = [:]
        var tagPickerFrames: [TaskTagPickerAnchor: CGRect] = [:]
    }

    private struct Harness: View {
        let workspace: TaskWorkspaceModel
        @ObservedObject var state: State

        var body: some View {
            VStack(alignment: .leading, spacing: 0) {
                Button("更多属性") {}
                    .buttonStyle(.plain)
                    .frame(width: 100, height: 32)
                    .background(AnchoredPropertyPanel(isPresented: $state.showsProperties, width: 270) {
                        QuickAddPropertiesPopover(
                            workspace: workspace,
                            selectedPriority: .none,
                            selectedList: TaskList.inbox.name,
                            selectedTags: [],
                            onPriority: { _ in },
                            onList: { state.listSelections.append($0) },
                            onTags: { state.tagSelections.append($0) },
                            onTemplate: {},
                            onDismiss: { state.showsProperties = false }
                        )
                        .coordinateSpace(name: "quick-add-render")
                        .onPreferenceChange(QuickAddFramesKey.self) { state.quickAddFrames = $0 }
                    })
                Spacer(minLength: 0)
            }
            .padding(20)
            .frame(width: 760, height: 560, alignment: .topLeading)
        }
    }

    private struct Fixture {
        let owner: NSWindow
        let host: NSHostingView<AnyView>
        let state: State
    }

    func testListSearchAndEscapeCancelWithoutApplyingAndKeepParentFrame() throws {
        let fixture = makeFixture()
        defer { close(fixture) }

        let parent = try XCTUnwrap(parentPanel(in: fixture.owner))
        let originalFrame = parent.frame
        try click(.list, in: parent, state: fixture.state)
        settle(fixture)

        let child = try XCTUnwrap(childPanel(in: parent))
        XCTAssertEqual(child.frame.width, 250, accuracy: 0.5)
        XCTAssertEqual(parent.frame, originalFrame)

        let editor = try XCTUnwrap(child.firstResponder as? NSTextView,
                                   "Search must own focus; key=\(child.isKeyWindow), responder=\(String(describing: child.firstResponder))")
        editor.insertText("no-such-list", replacementRange: editor.selectedRange())
        settle(fixture)
        XCTAssertTrue(editor.string.contains("no-such-list"))
        XCTAssertEqual(fixture.state.listSelections, [])

        sendEscape(to: child)
        settle(fixture)
        XCTAssertFalse(child.isVisible)
        XCTAssertTrue(parent.isVisible)
        XCTAssertEqual(parent.frame, originalFrame)
        XCTAssertEqual(fixture.state.listSelections, [])
    }

    func testTagCancelDoesNotApplyAndConfirmCallsBackOnce() throws {
        let fixture = makeFixture(withTag: "已有标签")
        defer { close(fixture) }

        let parent = try XCTUnwrap(parentPanel(in: fixture.owner))
        let originalFrame = parent.frame
        try click(.tags, in: parent, state: fixture.state)
        settle(fixture)
        var child = try XCTUnwrap(childPanel(in: parent))
        XCTAssertEqual(child.frame.width, 264, accuracy: 0.5)
        XCTAssertEqual(parent.frame, originalFrame)
        XCTAssertTrue(child.firstResponder is NSTextView, "Tag search must receive initial keyboard focus, not Confirm")

        try captureTagPickerFrames(in: child, state: fixture.state)
        try clickTagPicker(.tag("已有标签"), in: child, state: fixture.state)
        try clickTagPicker(.cancel, in: child, state: fixture.state)
        settle(fixture)
        XCTAssertEqual(fixture.state.tagSelections, [])
        XCTAssertTrue(parent.isVisible)
        XCTAssertFalse(child.isVisible)

        try click(.tags, in: parent, state: fixture.state)
        settle(fixture)
        child = try XCTUnwrap(childPanel(in: parent))
        try captureTagPickerFrames(in: child, state: fixture.state)
        try clickTagPicker(.tag("已有标签"), in: child, state: fixture.state)
        try clickTagPicker(.confirm, in: child, state: fixture.state)
        settle(fixture)

        XCTAssertEqual(fixture.state.tagSelections, [["已有标签"]])
        XCTAssertFalse(child.isVisible)
        XCTAssertTrue(parent.isVisible)
    }

    func testEscapeClosesChildThenParentAcrossRealPanelWindows() throws {
        let fixture = makeFixture()
        defer { close(fixture) }

        let parent = try XCTUnwrap(parentPanel(in: fixture.owner))
        try click(.list, in: parent, state: fixture.state)
        settle(fixture)
        let child = try XCTUnwrap(childPanel(in: parent))
        XCTAssertTrue(parent.parent === fixture.owner)
        XCTAssertTrue(child.parent === parent)

        // Both AnchoredPropertyPanel windows use default depth 3. A parent-window
        // Escape matches both routes, so the nested child panel must win first.
        sendEscape(to: parent)
        settle(fixture)
        XCTAssertFalse(child.isVisible)
        XCTAssertTrue(parent.isVisible)
        XCTAssertTrue(fixture.state.showsProperties)

        sendEscape(to: parent)
        settle(fixture)
        XCTAssertFalse(parent.isVisible)
        XCTAssertFalse(fixture.state.showsProperties)
    }

    func testClosingParentPanelCleansAnOpenSubmenuPanel() throws {
        let fixture = makeFixture()
        defer { close(fixture) }

        let parent = try XCTUnwrap(parentPanel(in: fixture.owner))
        try click(.list, in: parent, state: fixture.state)
        settle(fixture)
        let child = try XCTUnwrap(childPanel(in: parent))
        XCTAssertTrue(child.isVisible)

        fixture.state.showsProperties = false
        settle(fixture)

        XCTAssertFalse(parent.isVisible)
        XCTAssertFalse(child.isVisible)
        XCTAssertNil(child.parent)
    }

    func testOutsideClickClosesParentAndCleansOpenSubmenu() throws {
        let fixture = makeFixture()
        defer { close(fixture) }

        let parent = try XCTUnwrap(parentPanel(in: fixture.owner))
        try click(.list, in: parent, state: fixture.state)
        settle(fixture)
        let child = try XCTUnwrap(childPanel(in: parent))
        XCTAssertTrue(child.isVisible)

        let ownerContent = try XCTUnwrap(fixture.owner.contentView)
        let outsidePoint = NSPoint(x: ownerContent.bounds.maxX - 24,
                                   y: ownerContent.bounds.minY + 24)
        try sendClick(at: outsidePoint, in: fixture.owner)
        settle(fixture)

        XCTAssertFalse(parent.isVisible)
        XCTAssertFalse(child.isVisible)
        XCTAssertFalse(fixture.state.showsProperties)
        XCTAssertEqual(fixture.state.listSelections, [])
    }

    private func makeFixture(withTag tag: String? = nil) -> Fixture {
        let now = Date()
        var tasks: [Task] = []
        if let tag {
            var task = Task(id: UUID(), title: "标签数据", list: .inbox, priority: .none,
                            schedule: TaskSchedule(), parentID: nil, childOrder: 0,
                            createdAt: now, updatedAt: now)
            task.tags = [tag]
            tasks = [task]
        }
        let workspace = TaskWorkspaceModel(seedDemoData: false, initialTasks: tasks,
                                           initialLists: ["工作", "个人"])
        let state = State()
        let host = NSHostingView(rootView: AnyView(Harness(workspace: workspace, state: state)))
        let owner = NSWindow(contentRect: NSRect(x: 120, y: 100, width: 800, height: 600),
                             styleMask: [.borderless], backing: .buffered, defer: false)
        owner.isReleasedWhenClosed = false
        owner.appearance = NSAppearance(named: .aqua)
        owner.contentView = host
        owner.makeKeyAndOrderFront(nil)
        let fixture = Fixture(owner: owner, host: host, state: state)
        settle(fixture)
        return fixture
    }

    private func close(_ fixture: Fixture) {
        fixture.state.showsProperties = false
        settle(fixture)
        fixture.owner.contentView = nil
        fixture.owner.close()
    }

    private func settle(_ fixture: Fixture) {
        fixture.host.layoutSubtreeIfNeeded()
        if let parent = parentPanel(in: fixture.owner) {
            parent.contentView?.layoutSubtreeIfNeeded()
            if let child = childPanel(in: parent) {
                child.contentView?.layoutSubtreeIfNeeded()
            }
        }
        RunLoop.main.run(until: Date().addingTimeInterval(0.12))
        fixture.host.layoutSubtreeIfNeeded()
        if let parent = parentPanel(in: fixture.owner) {
            parent.contentView?.layoutSubtreeIfNeeded()
            if let child = childPanel(in: parent) {
                child.contentView?.layoutSubtreeIfNeeded()
            }
        }
    }

    private func parentPanel(in owner: NSWindow) -> NSPanel? {
        owner.childWindows?.compactMap { $0 as? NSPanel }.first(where: \.isVisible)
    }

    private func childPanel(in parent: NSWindow) -> NSPanel? {
        parent.childWindows?.compactMap { $0 as? NSPanel }.first(where: \.isVisible)
    }

    private func click(_ anchor: QuickAddRenderAnchor, in parent: NSPanel,
                       state: State) throws {
        let frame = try XCTUnwrap(state.quickAddFrames[anchor])
        let host = try XCTUnwrap(parent.contentView as? NSHostingView<AnyView>)
        try sendClick(in: host, frame: frame, window: parent)
    }

    private func captureTagPickerFrames(in child: NSPanel, state: State) throws {
        state.tagPickerFrames = [:]
        let host = try XCTUnwrap(child.contentView as? NSHostingView<AnyView>)
        host.rootView = AnyView(host.rootView
            .onPreferenceChange(TaskTagPickerFrames.self) { state.tagPickerFrames = $0 })
        host.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.12))
        host.layoutSubtreeIfNeeded()
    }

    private func clickTagPicker(_ anchor: TaskTagPickerAnchor, in child: NSPanel,
                                state: State) throws {
        let frame = try XCTUnwrap(state.tagPickerFrames[anchor])
        let host = try XCTUnwrap(child.contentView as? NSHostingView<AnyView>)
        try sendClick(in: host, frame: frame, window: child)
    }

    private func sendClick(in view: NSView, frame: CGRect, window: NSWindow) throws {
        let point = view.convert(NSPoint(x: frame.midX,
            y: view.isFlipped ? frame.midY : view.bounds.height - frame.midY), to: nil)
        try sendClick(at: point, in: window)
    }

    private func sendClick(at point: NSPoint, in window: NSWindow) throws {
        for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
            let event = try XCTUnwrap(NSEvent.mouseEvent(with: type, location: point,
                modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                windowNumber: window.windowNumber, context: nil, eventNumber: 0,
                clickCount: 1, pressure: 1))
            NSApp.sendEvent(event)
        }
    }

    private func sendEscape(to window: NSWindow) {
        let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
            context: nil, characters: "\u{1b}", charactersIgnoringModifiers: "\u{1b}",
            isARepeat: false, keyCode: 53)!
        NSApp.sendEvent(event)
    }
}
