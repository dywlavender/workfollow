import SwiftUI

enum NativeAppearance: String, CaseIterable, Identifiable {
    case system, light, dark
    var id: String { rawValue }
    var title: String {
        switch self {
        case .system: return "跟随系统"
        case .light: return "浅色"
        case .dark: return "深色"
        }
    }
    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

@MainActor
final class AppEnvironment: ObservableObject {
    let workspace = PreviewWorkspace()
    @Published var commandPalettePresented = false
    @Published private(set) var quickAddRequest = 0
    @Published var appearance: NativeAppearance {
        didSet { preferences.set(appearance.rawValue, forKey: "appearance") }
    }
    // Preferences and window restoration use the Native bundle's own domain.
    // No Flutter workspace store or Application Support directory is opened.
    private let preferences: UserDefaults

    init() {
        let preferences = UserDefaults.standard
        self.preferences = preferences
        appearance = NativeAppearance(rawValue:
            preferences.string(forKey: "appearance") ?? "system") ?? .system
    }

    func newTask() {
        if ![.today, .inbox].contains(workspace.destination) {
            workspace.navigate(to: .today)
        }
        workspace.select(nil)
        quickAddRequest += 1
    }
}
