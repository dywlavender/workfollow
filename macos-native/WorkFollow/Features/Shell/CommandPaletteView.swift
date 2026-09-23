import SwiftUI

struct CommandPaletteView: View {
    @ObservedObject var workspace: PreviewWorkspace
    @EnvironmentObject private var environment: AppEnvironment
    @State private var query = ""
    @FocusState private var focused: Bool

    private var destinations: [NativeDestination] {
        NativeDestination.allCases.filter { query.isEmpty || $0.title.localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: WFSpace.md) {
            HStack {
                Image(systemName: "magnifyingglass")
                TextField("搜索页面", text: $query).textFieldStyle(.plain)
                    .focused($focused).onSubmit { if let first = destinations.first { navigate(first) } }
                Button("取消") { environment.commandPalettePresented = false }
                    .keyboardShortcut(.cancelAction)
            }.padding(WFSpace.lg)
            Divider()
            ScrollView {
                VStack(spacing: WFSpace.xs) {
                    ForEach(destinations) { destination in
                        Button { navigate(destination) } label: {
                            Label(destination == .notesTrash ? "笔记垃圾桶" : destination.title,
                                  systemImage: destination.symbol)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(WFSpace.md).contentShape(Rectangle())
                        }.buttonStyle(.plain)
                    }
                }
            }
        }
        .frame(minWidth: 280, idealWidth: 400, maxWidth: 440,
               minHeight: 300, idealHeight: 390, maxHeight: 420)
        .onAppear { focused = true }
    }

    private func navigate(_ destination: NativeDestination) {
        workspace.navigate(to: destination)
        environment.commandPalettePresented = false
    }
}
