import Combine
import SwiftUI

/// Owns the Focus task picker's interaction state so the UI and its contract
/// tests exercise the same open, scope, select, clear, dismiss, and Escape rules.
@MainActor
final class FocusTaskPickerSession: ObservableObject {
    @Published private(set) var isPresented = false
    @Published private(set) var isScopePickerPresented = false
    @Published var scope: FocusTaskPickerScope = .today
    @Published var query = ""
    @Published var linkedTaskID: UUID?

    init(linkedTaskID: UUID? = nil) {
        self.linkedTaskID = linkedTaskID
    }

    var presentationBinding: Binding<Bool> {
        Binding(get: { self.isPresented },
                set: { $0 ? self.present() : self.dismiss() })
    }

    var scopePickerBinding: Binding<Bool> {
        Binding(get: { self.isScopePickerPresented },
                set: { $0 ? self.presentScopePicker() : self.dismissScopePicker() })
    }

    func present() {
        scope = .today
        query = ""
        isScopePickerPresented = false
        isPresented = true
    }

    func presentScopePicker() {
        guard isPresented else { return }
        isScopePickerPresented = true
    }

    func selectScope(_ scope: FocusTaskPickerScope) {
        self.scope = scope
        isScopePickerPresented = false
    }

    func dismissScopePicker() {
        isScopePickerPresented = false
    }

    func selectTask(_ taskID: UUID?) {
        linkedTaskID = taskID
        dismiss()
    }

    func dismiss() {
        isPresented = false
        isScopePickerPresented = false
        query = ""
    }

    func handleEscape() {
        if isScopePickerPresented {
            dismissScopePicker()
        } else {
            dismiss()
        }
    }
}
