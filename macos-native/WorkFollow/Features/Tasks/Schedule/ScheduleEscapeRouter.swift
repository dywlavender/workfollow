import AppKit
import SwiftUI

/// NSPopover consumes Escape before SwiftUI exit commands. Intercept it only
/// in this panel's window so the expanded editor can close before its parent.
struct ScheduleEscapeRouter: View {
    let onEscape: () -> Void

    var body: some View {
        PopupEscapeRouter(depth: 2, onEscape: onEscape)
    }
}
