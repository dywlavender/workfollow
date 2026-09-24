import AppKit

enum NativeAttachmentFiles {
    static var directory: URL { NativePreviewRepository.directory.appendingPathComponent("Attachments", isDirectory: true) }

    @MainActor
    static func choose(completion: @escaping (Result<[NativeAttachment], Error>) -> Void) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        panel.prompt = "添加附件"
        panel.begin { response in
            guard response == .OK else { return }
            do {
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                var attachments: [NativeAttachment] = []
                for url in panel.urls {
                    let access = url.startAccessingSecurityScopedResource()
                    defer { if access { url.stopAccessingSecurityScopedResource() } }
                    let id = UUID()
                    let storedName = id.uuidString + (url.pathExtension.isEmpty ? "" : "." + url.pathExtension)
                    try FileManager.default.copyItem(at: url, to: directory.appendingPathComponent(storedName))
                    attachments.append(NativeAttachment(id: id, name: url.lastPathComponent, storedName: storedName))
                }
                completion(.success(attachments))
            } catch { completion(.failure(error)) }
        }
    }

    static func url(for attachment: NativeAttachment) -> URL? {
        guard attachment.storedName == (attachment.storedName as NSString).lastPathComponent else { return nil }
        return directory.appendingPathComponent(attachment.storedName)
    }
}
