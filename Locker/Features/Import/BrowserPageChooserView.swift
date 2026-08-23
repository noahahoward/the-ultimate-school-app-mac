import SwiftUI

/// Pick a browser tab to read.
///
/// Deliberately separate from the window chooser: reading a page never looks at
/// the screen, so it must not be made to ask for permission to record it. The
/// browser is asked what it has open, and answers.
struct BrowserPageChooserView: View {
    var onClasses: ([ClassDraft]) -> Void
    var onAssignments: ([AssignmentDraft], String) -> Void
    var onCancel: () -> Void

    @State private var browsers: [BrowserTabs.Kind] = []
    @State private var browser: BrowserTabs.Kind?
    @State private var tabs: [BrowserTab] = []
    @State private var selected: BrowserTab?
    @State private var isLoading = true
    @State private var isReading = false
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
            Text("Read a page").font(.system(size: 13, weight: .semibold))
            Text("Pick the tab showing your classes or your work.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
    }

    @ViewBuilder
    private var content: some View {
        if isLoading {
            centered { ProgressView().controlSize(.small); Text("Asking your browser…").font(.system(size: 12)) }
        } else if browsers.isEmpty {
            centered {
                Image(systemName: "safari").font(.system(size: 26, weight: .light)).foregroundStyle(.tertiary)
                Text("No browser is open.").font(.system(size: 12)).foregroundStyle(.secondary)
            }
        } else if tabs.isEmpty {
            centered {
                Text(couldNotAsk)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 360)
                Button("Try again") { Task { await load() } }.controlSize(.small)
            }
        } else {
            VStack(spacing: 0) {
                if browsers.count > 1 {
                    Picker("Browser", selection: Binding(
                        get: { browser },
                        set: { newValue in
                            browser = newValue
                            Task { await loadTabs() }
                        }
                    )) {
                        ForEach(browsers) { kind in
                            Text(kind.applicationName).tag(kind as BrowserTabs.Kind?)
                        }
                    }
                    .padding(10)
                }

                List(selection: $selected) {
                    ForEach(tabs) { tab in
                        Text(tab.title)
                            .font(.system(size: 12))
                            .lineLimit(1)
                            .tag(tab as BrowserTab?)
                    }
                }
                .listStyle(.inset)
            }
        }
    }

    private var couldNotAsk: String {
        let name = browser?.applicationName ?? "Your browser"
        return "\(name) didn't list its tabs. It may be asking permission to be controlled — check for a dialog — or the browser has no windows open."
    }

    private var footer: some View {
        HStack {
            Button("Look again") { Task { await load() } }
                .disabled(isLoading || isReading)
            Spacer()
            if let errorText {
                Text(errorText)
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.overdue)
                    .lineLimit(2)
                    .frame(maxWidth: 260, alignment: .trailing)
            }
            Button("Cancel", action: onCancel)
            Button(isReading ? "Reading…" : "Read this page") { Task { await read() } }
                .buttonStyle(.borderedProminent)
                .disabled(selected == nil || isReading)
                .keyboardShortcut(.defaultAction)
        }
        .padding(12)
    }

    private func centered<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(spacing: 8) { Spacer(); content(); Spacer() }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Work

    private func load() async {
        isLoading = true
        errorText = nil
        browsers = BrowserTabs.runningBrowsers()
        browser = browser ?? browsers.first
        await loadTabs()
        isLoading = false
    }

    private func loadTabs() async {
        guard let browser else { tabs = []; return }
        let found = await BrowserTabs.tabs(for: browser)
        tabs = found
        // The active tab is the likeliest one wanted, and it sorts first.
        selected = found.first
    }

    private func read() async {
        guard let browser, let selected else { return }
        isReading = true
        errorText = nil

        do {
            let page = try await BrowserDOM.read(browser, tab: selected)

            guard !SignInDetector.isSignInPage(page) else {
                isReading = false
                errorText = "That page is asking you to sign in."
                return
            }

            let work = DOMAssignmentReader.assignments(from: page)
            let courses = DOMClassReader.classes(from: page)

            if work.count >= 2 || (work.count == 1 && courses.isEmpty) {
                isReading = false
                onAssignments(work, page.url)
                return
            }

            var classes = courses
            if classes.isEmpty {
                classes = ScheduleTextReader.classes(from: DOMClassReader.fallbackLines(from: page))
            }
            isReading = false

            guard !classes.isEmpty else {
                errorText = "Nothing was found on that page."
                return
            }
            onClasses(classes)
        } catch {
            isReading = false
            errorText = error.localizedDescription
        }
    }
}
