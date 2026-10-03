import SwiftUI

private struct MainWindowRailInsetKey: EnvironmentKey {
    static let defaultValue: CGFloat = 0
}

extension EnvironmentValues {
    var mainWindowRailInset: CGFloat {
        get { self[MainWindowRailInsetKey.self] }
        set { self[MainWindowRailInsetKey.self] = newValue }
    }
}
