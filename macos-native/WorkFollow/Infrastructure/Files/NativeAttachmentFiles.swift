import AppKit
import UniformTypeIdentifiers

/// 拖放进来的文件（`NSItemProvider`）→ 本地 URL。抽出来是因为它是**唯一**一段
/// 需要异步跨 provider 收集的逻辑：详情拖放和以后的"粘贴文件"都走它。
enum AttachmentDropImport {
    /// 收集完成后在主队列回调；没有任何文件 URL 时回调空数组。
    /// 结果**保持拖入顺序**：每个 provider 按文件序号落槽，异步完成顺序不影响结果。
    static func collect(from providers: [NSItemProvider],
                        completion: @escaping ([URL]) -> Void) {
        final class Collected: @unchecked Sendable {
            private let lock = NSLock()
            private var slots: [Int: URL] = [:]
            func set(_ url: URL, at index: Int) { lock.lock(); slots[index] = url; lock.unlock() }
            func snapshot() -> [URL] {
                lock.lock(); defer { lock.unlock() }
                return slots.keys.sorted().compactMap { slots[$0] }
            }
        }
        let collected = Collected()
        let group = DispatchGroup()
        let fileProviders = providers.filter {
            $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier)
        }
        for (index, provider) in fileProviders.enumerated() {
            group.enter()
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                defer { group.leave() }
                let url: URL?
                if let data = item as? Data {
                    url = URL(dataRepresentation: data, relativeTo: nil)
                } else if let value = item as? URL {
                    url = value
                } else if let string = item as? String {
                    url = URL(string: string)
                } else {
                    url = nil
                }
                if let url { collected.set(url, at: index) }
            }
        }
        group.notify(queue: .main) { completion(collected.snapshot()) }
    }
}

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
            do { completion(.success(try importFiles(panel.urls))) }
            catch { completion(.failure(error)) }
        }
    }

    /// 外部来源（拖放 / 粘贴）导入附件：与选择面板共用同一套落盘规则
    /// （UUID 文件名 + 原扩展名，保留原名展示）。
    @MainActor
    @discardableResult
    static func importFiles(_ urls: [URL]) throws -> [NativeAttachment] {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var attachments: [NativeAttachment] = []
        for url in urls {
            let access = url.startAccessingSecurityScopedResource()
            defer { if access { url.stopAccessingSecurityScopedResource() } }
            let id = UUID()
            let storedName = id.uuidString + (url.pathExtension.isEmpty ? "" : "." + url.pathExtension)
            try FileManager.default.copyItem(at: url, to: directory.appendingPathComponent(storedName))
            attachments.append(NativeAttachment(id: id, name: url.lastPathComponent, storedName: storedName))
        }
        return attachments
    }

    static func url(for attachment: NativeAttachment) -> URL? {
        guard attachment.storedName == (attachment.storedName as NSString).lastPathComponent else { return nil }
        return directory.appendingPathComponent(attachment.storedName)
    }
}
