import SwiftUI

struct SettingsShellView: View {
    @EnvironmentObject private var environment: AppEnvironment

    var body: some View {
        Form {
            Picker("外观", selection: $environment.appearance) {
                ForEach(NativeAppearance.allCases) { appearance in
                    Text(appearance.title).tag(appearance)
                }
            }
            .pickerStyle(.segmented)
        }
        .formStyle(.grouped)
        .frame(width: 420, height: 160)
        .navigationTitle("设置")
    }
}
