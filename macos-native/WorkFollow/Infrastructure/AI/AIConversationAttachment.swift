import AppKit
import Combine
import PDFKit
import UniformTypeIdentifiers

/// History stores local file references; image bytes travel only from the backend to Pi.
struct AIConversationAttachment: Identifiable, Codable, Equatable, Sendable {
    var id: UUID
    var name: String
    var path: String
    var mimeType: String
    var textPath: String?
    var isImage: Bool { mimeType.hasPrefix("image/") }
    var url: URL { URL(fileURLWithPath: path) }
    var parameters: [String: Any] {
        var value: [String: Any] = ["name": name, "path": path, "mimeType": mimeType]
        if let textPath { value["textPath"] = textPath }
        return value
    }
    var extractedText: String { textPath.flatMap { try? String(contentsOfFile: $0, encoding: .utf8) } ?? "" }
}

enum AIConversationAttachmentFiles {
    static func directory(root: URL, scene: String, id: UUID) -> URL {
        root.appendingPathComponent("attachments", isDirectory: true)
            .appendingPathComponent(scene, isDirectory: true)
            .appendingPathComponent(id.uuidString.lowercased(), isDirectory: true)
    }

    static func importFile(_ source: URL, into directory: URL) throws -> AIConversationAttachment {
        let access = source.startAccessingSecurityScopedResource()
        defer { if access { source.stopAccessingSecurityScopedResource() } }
        let id = UUID(), folder = directory.appendingPathComponent(id.uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        do {
            let type = UTType(filenameExtension: source.pathExtension)
            let isImage = type?.conforms(to: .image) == true
            let supportedImage = ["image/png", "image/jpeg", "image/webp", "image/gif"].contains(type?.preferredMIMEType ?? "")
            let destination: URL
            let mime: String
            if isImage && !supportedImage {
                destination = folder.appendingPathComponent(source.deletingPathExtension().lastPathComponent + ".png")
                try png(from: Data(contentsOf: source)).write(to: destination)
                mime = "image/png"
            } else {
                destination = folder.appendingPathComponent(source.lastPathComponent)
                try FileManager.default.copyItem(at: source, to: destination)
                mime = type?.preferredMIMEType ?? "application/octet-stream"
            }
            var attachment = AIConversationAttachment(id: id, name: source.lastPathComponent,
                path: destination.path, mimeType: mime)
            if !isImage, let text = text(from: destination, type: type), !text.isEmpty {
                let extracted = folder.appendingPathComponent("extracted.txt")
                // Avoid colliding with an original file that has this name.
                let sidecar = extracted == destination ? folder.appendingPathComponent("content.txt") : extracted
                try text.write(to: sidecar, atomically: true, encoding: .utf8)
                attachment.textPath = sidecar.path
            }
            return attachment
        } catch {
            try? FileManager.default.removeItem(at: folder)
            throw error
        }
    }

    static func importImage(_ data: Data, into directory: URL) throws -> AIConversationAttachment {
        let id = UUID(), folder = directory.appendingPathComponent(id.uuidString, isDirectory: true)
        let image = try png(from: data)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appendingPathComponent("粘贴的图片.png")
        do { try image.write(to: url) }
        catch { try? FileManager.default.removeItem(at: folder); throw error }
        return .init(id: id, name: url.lastPathComponent, path: url.path, mimeType: "image/png")
    }

    static func remove(_ values: [AIConversationAttachment]) {
        for value in values { try? FileManager.default.removeItem(at: value.url.deletingLastPathComponent()) }
    }

    private static func png(from data: Data) throws -> Data {
        guard let bitmap = NSBitmapImageRep(data: data), let png = bitmap.representation(using: .png, properties: [:]) else {
            throw SummaryPiError.failed("无法读取这张图片")
        }
        return png
    }

    private static func text(from url: URL, type: UTType?) -> String? {
        if type?.conforms(to: .pdf) == true { return PDFDocument(url: url)?.string }
        if ["rtf", "doc", "docx"].contains(url.pathExtension.lowercased()) {
            return (try? NSAttributedString(url: url, options: [:], documentAttributes: nil))?.string
        }
        let extensions = ["txt", "md", "markdown", "csv", "tsv", "json", "jsonl", "xml", "yaml", "yml", "log", "swift", "py", "js", "ts", "css"]
        guard type?.conforms(to: .text) == true || extensions.contains(url.pathExtension.lowercased()) else { return nil }
        return (try? String(contentsOf: url, encoding: .utf8)) ?? (try? String(contentsOf: url, encoding: .utf16))
    }
}

@MainActor
final class AIAttachmentDraft: ObservableObject {
    @Published private(set) var items: [AIConversationAttachment] = []
    @Published private(set) var isImporting = false
    @Published var error: String?
    let directory: URL
    private var importToken = UUID()

    init(directory: URL) { self.directory = directory }

    func add(files: [URL] = [], image: Data? = nil) {
        guard !isImporting, !files.isEmpty || image != nil else { return }
        isImporting = true; error = nil
        let token = UUID(); importToken = token
        let directory = directory
        _Concurrency.Task { [weak self] in
            let result = await _Concurrency.Task.detached(priority: .userInitiated) {
                var imported: [AIConversationAttachment] = []
                do {
                    for file in files { imported.append(try AIConversationAttachmentFiles.importFile(file, into: directory)) }
                    if let image { imported.append(try AIConversationAttachmentFiles.importImage(image, into: directory)) }
                    return Result<[AIConversationAttachment], Error>.success(imported)
                } catch {
                    AIConversationAttachmentFiles.remove(imported)
                    return .failure(error)
                }
            }.value
            guard let self, self.importToken == token else {
                if case let .success(values) = result { AIConversationAttachmentFiles.remove(values) }
                return
            }
            self.isImporting = false
            switch result {
            case let .success(values): self.items += values
            case let .failure(error): self.error = "添加附件失败：" + error.localizedDescription
            }
        }
    }

    func choose() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.item]
        panel.canChooseFiles = true; panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true; panel.prompt = "添加附件"
        let completion: (NSApplication.ModalResponse) -> Void = { [weak self] response in
            if response == .OK { self?.add(files: panel.urls) }
        }
        if let window = NSApp.keyWindow { panel.beginSheetModal(for: window, completionHandler: completion) }
        else { panel.begin(completionHandler: completion) }
    }

    func remove(_ id: UUID) {
        AIConversationAttachmentFiles.remove(items.filter { $0.id == id })
        items.removeAll { $0.id == id }
    }
    func take() -> [AIConversationAttachment] { let values = items; items = []; return values }
    func discard() {
        importToken = UUID(); isImporting = false
        AIConversationAttachmentFiles.remove(take()); error = nil
    }
}
