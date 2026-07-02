import AppKit
import Foundation

// Chrome Native Messaging host。
// stdin から 4byte 長プレフィックス付き JSON を読み、設定ファイル更新と
// Distributed Notification 経由で CodexLiveWallpaper.app へコマンドを中継する。

enum Paths {
    static let supportDir = FileManager.default
        .homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/CodexLiveWallpaper")
    static let configURL = supportDir.appendingPathComponent("youtube-url.txt")
    static let playlistURL = supportDir.appendingPathComponent("playlist.txt")
    static let volumeURL = supportDir.appendingPathComponent("volume.txt")
    static let largestOnlyURL = supportDir.appendingPathComponent("largest-only.txt")
}

let bundleIdentifier = "com.codex.livewallpaper"
let notificationName = "com.codex.livewallpaper.command"

func readMessage() -> [String: Any]? {
    let stdin = FileHandle.standardInput
    guard let lengthData = try? stdin.read(upToCount: 4), lengthData.count == 4 else {
        return nil
    }
    let length = lengthData.withUnsafeBytes { $0.load(as: UInt32.self) }
    guard length > 0, length < 8 * 1024 * 1024,
          let body = try? stdin.read(upToCount: Int(length)), body.count == Int(length) else {
        return nil
    }
    return (try? JSONSerialization.jsonObject(with: body)) as? [String: Any]
}

func writeMessage(_ object: [String: Any]) {
    guard let data = try? JSONSerialization.data(withJSONObject: object) else {
        return
    }
    var length = UInt32(data.count)
    let lengthData = Data(bytes: &length, count: 4)
    let stdout = FileHandle.standardOutput
    stdout.write(lengthData)
    stdout.write(data)
}

func sanitizeID(_ raw: String) -> String? {
    let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_-")
    let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty, trimmed.unicodeScalars.allSatisfy({ allowed.contains($0) }) else {
        return nil
    }
    return trimmed
}

func runningApp() -> NSRunningApplication? {
    NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier).first
}

func launchApp() {
    let appURL = URL(fileURLWithPath: "/Applications/CodexLiveWallpaper.app")
    let configuration = NSWorkspace.OpenConfiguration()
    configuration.activates = false
    let semaphore = DispatchSemaphore(value: 0)
    NSWorkspace.shared.openApplication(at: appURL, configuration: configuration) { _, _ in
        semaphore.signal()
    }
    _ = semaphore.wait(timeout: .now() + 10)
}

func postCommand(_ command: [String: Any]) {
    guard let data = try? JSONSerialization.data(withJSONObject: command),
          let json = String(data: data, encoding: .utf8) else {
        return
    }
    DistributedNotificationCenter.default().postNotificationName(
        Notification.Name(notificationName),
        object: json,
        userInfo: nil,
        deliverImmediately: true
    )
}

func persist(command: [String: Any], type: String) {
    try? FileManager.default.createDirectory(at: Paths.supportDir, withIntermediateDirectories: true)
    switch type {
    case "play":
        if let url = command["url"] as? String,
           !url.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            try? (url.trimmingCharacters(in: .whitespacesAndNewlines) + "\n")
                .write(to: Paths.configURL, atomically: true, encoding: .utf8)
        }
        let ids = ((command["videoIds"] as? [Any]) ?? [])
            .compactMap { $0 as? String }
            .compactMap(sanitizeID)
        if ids.count > 1 {
            try? (ids.joined(separator: "\n") + "\n")
                .write(to: Paths.playlistURL, atomically: true, encoding: .utf8)
        } else {
            try? FileManager.default.removeItem(at: Paths.playlistURL)
        }
    case "off":
        try? FileManager.default.removeItem(at: Paths.configURL)
        try? FileManager.default.removeItem(at: Paths.playlistURL)
    case "volume":
        if let value = (command["value"] as? NSNumber)?.intValue {
            try? "\(min(100, max(0, value)))\n".write(to: Paths.volumeURL, atomically: true, encoding: .utf8)
        }
    case "screens":
        if (command["largestOnly"] as? Bool) == true {
            try? "1\n".write(to: Paths.largestOnlyURL, atomically: true, encoding: .utf8)
        } else {
            try? FileManager.default.removeItem(at: Paths.largestOnlyURL)
        }
    default:
        break
    }
}

while let command = readMessage() {
    guard let type = command["type"] as? String else {
        writeMessage(["ok": false, "error": "missing type"])
        continue
    }

    persist(command: command, type: type)

    let wasRunning = runningApp() != nil
    if wasRunning {
        postCommand(command)
    } else if type == "play" {
        launchApp()
    }

    writeMessage(["ok": true, "running": wasRunning, "type": type])
}
