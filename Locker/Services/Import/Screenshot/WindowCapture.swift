import Foundation
import ScreenCaptureKit
import AppKit
import CoreGraphics

/// A window that can be captured, as the chooser presents it.
struct CapturableWindow: Identifiable, Hashable, Sendable {
    var id: CGWindowID
    var appName: String
    var title: String
    var bundleIdentifier: String?
    var width: Int
    var height: Int

    /// The browsers whose tabs Locker knows how to list.
    var isBrowser: Bool { BrowserTabs.Kind(bundleIdentifier: bundleIdentifier) != nil }

    var subtitle: String {
        title.isEmpty ? "\(width) × \(height)" : title
    }
}

/// Picks a window and captures it directly.
///
/// The crosshair used by ⇧⌘4 swallows every click while it is up, so a page
/// cannot be navigated to first. Capturing a chosen window instead means the
/// student can get the page exactly right, then come to Locker and point at it.
enum WindowCapture {

    enum Failure: LocalizedError {
        case needsPermission
        case notFound
        case captureFailed

        var errorDescription: String? {
            switch self {
            case .needsPermission:
                "Locker needs permission to see other windows. Open System Settings › Privacy & Security › Screen & System Audio Recording and switch Locker on, then try again."
            case .notFound:
                "That window has closed."
            case .captureFailed:
                "That window couldn't be captured."
            }
        }
    }

    /// Every window worth offering: real windows, big enough to hold a schedule,
    /// and not Locker's own.
    static func available() async throws -> [CapturableWindow] {
        let content: SCShareableContent
        do {
            content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true)
        } catch {
            throw Failure.needsPermission
        }

        let ownBundle = Bundle.main.bundleIdentifier
        return content.windows
            .filter { window in
                guard window.isOnScreen else { return false }
                guard window.frame.width >= 200, window.frame.height >= 150 else { return false }
                guard window.owningApplication?.bundleIdentifier != ownBundle else { return false }
                // Layer 0 is ordinary document windows; anything else is a panel,
                // a menu or the wallpaper.
                return window.windowLayer == 0
            }
            .map { window in
                CapturableWindow(
                    id: window.windowID,
                    appName: window.owningApplication?.applicationName ?? "Unknown app",
                    title: window.title ?? "",
                    bundleIdentifier: window.owningApplication?.bundleIdentifier,
                    width: Int(window.frame.width),
                    height: Int(window.frame.height)
                )
            }
            .sorted {
                $0.appName == $1.appName
                    ? $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
                    : $0.appName.localizedCaseInsensitiveCompare($1.appName) == .orderedAscending
            }
    }

    /// Captures one window, whether or not it is in front.
    static func capture(_ window: CapturableWindow) async throws -> CGImage {
        let content: SCShareableContent
        do {
            content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true)
        } catch {
            throw Failure.needsPermission
        }
        guard let target = content.windows.first(where: { $0.windowID == window.id }) else {
            throw Failure.notFound
        }

        let configuration = SCStreamConfiguration()
        // Capture at backing scale so the text stays sharp enough to read.
        configuration.width = Int(target.frame.width * 2)
        configuration.height = Int(target.frame.height * 2)
        configuration.showsCursor = false
        configuration.ignoreShadowsSingleWindow = true

        do {
            return try await SCScreenshotManager.captureImage(
                contentFilter: SCContentFilter(desktopIndependentWindow: target),
                configuration: configuration
            )
        } catch {
            throw Failure.captureFailed
        }
    }

    /// Whether permission has already been granted, so the chooser can explain
    /// itself before the system prompt appears.
    static func hasPermission() async -> Bool {
        ((try? await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true)) != nil)
    }
}
