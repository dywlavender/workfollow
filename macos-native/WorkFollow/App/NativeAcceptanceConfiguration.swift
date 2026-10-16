import Foundation

/// Passive diagnostics enabled only in an explicitly configured acceptance copy.
@MainActor
enum NativeAcceptanceInteractionTrace {
    static var enabled: Bool {
        #if DEBUG
        Bundle.main.object(forInfoDictionaryKey: "WorkFollowAcceptanceInteractionTrace") as? Bool ?? false
        #else
        false
        #endif
    }

    static func record(_ event: String, _ fields: [String: Any] = [:]) {
        guard enabled,
              let root = Bundle.main.object(forInfoDictionaryKey: "WorkFollowAcceptanceStorageRoot") as? String else { return }
        let url = URL(fileURLWithPath: root).appendingPathComponent("interaction-trace.jsonl")
        var record = fields
        record["event"] = event
        record["time"] = Date().timeIntervalSince1970
        guard var data = try? JSONSerialization.data(withJSONObject: record, options: [.sortedKeys]) else { return }
        data.append(0x0A)
        if !FileManager.default.fileExists(atPath: url.path) {
            _ = FileManager.default.createFile(atPath: url.path, contents: nil)
        }
        guard let handle = try? FileHandle(forWritingTo: url) else { return }
        defer { try? handle.close() }
        _ = try? handle.seekToEnd()
        try? handle.write(contentsOf: data)
    }
}

/// Acceptance copies declare their fixture through their own bundle metadata.
/// Ordinary builds use the real clock and saved window geometry.
enum NativeAcceptanceConfiguration {
    static func makeClock() -> () -> Date {
        #if DEBUG
        let value = Bundle.main.object(forInfoDictionaryKey: "WorkFollowAcceptanceClock") as? String
        return clock(reference: value, wallClock: Date.init)
        #else
        return Date.init
        #endif
    }

    static func clock(reference: String?, wallClock: @escaping () -> Date) -> () -> Date {
        guard let reference else { return wallClock }
        let formatter = ISO8601DateFormatter()
        guard let anchor = formatter.date(from: reference) else { return wallClock }
        let started = wallClock()
        return { anchor.addingTimeInterval(wallClock().timeIntervalSince(started)) }
    }

    static var windowSize: CGSize? {
        #if DEBUG
        guard let width = Bundle.main.object(forInfoDictionaryKey: "WorkFollowAcceptanceWindowWidth") as? NSNumber,
              let height = Bundle.main.object(forInfoDictionaryKey: "WorkFollowAcceptanceWindowHeight") as? NSNumber else {
            return nil
        }
        return CGSize(width: width.doubleValue, height: height.doubleValue)
        #else
        return nil
        #endif
    }

    static var destination: NativeDestination? {
        #if DEBUG
        guard let value = Bundle.main.object(forInfoDictionaryKey: "WorkFollowAcceptanceDestination") as? String else {
            return nil
        }
        return NativeDestination(rawValue: value)
        #else
        return nil
        #endif
    }

    static var appearance: NativeAppearance? {
        #if DEBUG
        guard let value = Bundle.main.object(forInfoDictionaryKey: "WorkFollowAcceptanceAppearance") as? String else {
            return nil
        }
        return NativeAppearance(rawValue: value)
        #else
        return nil
        #endif
    }

    static var selectsFirstTask: Bool {
        #if DEBUG
        Bundle.main.object(forInfoDictionaryKey: "WorkFollowAcceptanceSelectFirst") as? Bool ?? false
        #else
        false
        #endif
    }
}
