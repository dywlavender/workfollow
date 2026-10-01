import AppKit
import SwiftUI
import XCTest
@testable import WorkFollow

@MainActor
final class TaskTemplateGalleryRenderTests: XCTestCase {
    func testGalleryCapturesDefaultAndSearchResultsInRealWindows() throws {
        let workspace = TaskWorkspaceModel(seedDemoData: false)
        let storeDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("task-template-gallery-store-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: storeDirectory) }
        let templateStore = TemplateStore(directory: storeDirectory)

        let defaultRender = try renderGallery(
            workspace: workspace,
            templateStore: templateStore,
            query: "",
            name: "template-gallery-default"
        )
        XCTAssertEqual(defaultRender.cardFrames.count, 3,
                       "The default gallery should show the three built-in templates")
        XCTAssertTrue(defaultRender.screenFrame.insetBy(dx: -1, dy: -1).contains(defaultRender.window.frame),
                      "The gallery window must stay inside its screen's visible frame")
        XCTAssertGreaterThan(defaultRender.imageSize.width, 800)
        XCTAssertGreaterThan(defaultRender.imageSize.height, 500)
        XCTAssertTrue(FileManager.default.fileExists(atPath: defaultRender.screenshot.path))

        let searchRender = try renderGallery(
            workspace: workspace,
            templateStore: templateStore,
            query: "每日记录",
            name: "template-gallery-search"
        )
        XCTAssertEqual(searchRender.cardFrames.count, 1,
                       "Searching by a template name should render only the matching card")
        XCTAssertTrue(searchRender.cardFrames.values.allSatisfy { $0.width > 200 && $0.height >= 280 })
        XCTAssertTrue(searchRender.screenFrame.insetBy(dx: -1, dy: -1).contains(searchRender.window.frame))
        XCTAssertTrue(FileManager.default.fileExists(atPath: searchRender.screenshot.path))
    }

    func testClickingWholeCardAppliesOnceAndCallsSuccessCallbacksOnce() throws {
        let workspace = TaskWorkspaceModel(seedDemoData: false)
        let storeDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("task-template-gallery-click-store-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: storeDirectory) }
        let templateStore = TemplateStore(directory: storeDirectory)
        let expectedTemplate = try XCTUnwrap(BuiltInTaskTemplates.all.first)
        var cardFrames: [UUID: CGRect] = [:]
        var appliedIDs: [UUID] = []
        var dismissCount = 0
        let root = TaskTemplateGalleryView(
            workspace: workspace,
            templateStore: templateStore,
            onDismiss: { dismissCount += 1 },
            onApplied: { appliedIDs.append($0) }
        )
        .environment(\.colorScheme, .light)
        .onPreferenceChange(TaskTemplateGalleryFramesKey.self) { cardFrames = $0 }
        let window = makeGalleryWindow(rootView: root)
        defer {
            window.orderOut(nil)
            window.contentView = nil
            window.close()
        }
        settle(window) { cardFrames.count == BuiltInTaskTemplates.all.count }

        let cardFrame = try XCTUnwrap(cardFrames[expectedTemplate.id])
        try click(cardFrame, in: window)
        try click(cardFrame, in: window)
        settle(window) { appliedIDs.count == 1 }

        XCTAssertEqual(workspace.allTasks.count, 1)
        XCTAssertEqual(workspace.allTasks.first?.title, expectedTemplate.title)
        let selectedTaskID = try XCTUnwrap(workspace.selectedTaskID)
        XCTAssertEqual(appliedIDs, [selectedTaskID], "The success callback must run exactly once for the created task")
        XCTAssertEqual(dismissCount, 1)
    }

    func testFailedApplyLeavesGalleryOpenAndDoesNotNotifyOrDismiss() throws {
        let workspace = TaskWorkspaceModel(seedDemoData: false)
        let storeDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("task-template-gallery-failure-store-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: storeDirectory) }
        let templateStore = TemplateStore(directory: storeDirectory)
        let now = Date()
        let emptyTitleTask = Task(
            id: UUID(), title: "", list: .inbox, priority: .none, schedule: TaskSchedule(),
            parentID: nil, childOrder: 0, createdAt: now, updatedAt: now
        )
        XCTAssertTrue(templateStore.save(name: "无标题模板", from: emptyTitleTask))
        let persistenceFinished = expectation(description: "flush the temporary template store before cleanup")
        templateStore.flush { error in
            XCTAssertNil(error)
            persistenceFinished.fulfill()
        }
        wait(for: [persistenceFinished], timeout: 2)

        var cardFrames: [UUID: CGRect] = [:]
        var appliedCount = 0
        var dismissCount = 0
        let root = TaskTemplateGalleryView(
            workspace: workspace,
            templateStore: templateStore,
            onDismiss: { dismissCount += 1 },
            onApplied: { _ in appliedCount += 1 },
            initialSearchText: "无标题模板"
        )
        .environment(\.colorScheme, .light)
        .onPreferenceChange(TaskTemplateGalleryFramesKey.self) { cardFrames = $0 }
        let window = makeGalleryWindow(rootView: root)
        defer {
            window.orderOut(nil)
            window.contentView = nil
            window.close()
        }
        settle(window) { cardFrames.count == 1 }
        let cardFrame = try XCTUnwrap(cardFrames.values.first)

        try click(cardFrame, in: window)
        settle(window)

        XCTAssertTrue(workspace.allTasks.isEmpty)
        XCTAssertEqual(appliedCount, 0)
        XCTAssertEqual(dismissCount, 0)
        XCTAssertEqual(cardFrames.count, 1, "A failed apply should leave the Gallery visible for retry")
    }

    func testEscapeClosesEducationBeforeGalleryAndCreatesNoTask() throws {
        let workspace = TaskWorkspaceModel(seedDemoData: false)
        let storeDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("task-template-gallery-escape-store-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: storeDirectory) }
        let templateStore = TemplateStore(directory: storeDirectory)
        var controls: [String: CGRect] = [:]
        var dismissCount = 0
        var appliedCount = 0
        let root = TaskTemplateGalleryView(
            workspace: workspace,
            templateStore: templateStore,
            onDismiss: { dismissCount += 1 },
            onApplied: { _ in appliedCount += 1 }
        )
        .environment(\.colorScheme, .light)
        .onPreferenceChange(TaskTemplateGalleryControlFramesKey.self) { controls = $0 }
        let window = makeGalleryWindow(rootView: root)
        defer {
            window.orderOut(nil)
            window.contentView = nil
            window.close()
        }
        settle(window) { controls["management"] != nil }
        let galleryFrame = window.frame
        try click(try XCTUnwrap(controls["management"]), in: window)
        settle(window) { controls["education"] != nil }

        XCTAssertEqual(window.frame, galleryFrame,
                       "The education card must overlay the gallery without resizing its window")
        let education = try XCTUnwrap(controls["education"])
        XCTAssertEqual(education.width, 380, accuracy: 0.5)
        XCTAssertLessThan(education.height, 380)
        let host = try XCTUnwrap(window.contentView)
        let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: bitmap)
        let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
        let output = URL(fileURLWithPath: "/tmp/workfollow-template-renders", isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        try png.write(to: output.appendingPathComponent("template-education.png"))

        sendEscape(to: window)
        settle(window) { controls["education"] == nil }
        XCTAssertNil(controls["education"], "The first Escape should close only the education overlay")
        XCTAssertEqual(dismissCount, 0)
        XCTAssertTrue(workspace.allTasks.isEmpty)

        sendEscape(to: window)
        settle(window) { dismissCount == 1 }
        XCTAssertEqual(dismissCount, 1, "The next Escape should dismiss the gallery")
        XCTAssertEqual(appliedCount, 0)
        XCTAssertTrue(workspace.allTasks.isEmpty, "Dismissing with Escape must never create a task")
    }

    private func renderGallery(workspace: TaskWorkspaceModel,
                               templateStore: TemplateStore,
                               query: String,
                               name: String) throws -> RenderedGallery {
        let screen = NSScreen.main ?? NSScreen.screens.first
        let visibleFrame = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let size = NSSize(width: max(1, min(1000, visibleFrame.width - 40)),
                          height: max(1, min(700, visibleFrame.height - 40)))
        let origin = NSPoint(x: visibleFrame.midX - size.width / 2,
                             y: visibleFrame.midY - size.height / 2)

        var cardFrames: [UUID: CGRect] = [:]
        let root = TaskTemplateGalleryView(
            workspace: workspace,
            templateStore: templateStore,
            onDismiss: {},
            initialSearchText: query
        )
        .environment(\.colorScheme, .light)
        .onPreferenceChange(TaskTemplateGalleryFramesKey.self) { cardFrames = $0 }

        let window = NSWindow(contentRect: NSRect(origin: origin, size: size),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        configure(window, rootView: root)
        defer {
            window.orderOut(nil)
            window.contentView = nil
            window.close()
        }
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        settle(window) { cardFrames.count >= (query.isEmpty ? 3 : 1) }

        let host = try XCTUnwrap(window.contentView)
        let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: bitmap)
        let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
        let directory = URL(fileURLWithPath: "/tmp/workfollow-template-renders", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let screenshot = directory.appendingPathComponent("\(name).png")
        try png.write(to: screenshot)

        let rendered = RenderedGallery(
            window: window,
            screenFrame: window.screen?.visibleFrame ?? visibleFrame,
            cardFrames: cardFrames,
            imageSize: CGSize(width: bitmap.pixelsWide, height: bitmap.pixelsHigh),
            screenshot: screenshot
        )
        return rendered
    }

    private func makeGalleryWindow<Root: View>(rootView: Root) -> NSWindow {
        let visibleFrame = NSScreen.main?.visibleFrame
            ?? NSScreen.screens.first?.visibleFrame
            ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let size = NSSize(width: max(1, min(1000, visibleFrame.width - 40)),
                          height: max(1, min(700, visibleFrame.height - 40)))
        let origin = NSPoint(x: visibleFrame.midX - size.width / 2,
                             y: visibleFrame.midY - size.height / 2)
        let window = NSWindow(contentRect: NSRect(origin: origin, size: size),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        configure(window, rootView: rootView)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        return window
    }

    private func configure<Root: View>(_ window: NSWindow, rootView: Root) {
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: .aqua)
        window.backgroundColor = .clear
        window.hasShadow = false
        window.contentView = NSHostingView(rootView: rootView)
    }

    private func click(_ frame: CGRect, in window: NSWindow) throws {
        let host = try XCTUnwrap(window.contentView)
        let localPoint = CGPoint(
            x: frame.midX,
            y: host.isFlipped ? frame.midY : host.bounds.height - frame.midY
        )
        let point = host.convert(localPoint, to: nil)
        for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
            window.sendEvent(try XCTUnwrap(NSEvent.mouseEvent(
                with: type,
                location: point,
                modifierFlags: [],
                timestamp: ProcessInfo.processInfo.systemUptime,
                windowNumber: window.windowNumber,
                context: nil,
                eventNumber: 0,
                clickCount: 1,
                pressure: 1
            )))
        }
    }

    private func sendEscape(to window: NSWindow) {
        let event = NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: window.windowNumber,
            context: nil,
            characters: "\u{1b}",
            charactersIgnoringModifiers: "\u{1b}",
            isARepeat: false,
            keyCode: 53
        )!
        NSApp.sendEvent(event)
    }

    private func settle(_ window: NSWindow, until rendered: () -> Bool) {
        for _ in 0..<40 {
            window.contentView?.layoutSubtreeIfNeeded()
            window.displayIfNeeded()
            if rendered() { break }
            RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        }
        window.contentView?.layoutSubtreeIfNeeded()
        window.displayIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
    }

    private func settle(_ window: NSWindow) {
        window.contentView?.layoutSubtreeIfNeeded()
        window.displayIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.12))
        window.contentView?.layoutSubtreeIfNeeded()
        window.displayIfNeeded()
    }

    private struct RenderedGallery {
        let window: NSWindow
        let screenFrame: CGRect
        let cardFrames: [UUID: CGRect]
        let imageSize: CGSize
        let screenshot: URL
    }
}
