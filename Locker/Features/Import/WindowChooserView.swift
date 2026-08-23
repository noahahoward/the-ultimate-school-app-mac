import SwiftUI
import AppKit

/// Pick a window to capture, and a tab if it's a browser.
struct WindowChooserView: View {
    var onCapture: (CGImage) -> Void
    /// Classes read straight from a browser page, which keeps names the screen
    /// would have clipped.
    var onClasses: ([ClassDraft]) -> Void
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
            List(selection: selectionBinding) {
                ForEach(grouped, id: \.app) { group in
                    Section(group.app) {
                        ForEach(group.windows) { window in
                            row(window).tag(window.id)
                        }
                    }
                }
            }
            .listStyle(.inset)
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

    private var selectionBinding: Binding<CGWindowID?> {
        Binding(
            get: { selected?.id },
            set: { id in
                selected = windows.first { $0.id == id }
                tabs = []
                selectedTab = nil
                if let selected, selected.isBrowser { Task { await loadTabs(for: selected) } }
            }
        )
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

            // Course links first, which give a name that cannot be clipped. Where
            // a portal has no such links — most do not — the page's own text is
            // still far better than a picture of it.
            var classes = DOMClassReader.classes(from: page)
            if classes.isEmpty {
                classes = ScheduleTextReader.classes(from: DOMClassReader.fallbackLines(from: page))
            }
            isReadingPage = false

            guard !classes.isEmpty else {
                errorText = "No classes were found on that page. Try Capture instead, or open the page that lists the classes."
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
