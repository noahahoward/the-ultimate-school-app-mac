import Foundation
import AppKit

/// A tab in a browser window.
struct BrowserTab: Identifiable, Hashable, Sendable {
    var id: String { "\(windowIndex).\(tabIndex)" }
    var windowIndex: Int
    var tabIndex: Int
    var title: String
}

/// Lists a browser's tabs and brings one to the front.
///
/// A window capture takes whatever tab is showing, so without this the student
/// has to switch tabs themselves and come back. Reading tabs needs the user's
/// permission to control the browser; if that is refused, nothing breaks — the
/// capture just uses the tab already open.
enum BrowserTabs {

    enum Kind: Sendable {
        case safari
        case chromium(name: String)

        init?(bundleIdentifier: String?) {
            switch bundleIdentifier {
            case "com.apple.Safari", "com.apple.SafariTechnologyPreview":
                self = .safari
            case "com.google.Chrome": self = .chromium(name: "Google Chrome")
            case "com.brave.Browser": self = .chromium(name: "Brave Browser")
            case "com.microsoft.edgemac": self = .chromium(name: "Microsoft Edge")
            case "company.thebrowser.Browser": self = .chromium(name: "Arc")
            case "com.vivaldi.Vivaldi": self = .chromium(name: "Vivaldi")
            case "com.operasoftware.Opera": self = .chromium(name: "Opera")
            default: return nil
            }
        }

        var applicationName: String {
            switch self {
            case .safari: "Safari"
            case .chromium(let name): name
            }
        }
    }

    /// How long to wait on the browser before giving up. The first call can put a
    /// permission dialog on screen, and Locker must not sit frozen behind it.
    static let timeout: TimeInterval = 4

    static func tabs(for window: CapturableWindow) async -> [BrowserTab] {
        guard let kind = Kind(bundleIdentifier: window.bundleIdentifier) else { return [] }
        let script = listScript(kind)
        guard let output = await run(script) else { return [] }

        return output
            .split(whereSeparator: \.isNewline)
            .compactMap { line in
                let parts = line.components(separatedBy: "\u{1F}")
                guard parts.count == 3,
                      let windowIndex = Int(parts[0]), let tabIndex = Int(parts[1]) else { return nil }
                let title = parts[2].trimmingCharacters(in: .whitespaces)
                guard !title.isEmpty else { return nil }
                return BrowserTab(windowIndex: windowIndex, tabIndex: tabIndex, title: title)
            }
    }

    /// Brings a tab to the front so a window capture picks it up.
    @discardableResult
    static func focus(_ tab: BrowserTab, in window: CapturableWindow) async -> Bool {
        guard let kind = Kind(bundleIdentifier: window.bundleIdentifier) else { return false }
        return await run(focusScript(kind, tab: tab)) != nil
    }

    // MARK: - Scripts

    private static func listScript(_ kind: Kind) -> String {
        let app = kind.applicationName
        switch kind {
        case .safari:
            return """
            tell application "\(app)"
                set out to ""
                repeat with w from 1 to (count of windows)
                    repeat with t from 1 to (count of tabs of window w)
                        set out to out & w & (ASCII character 31) & t & (ASCII character 31) & (name of tab t of window w) & linefeed
                    end repeat
                end repeat
                return out
            end tell
            """
        case .chromium:
            return """
            tell application "\(app)"
                set out to ""
                repeat with w from 1 to (count of windows)
                    repeat with t from 1 to (count of tabs of window w)
                        set out to out & w & (ASCII character 31) & t & (ASCII character 31) & (title of tab t of window w) & linefeed
                    end repeat
                end repeat
                return out
            end tell
            """
        }
    }

    private static func focusScript(_ kind: Kind, tab: BrowserTab) -> String {
        let app = kind.applicationName
        switch kind {
        case .safari:
            return """
            tell application "\(app)"
                set current tab of window \(tab.windowIndex) to tab \(tab.tabIndex) of window \(tab.windowIndex)
            end tell
            """
        case .chromium:
            return """
            tell application "\(app)"
                set active tab index of window \(tab.windowIndex) to \(tab.tabIndex)
            end tell
            """
        }
    }

    /// Runs AppleScript out of process with a deadline, so a permission dialog or
    /// a wedged browser can never freeze Locker.
    private static func run(_ source: String) async -> String? {
        await withCheckedContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            process.arguments = ["-e", source]

            let output = Pipe()
            process.standardOutput = output
            process.standardError = Pipe()

            var finished = false
            let lock = NSLock()
            func settle(_ value: String?) {
                lock.lock()
                defer { lock.unlock() }
                guard !finished else { return }
                finished = true
                continuation.resume(returning: value)
            }

            process.terminationHandler = { proc in
                guard proc.terminationStatus == 0 else { settle(nil); return }
                let data = output.fileHandleForReading.readDataToEndOfFile()
                settle(String(data: data, encoding: .utf8))
            }

            do {
                try process.run()
            } catch {
                settle(nil)
                return
            }

            DispatchQueue.global().asyncAfter(deadline: .now() + timeout) {
                if process.isRunning { process.terminate() }
                settle(nil)
            }
        }
    }
}
