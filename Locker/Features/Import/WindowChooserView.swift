import SwiftUI
import AppKit

/// Pick a window to capture, and a tab if it's a browser.
struct WindowChooserView: View {
    var onCapture: (CGImage) -> Void
    /// Classes read straight from a browser page, which keeps names the screen
    /// would have clipped.
    var onClasses: ([ClassDraft]) -> Void
    /// Work read from a page, such as Classroom's to-do list.
    var onAssignments: ([AssignmentDraft], String) -> Void
    var onCancel: () -> Void

    @State private var windows: [CapturableWindow] = []
    @State private var selected: CapturableWindow?
    @State private var tabs: [BrowserTab] = []
    @State private var selectedTab: BrowserTab?
    @State private var isLoading = true
    @State private var isCapturing = false
    @State private var isReadingPage = false
    @State private var isLoadingTabs = false
    @State private var errorText: String?

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
            Divider()
            footer
        }
        .task { await load() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text("Choose a window").font(.system(size: 13, weight: .semibold))
            Text("Set the page up however you like first — nothing is captured until you pick.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
    }

    @ViewBuilder
    private var content: some View {
        if isLoading {
            centered { ProgressView().controlSize(.small); Text("Looking for windows…").font(.system(size: 12)) }
        } else if let errorText {
            centered {
                Image(systemName: "lock.display")
                    .font(.system(size: 26, weight: .light))
                    .foregroundStyle(.tertiary)
                Text(errorText)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 340)
                Button("Open Screen Recording settings") {
                    let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!
                    NSWorkspace.shared.open(url)
                }
                .controlSize(.small)
                Button("Try again") { Task { await load() } }
                    .buttonStyle(.link)
                    .font(.system(size: 11))
            }
        } else if windows.isEmpty {
            centered {
                Text("No other windows are open.").font(.system(size: 12)).foregroundStyle(.secondary)
                Button("Look again") { Task { await load() } }.controlSize(.small)
            }
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(grouped, id: \.app) { group in
                        Text(group.app)
                            .font(Theme.eyebrow)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 12)
                            .padding(.top, 10)
                            .padding(.bottom, 4)

                        ForEach(group.windows) { window in
                            Button { select(window) } label: {
                                row(window)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 6)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .contentShape(Rectangle())
                                    .background(selected?.id == window.id
                                                ? Theme.accent.opacity(0.14) : Color.clear)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }

    private func row(_ window: CapturableWindow) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Text(window.subtitle)
                    .font(.system(size: 12))
                    .lineLimit(1)
                if window.isBrowser {
                    Chip(text: "Browser", tint: Theme.accent)
                }
            }

            if selected?.id == window.id, window.isBrowser {
                if isLoadingTabs {
                    Text("Reading tabs…").font(.system(size: 11)).foregroundStyle(.tertiary)
                } else if tabs.isEmpty {
                    Text("Locker can't read this browser's tabs, so it will capture the tab that's showing.")
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Picker("Tab", selection: $selectedTab) {
                        ForEach(tabs) { tab in
                            Text(tab.title).tag(tab as BrowserTab?)
                        }
                    }
                    .labelsHidden()
                    .controlSize(.small)
                }
            }
        }
        .padding(.vertical, 2)
    }

    private var footer: some View {
        HStack {
            Button("Look again") { Task { await load() } }
                .disabled(isLoading || isCapturing)
            Spacer()
            Button("Cancel", action: onCancel)
            if selected?.isBrowser == true {
                Button(isReadingPage ? "Reading…" : "Read the page") { Task { await readPage() } }
                    .disabled(isReadingPage || isCapturing)
                    .help("Reads the page itself, so long class names aren't cut short")
            }
            Button(isCapturing ? "Capturing…" : "Capture") { Task { await capture() } }
                .buttonStyle(.borderedProminent)
                .disabled(selected == nil || isCapturing || isReadingPage)
                .keyboardShortcut(.defaultAction)
        }
        .padding(12)
    }

    private func centered<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(spacing: 8) { Spacer(); content(); Spacer() }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Data

    private var grouped: [(app: String, windows: [CapturableWindow])] {
        Dictionary(grouping: windows, by: \.appName)
            .map { (app: $0.key, windows: $0.value) }
            .sorted { $0.app.localizedCaseInsensitiveCompare($1.app) == .orderedAscending }
    }

    private func select(_ window: CapturableWindow) {
        selected = window
        tabs = []
        selectedTab = nil
        if window.isBrowser { Task { await loadTabs(for: window) } }
    }

    private func load() async {
        isLoading = true
        errorText = nil
        do {
            windows = try await WindowCapture.available()
            // A browser is the window worth landing on: it is the only one whose
            // page can be read rather than photographed.
            selected = windows.first { $0.isBrowser } ?? windows.first
            if let selected, selected.isBrowser { Task { await loadTabs(for: selected) } }
        } catch {
            windows = []
            errorText = error.localizedDescription
        }
        isLoading = false
    }

    private func loadTabs(for window: CapturableWindow) async {
        isLoadingTabs = true
        let found = await BrowserTabs.tabs(for: window)
        // The selection may have moved on while the browser was answering.
        guard selected?.id == window.id else { isLoadingTabs = false; return }
        tabs = found
        selectedTab = found.first
        isLoadingTabs = false
    }

    /// Asks the browser for the page instead of photographing it.
    private func readPage() async {
        guard let window = selected else { return }
        isReadingPage = true
        errorText = nil

        do {
            let page = try await BrowserDOM.read(window, tab: selectedTab)

            // A page that wants a sign-in has nothing on it, and saying "no
            // classes found" would send the student looking for the wrong fault.
            guard !SignInDetector.isSignInPage(page) else {
                isReadingPage = false
                errorText = "That page is asking you to sign in. Sign in to it in your browser, then read it again."
                return
            }

            // Work first: a to-do page is full of assignment links and no course
            // links, so looking for classes there would find nothing.
            let assignments = DOMAssignmentReader.assignments(from: page)
            if assignments.count >= 2 || (assignments.count == 1 && DOMClassReader.classes(from: page).isEmpty) {
                isReadingPage = false
                onAssignments(assignments, page.url)
                return
            }

            // Course links next, which give a name that cannot be clipped. Where
            // a portal has no such links — most do not — the page's own text is
            // still far better than a picture of it.
            var classes = DOMClassReader.classes(from: page)
            if classes.isEmpty {
                classes = ScheduleTextReader.classes(from: DOMClassReader.fallbackLines(from: page))
            }
            isReadingPage = false

            guard !classes.isEmpty else {
                errorText = "Nothing was found on that page. Open the page that lists your classes or your work, or use Capture instead."
                return
            }
            onClasses(classes)
        } catch {
            isReadingPage = false
            errorText = error.localizedDescription
        }
    }

    private func capture() async {
        guard let window = selected else { return }
        isCapturing = true
        errorText = nil

        // Bring the chosen tab forward first, then give the browser a moment to
        // actually draw it before the shot is taken.
        if let selectedTab, window.isBrowser {
            await BrowserTabs.focus(selectedTab, in: window)
            try? await Task.sleep(nanoseconds: 400_000_000)
        }

        do {
            let image = try await WindowCapture.capture(window)
            isCapturing = false
            onCapture(image)
        } catch {
            isCapturing = false
            errorText = error.localizedDescription
        }
    }
}
