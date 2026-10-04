import AppKit
import SwiftUI
import XCTest
@testable import WorkFollow

@MainActor
enum InspectorPanelTestSupport {
    private final class RenderProbe {
        var main: [InspectorRenderAnchor: CGRect] = [:]
        var popup: [InspectorRenderAnchor: CGRect] = [:]
        var tags: [TaskTagPickerAnchor: CGRect] = [:]
    }
    private static var probes: [ObjectIdentifier: RenderProbe] = [:]
    private final class OwnerWindow: NSWindow {
        override var canBecomeKey: Bool { true }
    }
    static let actionPanelTitle = "任务详情操作"
    static let focusSubmenuTitle = "任务操作子菜单"
    static let datePanelTitle = "日期属性"

    private struct AccessibilityNode {
        let role: String
        let label: String
        let frame: CGRect
    }

    static func inspectorHost(
        workspace: TaskWorkspaceModel,
        width: CGFloat = 760,
        height: CGFloat = 700,
        environment: AppEnvironment? = nil,
        onFrames: (([InspectorRenderAnchor: CGRect]) -> Void)? = nil
    ) -> NSHostingView<AnyView> {
        let probe = RenderProbe()
        var root = AnyView(TaskInspectorShell(workspace: workspace, showBack: false)
            .frame(width: width, height: height)
            .coordinateSpace(name: "inspector-render")
            .onPreferenceChange(InspectorFramesKey.self) { probe.main = $0; onFrames?($0) }
            .environment(\.popupContentObservation, { content in
                AnyView(content.coordinateSpace(name: "inspector-render")
                    .onPreferenceChange(InspectorFramesKey.self) {
                        if $0[.focusPomodoro] != nil {
                            probe.popup.merge($0, uniquingKeysWith: { _, new in new })
                        } else if !$0.isEmpty { probe.popup = $0 }
                    }
                    .onPreferenceChange(TaskTagPickerFrames.self) { probe.tags = $0 })
            }))
        if let environment { root = AnyView(root.environmentObject(environment)) }
        let host = NSHostingView(rootView: root)
        probes[ObjectIdentifier(host)] = probe
        return host
    }

    static func ownerWindow(for host: NSView, width: CGFloat = 760, height: CGFloat = 700) -> NSWindow {
        let window = OwnerWindow(contentRect: NSRect(x: 100, y: 100, width: width, height: height),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: .aqua)
        window.contentView = host
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        settle(window)
        return window
    }

    static func actionPanel(in owner: NSWindow) throws -> NSPanel {
        try panel(title: actionPanelTitle, below: owner)
    }

    static func panel(title: String, below root: NSWindow) throws -> NSPanel {
        try XCTUnwrap(descendants(of: root).first { $0.title == title && $0.isVisible } as? NSPanel,
                      "No visible ‘\(title)’ panel below ‘\(root.title)’")
    }

    static func visibleWindows(below root: NSWindow) -> [NSWindow] {
        descendants(of: root).filter(\.isVisible)
    }

    static func clickButton(containing label: String, in window: NSWindow) throws {
        let frame = try accessibilityFrame(containing: label, role: "AXButton", in: window)
        try click(screenFrame: frame, in: window)
    }

    static func clickElement(containing label: String, in window: NSWindow) throws {
        let frame = try accessibilityFrame(containing: label, role: nil, in: window)
        try click(screenFrame: frame, in: window)
    }

    /// Preference frames use the named SwiftUI coordinate space: origin at top-left.
    static func click(_ frame: CGRect, in view: NSView, window: NSWindow,
                      modifiers: NSEvent.ModifierFlags = []) throws {
        let point = view.convert(NSPoint(x: frame.midX,
                                         y: view.isFlipped ? frame.midY : view.bounds.height - frame.midY),
                                 to: nil)
        try sendClick(at: point, to: window, modifiers: modifiers)
        settle(window)
    }

    /// Accessibility frames are in global screen coordinates; the event is delivered to
    /// the actual window that owns the accessible control.
    static func click(screenFrame: CGRect, in window: NSWindow) throws {
        let screenPoint = NSPoint(x: screenFrame.midX, y: screenFrame.midY)
        let point = window.convertFromScreen(NSRect(origin: screenPoint, size: .zero)).origin
        try sendClick(at: point, to: window)
        settle(window)
    }

    static func sendEscape(to window: NSWindow) throws {
        let event = try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero,
            modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: window.windowNumber, context: nil,
            characters: "\u{1b}", charactersIgnoringModifiers: "\u{1b}",
            isARepeat: false, keyCode: 53))
        NSApp.sendEvent(event)
        settle(window)
    }

    static func settle(_ root: NSWindow, duration: TimeInterval = 0.14) {
        func layout(_ window: NSWindow) {
            window.contentView?.layoutSubtreeIfNeeded()
            for child in window.childWindows ?? [] { layout(child) }
        }
        layout(root)
        RunLoop.current.run(until: Date().addingTimeInterval(duration))
        layout(root)
    }

    private static var clickEventNumber = 0
    private static func sendClick(at point: NSPoint, to window: NSWindow,
                                  modifiers: NSEvent.ModifierFlags = []) throws {
        clickEventNumber += 2
        func event(_ type: NSEvent.EventType) throws -> NSEvent {
            try XCTUnwrap(NSEvent.mouseEvent(with: type, location: point,
                modifierFlags: modifiers, timestamp: ProcessInfo.processInfo.systemUptime,
                windowNumber: window.windowNumber, context: nil,
                eventNumber: clickEventNumber + (type == .leftMouseUp ? 1 : 0),
                clickCount: 1, pressure: type == .leftMouseUp ? 0 : 1))
        }
        // Native text controls may synchronously track until mouse-up. Queue
        // that event first so dispatching mouse-down cannot deadlock the test.
        NSApp.postEvent(try event(.leftMouseUp), atStart: true)
        NSApp.postEvent(try event(.leftMouseDown), atStart: true)
        let down = try XCTUnwrap(NSApp.nextEvent(matching: .leftMouseDown, until: Date(),
                                                inMode: .default, dequeue: true))
        NSApp.sendEvent(down)
        if let remaining = NSApp.nextEvent(matching: .leftMouseUp, until: Date(),
                                           inMode: .default, dequeue: true) {
            NSApp.sendEvent(remaining)
        }
    }

    private static func accessibilityFrame(
        containing labelFragment: String,
        role: String?,
        in window: NSWindow
    ) throws -> CGRect {
        let root = try XCTUnwrap(window.contentView, "Window has no content view")
        var owner = window
        while let parent = owner.parent { owner = parent }
        if let host = owner.contentView, let probe = probes[ObjectIdentifier(host)] {
            let anchors: [String: InspectorRenderAnchor] = [
                "更多任务操作": .footerMore, "设置日期": .schedule, "任务标题": .title,
                "开始专注": .focusMenuRow, "关联主任务": .parentMenuRow,
                "标签": .tagsMenuRow, "任务动态": .activityMenuRow, "创建副本": .duplicateMenuRow,
                "开始番茄专注": .focusPomodoro, "开始正计时": .focusStopwatch
            ]
            let frames = window === owner ? probe.main : probe.popup
            var rect = anchors[labelFragment].flatMap { frames[$0] }
            if probe.popup[.tagPicker] != nil, window !== owner {
                rect = labelFragment == "确定" ? probe.tags[.confirm] : probe.tags[.tag(labelFragment)]
            }
            if let rect {
                let local = CGRect(x: rect.minX,
                    y: root.isFlipped ? rect.minY : root.bounds.height - rect.maxY,
                    width: rect.width, height: rect.height)
                return window.convertToScreen(root.convert(local, to: nil))
            }
        }
        let nodes = accessibilityNodes(in: root)
        let match = nodes.first {
            (role == nil || $0.role == role) &&
            $0.label.localizedCaseInsensitiveContains(labelFragment) && !$0.frame.isEmpty
        }
        let available = nodes
            .filter { !$0.label.isEmpty }
            .map { "\($0.role): \($0.label)" }
            .joined(separator: ", ")
        return try XCTUnwrap(match?.frame,
            "No AX \(role ?? "element") containing ‘\(labelFragment)’ in ‘\(window.title)’. Found: [\(available)]")
    }

    private static func accessibilityNodes(in root: NSView) -> [AccessibilityNode] {
        var visited: Set<ObjectIdentifier> = []
        var result: [AccessibilityNode] = []

        func visit(_ value: Any) {
            guard let object = value as? NSObject,
                  visited.insert(ObjectIdentifier(object)).inserted else { return }

            let role = accessibilityString("accessibilityRole", on: object) ?? ""
            let label = ["accessibilityLabel", "accessibilityTitle", "accessibilityValue",
                         "accessibilityHelp", "accessibilityDescription", "accessibilityIdentifier"]
                .compactMap { accessibilityString($0, on: object) }
                .filter { !$0.isEmpty }.joined(separator: " · ")
            if !role.isEmpty || !label.isEmpty {
                let frameValue = accessibilityValue("accessibilityFrame", on: object)
                let frame = (frameValue as? NSValue)?.rectValue ?? .zero
                result.append(AccessibilityNode(role: role, label: label, frame: frame))
            }

            if let children = accessibilityValue("accessibilityChildren", on: object) as? [Any] {
                children.forEach(visit)
            }
            // AppKit controls may expose their accessible children as native subviews;
            // SwiftUI controls often vend virtual NSAccessibilityElement children instead.
            (object as? NSView)?.subviews.forEach(visit)
        }

        visit(root)
        return result
    }

    private static func accessibilityValue(_ key: String, on object: NSObject) -> Any? {
        let selector = NSSelectorFromString(key)
        guard object.responds(to: selector) else { return nil }
        return object.value(forKey: key)
    }

    private static func accessibilityString(_ key: String, on object: NSObject) -> String? {
        guard let value = accessibilityValue(key, on: object) else { return nil }
        if let string = value as? String { return string }
        if let string = value as? NSString { return string as String }
        return nil
    }

    private static func descendants(of root: NSWindow) -> [NSWindow] {
        var result: [NSWindow] = []
        func visit(_ window: NSWindow) {
            for child in window.childWindows ?? [] {
                result.append(child)
                visit(child)
            }
        }
        visit(root)
        return result
    }
}
