import SwiftUI

struct AIConversationArtifactsView: View {
    let artifacts: [AIConversationArtifact]
    var body: some View {
        ForEach(artifacts) { artifact in
            AIMessageContent(text: display(artifact)).padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(WFColors.secondarySurface, in: RoundedRectangle(cornerRadius: 10))
        }
    }
    private func display(_ artifact: AIConversationArtifact) -> String {
        guard artifact.kind == .tasks,
              let object = try? JSONSerialization.jsonObject(with: Data(artifact.content.utf8)) as? [String: Any],
              let tasks = object["tasks"] as? [[String: Any]] else { return artifact.content }
        if tasks.isEmpty { return "没有发现新的待办。" }
        return tasks.compactMap { task in
            guard let title = task["title"] as? String else { return nil }
            let date = task["date"] as? String
            return "- " + title + (date.map { "（\($0)）" } ?? "")
        }.joined(separator: "\n")
    }
}
