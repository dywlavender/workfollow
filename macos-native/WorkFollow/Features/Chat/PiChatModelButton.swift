import SwiftUI

struct PiChatModelButton: View {
    @ObservedObject var store: MeetingStore
    var disabled: Bool
    @StateObject private var catalog = PiModelCatalog()
    @State private var query = ""
    var body: some View {
        BusinessMenu(width: 350, title: "Pi 对话模型", search: catalog.models.count > 8 ? $query : nil) {
            BusinessMenuOption("跟随 Pi 默认模型", selected: store.configuration.resolvedMinutesModel.isEmpty) { store.configuration.minutesModel = "" }
            ForEach(catalog.models.filter { $0.supportsText && (query.isEmpty || $0.menuTitle.localizedStandardContains(query)) }) { model in
                BusinessMenuOption(model.menuTitle, selected: model.id == store.configuration.resolvedMinutesModel) { store.configuration.minutesModel = model.id }
            }
            if let error = catalog.error { Text(error).font(WFType.supporting).padding(10) }
        } label: {
            HStack(spacing: 8) {
                Text(catalog.model(for: store.configuration.resolvedMinutesModel)?.title ?? (store.configuration.resolvedMinutesModel.isEmpty ? "Pi 默认模型" : store.configuration.resolvedMinutesModel))
                    .lineLimit(1).truncationMode(.middle)
                Spacer(minLength: 0)
                Image(systemName: "chevron.down").font(.system(size: 9))
            }.font(WFType.supporting).padding(12).contentShape(Rectangle())
        }.disabled(disabled || catalog.loading)
            .accessibilityLabel("Pi 对话模型")
            .task(id: store.configuration.executable) { await catalog.refresh(executable: store.configuration.executable) }
    }
}
