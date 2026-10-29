import AppKit

/// 公式编辑窗：输入 LaTeX，下方实时预览，保存后写回正文附件。
@MainActor
final class FormulaEditorWindowController: NSWindowController, NSWindowDelegate {
    private let input = NSTextField(string: "")
    private let preview = FormulaPreviewView()
    private let status = NSTextField(labelWithString: "")
    private let saveButton = NSButton(title: "插入公式", target: nil, action: nil)
    private let cancelButton = NSButton(title: "取消", target: nil, action: nil)
    private let formulaID: UUID
    private let onSave: (NativeFormula) -> Bool
    private let onClose: () -> Void
    private var hasClosed = false

    init(formula: NativeFormula?, onSave: @escaping (NativeFormula) -> Bool,
         onClose: @escaping () -> Void) {
        self.onSave = onSave
        self.onClose = onClose
        formulaID = formula?.id ?? UUID()
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 520, height: 300),
                              styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = formula == nil ? "插入公式" : "编辑公式"
        window.isReleasedWhenClosed = false
        super.init(window: window)
        window.delegate = self

        input.stringValue = formula?.latex ?? ""
        input.placeholderString = #"例如：\frac{a}{b} + \sqrt{x^2 + y^2}"#
        input.font = .monospacedSystemFont(ofSize: 13, weight: .regular)
        input.focusRingType = .none
        input.target = self
        input.action = #selector(saveFormula)
        NotificationCenter.default.addObserver(self, selector: #selector(inputChanged),
                                               name: NSControl.textDidChangeNotification, object: input)

        status.font = .systemFont(ofSize: 11)
        status.textColor = .secondaryLabelColor
        status.stringValue = #"支持 \frac \sqrt 上下标 ^ _ 与常用希腊字母；留空则不插入。"#

        saveButton.target = self
        saveButton.action = #selector(saveFormula)
        saveButton.bezelStyle = .rounded
        saveButton.focusRingType = .none
        saveButton.title = formula == nil ? "插入公式" : "保存公式"
        cancelButton.target = self
        cancelButton.action = #selector(cancel)
        cancelButton.bezelStyle = .rounded
        cancelButton.focusRingType = .none
        cancelButton.keyEquivalent = "\u{1b}"
        saveButton.keyEquivalent = "\r"

        let hint = NSTextField(labelWithString: "LaTeX")
        hint.font = .systemFont(ofSize: 11, weight: .medium)
        hint.textColor = .secondaryLabelColor
        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let buttons = NSStackView(views: [spacer, cancelButton, saveButton])
        buttons.spacing = 8

        let root = NSView()
        window.contentView = root
        for view in [hint, input, status, preview, buttons] {
            view.translatesAutoresizingMaskIntoConstraints = false
            root.addSubview(view)
        }
        NSLayoutConstraint.activate([
            hint.topAnchor.constraint(equalTo: root.topAnchor, constant: 14),
            hint.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 16),
            input.topAnchor.constraint(equalTo: hint.bottomAnchor, constant: 6),
            input.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 16),
            input.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -16),
            input.heightAnchor.constraint(equalToConstant: 26),
            preview.topAnchor.constraint(equalTo: input.bottomAnchor, constant: 12),
            preview.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 16),
            preview.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -16),
            preview.heightAnchor.constraint(equalToConstant: 120),
            status.topAnchor.constraint(equalTo: preview.bottomAnchor, constant: 8),
            status.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 16),
            status.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -16),
            buttons.topAnchor.constraint(equalTo: status.bottomAnchor, constant: 10),
            buttons.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 16),
            buttons.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -16),
            buttons.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -14)
        ])
        preview.latex = input.stringValue
    }

    required init?(coder: NSCoder) { fatalError("Use init(formula:onSave:onClose:)") }

    func present(asSheetOf parent: NSWindow) {
        guard let window else { return }
        parent.beginSheet(window) { [weak self] _ in self?.finishClose() }
        DispatchQueue.main.async { [weak self] in
            guard let self, let window = self.window else { return }
            window.makeFirstResponder(self.input)
        }
    }

    @objc private func inputChanged() {
        preview.latex = input.stringValue
        status.textColor = .secondaryLabelColor
        status.stringValue = #"支持 \frac \sqrt 上下标 ^ _ 与常用希腊字母；留空则不插入。"#
    }

    @objc private func saveFormula() {
        let latex = input.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !latex.isEmpty else {
            status.textColor = .systemRed
            status.stringValue = "请输入公式内容。"
            return
        }
        guard onSave(NativeFormula(id: formulaID, latex: latex)) else {
            status.textColor = .systemRed
            status.stringValue = "正文已变化，公式未能保存，请重试。"
            return
        }
        close()
    }

    @objc private func cancel() { close() }

    func windowShouldClose(_ sender: NSWindow) -> Bool { true }
    func windowWillClose(_ notification: Notification) { finishClose() }

    override func close() {
        guard let window, let parent = window.sheetParent else { super.close(); finishClose(); return }
        parent.endSheet(window)
        super.close()
    }

    private func finishClose() {
        guard !hasClosed else { return }
        hasClosed = true
        NotificationCenter.default.removeObserver(self)
        onClose()
    }
}

/// 预览：把公式渲染成图片居中画在白底卡片里。
final class FormulaPreviewView: NSView {
    var latex: String = "" {
        didSet { cached = nil; needsDisplay = true }
    }
    private var cached: NSImage?

    override var isFlipped: Bool { true }
    override var isOpaque: Bool { false }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        cached = nil
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        let card = bounds.insetBy(dx: 1, dy: 1)
        let path = NSBezierPath(roundedRect: card, xRadius: 8, yRadius: 8)
        NSColor.textBackgroundColor.setFill()
        path.fill()
        NSColor.separatorColor.setStroke()
        path.lineWidth = 1
        path.stroke()
        let trimmed = latex.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            let hint = "在此预览公式" as NSString
            let size = hint.size(withAttributes: [.font: NSFont.systemFont(ofSize: 12)])
            hint.draw(at: NSPoint(x: card.midX - size.width / 2, y: card.midY - size.height / 2),
                      withAttributes: [.font: NSFont.systemFont(ofSize: 12),
                                       .foregroundColor: NSColor.tertiaryLabelColor])
            return
        }
        if cached == nil {
            cached = FormulaTypesetter.image(for: trimmed, fontSize: 20, appearance: effectiveAppearance)
        }
        guard let image = cached else { return }
        let maxSize = NSSize(width: card.width - 24, height: card.height - 24)
        let ratio = min(1, min(maxSize.width / max(1, image.size.width),
                               maxSize.height / max(1, image.size.height)))
        let size = NSSize(width: image.size.width * ratio, height: image.size.height * ratio)
        let rect = NSRect(x: card.midX - size.width / 2, y: card.midY - size.height / 2,
                          width: size.width, height: size.height)
        image.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1,
                   respectFlipped: true, hints: nil)
    }
}
