import AppKit

extension NativeTextView {
    @objc func editDocumentLink(_ sender: Any?) {
        guard isEditable else { return }
        var range = selectedRange()
        let alert = NSAlert()
        alert.messageText = "编辑链接"
        alert.informativeText = "输入 https://、http:// 或 mailto: 地址。未选中文字时插入地址本身。"
        let input = NSTextField(frame: NSRect(x: 0, y: 0, width: 320, height: 26))
        input.placeholderString = "https://example.com"
        var linkRange = NSRange(location: 0, length: 0)
        if range.location < attributedString().length,
           let link = attributedString().attribute(.link, at: range.location, effectiveRange: &linkRange) {
            input.stringValue = String(describing: link)
            if range.length == 0 { range = linkRange }
        }
        alert.accessoryView = input
        alert.addButton(withTitle: "确定")
        alert.addButton(withTitle: "取消")
        alert.window.initialFirstResponder = input
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let value = input.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: value), ["https", "http", "mailto"].contains(url.scheme?.lowercased() ?? "") else {
            let warning = NSAlert()
            warning.messageText = "链接地址无效"
            warning.informativeText = "请使用包含 https://、http:// 或 mailto: 的完整地址。"
            warning.runModal()
            return
        }
        setDocumentLink(url.absoluteString, range: range)
    }

    func setDocumentLink(_ target: String, range: NSRange) {
        guard NSMaxRange(range) <= attributedString().length else { return }
        let value = range.length == 0
            ? NSMutableAttributedString(string: target, attributes: typingAttributes)
            : NSMutableAttributedString(attributedString: attributedString().attributedSubstring(from: range))
        value.addAttribute(.link, value: target, range: NSRange(location: 0, length: value.length))
        replaceRichContent(value, range: range)
        typingAttributes.removeValue(forKey: .link)
    }

    @objc func removeDocumentLink(_ sender: Any?) {
        guard isEditable else { return }
        var range = selectedRange()
        let source = attributedString()
        if range.length == 0, range.location < source.length {
            guard source.attribute(.link, at: range.location, effectiveRange: &range) != nil else { return }
        }
        guard range.length > 0, NSMaxRange(range) <= source.length else { return }
        let value = NSMutableAttributedString(attributedString: source.attributedSubstring(from: range))
        value.removeAttribute(.link, range: NSRange(location: 0, length: value.length))
        replaceRichContent(value, range: range)
        setSelectedRange(range)
        typingAttributes.removeValue(forKey: .link)
    }

    /// Attribute removal must not inherit attributes from the replaced text.
    private func replaceRichContent(_ value: NSAttributedString, range: NSRange) {
        guard let storage = textStorage, NSMaxRange(range) <= storage.length,
              shouldChangeText(in: range, replacementString: value.string) else { return }
        let previous = storage.attributedSubstring(from: range)
        undoManager?.registerUndo(withTarget: self) { view in
            view.replaceRichContent(previous, range: NSRange(location: range.location, length: value.length))
        }
        storage.replaceCharacters(in: range, with: value)
        setSelectedRange(NSRange(location: range.location + value.length, length: 0))
        didChangeText()
    }

    @objc func insertDocumentAttachment(_ sender: Any?) {
        guard isEditable else { return }
        let identity = documentIdentity
        NativeAttachmentFiles.choose { [weak self] result in
            guard let self, self.documentIdentity == identity else { return }
            switch result {
            case .success(let files): self.insertAttachments(files)
            case .failure(let error):
                let alert = NSAlert(error: error)
                alert.runModal()
            }
        }
    }

    func insertAttachments(_ files: [NativeAttachment]) {
        guard !files.isEmpty else { return }
        let runs = files.flatMap { [DocumentRun(text: "\u{FFFC}", attachment: $0), DocumentRun(text: " ")] }
        let content = NativeDocument(blocks: [DocumentBlock(kind: .paragraph, runs: runs)])
        insertText(DocumentTextCodec.render(content), replacementRange: selectedRange())
        typingAttributes = DocumentTextCodec.attributes(kind: .paragraph, marks: [])
    }
}
