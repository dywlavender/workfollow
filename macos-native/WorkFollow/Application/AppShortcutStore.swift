import AppKit
import Carbon.HIToolbox
import SwiftUI

struct AppShortcutChord: Codable, Equatable {
    private static let allowedModifiers: NSEvent.ModifierFlags = [.control, .option, .shift, .command]
    let key: String
    private let modifierMask: UInt
    let keyCode: UInt16?
    private let typedKey: String?

    init(_ key: KeyEquivalent, _ modifiers: NSEvent.ModifierFlags = .command, keyCode: UInt16? = nil) {
        self.init(key: String(key.character), modifiers: modifiers, keyCode: keyCode)
    }

    private init(key: String, modifiers: NSEvent.ModifierFlags, keyCode: UInt16?, typedKey: String? = nil) {
        self.key = Self.normalized(key)
        modifierMask = modifiers.intersection(Self.allowedModifiers).rawValue
        self.keyCode = keyCode
        self.typedKey = typedKey.map(Self.normalized)
    }

    init?(event: NSEvent) {
        guard let key = event.characters(byApplyingModifiers: []) ?? event.charactersIgnoringModifiers,
              Self.normalized(key).count == 1 else { return nil }
        let typedModifiers = event.modifierFlags.intersection([.shift, .option])
        self.init(key: key, modifiers: event.modifierFlags, keyCode: event.keyCode,
                  typedKey: event.characters(byApplyingModifiers: typedModifiers))
    }

    var appKitModifiers: NSEvent.ModifierFlags { .init(rawValue: modifierMask) }
    var swiftUIShortcut: KeyboardShortcut? {
        guard key.count == 1, let character = key.first else { return nil }
        return KeyboardShortcut(KeyEquivalent(character), modifiers: swiftUIModifiers)
    }

    private var swiftUIModifiers: SwiftUI.EventModifiers {
        var result: SwiftUI.EventModifiers = []
        if appKitModifiers.contains(.control) { result.insert(.control) }
        if appKitModifiers.contains(.option) { result.insert(.option) }
        if appKitModifiers.contains(.shift) { result.insert(.shift) }
        if appKitModifiers.contains(.command) { result.insert(.command) }
        return result
    }

    var carbonModifiers: UInt32 {
        var result: UInt32 = 0
        if appKitModifiers.contains(.control) { result |= UInt32(controlKey) }
        if appKitModifiers.contains(.option) { result |= UInt32(optionKey) }
        if appKitModifiers.contains(.shift) { result |= UInt32(shiftKey) }
        if appKitModifiers.contains(.command) { result |= UInt32(cmdKey) }
        return result
    }

    var label: String {
        var modifiers = ""
        if appKitModifiers.contains(.control) { modifiers += "⌃" }
        if appKitModifiers.contains(.option) { modifiers += "⌥" }
        if appKitModifiers.contains(.shift) { modifiers += "⇧" }
        if appKitModifiers.contains(.command) { modifiers += "⌘" }
        let keys = [" ": "空格", "\r": "↵", "\u{1b}": "Esc", "\t": "⇥", "\u{7f}": "⌫",
                    "\u{f700}": "↑", "\u{f701}": "↓", "\u{f702}": "←", "\u{f703}": "→"]
        if let number = functionNumber { return modifiers + "F\(number)" }
        return modifiers + (keys[key] ?? key.uppercased())
    }

    var canRecord: Bool {
        key.count == 1 && (functionNumber != nil || !appKitModifiers.intersection([.command, .control, .option]).isEmpty)
    }

    private var functionNumber: Int? {
        guard let scalar = key.unicodeScalars.first, (0xf704...0xf726).contains(scalar.value) else { return nil }
        return Int(scalar.value) - 0xf704 + 1
    }

    func sameKeys(as other: Self) -> Bool {
        key == other.key && modifierMask == other.modifierMask
    }

    func matches(_ press: KeyPress) -> Bool {
        let modifiers = press.modifiers.intersection([.control, .option, .shift, .command])
        let pressed = Self.normalized(String(press.key.character))
        return modifiers == swiftUIModifiers && (pressed == key || pressed == typedKey)
    }

    var webBinding: [String: Any] {
        let named = ["\r": "enter", "\t": "tab", "\u{1b}": "escape", "\u{7f}": "backspace",
                     "\u{f700}": "arrowup", "\u{f701}": "arrowdown",
                     "\u{f702}": "arrowleft", "\u{f703}": "arrowright"]
        let webKey = functionNumber.map { "f\($0)" } ?? named[key] ?? key
        return ["key": webKey, "typedKey": typedKey.map { named[$0] ?? $0 } ?? webKey,
                "meta": appKitModifiers.contains(.command), "shift": appKitModifiers.contains(.shift),
                "alt": appKitModifiers.contains(.option), "ctrl": appKitModifiers.contains(.control)]
    }

    private static func normalized(_ key: String) -> String {
        if key == "\u{3}" || key == "\n" { return "\r" }
        return key.lowercased()
    }

    static func legacyQuickAdd(defaults: UserDefaults?) -> Self? {
        guard let defaults, let code = defaults.object(forKey: "globalQuickAddKeyCode") as? Int,
              let keyCode = UInt16(exactly: code) else { return nil }
        let carbon = defaults.object(forKey: "globalQuickAddModifiers") as? Int ?? (cmdKey | shiftKey)
        var modifiers: NSEvent.ModifierFlags = []
        if carbon & controlKey != 0 { modifiers.insert(.control) }
        if carbon & optionKey != 0 { modifiers.insert(.option) }
        if carbon & shiftKey != 0 { modifiers.insert(.shift) }
        if carbon & cmdKey != 0 { modifiers.insert(.command) }
        // The old setting stores a physical Carbon key code.
        let keys = [0: "a", 1: "s", 2: "d", 3: "f", 4: "h", 5: "g", 6: "z", 7: "x", 8: "c", 9: "v",
                    11: "b", 12: "q", 13: "w", 14: "e", 15: "r", 16: "y", 17: "t", 18: "1", 19: "2",
                    20: "3", 21: "4", 22: "6", 23: "5", 24: "=", 25: "9", 26: "7", 27: "-", 28: "8",
                    29: "0", 30: "]", 31: "o", 32: "u", 33: "[", 34: "i", 35: "p", 36: "\r", 37: "l",
                    38: "j", 39: "'", 40: "k", 41: ";", 42: "\\", 43: ",", 44: "/", 45: "n", 46: "m",
                    47: ".", 48: "\t", 49: " ", 50: "\u{60}"]
        return Self(key: keys[code] ?? "键位 \(code)", modifiers: modifiers, keyCode: keyCode)
    }
}

enum AppShortcutAction: String, CaseIterable, Identifiable {
    case newTask, newFloatingNote, quickOpen, openSettings, globalQuickAdd
    case today, inbox, nextSevenDays, calendar, notes, matrix, toggleSidebar
    case clearTaskDate, taskToday, taskTomorrow, taskNextWeek
    case undo, redo, findBody, bold, italic, underline
    case createFromSearch, quickAddDescription, toggleTaskCompletion, sendAI, applyAITasks, saveDrawing, pauseFocus, endFocus

    enum Group: String, CaseIterable {
        case general = "常用", navigation = "导航", tasks = "任务日期", editor = "编辑", context = "场景操作"
    }

    enum Scope: Equatable {
        case application, editor, search, quickAdd, taskList, aiChat, aiTasks, drawing, focus

        func overlaps(_ other: Self) -> Bool { self == .application || other == .application || self == other }
    }

    struct Definition {
        let title: String
        let group: Group
        let chord: AppShortcutChord
        let scope: Scope

        init(_ title: String, _ group: Group, _ key: KeyEquivalent,
             _ modifiers: NSEvent.ModifierFlags = .command, scope: Scope = .application, keyCode: UInt16? = nil) {
            self.title = title
            self.group = group
            self.chord = AppShortcutChord(key, modifiers, keyCode: keyCode)
            self.scope = scope
        }
    }

    var id: String { rawValue }
    var title: String { definition.title }
    var defaultChord: AppShortcutChord { definition.chord }

    var definition: Definition {
        switch self {
        case .newTask: return .init("新建任务", .general, "n")
        case .newFloatingNote: return .init("新建悬浮笔记", .general, "n", [.command, .option])
        case .quickOpen: return .init("快速打开", .general, "k")
        case .openSettings: return .init("打开设置", .general, ",")
        case .globalQuickAdd: return .init("全局快速添加", .general, "a", [.command, .shift], keyCode: UInt16(kVK_ANSI_A))
        case .today: return .init("前往今天", .navigation, "1")
        case .inbox: return .init("前往收集箱", .navigation, "2")
        case .nextSevenDays: return .init("前往最近 7 天", .navigation, "9")
        case .calendar: return .init("打开日历", .navigation, "4")
        case .notes: return .init("打开笔记", .navigation, "5")
        case .matrix: return .init("打开四象限", .navigation, "6")
        case .toggleSidebar: return .init("显示或隐藏侧栏", .navigation, "\\")
        case .clearTaskDate: return .init("清除当前任务日期", .tasks, "0", [.command, .shift])
        case .taskToday: return .init("当前任务设为今天", .tasks, "1", [.command, .shift])
        case .taskTomorrow: return .init("当前任务设为明天", .tasks, "2", [.command, .shift])
        case .taskNextWeek: return .init("当前任务设为下周", .tasks, "3", [.command, .shift])
        case .undo: return .init("撤销", .editor, "z")
        case .redo: return .init("重做", .editor, "z", [.command, .shift])
        case .findBody: return .init("查找正文", .editor, "f")
        case .bold: return .init("正文加粗", .editor, "b", scope: .editor)
        case .italic: return .init("正文斜体", .editor, "i", scope: .editor)
        case .underline: return .init("正文下划线", .editor, "u", scope: .editor)
        case .createFromSearch: return .init("从快速打开新建任务", .context, .return, scope: .search)
        case .quickAddDescription: return .init("快速添加任务描述", .context, .return, .shift, scope: .quickAdd)
        case .toggleTaskCompletion: return .init("完成或恢复选中任务", .context, .space, [], scope: .taskList)
        case .sendAI: return .init("发送 AI 消息", .context, .return, [], scope: .aiChat)
        case .applyAITasks: return .init("确认创建 AI 待办", .context, .return, scope: .aiTasks)
        case .saveDrawing: return .init("保存并关闭流程图", .context, "s", scope: .drawing)
        case .pauseFocus: return .init("暂停或继续专注", .context, .space, [], scope: .focus)
        case .endFocus: return .init("结束专注", .context, .escape, [], scope: .focus)
        }
    }

    var defaultAliases: [AppShortcutChord] {
        switch self {
        case .undo: return [.init("z", .control)]
        case .redo: return [.init("z", [.control, .shift]), .init("y")]
        case .bold, .italic, .underline: return defaultChord.key.first.map { [.init(KeyEquivalent($0), .control)] } ?? []
        case .sendAI: return [.init(.return)]
        default: return []
        }
    }

    static let webActions: [Self] = [.undo, .redo, .bold, .italic, .underline]
}

enum AppShortcutError: LocalizedError {
    case modifiersRequired, reserved, occupied(AppShortcutAction), globalUnavailable

    var errorDescription: String? {
        switch self {
        case .modifiersRequired: return "请使用包含 ⌘、⌥ 或 ⌃ 的组合键，或按功能键。"
        case .reserved: return "这个键位已由 macOS 或文本编辑占用。"
        case .occupied(let action): return "这个键位已用于“\(action.title)”。"
        case .globalUnavailable: return "这个全局快捷键不可用，可能已被系统或其他应用占用。"
        }
    }
}

@MainActor
final class AppShortcutStore: ObservableObject {
    static let shared = AppShortcutStore(defaults: .standard)
    static let storageKey = "workfollow.keyboardShortcuts"

    @Published private(set) var overrides: [String: AppShortcutChord]
    private let defaults: UserDefaults?

    init(defaults: UserDefaults? = nil) {
        self.defaults = defaults
        if let data = defaults?.data(forKey: Self.storageKey),
           let stored = try? JSONDecoder().decode([String: AppShortcutChord].self, from: data) {
            overrides = stored
        } else if let legacy = AppShortcutChord.legacyQuickAdd(defaults: defaults) {
            overrides = [AppShortcutAction.globalQuickAdd.rawValue: legacy]
        } else {
            overrides = [:]
        }
    }

    func chord(for action: AppShortcutAction) -> AppShortcutChord { overrides[action.rawValue] ?? action.defaultChord }
    func isDefault(_ action: AppShortcutAction) -> Bool { chord(for: action).sameKeys(as: action.defaultChord) }
    func matches(_ action: AppShortcutAction, event: NSEvent) -> Bool {
        guard let pressed = AppShortcutChord(event: event) else { return false }
        return bindings(for: action).contains { $0.sameKeys(as: pressed) }
    }

    func set(_ chord: AppShortcutChord, for action: AppShortcutAction,
             applyGlobal: ((AppShortcutChord) -> Bool)? = nil) throws {
        guard chord.canRecord || chord.sameKeys(as: action.defaultChord) else { throw AppShortcutError.modifiersRequired }
        guard !Self.reserved.contains(where: { $0.sameKeys(as: chord) }) else { throw AppShortcutError.reserved }
        let proposed = chord.sameKeys(as: action.defaultChord) ? [chord] + action.defaultAliases : [chord]
        if let conflict = AppShortcutAction.allCases.first(where: { other in
            other != action && other.definition.scope.overlaps(action.definition.scope)
                && bindings(for: other).contains { existing in proposed.contains { $0.sameKeys(as: existing) } }
        }) {
            throw AppShortcutError.occupied(conflict)
        }
        if action == .globalQuickAdd {
            guard chord.keyCode != nil, applyGlobal?(chord) != false else { throw AppShortcutError.globalUnavailable }
        }
        var changed = overrides
        changed[action.rawValue] = chord.sameKeys(as: action.defaultChord) && action != .globalQuickAdd ? nil : chord
        persist(changed)
    }

    func restoreDefaults(applyGlobal: ((AppShortcutChord) -> Bool)? = nil) throws {
        if overrides[AppShortcutAction.globalQuickAdd.rawValue] != nil,
           applyGlobal?(AppShortcutAction.globalQuickAdd.defaultChord) == false {
            throw AppShortcutError.globalUnavailable
        }
        persist([:])
    }

    private func bindings(for action: AppShortcutAction) -> [AppShortcutChord] {
        let current = chord(for: action)
        return isDefault(action) ? [current] + action.defaultAliases : [current]
    }

    func webBindings(removedDefaults: Bool = false) -> [[String: Any]] {
        AppShortcutAction.webActions.flatMap { action in
            let choices = removedDefaults
                ? (isDefault(action) ? [] : [action.defaultChord] + action.defaultAliases)
                : bindings(for: action)
            return choices.map { chord in
                var value = chord.webBinding
                value["action"] = action.rawValue
                return value
            }
        }
    }

    private func persist(_ values: [String: AppShortcutChord]) {
        overrides = values
        if let data = try? JSONEncoder().encode(values) { defaults?.set(data, forKey: Self.storageKey) }
    }

    private static let reserved: [AppShortcutChord] =
        Array("qwhmacxv").map { AppShortcutChord(KeyEquivalent($0)) }
        + [.init(.tab), .init(.space), .init("h", [.command, .option])]
}
