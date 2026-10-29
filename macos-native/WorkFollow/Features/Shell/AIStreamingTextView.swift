import SwiftUI

struct AIStreamingTextView: View {
    let text: String
    let status: String

    var body: some View {
        VStack(alignment: text.isEmpty ? .center : .leading, spacing: 12) {
            HStack(spacing: 10) {
                ProgressView().controlSize(.small)
                Text(status).font(WFType.supporting).foregroundStyle(WFColors.secondaryText)
            }.padding(.horizontal, 20).padding(.top, text.isEmpty ? 0 : 16)
            if !text.isEmpty {
                ScrollView {
                    Text(text).font(WFType.body).textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading).padding(20)
                }.compactScrollbars()
            }
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
