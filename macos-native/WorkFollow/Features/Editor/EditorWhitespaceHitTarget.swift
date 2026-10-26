import AppKit
import SwiftUI

/// Receives only the host's unused space, without growing the text view or
/// competing with its native selection, decorations or the surrounding fields.
struct EditorWhitespaceHitTarget: NSViewRepresentable {
    let handle: DocumentEditorHandle
    let documentID: UUID

    func makeNSView(context: Context) -> TargetView { TargetView() }

    func updateNSView(_ view: TargetView, context: Context) {
        view.handle = handle
        view.documentID = documentID
        view.window?.invalidateCursorRects(for: view)
    }

    final class TargetView: NSView {
        weak var handle: DocumentEditorHandle?
        var documentID: UUID?
        private var dragAnchor: Int?
        override var isFlipped: Bool { true }
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

        private var editor: NativeTextView? {
            guard let textView = handle?.textView, let window,
                  textView.window === window, textView.documentIdentity == documentID,
                  textView.isEditable, !textView.isHiddenOrHasHiddenAncestor else { return nil }
            return textView
        }

        private func bodyRect(for editor: NativeTextView) -> NSRect {
            let top = max(bounds.minY, convert(editor.bounds, from: editor).minY)
            return NSRect(x: bounds.minX, y: top, width: bounds.width,
                          height: max(0, bounds.maxY - top)).intersection(visibleRect)
        }

        override func hitTest(_ point: NSPoint) -> NSView? {
            guard let editor else { return nil }
            let local = convert(point, from: superview)
            guard bounds.intersection(visibleRect).contains(local),
                  bodyRect(for: editor).contains(local),
                  !convert(editor.bounds, from: editor).contains(local) else { return nil }
            return self
        }

        override func resetCursorRects() {
            super.resetCursorRects()
            guard let editor else { return }
            let body = bodyRect(for: editor)
            let text = convert(editor.bounds, from: editor)
            let spaces = [
                NSRect(x: body.minX, y: body.minY, width: max(0, text.minX - body.minX), height: body.height),
                NSRect(x: text.maxX, y: body.minY, width: max(0, body.maxX - text.maxX), height: body.height),
                NSRect(x: body.minX, y: text.maxY, width: body.width, height: max(0, body.maxY - text.maxY))
            ]
            for space in spaces {
                let visible = space.intersection(body)
                if !visible.isEmpty { addCursorRect(visible, cursor: .iBeam) }
            }
        }

        override func mouseDown(with event: NSEvent) {
            guard let editor else { return }
            editor.dismissSlash()
            editor.dismissTagCompletion()
            editor.hideLinkHoverMenu()
            editor.dismissChecklistReminderPanel()
            handle?.flushPendingComposition()
            let index = editor.insertionIndex(nearest: editor.convert(event.locationInWindow, from: nil))
            let previous = editor.selectedRange()
            let anchor = event.modifierFlags.contains(.shift)
                ? (index < previous.location ? NSMaxRange(previous) : previous.location) : index
            dragAnchor = anchor
            editor.window?.makeFirstResponder(editor)
            editor.breakUndoCoalescing()
            editor.setSelectedRange(NSRange(location: min(anchor, index), length: abs(index - anchor)))
            if event.clickCount == 2 { editor.selectWord(nil) }
            else if event.clickCount >= 3 { editor.selectParagraph(nil) }
        }

        override func mouseDragged(with event: NSEvent) {
            guard let editor, let anchor = dragAnchor else { return }
            let index = editor.insertionIndex(nearest: editor.convert(event.locationInWindow, from: nil))
            editor.setSelectedRange(NSRange(location: min(anchor, index), length: abs(index - anchor)))
        }

        override func mouseUp(with event: NSEvent) { dragAnchor = nil }
    }
}

extension NativeTextView {
    /// Project onto a visual line before asking TextKit for a character. Its
    /// insertion lookup alone can return zero for points in the host's gutters.
    func insertionIndex(nearest point: NSPoint) -> Int {
        let length = textStorage?.length ?? 0
        guard let layout = textLayoutManager else { return min(length, characterIndexForInsertion(at: point)) }
        let origin = textContainerOrigin
        var nearest: NSRect?
        var distance = CGFloat.greatestFiniteMagnitude
        func consider(_ rect: NSRect) {
            guard rect.height > 0 else { return }
            let next = max(max(rect.minY - point.y, point.y - rect.maxY), 0)
            if next < distance { distance = next; nearest = rect }
        }
        layout.enumerateTextLayoutFragments(from: nil, options: [.ensuresLayout, .ensuresExtraLineFragment]) { fragment in
            for line in fragment.textLineFragments {
                consider(line.typographicBounds.offsetBy(dx: fragment.layoutFragmentFrame.minX + origin.x,
                                                        dy: fragment.layoutFragmentFrame.minY + origin.y))
            }
            return fragment.layoutFragmentFrame.minY + origin.y <= point.y || nearest == nil
        }
        if (length == 0 || string.hasSuffix("\n")), let trailing = viewRect(forCharacterAt: length) {
            let trailingDistance = max(max(trailing.minY - point.y, point.y - trailing.maxY), 0)
            if trailingDistance <= distance, point.y >= trailing.minY { return length }
        }
        guard let nearest else { return min(length, characterIndexForInsertion(at: point)) }
        let x = min(max(point.x, nearest.minX + 0.25), max(nearest.minX + 0.25, nearest.maxX - 0.25))
        return min(length, characterIndexForInsertion(at: NSPoint(x: x, y: nearest.midY)))
    }
}
