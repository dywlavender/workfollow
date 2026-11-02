#if DEBUG
import AppKit

/// 临时诊断（仅 `--wf-scroll-probe` 启动时生效）：观察笔记编辑器几何；当
/// /tmp/wf-scroll-probe-go 文件出现且编辑器有长正文时，回放一次滚轮并打印
/// 滚动位置变化，用于复现“内容多时不能滚动”。
@MainActor
enum ScrollProbeDebug {
    static var enabled: Bool {
        ProcessInfo.processInfo.arguments.contains("--wf-scroll-probe")
    }

    static func schedule() {
        guard enabled else { return }
        log("probe scheduled (file-trigger mode)")
        for tick in 0..<7200 {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(tick) * 0.5) { observe(tick) }
        }
    }

    private static var wheelTestDone = false

    private static func observe(_ tick: Int) {
        var editor: NativeTextView?
        var hostWindow: NSWindow?
        for window in NSApp.windows where window.isVisible {
            var list: [NativeTextView] = []
            findAllTextViews(in: window.contentView ?? NSView(), into: &list)
            if let first = list.first { editor = first; hostWindow = window; break }
        }
        guard let editor, let window = hostWindow else { return }
        let chars = editor.string.count
        let scroll = editor.enclosingScrollView
        let doc = scroll?.documentView?.frame.size ?? .zero
        let vp = scroll?.contentView.bounds.size ?? .zero
        if tick % 4 == 0 || chars > 5000 {
            log("tick \(tick): id=\(editor.documentIdentity.uuidString.prefix(8)) h=\(editor.frame.height) chars=\(chars) doc=\(doc) vp=\(vp) origin=\(scroll?.contentView.bounds.origin ?? .zero)")
        }
        guard chars > 5000, doc.height > vp.height + 1, !wheelTestDone,
              FileManager.default.fileExists(atPath: "/tmp/wf-scroll-probe-go") else { return }
        try? FileManager.default.removeItem(atPath: "/tmp/wf-scroll-probe-go")
        wheelTestDone = true
        log("WHEEL TEST on editor h=\(editor.frame.height) doc=\(doc)")
        let b = editor.bounds
        let centerInWindow = editor.convert(NSPoint(x: b.midX, y: b.midY), to: nil)
        let appKitPoint = window.convertToScreen(NSRect(origin: centerInWindow, size: .zero)).origin
        // CGEvent.location 用左上角坐标；convertToScreen 是左下角，要翻转。
        let screenHeight = (window.screen ?? NSScreen.main)?.frame.height ?? (appKitPoint.y * 2)
        let screenPoint = NSPoint(x: appKitPoint.x, y: screenHeight - appKitPoint.y)
        for round in 1...4 {
            guard let event = CGEvent(scrollWheelEvent2Source: nil, units: .line,
                                      wheelCount: 1, wheel1: -8, wheel2: 0, wheel3: 0) else { return }
            event.location = CGPoint(x: screenPoint.x, y: screenPoint.y)
            event.postToPid(ProcessInfo.processInfo.processIdentifier)
            window.contentView?.layoutSubtreeIfNeeded()
            log("   wheel \(round): origin=\(scroll?.contentView.bounds.origin ?? .zero)")
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            log("   wheel settled: origin=\(scroll?.contentView.bounds.origin ?? .zero)")
            wheelTestDone = false
        }
    }

    private static func findAllTextViews(in view: NSView, into result: inout [NativeTextView]) {
        if let native = view as? NativeTextView { result.append(native) }
        for sub in view.subviews { findAllTextViews(in: sub, into: &result) }
    }

    private static func log(_ text: String) {
        FileHandle.standardError.write(Data("SCROLL-PROBE: \(text)\n".utf8))
    }
}
#endif
