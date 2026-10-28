import AppKit
import CoreText

/// 公式排版：解析 LaTeX 的常用排版子集（分式 / 根号 / 上下标 / 希腊字母 /
/// 常用运算符），按基线组合成一张 NSImage。不做完整 TeX。
enum FormulaTypesetter {
    static let padding: CGFloat = 7

    static func measuredSize(_ latex: String, fontSize: CGFloat = 17) -> NSSize {
        let box = layout(parse(latex), size: fontSize)
        return NSSize(width: ceil(max(8, box.width + padding * 2)),
                      height: ceil(max(18, box.ascent + box.descent + padding * 2)))
    }

    /// 渲染成 2x 位图后把 `size` 设回逻辑尺寸：附件单元按点绘制，Retina 下仍清晰。
    static func image(for latex: String, fontSize: CGFloat = 17, scale: CGFloat = 2,
                      appearance: NSAppearance? = nil) -> NSImage? {
        let raw = parse(latex)
        let box = layout(raw, size: fontSize * scale)
        let logical = NSSize(width: ceil(max(8, box.width / scale + padding * 2)),
                             height: ceil(max(18, (box.ascent + box.descent) / scale + padding * 2)))
        let pixel = NSSize(width: logical.width * scale, height: logical.height * scale)
        guard pixel.width > 0, pixel.height > 0, pixel.width < 4000, pixel.height < 2000 else { return nil }
        let image = NSImage(size: pixel)
        // labelColor 是动态色：位图必须按请求时的外观解析，否则深色模式会烘成黑字。
        let previous = NSAppearance.current
        if let appearance { NSAppearance.current = appearance }
        image.lockFocus()
        box.draw(padding * scale, padding * scale + box.descent)
        image.unlockFocus()
        NSAppearance.current = previous
        image.size = logical
        return image
    }

    // MARK: - 节点

    private indirect enum Node {
        case symbol(String)
        case text(String)
        case space
        case sequence([Node])
        case script(Node, Node?, Node?)
        case fraction(Node, Node)
        case sqrt(Node)
    }

    private struct Box {
        var width: CGFloat
        var ascent: CGFloat
        var descent: CGFloat
        /// 在非翻转坐标里，以 (x, baselineY) 为基线起点绘制。
        var draw: (CGFloat, CGFloat) -> Void

        static let empty = Box(width: 0, ascent: 0, descent: 0, draw: { _, _ in })

        static func + (lhs: Box, rhs: Box) -> Box {
            Box(width: lhs.width + rhs.width,
                ascent: max(lhs.ascent, rhs.ascent),
                descent: max(lhs.descent, rhs.descent)) { x, baseline in
                lhs.draw(x, baseline)
                rhs.draw(x + lhs.width, baseline)
            }
        }

        func padded(_ horizontal: CGFloat) -> Box {
            Box(width: width + horizontal * 2, ascent: ascent, descent: descent) { x, baseline in
                draw(x + horizontal, baseline)
            }
        }
    }

    // MARK: - 解析

    private static let greek: [String: String] = [
        "alpha": "α", "beta": "β", "gamma": "γ", "delta": "δ", "epsilon": "ε",
        "varepsilon": "ε", "zeta": "ζ", "eta": "η", "theta": "θ", "lambda": "λ",
        "mu": "μ", "nu": "ν", "xi": "ξ", "pi": "π", "rho": "ρ", "sigma": "σ",
        "tau": "τ", "phi": "φ", "chi": "χ", "psi": "ψ", "omega": "ω",
        "Gamma": "Γ", "Delta": "Δ", "Theta": "Θ", "Lambda": "Λ", "Pi": "Π",
        "Sigma": "Σ", "Phi": "Φ", "Psi": "Ψ", "Omega": "Ω"
    ]

    private static let operators: [String: String] = [
        "cdot": "·", "times": "×", "div": "÷", "pm": "±", "mp": "∓",
        "le": "≤", "leq": "≤", "ge": "≥", "geq": "≥", "ne": "≠", "neq": "≠",
        "approx": "≈", "equiv": "≡", "infty": "∞", "sum": "∑", "int": "∫",
        "partial": "∂", "nabla": "∇", "to": "→", "rightarrow": "→",
        "leftarrow": "←", "Rightarrow": "⇒", "cdots": "⋯", "ldots": "…",
        "angle": "∠", "perp": "⊥", "parallel": "∥", "degree": "°"
    ]

    private static let binaryOperators: Set<String> = [
        "=", "+", "-", "<", ">", "≤", "≥", "≠", "≈", "±", "×", "·", "÷", "→", "←", "⇒", "≡"
    ]

    private struct Parser {
        let characters: [Character]
        var index = 0

        init(_ source: String) { characters = Array(source) }

        mutating func parseSequence(stopAtBrace: Bool) -> [Node] {
            var nodes: [Node] = []
            while let character = peek() {
                if character == "}" {
                    if stopAtBrace { index += 1; break }
                    index += 1
                    continue
                }
                if let node = parseScripted() {
                    nodes.append(node)
                } else {
                    index += 1
                }
            }
            return nodes
        }

        mutating func parseScripted() -> Node? {
            guard let base = parseAtom() else { return nil }
            var superscript: Node?
            var subscriptNode: Node?
            while let character = peek(), character == "^" || character == "_" {
                index += 1
                let target = parseArgument()
                if character == "^" { superscript = target } else { subscriptNode = target }
            }
            if superscript == nil, subscriptNode == nil { return base }
            return .script(base, superscript, subscriptNode)
        }

        mutating func parseArgument() -> Node {
            if peek() == "{" { return parseAtom() ?? .sequence([]) }
            return parseAtom() ?? .space
        }

        mutating func parseAtom() -> Node? {
            guard let character = peek() else { return nil }
            if character == "{" {
                index += 1
                return .sequence(parseSequence(stopAtBrace: true))
            }
            if character == "\\" { return parseCommand() }
            if character == "}" { return nil }
            if character == " " || character == "\n" { index += 1; return .space }
            if character == "^" || character == "_" { index += 1; return nil }
            index += 1
            return .symbol(String(character))
        }

        mutating private func parseCommand() -> Node? {
            index += 1
            var name = ""
            while let character = peek(), character.isLetter {
                name.append(character)
                index += 1
            }
            if name.isEmpty {
                guard let character = peek() else { return nil }
                index += 1
                switch character {
                case ",", ";", ":", " ": return .space
                case "\\": return .space
                default: return .symbol(String(character))
                }
            }
            switch name {
            case "frac":
                return .fraction(parseArgument(), parseArgument())
            case "sqrt":
                return .sqrt(parseArgument())
            case "text", "mathrm", "operatorname":
                return .text(parseRawGroup())
            case "quad", "qquad":
                return .space
            case "left", "right":
                return parseAtom()
            case "mathbf", "mathcal":
                return parseArgument()
            default:
                if let symbol = greek[name] { return .symbol(symbol) }
                if let symbol = operators[name] { return .symbol(symbol) }
                return .text("\\" + name)
            }
        }

        mutating private func parseRawGroup() -> String {
            guard peek() == "{" else { return "" }
            index += 1
            var text = ""
            var depth = 1
            while let character = peek() {
                index += 1
                if character == "{" { depth += 1 }
                else if character == "}" { depth -= 1; if depth == 0 { break } }
                text.append(character)
            }
            return text
        }

        private func peek() -> Character? {
            index < characters.count ? characters[index] : nil
        }
    }

    private static func parse(_ source: String) -> [Node] {
        var parser = Parser(source)
        return parser.parseSequence(stopAtBrace: false)
    }

    // MARK: - 排版

    private static func layout(_ nodes: [Node], size: CGFloat) -> Box {
        nodes.map { layout($0, size: size) }.reduce(.empty, +)
    }

    private static func layout(_ node: Node, size: CGFloat) -> Box {
        switch node {
        case .space:
            return Box(width: size * 0.22, ascent: 0, descent: 0, draw: { _, _ in })
        case .text(let value):
            return textBox(value, size: size, italic: false)
        case .symbol(let value):
            let italic = value.count == 1 && value.rangeOfCharacter(from: .letters) != nil
            var box = textBox(value, size: size, italic: italic)
            if binaryOperators.contains(value) { box = box.padded(size * 0.16) }
            return box
        case .sequence(let children):
            return layout(children, size: size)
        case .script(let base, let superscript, let subscriptNode):
            return scriptBox(base: layout(base, size: size),
                             superscript: superscript.map { layout($0, size: size * 0.66) },
                             subscriptNode: subscriptNode.map { layout($0, size: size * 0.66) },
                             size: size)
        case .fraction(let numerator, let denominator):
            return fractionBox(layout(numerator, size: size * 0.86),
                               layout(denominator, size: size * 0.86), size: size)
        case .sqrt(let content):
            return sqrtBox(layout(content, size: size * 0.95), size: size)
        }
    }

    private static func textBox(_ text: String, size: CGFloat, italic: Bool) -> Box {
        guard !text.isEmpty else { return .empty }
        let font = mathFont(size: size, italic: italic)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.labelColor
        ]
        // 用 CoreText 按**基线**绘制：NSString.draw(at:) 的行片段原点随翻转上下文
        // 变化，分式的分子/分母会整体下沉（实测分数线穿过分子、分母被裁）。
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: attributes))
        var ascent: CGFloat = 0
        var descent: CGFloat = 0
        var leading: CGFloat = 0
        let width = CGFloat(CTLineGetTypographicBounds(line, &ascent, &descent, &leading))
        return Box(width: ceil(width), ascent: ascent, descent: max(0, descent)) { x, baseline in
            guard let context = NSGraphicsContext.current?.cgContext else { return }
            context.saveGState()
            context.textMatrix = .identity
            context.textPosition = CGPoint(x: x, y: baseline)
            CTLineDraw(line, context)
            context.restoreGState()
        }
    }

    private static func mathFont(size: CGFloat, italic: Bool) -> NSFont {
        var font = NSFont.systemFont(ofSize: size)
        if italic { font = NSFontManager.shared.convert(font, toHaveTrait: .italicFontMask) }
        if let descriptor = font.fontDescriptor.withDesign(.serif),
           let serif = NSFont(descriptor: descriptor, size: size) {
            font = serif
        }
        return font
    }

    private static func scriptBox(base: Box, superscript: Box?, subscriptNode: Box?,
                                  size: CGFloat) -> Box {
        let gap: CGFloat = 2
        let rise = size * 0.38
        let drop = size * 0.16
        let scriptWidth = max(superscript?.width ?? 0, subscriptNode?.width ?? 0)
        let ascent = max(base.ascent, (superscript?.ascent ?? 0) + rise)
        let descent = max(base.descent, (subscriptNode?.descent ?? 0) + drop)
        return Box(width: base.width + gap + scriptWidth, ascent: ascent, descent: descent) {
            x, baseline in
            base.draw(x, baseline)
            superscript?.draw(x + base.width + gap, baseline + rise)
            subscriptNode?.draw(x + base.width + gap, baseline - drop)
        }
    }

    private static func fractionBox(_ numerator: Box, _ denominator: Box, size: CGFloat) -> Box {
        let gap: CGFloat = size * 0.2
        let width = max(numerator.width, denominator.width) + size * 0.5
        let ascent = numerator.ascent + numerator.descent + gap
        let descent = denominator.ascent + denominator.descent + gap
        return Box(width: width, ascent: ascent, descent: descent) { x, baseline in
            numerator.draw(x + (width - numerator.width) / 2, baseline + gap + numerator.descent)
            denominator.draw(x + (width - denominator.width) / 2, baseline - gap - denominator.ascent)
            let rule = NSBezierPath()
            rule.move(to: NSPoint(x: x, y: baseline))
            rule.line(to: NSPoint(x: x + width, y: baseline))
            rule.lineWidth = max(0.8, size * 0.06)
            NSColor.labelColor.setStroke()
            rule.stroke()
        }
    }

    private static func sqrtBox(_ content: Box, size: CGFloat) -> Box {
        let radical = textBox("√", size: size * 1.25, italic: false)
        let offset = radical.width * 0.72
        let width = offset + content.width + size * 0.2
        let ascent = max(content.ascent + size * 0.18, radical.ascent)
        return Box(width: width, ascent: ascent, descent: content.descent) { x, baseline in
            radical.draw(x, baseline - size * 0.04)
            content.draw(x + offset, baseline)
            let top = baseline + content.ascent + size * 0.16
            let rule = NSBezierPath()
            rule.move(to: NSPoint(x: x + offset, y: top))
            rule.line(to: NSPoint(x: x + width, y: top))
            rule.lineWidth = max(0.8, size * 0.06)
            NSColor.labelColor.setStroke()
            rule.stroke()
        }
    }
}

/// 正文里的公式附件单元：居中绘制渲染结果，双击进入公式编辑窗。
final class DocumentFormulaCell: NSTextAttachmentCell {
    let formula: NativeFormula
    private var renderedImage: NSImage?
    private var renderedAppearance: NSAppearance.Name?
    private let logicalSize: NSSize

    init(formula: NativeFormula) {
        self.formula = formula
        logicalSize = FormulaTypesetter.measuredSize(formula.latex)
        super.init(textCell: "")
    }

    required init(coder: NSCoder) { fatalError("DocumentFormulaCell is a document projection") }

    override func cellSize() -> NSSize { logicalSize }

    override func draw(withFrame frame: NSRect, in controlView: NSView?) {
        let fallback = NSAppearance(named: .aqua) ?? NSAppearance(named: .darkAqua)!
        let appearance = controlView?.effectiveAppearance ?? NSAppearance.current ?? fallback
        if renderedAppearance != appearance.name {
            renderedAppearance = appearance.name
            renderedImage = FormulaTypesetter.image(for: formula.latex, appearance: appearance)
        }
        let rect = NSRect(x: frame.minX,
                          y: frame.midY - logicalSize.height / 2,
                          width: logicalSize.width,
                          height: logicalSize.height)
        if let image = renderedImage {
            NSGraphicsContext.current?.imageInterpolation = .high
            image.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1,
                       respectFlipped: true, hints: nil)
        } else {
            let fallback = formula.latex as NSString
            fallback.draw(in: rect, withAttributes: [
                .font: NSFont.monospacedSystemFont(ofSize: 13, weight: .regular),
                .foregroundColor: NSColor.labelColor
            ])
        }
    }
}
