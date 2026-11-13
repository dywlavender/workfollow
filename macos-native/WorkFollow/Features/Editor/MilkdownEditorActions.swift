import AppKit
import os
import UniformTypeIdentifiers

/// ghost 续写链路的诊断日志（`log stream --predicate 'category == "ghost"'`）。
private let ghostLog = Logger(subsystem: "com.workfollow.native", category: "ghost")

/// An asynchronous paste owns a document generation and the selection captured
/// before loading images. The JS transaction rechecks these tokens atomically.
@MainActor
struct MilkdownClipboardPasteTarget {
    let documentID: UUID
    let epoch: UUID
    let revision: Int
    let from: Int
    let to: Int

    init?(editor: MilkdownWebView) {
        guard editor.isDocumentReady, !editor.isReadOnly,
              let id = editor.documentIdentity, let selection = editor.selection,
              selection.revision == editor.revision else { return nil }
        documentID = id; epoch = editor.epoch; revision = selection.revision
        from = selection.from; to = selection.to
    }

    func matches(_ editor: MilkdownWebView) -> Bool {
        editor.isDocumentReady && !editor.isReadOnly && editor.documentIdentity == documentID
            && editor.epoch == epoch && editor.revision == revision
    }
}

extension MilkdownWebView {
    /// 选区浮条/右键菜单的 AI 动作 ID → 会话预设。总结复用 organize 的
    /// 「整理成清晰的要点」，翻译用中英互译问句。
    static func selectionIntent(for id: String) -> AIConversationPreset {
        switch id {
        case "ai.translate": .translate
        case "ai.summarize": .organize
        default: .polish
        }
    }

    func handleAction(_ name: String, payload: [String: Any]) {
        guard let context = active else { return }
        switch name {
        case "openLink":
            guard let raw = payload["url"] as? String else { return }
            if context.profile.onOpenLink?(raw) != true, let url = URL(string: raw) { NSWorkspace.shared.open(url) }
        case "copy":
            guard let wire = payload["doc"] else { return }
            do {
                let value = try JSONDecoder().decode(MilkdownDocument.self, from: JSONSerialization.data(withJSONObject: wire))
                let fragment = DocumentClipboardCodec.Fragment(document: try codec.decode(value),
                    startsAtParagraphBoundary: payload["startsAtParagraphBoundary"] as? Bool ?? payload["wholeBlocks"] as? Bool ?? false,
                    endsAtParagraphBoundary: payload["endsAtParagraphBoundary"] as? Bool ?? payload["wholeBlocks"] as? Bool ?? false)
                _ = DocumentClipboardCodec.write(fragment, to: .general)
            } catch { report(error) }
        case "paste": paste()
        case "copyLink":
            guard let url = payload["url"] as? String else { return }
            NSPasteboard.general.clearContents(); NSPasteboard.general.setString(url, forType: .string)
        case "editLink":
            guard let value = payload["selection"], let data = try? JSONSerialization.data(withJSONObject: value),
                  let target = try? JSONDecoder().decode(MilkdownSelection.self, from: data) else { return }
            editLink(selection: target)
        case "dropFiles":
            guard !isReadOnly else { return }
            for item in payload["files"] as? [[String: String]] ?? [] {
                guard let raw = item["data"].flatMap({ Data(base64Encoded: $0) }) else { continue }
                if NSImage(data: raw) != nil { insertImage(raw, name: item["name"] ?? "图片.png") }
                else {
                    do {
                        let id = UUID(), name = (item["name"] ?? "附件") as NSString
                        let stored = id.uuidString + (name.pathExtension.isEmpty ? "" : "." + name.pathExtension)
                        try FileManager.default.createDirectory(at: NativeAttachmentFiles.directory, withIntermediateDirectories: true)
                        try raw.write(to: NativeAttachmentFiles.directory.appendingPathComponent(stored), options: .atomic)
                        insertAttachmentValues([NativeAttachment(id: id, name: name.lastPathComponent, storedName: stored)])
                    } catch { report(error) }
                }
            }
        case "command":
            guard !isReadOnly, let id = payload["id"] as? String else { return }
            switch id {
            case "shared.link": editLink()
            case "shared.attachment": chooseAttachments()
            case "shared.drawio": editDiagram()
            default: context.profile.slashCommands.first { $0.id == id }?.performWeb?()
            }
        case "selectionAction":
            guard !isReadOnly, let id = payload["id"] as? String,
                  let object = payload["selection"], let data = try? JSONSerialization.data(withJSONObject: object),
                  let target = try? JSONDecoder().decode(MilkdownSelection.self, from: data) else { return }
            switch id {
            case "ai.polish", "ai.translate", "ai.summarize":
                let intent = Self.selectionIntent(for: id)
                // 笔记宿主接管时结果直接落在右侧 AI 栏，替换/插入由选区快照回写；
                // 其它宿主（任务详情等）没有这一栏，仍走独立选区浮窗。
                if let snapshot = AISelectionTarget(editor: self, selection: target),
                   context.profile.onSelectionAI?(snapshot, intent) == true { break }
                AISelectionWindowController.shared.present(editor: self, selection: target, intent: intent)
            default:
                context.profile.selectionActions.first { $0.id == id }?.perform(target.text)
            }
        case "tagInserted": if let value = payload["value"] as? String { context.profile.onTagInserted(value) }
        case "listInserted": if let value = payload["value"] as? String { context.profile.onListInserted(value) }
        case "reminder": showReminder(payload)
        case "inlineDateReminder":
            showReminder(payload, suggested: Self.suggestedDate(for: payload["text"] as? String ?? ""),
                         inlineDate: true)
        case "inlineDateReminderTask": createReminderTask(payload)
        case "ghostRequest": requestGhost(payload)
        case "editDiagram": editDiagram(id: (payload["id"] as? String).flatMap(UUID.init(uuidString:)))
        case "previewImage":
            guard let id = (payload["id"] as? String).flatMap(UUID.init(uuidString:)),
                  let raw = asset(id)?.0, let image = NSImage(data: raw) else { return }
            ImagePreviewWindowController.present(image: image, name: codec.asset(id)?.attachment?.name ?? codec.asset(id)?.diagram?.title ?? "图片")
        case "openAttachment":
            guard let id = (payload["id"] as? String).flatMap(UUID.init(uuidString:)),
                  let file = codec.asset(id)?.attachment, let url = NativeAttachmentFiles.url(for: file) else { return }
            NSWorkspace.shared.open(url)
        default: break
        }
    }

    func editLink(selection supplied: MilkdownSelection? = nil) {
        guard !isReadOnly else { return }
        let target = supplied ?? selection
        let current = target?.style.marks.first { $0.type == "link" }?.value ?? ""
        guard let value = WorkfollowDialog.prompt("编辑链接", message: "输入完整链接地址。", placeholder: "https://example.com", value: current, confirm: "保存链接"),
              let url = URL(string: value), ["https", "http", "mailto", "workfollow"].contains(url.scheme?.lowercased() ?? "") else { return }
        if target?.from == target?.to {
            _ = insert(NativeDocument(blocks: [DocumentBlock(kind: .paragraph, runs: [.init(text: value, marks: [.link(value)])])]))
        } else { perform("link", payload: ["value": value]) }
    }
    func chooseAttachments() {
        guard !isReadOnly else { return }
        let identity = documentIdentity
        NativeAttachmentFiles.choose { [weak self] result in
            guard let self, documentIdentity == identity else { return }
            switch result { case .success(let files): insertAttachmentValues(files); case .failure(let error): report(error) }
        }
    }
    func chooseImage() {
        guard !isReadOnly else { return }
        let identity = documentIdentity
        ImagePickPanel.present { [weak self] data in
            guard let self, documentIdentity == identity, let data else { return }
            insertImage(data)
        }
    }
    func insertImage(_ raw: Data, name: String = "图片.png") {
        guard !isReadOnly, NSImage(data: raw) != nil else { return }
        let data = NativeTextView.normalizedPNG(raw)
        insertAttachmentValues([NativeAttachment(id: UUID(), name: name, storedName: "data:image/png;base64," + data.base64EncodedString())])
    }
    func insertAttachmentValues(_ files: [NativeAttachment]) {
        _ = insert(NativeDocument(blocks: [DocumentBlock(kind: .paragraph, runs: files.map {
            DocumentRun(text: "\u{fffc}", attachment: $0)
        })]))
    }
    func paste(from pasteboard: NSPasteboard = .general,
               imageLoader: @escaping DocumentExternalClipboardCodec.ImageLoader = DocumentExternalClipboardCodec.loadImage) {
        guard !isReadOnly else { return }
        if let fragment = DocumentClipboardCodec.read(from: pasteboard) {
            _ = insert(fragment.document, wholeBlocks: fragment.startsAtParagraphBoundary && fragment.endsAtParagraphBoundary); return
        }
        let kind = selection.map { DocumentTextCodec.kind($0.style.blockToken) } ?? .paragraph
        // Mixed HTML must take precedence over file URLs or a single bitmap
        // published alongside it, otherwise all surrounding text/images vanish.
        if let html = pasteboard.string(forType: .html),
           let plan = DocumentExternalClipboardCodec.imagePlan(fromHTML: html, destinationKind: kind), plan.hasImages {
            guard let target = MilkdownClipboardPasteTarget(editor: self) else { return }
            _Concurrency.Task { [weak self] in
                _ = await self?.paste(plan: plan, target: target, imageLoader: imageLoader)
            }
            return
        }
        let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
        if !urls.isEmpty {
            if let callback = active?.profile.onPasteFiles { callback(urls) }
            else { do { insertAttachmentValues(try NativeAttachmentFiles.importFiles(urls)) } catch { report(error) } }
            return
        }
        if let data = pasteboard.data(forType: .png) ?? pasteboard.data(forType: .tiff) {
            insertImage(data, name: "粘贴的图片.png"); return
        }
        if let fragment = DocumentExternalClipboardCodec.read(from: pasteboard, destinationKind: kind) {
            _ = insert(fragment.document, wholeBlocks: fragment.startsAtParagraphBoundary && fragment.endsAtParagraphBoundary)
        } else if let text = pasteboard.string(forType: .string) { perform("insertText", payload: ["text": text]) }
    }
    /// Testable completion path: image failures retain their alt/link and the
    /// entire fragment is inserted through one awaited selection transaction.
    @discardableResult
    func paste(plan: DocumentExternalClipboardCodec.HTMLImagePlan, target: MilkdownClipboardPasteTarget,
               imageLoader: DocumentExternalClipboardCodec.ImageLoader = DocumentExternalClipboardCodec.loadImage) async -> Bool {
        guard target.matches(self), !_Concurrency.Task.isCancelled else { return false }
        let fragment = await plan.resolveImages(using: imageLoader)
        guard target.matches(self), !_Concurrency.Task.isCancelled else { return false }
        do {
            var wire = try object(encode(fragment.document)) as! [String: Any]
            wire["wholeBlocks"] = fragment.startsAtParagraphBoundary && fragment.endsAtParagraphBoundary
            let payload: [String: Any] = ["documentID": target.documentID.uuidString,
                "epoch": target.epoch.uuidString, "revision": target.revision,
                "from": target.from, "to": target.to, "inserting": false, "doc": wire]
            guard try await call("applySelection", payload) as? Bool == true else { return false }
            await flush()
            return documentIdentity == target.documentID && epoch == target.epoch
        } catch {
            if target.matches(self) { report(error) }
            return false
        }
    }

    func editDiagram(id: UUID? = nil) {
        guard !isReadOnly, let window else { return }
        if let diagramEditor { diagramEditor.window?.makeKeyAndOrderFront(nil); return }
        let identity = documentIdentity
        let existing = id.flatMap { id in document.blocks.flatMap(\.runs).compactMap(\.diagram).first { $0.id == id } }
        var updating = existing != nil
        let controller = DrawioEditorWindowController(diagram: existing, onSave: { [weak self] drawing in
            guard let self, identity == documentIdentity else { return false }
            let saved = await saveDiagram(drawing, updating: updating)
            if saved { updating = true }
            return saved
        }, onClose: { [weak self] in self?.diagramEditor = nil })
        diagramEditor = controller; controller.present(asSheetOf: window)
    }
    @discardableResult
    func saveDiagram(_ drawing: NativeDiagram, updating: Bool) async -> Bool {
        guard isDocumentReady, !isReadOnly else { return false }
        let identity = documentIdentity, token = epoch
        let content = NativeDocument(blocks: [DocumentBlock(kind: .paragraph, runs: [.init(text: "\u{fffc}", diagram: drawing)])])
        do {
            let wire = try encode(content)
            let payload: [String: Any]
            if updating {
                guard let embed = wire.blocks.first?.runs.first?.embed else { return false }
                payload = ["name": "updateEmbed", "payload": ["id": drawing.id.uuidString, "value": try object(embed)]]
            } else { payload = ["name": "insertFragment", "payload": ["doc": try object(wire)]] }
            guard try await call("command", payload) as? Bool == true else { return false }
            await flush()
            return documentIdentity == identity && epoch == token && document.blocks.flatMap(\.runs).contains { $0.diagram == drawing }
        } catch {
            report(error); return false
        }
    }
    func insertTable() { _ = insert(NativeDocument(blocks: [DocumentBlock(kind: .paragraph, runs: [.init(text: "\u{fffc}", table: .empty())])])) }
    func insertFormula() { _ = insert(NativeDocument(blocks: [DocumentBlock(kind: .paragraph, runs: [.init(text: "\u{fffc}", formula: NativeFormula())])])) }

    /// 行内日期词交给快速添加解析器换算成默认提醒时间；「前/之前」暂按当天处理。
    private static func suggestedDate(for text: String) -> Date? {
        guard !text.isEmpty else { return nil }
        return QuickAddParser.parse(text, now: Date(), calendar: .current, knownLists: []).dueAt
    }

    /// text.generate 被模型服务策略性拒绝（client_unauthorized）后，本轮运行
    /// 不再重复请求；超时等瞬时失败不禁用，避免冷启动第一枪误杀续写。
    /// 停顿后的短续写。走 text.generate 的裸补全，不落会话、不写文档；
    /// 结果回来时校验文档身份与请求序号，过期建议直接丢弃。
    private func requestGhost(_ payload: [String: Any]) {
        guard !ghostDisabled, !isReadOnly, let context = payload["context"] as? String,
              let request = payload["request"] as? Int,
              let documentID = payload["documentID"] as? String,
              let epochString = payload["epoch"] as? String,
              let anchor = payload["anchor"] as? Int else {
            if ghostDisabled { ghostLog.info("ghost 已禁用，忽略请求") }
            else { ghostLog.error("ghostRequest 守卫拦截 readOnly=\(self.isReadOnly) keys=\(Array(payload.keys).sorted(), privacy: .public)") }
            return
        }
        let identity = documentIdentity, expectedEpoch = epoch
        let prompt = "续写下面这段文字，只输出紧接着的一小句，不超过 25 个汉字。不要重复原文、不要解释、不要换行、不要加引号：\n" + context
        ghostLog.info("ghostRequest 收到 anchor=\(anchor) 上下文 \(context.count) 字")
        _Concurrency.Task { [weak self] in
            let text: String
            do { text = try await SummaryPiOptimizer(timeout: 15).generate(prompt: prompt) }
            catch {
                let description = String(describing: error)
                ghostLog.error("ghost AI 失败：\(description, privacy: .public)")
                if description.contains("client_unauthorized") {
                    self?.ghostDisabled = true
                    ghostLog.error("模型服务拒绝通用补全 API，本轮运行禁用 ghost 续写")
                }
                return
            }
            ghostLog.info("ghost AI 返回 \(text.count) 字")
            guard let self, self.documentIdentity == identity, self.epoch == expectedEpoch,
                  self.documentIdentity?.uuidString == documentID,
                  self.epoch.uuidString == epochString, !text.isEmpty else {
                ghostLog.error("ghost 建议过期丢弃")
                return
            }
            do {
                _ = try await self.call("applyGhost", ["text": text,
                    "documentID": documentID, "epoch": epochString,
                    "anchor": anchor, "request": request])
                ghostLog.info("applyGhost 已发送")
            } catch {
                ghostLog.error("applyGhost 失败：\(String(describing: error), privacy: .public)")
            }
        }
    }

    private func showReminder(_ payload: [String: Any], suggested: Date? = nil, inlineDate: Bool = false) {
        guard !isReadOnly, let window, let context = active,
              let id = (payload["blockID"] as? String).flatMap(UUID.init(uuidString:)),
              let index = document.blocks.firstIndex(where: { $0.id == id }),
              let rect = payload["rect"] as? [String: CGFloat] else { return }
        let height = rect["height"] ?? 20
        let webRect = NSRect(x: rect["x"] ?? 0, y: webView.bounds.height - (rect["y"] ?? 0) - height,
            width: rect["width"] ?? 20, height: height)
        let anchor = window.convertToScreen(webView.convert(webRect, to: nil))
        reminderPanel?.dismiss()
        let identity = documentIdentity
        reminderPanel = ChecklistItemReminderPanel(anchor: anchor, owner: window, now: Date(), calendar: .current,
            // 已设过的提醒优先回显；行内日期建议值只作没有提醒时的默认选中。
            current: document.blocks[index].checklist?.reminderAt ?? suggested, notice: context.profile.checklistReminderNotice(),
            onSelect: { [weak self] date in
                guard let self, documentIdentity == identity, let index = document.blocks.firstIndex(where: { $0.id == id }) else { return }
                // 行内日期流同步关联待办任务（双向同步的可见出口）；清单铃铛流
                // 保持本地提醒，不重复建任务。
                if inlineDate, let setInline = context.profile.setInlineDateReminder {
                    setInline(index, date)
                } else {
                    context.profile.setChecklistReminder(index, date)
                }
            }, onDismiss: { [weak self] in self?.reminderPanel = nil })
    }

    /// 行内日期提醒的「设置待办任务」：关联任务被删除（或移入垃圾桶）后从
    /// 悬浮菜单重建关联；提醒时间沿用块上已有的 reminderAt，走同一条
    /// `setInlineDateReminder` 幂等链路（无链接即创建，已链接只同步提醒）。
    private func createReminderTask(_ payload: [String: Any]) {
        guard !isReadOnly, let context = active,
              let id = (payload["blockID"] as? String).flatMap(UUID.init(uuidString:)),
              let index = document.blocks.firstIndex(where: { $0.id == id }) else { return }
        context.profile.setInlineDateReminder?(index, document.blocks[index].checklist?.reminderAt)
    }
}
