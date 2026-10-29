import Foundation

enum MeetingTranscriptSearch {
    static func matches(_ line: MeetingTranscriptLine, query: String) -> Bool {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return query.isEmpty || (line.speakerDisplayName + " " + line.text).localizedCaseInsensitiveContains(query)
            || KnowledgeCorpus.timestamp(line.offset).contains(query)
    }
}
