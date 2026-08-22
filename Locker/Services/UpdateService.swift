import Foundation
import AppKit

struct AvailableUpdate: Equatable, Identifiable {
    var id: String { tagName }
    var tagName: String
    var version: String
    var name: String
    var notes: String
    var downloadURL: URL?
    var pageURL: URL?
    var publishedAt: Date?
    var sizeBytes: Int?
}

enum UpdateState: Equatable {
    case idle
    case checking
    case upToDate(checkedAt: Date)
    case available(AvailableUpdate)
    case downloading(progress: Double)
    case readyToRelaunch
    case failed(String)
}

/// Checks a public GitHub repository's releases for a newer build and installs it.
///
/// Nothing here needs a token: public release metadata and assets are anonymous
/// endpoints, so there is no account to set up.
@MainActor
final class UpdateService: ObservableObject {
    static let shared = UpdateService()

    /// Overridable in Settings, so a fork or a renamed repo needs no rebuild.
    /// GitHub redirects API calls after a rename, so this keeps working either way.
    static let defaultRepo = "noahahoward/the-ultimate-school-app-mac"

    @Published private(set) var state: UpdateState = .idle

    private var session: URLSession = .shared
    private init() {}

    var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    }

    var currentBuild: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0"
    }

    // MARK: - Checking

    /// `repo` is an "owner/name" slug, or a full github.com URL.
    @discardableResult
    func check(repo rawRepo: String) async -> UpdateState {
        let repo = Self.normalizeRepo(rawRepo)
        guard !repo.isEmpty else {
            state = .failed("Set the update repository in Settings first.")
            return state
        }

        state = .checking
        do {
            guard let release = try await latestRelease(repo: repo) else {
                state = .upToDate(checkedAt: Date())
                return state
            }
            let update = Self.update(from: release)
            if Self.isNewer(update.version, than: currentVersion) {
                state = .available(update)
            } else {
                state = .upToDate(checkedAt: Date())
            }
        } catch {
            state = .failed(error.localizedDescription)
        }
        return state
    }

    private struct Release: Decodable {
        struct Asset: Decodable {
            var name: String
            var browser_download_url: String
            var size: Int?
            var content_type: String?
        }
        var tag_name: String
        var name: String?
        var body: String?
        var html_url: String?
        var published_at: String?
        var draft: Bool?
        var prerelease: Bool?
        var assets: [Asset]?
    }

    private func latestRelease(repo: String) async throws -> Release? {
        let url = URL(string: "https://api.github.com/repos/\(repo)/releases/latest")!
        var request = URLRequest(url: url)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("Locker/\(currentVersion)", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 20

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw UpdateError.message("No response from GitHub.")
        }
        switch http.statusCode {
        case 200: break
        case 404: throw UpdateError.message("No releases published yet at \(repo).")
        case 403: throw UpdateError.message("GitHub is rate limiting update checks. Try again later.")
        default: throw UpdateError.message("GitHub returned HTTP \(http.statusCode).")
        }

        let release = try JSONDecoder().decode(Release.self, from: data)
        if release.draft == true { return nil }
        return release
    }

    private static func update(from release: Release) -> AvailableUpdate {
        // Prefer a zipped app bundle; fall back to the first asset so a release
        // packaged some other way still offers a download link.
        let assets = release.assets ?? []
        let asset = assets.first { $0.name.lowercased().hasSuffix(".zip") } ?? assets.first

        let formatter = ISO8601DateFormatter()
        return AvailableUpdate(
            tagName: release.tag_name,
            version: version(fromTag: release.tag_name),
            name: release.name ?? release.tag_name,
            notes: release.body ?? "",
            downloadURL: asset.flatMap { URL(string: $0.browser_download_url) },
            pageURL: release.html_url.flatMap(URL.init(string:)),
            publishedAt: release.published_at.flatMap { formatter.date(from: $0) },
            sizeBytes: asset?.size
        )
    }

    // MARK: - Installing

    func downloadAndInstall(_ update: AvailableUpdate) async {
        guard let downloadURL = update.downloadURL else {
            state = .failed("That release has no downloadable app bundle.")
            return
        }

        state = .downloading(progress: 0)
        do {
            let (temporaryFile, response) = try await session.download(from: downloadURL)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                throw UpdateError.message("Download failed.")
            }

            state = .downloading(progress: 0.7)
            let workspace = FileManager.default.temporaryDirectory
                .appendingPathComponent("LockerUpdate-\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: workspace) }

            let archive = workspace.appendingPathComponent("update.zip")
            try FileManager.default.moveItem(at: temporaryFile, to: archive)

            let unpacked = workspace.appendingPathComponent("unpacked", isDirectory: true)
            try FileManager.default.createDirectory(at: unpacked, withIntermediateDirectories: true)
            try Self.unzip(archive, into: unpacked)

            guard let newApp = Self.findAppBundle(in: unpacked) else {
                throw UpdateError.message("The download didn't contain a Locker app.")
            }
            try Self.validate(bundleAt: newApp)
            // Anything downloaded carries a quarantine flag, and Gatekeeper refuses
            // to launch an ad-hoc signed build that has one. The user already chose
            // to install this update, so clear it before swapping the app in.
            Self.clearQuarantine(at: newApp)

            state = .downloading(progress: 0.9)
            try Self.replaceRunningApp(with: newApp)

            state = .readyToRelaunch
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    func relaunch() {
        let path = Bundle.main.bundleURL
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: path, configuration: configuration) { _, _ in
            DispatchQueue.main.async { NSApp.terminate(nil) }
        }
    }

    func openReleasePage(_ update: AvailableUpdate) {
        guard let url = update.pageURL ?? update.downloadURL else { return }
        NSWorkspace.shared.open(url)
    }

    // MARK: - File work

    private static func unzip(_ archive: URL, into directory: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        process.arguments = ["-x", "-k", archive.path, directory.path]
        let errorPipe = Pipe()
        process.standardError = errorPipe
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw UpdateError.message("Couldn't unpack the update.")
        }
    }

    private static func findAppBundle(in directory: URL) -> URL? {
        let contents = (try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]
        )) ?? []

        if let app = contents.first(where: { $0.pathExtension == "app" }) { return app }
        // Some releases wrap the bundle in a folder.
        for entry in contents where entry.hasDirectoryPath {
            if let nested = findAppBundle(in: entry) { return nested }
        }
        return nil
    }

    /// Refuses to install anything that isn't a real, newer Locker.
    private static func validate(bundleAt url: URL) throws {
        guard let bundle = Bundle(url: url),
              let identifier = bundle.bundleIdentifier else {
            throw UpdateError.message("The downloaded app is not a valid bundle.")
        }
        guard identifier == Bundle.main.bundleIdentifier else {
            throw UpdateError.message("The downloaded app has a different bundle ID (\(identifier)).")
        }
    }

    private static func clearQuarantine(at url: URL) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/xattr")
        process.arguments = ["-dr", "com.apple.quarantine", url.path]
        process.standardError = Pipe()
        process.standardOutput = Pipe()
        try? process.run()
        process.waitUntilExit()
    }

    private static func replaceRunningApp(with newApp: URL) throws {
        let destination = Bundle.main.bundleURL
        do {
            _ = try FileManager.default.replaceItemAt(destination, withItemAt: newApp)
        } catch {
            throw UpdateError.message(
                "Couldn't replace the app at \(destination.path). Move Locker to your Applications folder "
                + "and try again, or download the update from the release page."
            )
        }
    }

    // MARK: - Versions

    /// Accepts "owner/name", a full URL, or a URL with a trailing ".git".
    static func normalizeRepo(_ raw: String) -> String {
        var value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return "" }
        for prefix in ["https://github.com/", "http://github.com/", "github.com/", "git@github.com:"] {
            if value.hasPrefix(prefix) { value = String(value.dropFirst(prefix.count)) }
        }
        if value.hasSuffix(".git") { value = String(value.dropLast(4)) }
        value = value.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let parts = value.split(separator: "/")
        guard parts.count >= 2 else { return "" }
        return "\(parts[0])/\(parts[1])"
    }

    static func version(fromTag tag: String) -> String {
        var value = tag.trimmingCharacters(in: .whitespaces)
        if value.lowercased().hasPrefix("v") { value = String(value.dropFirst()) }
        return value
    }

    /// Numeric, component-wise comparison so 1.10 correctly beats 1.9.
    static func isNewer(_ candidate: String, than current: String) -> Bool {
        let left = components(candidate)
        let right = components(current)
        for index in 0..<max(left.count, right.count) {
            let l = index < left.count ? left[index] : 0
            let r = index < right.count ? right[index] : 0
            if l != r { return l > r }
        }
        return false
    }

    private static func components(_ version: String) -> [Int] {
        version
            .split(whereSeparator: { $0 == "." || $0 == "-" || $0 == "+" })
            .map { Int($0.prefix { $0.isNumber }) ?? 0 }
    }
}

enum UpdateError: LocalizedError {
    case message(String)
    var errorDescription: String? {
        switch self { case .message(let text): text }
    }
}
