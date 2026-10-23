import AppKit

/// 代码块语法着色（本地轻量实现）。
///
/// 滴答用 `Highlightr`（内置 highlight.js 185 种语言 + `ticktick.light/dark.css`），
/// 本地不引外部依赖，只做一个"够用"的 tokenizer：注释 / 字符串 / 数字 / 关键字 /
/// 类型名 / 函数名。配色直接取滴答 `ticktick.light.css` / `ticktick.dark.css`
/// 的同角色值，保证两边的代码块看起来是同一套。
///
/// **只影响绘制**：结果写进 `.foregroundColor`，不参与 `DocumentTextCodec.decode`
/// （解码只看 `blockKey` / `inlineCodeKey` / 字体 trait），所以不会污染存储格式。
enum CodeSyntaxHighlighter {

    enum Token: Equatable {
        case plain, comment, string, number, keyword, type, function
    }

    /// 滴答 CSS 的角色映射（light / dark）：
    /// - `.hljs-keyword` → #FF871D / #C4742E
    /// - `.hljs-string` → #14C257 / #319A59
    /// - `.hljs-number` → #EF42B5 / #B4317E
    /// - `.hljs-comment` → #B8B8B8 / #535353
    /// - `.hljs-type/.hljs-title` → #14C257 / #319A59
    /// - `.hljs-variable/.hljs-selector-id` → #FF871D / #3F62BF
    static func color(for token: Token, appearance: NSAppearance) -> NSColor? {
        let dark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        func hex(_ light: UInt32, _ darkValue: UInt32) -> NSColor {
            let value = dark ? darkValue : light
            return NSColor(srgbRed: CGFloat((value >> 16) & 0xFF) / 255,
                           green: CGFloat((value >> 8) & 0xFF) / 255,
                           blue: CGFloat(value & 0xFF) / 255, alpha: 1)
        }
        switch token {
        case .plain: return nil
        case .keyword: return hex(0xFF871D, 0xC4742E)
        case .string: return hex(0x14C257, 0x319A59)
        case .number: return hex(0xEF42B5, 0xB4317E)
        case .comment: return hex(0xB8B8B8, 0x535353)
        case .type, .function: return hex(0x14C257, 0x319A59)
        }
    }

    // MARK: - 语言识别

    enum Language: Equatable {
        case swift, javascript, python, shell, sql, json, generic

        /// 语言按**内容特征**猜：`NativeDocument` 的代码块不带语言字段，加一个
        /// 字段就要动存储格式（本批不做），所以用几条高置信度的信号判断；
        /// 认不出就按 `generic`（只着色注释/字符串/数字，不猜关键字）。
        ///
        /// 这是"看着像"的着色，不是编译器级解析——错判的代价只是颜色不同，
        /// 不影响文字、光标与存储。
        static func detect(in text: String) -> Language {
            let sample = String(text.prefix(4000))
            let lower = sample.lowercased()
            func has(_ needles: String...) -> Bool { needles.contains { lower.contains($0) } }

            // 顺序按"信号强度"排：先排除最独特的，再落到宽泛的。
            if has("#!/bin/", "#!/usr/bin/", "#!/bin/bash", "#!/bin/zsh") { return .shell }
            if let first = sample.trimmingCharacters(in: .whitespacesAndNewlines).first,
               first == "{" || first == "[",
               (try? JSONSerialization.jsonObject(with: Data(sample.utf8))) != nil {
                return .json
            }
            if has("select ", "insert into ", "create table ") || (has(" from ") && has(" where ")) {
                return .sql
            }
            if has("func ", "guard let ", "import swiftui", "import foundation", "import appkit") { return .swift }
            // Python：`def x():` 加缩进块，且没有大括号块语言的分号
            if has("def ") || has("import ", "from ") && has(":\n", "self.") {
                let braceBlocks = has("};", ") {", "} else {")
                if !braceBlocks, has("def ") || has("self.", "elif ") { return .python }
            }
            if has("function ", "=>", "console.log", "require(", "export default", "const ") { return .javascript }
            if has("echo ", "sudo ") { return .shell }
            return .generic
        }

        var keywords: Set<String> {
            switch self {
            case .swift:
                return ["func", "let", "var", "if", "else", "guard", "return", "for", "while", "repeat",
                        "switch", "case", "default", "break", "continue", "struct", "class", "enum",
                        "protocol", "extension", "import", "init", "deinit", "self", "super", "nil",
                        "true", "false", "try", "catch", "throw", "throws", "async", "await", "actor",
                        "some", "any", "in", "where", "defer", "inout", "static", "private", "public",
                        "internal", "fileprivate", "open", "final", "override", "mutating", "lazy"]
            case .javascript:
                return ["function", "const", "let", "var", "if", "else", "return", "for", "while", "do",
                        "switch", "case", "default", "break", "continue", "class", "extends", "new",
                        "this", "super", "null", "undefined", "true", "false", "try", "catch", "finally",
                        "throw", "async", "await", "import", "export", "from", "of", "in", "typeof",
                        "instanceof", "yield", "interface", "type", "enum", "implements", "readonly"]
            case .python:
                return ["def", "class", "if", "elif", "else", "return", "for", "while", "break",
                        "continue", "import", "from", "as", "with", "try", "except", "finally", "raise",
                        "pass", "lambda", "yield", "global", "nonlocal", "assert", "del", "in", "is",
                        "not", "and", "or", "None", "True", "False", "async", "await", "self"]
            case .shell:
                return ["if", "then", "else", "elif", "fi", "for", "in", "do", "done", "while", "until",
                        "case", "esac", "function", "return", "export", "local", "readonly", "echo",
                        "cd", "set", "unset", "source", "alias", "sudo"]
            case .sql:
                return ["select", "from", "where", "insert", "into", "values", "update", "set", "delete",
                        "create", "table", "drop", "alter", "add", "join", "left", "right", "inner",
                        "outer", "on", "group", "by", "order", "having", "limit", "offset", "as", "and",
                        "or", "not", "null", "primary", "key", "foreign", "references", "index", "distinct"]
            case .json, .generic:
                return []
            }
        }

        /// 注释前缀；`nil` 表示该语言不按前缀切注释（JSON 没有注释）。
        var lineComment: String? {
            switch self {
            case .python, .shell: return "#"
            case .sql: return "--"
            case .json: return nil
            default: return "//"
            }
        }

        var supportsBlockComment: Bool {
            switch self {
            case .swift, .javascript, .sql, .generic: return true
            default: return false
            }
        }

        /// 标识符后面的 `(` 视为函数调用（Swift/JS/Python 通用近似）。
        var highlightsCalls: Bool {
            switch self {
            case .swift, .javascript, .python: return true
            default: return false
            }
        }
    }

    // MARK: - 分词

    /// 返回每个字符的 token 类别（与 `text` 的 UTF-16 长度一致）。
    /// 逐字符扫描，不做正则：代码块通常只有几十行，O(n) 足够，且不会因为
    /// 正则回溯在大文件上卡住输入。
    static func tokenize(_ text: String, language: Language) -> [Token] {
        let ns = text as NSString
        let length = ns.length
        var tokens = [Token](repeating: .plain, count: length)
        guard length > 0 else { return tokens }

        let keywords = language.keywords
        var index = 0

        func mark(_ range: NSRange, _ token: Token) {
            guard range.length > 0, NSMaxRange(range) <= length else { return }
            for offset in range.location..<NSMaxRange(range) { tokens[offset] = token }
        }

        while index < length {
            let character = ns.character(at: index)

            // 行注释
            if let marker = language.lineComment,
               matches(ns, index: index, marker) {
                var end = index
                while end < length, ns.character(at: end) != 0x0A { end += 1 }
                mark(NSRange(location: index, length: end - index), .comment)
                index = end
                continue
            }

            // 块注释
            if language.supportsBlockComment, matches(ns, index: index, "/*") {
                var end = index + 2
                while end + 1 < length, !(ns.character(at: end) == 0x2A && ns.character(at: end + 1) == 0x2F) {
                    end += 1
                }
                let stop = min(end + 2, length)
                mark(NSRange(location: index, length: stop - index), .comment)
                index = stop
                continue
            }

            // 字符串（单/双引号；反斜杠转义；不跨行，避免未闭合引号吃掉整块）
            if character == 0x22 || character == 0x27 {
                var end = index + 1
                while end < length {
                    let current = ns.character(at: end)
                    if current == 0x5C { end += 2; continue }
                    if current == character { end += 1; break }
                    if current == 0x0A { break }
                    end += 1
                }
                mark(NSRange(location: index, length: min(end, length) - index), .string)
                index = min(end, length)
                continue
            }

            // 数字（含 0x 十六进制、小数点、下划线分隔）
            if isDigit(character) {
                let isHex = character == 0x30 && index + 1 < length
                    && (ns.character(at: index + 1) == 0x78 || ns.character(at: index + 1) == 0x58)
                var end = index + 1
                while end < length {
                    let next = ns.character(at: end)
                    if isDigit(next) || next == 0x5F { end += 1; continue }
                    if next == 0x2E { end += 1; continue }
                    if isHex, isHexLetter(next) { end += 1; continue }
                    break
                }
                mark(NSRange(location: index, length: end - index), .number)
                index = end
                continue
            }

            // 标识符 / 关键字 / 类型 / 函数名
            if isIdentifierStart(character) {
                var end = index + 1
                while end < length, isIdentifierPart(ns.character(at: end)) { end += 1 }
                let word = ns.substring(with: NSRange(location: index, length: end - index))
                let token: Token
                if keywords.contains(word) {
                    token = .keyword
                } else if language.highlightsCalls, nextNonSpace(ns, from: end) == 0x28 {
                    token = .function
                } else if let first = word.unicodeScalars.first, CharacterSet.uppercaseLetters.contains(first) {
                    token = .type
                } else {
                    token = .plain
                }
                mark(NSRange(location: index, length: end - index), token)
                index = end
                continue
            }

            index += 1
        }
        return tokens
    }

    // MARK: - 着色应用

    /// 给 `range`（代码块整段）内的文字上色。`baseColor` 是正文颜色，
    /// `.plain` token 会被显式写回基色——否则从普通段落改成代码块时，
    /// 上一轮的强调色会留在没被重新标记的字符上。
    static func apply(to storage: NSMutableAttributedString, range: NSRange, language: Language,
                      baseColor: NSColor, appearance: NSAppearance) {
        guard range.length > 0, NSMaxRange(range) <= storage.length else { return }
        let text = (storage.string as NSString).substring(with: range)
        let tokens = tokenize(text, language: language)
        guard tokens.count == range.length else { return }
        var cache: [Token: NSColor] = [:]
        storage.beginEditing()
        var index = 0
        while index < tokens.count {
            let token = tokens[index]
            var end = index + 1
            while end < tokens.count, tokens[end] == token { end += 1 }
            let resolved: NSColor
            if token == .plain {
                resolved = baseColor
            } else if let cached = cache[token] {
                resolved = cached
            } else {
                let themed = color(for: token, appearance: appearance) ?? baseColor
                cache[token] = themed
                resolved = themed
            }
            storage.addAttribute(.foregroundColor, value: resolved,
                                 range: NSRange(location: range.location + index, length: end - index))
            index = end
        }
        storage.endEditing()
    }

    // MARK: - 字符判定

    private static func matches(_ ns: NSString, index: Int, _ marker: String) -> Bool {
        let marker = marker as NSString
        guard index + marker.length <= ns.length else { return false }
        return ns.substring(with: NSRange(location: index, length: marker.length)) == marker as String
    }

    private static func nextNonSpace(_ ns: NSString, from index: Int) -> unichar? {
        var cursor = index
        while cursor < ns.length {
            let character = ns.character(at: cursor)
            if character != 0x20, character != 0x09 { return character }
            cursor += 1
        }
        return nil
    }

    private static func isDigit(_ character: unichar) -> Bool { character >= 0x30 && character <= 0x39 }
    private static func isHexLetter(_ character: unichar) -> Bool {
        (character >= 0x41 && character <= 0x46) || (character >= 0x61 && character <= 0x66)
    }
    private static func isIdentifierStart(_ character: unichar) -> Bool {
        (character >= 0x41 && character <= 0x5A) || (character >= 0x61 && character <= 0x7A)
            || character == 0x5F || character > 0x7F
    }
    private static func isIdentifierPart(_ character: unichar) -> Bool {
        isIdentifierStart(character) || isDigit(character)
    }
}
