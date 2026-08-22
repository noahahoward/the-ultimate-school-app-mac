import Foundation
import AppKit
import CoreGraphics

/// Takes a screenshot from inside Locker.
///
/// Hands the job to the same system tool ⇧⌘4 uses, so the student gets the
/// familiar crosshair and Locker needs no screen-recording permission of its own.
enum ScreenCapture {

    enum Failure: LocalizedError {
        case cancelled
        case unavailable

        var errorDescription: String? {
            switch self {
            case .cancelled: "No area was selected."
            case .unavailable: "Screen capture isn't available on this Mac."
            }
        }
    }

    /// Shows the crosshair and returns the selected area. Nil when cancelled.
    static func selectArea() async throws -> CGImage {
        let destination = FileManager.default.temporaryDirectory
            .appendingPathComponent("locker-capture-\(UUID().uuidString).png")
        defer { try? FileManager.default.removeItem(at: destination) }

        let tool = URL(fileURLWithPath: "/usr/sbin/screencapture")
        guard FileManager.default.isExecutableFile(atPath: tool.path) else { throw Failure.unavailable }

        let process = Process()
        process.executableURL = tool
        // -i interactive selection, -x silent, -r no window shadow.
        process.arguments = ["-i", "-x", "-r", destination.path]

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            process.terminationHandler = { _ in continuation.resume() }
            do { try process.run() } catch { continuation.resume(throwing: Failure.unavailable) }
        }

        // Pressing Escape leaves no file behind.
        guard FileManager.default.fileExists(atPath: destination.path),
              let image = NSImage(contentsOf: destination),
              let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            throw Failure.cancelled
        }
        return cgImage
    }
}

/// Remembers how a schedule's columns were labelled, so the same layout imports
/// correctly next time.
///
/// This is what makes correcting the reading worth doing: a fix applies to every
/// future screenshot from the same source rather than just this one.
enum LayoutMemory {

    /// A stable description of a table's shape, independent of the values in it.
    ///
    /// Built from what each column *contains* rather than what it says, so two
    /// screenshots of the same page taken weeks apart still match.
    static func fingerprint(of table: DetectedTable) -> String {
        let shapes = (0..<table.columnCount).map { index -> String in
            let cells = table.column(index).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            guard !cells.isEmpty else { return "-" }
            if cells.allSatisfy({ $0.contains(":") }) { return "t" }
            if cells.allSatisfy({ $0.allSatisfy { $0.isNumber } }) { return "n" }
            if cells.allSatisfy({ $0.contains(",") }) { return "c" }
            return "w"
        }
        return "\(table.columnCount):\(shapes.joined())"
    }

    static func roles(for table: DetectedTable, saved: [SavedColumnLayout]) -> [ColumnRole]? {
        let key = fingerprint(of: table)
        guard let match = saved.first(where: { $0.fingerprint == key }),
              match.roles.count == table.columnCount else { return nil }
        return match.roles.map { ColumnRole(rawValue: $0) ?? .ignore }
    }

    static func remember(
        roles: [ColumnRole],
        for table: DetectedTable,
        in saved: [SavedColumnLayout]
    ) -> [SavedColumnLayout] {
        let entry = SavedColumnLayout(
            fingerprint: fingerprint(of: table),
            roles: roles.map(\.rawValue)
        )
        var updated = saved.filter { $0.fingerprint != entry.fingerprint }
        updated.append(entry)
        // A handful is plenty; a student has a few sources, not hundreds.
        return Array(updated.suffix(12))
    }
}

struct SavedColumnLayout: Codable, Hashable, Sendable {
    var fingerprint: String
    var roles: [String]
}
