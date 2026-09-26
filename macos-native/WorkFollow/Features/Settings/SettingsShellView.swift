import SwiftUI

struct SettingsShellView: View {
    @EnvironmentObject private var environment: AppEnvironment

    var body: some View {
        TabView {
            Form {
                Picker("外观", selection: $environment.appearance) {
                    ForEach(NativeAppearance.allCases) { appearance in
                        Text(appearance.title).tag(appearance)
                    }
                }
                .pickerStyle(.segmented)
            }
            .formStyle(.grouped)
            .tabItem { Label("通用", systemImage: "gearshape") }

            SettingsDataView()
                .tabItem { Label("数据", systemImage: "externaldrive") }
        }
        .frame(width: 420, height: 620)
        .navigationTitle("设置")
    }
}
