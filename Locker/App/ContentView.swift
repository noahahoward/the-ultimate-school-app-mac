import SwiftUI
import SwiftData

struct ContentView: View {
    @EnvironmentObject private var app: AppState
    @Environment(\.openSettings) private var openSettings
    @State private var isDropTargeted = false

    var body: some View {
        NavigationSplitView {
            List(selection: $app.section) {
                ForEach(AppSection.allCases) { section in
                    Label(section.title, systemImage: section.symbol)
                        .tag(section)
                }
            }
            .navigationSplitViewColumnWidth(min: 170, ideal: 190, max: 240)
            .safeAreaInset(edge: .bottom) {
                VStack(alignment: .leading, spacing: 0) {
                    syncFooter
                    Divider()
                    Button {
                        app.settingsTab = .general
                        openSettings()
                    } label: {
                        Label("Settings", systemImage: "gearshape")
                            .font(.system(size: 12))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .keyboardShortcut(",", modifiers: .command)
                    .help("Settings (⌘,)")
                }
            }
        } detail: {
            detail
                .toolbar {
                    if BrowserTabs.anyBrowserRunning {
                        ToolbarItem(placement: .primaryAction) {
                            Button {
                                app.importEntry = .browserPage
                                app.activeSheet = .screenshotImport
                            } label: {
                                Label("Read a browser page", systemImage: "doc.text.magnifyingglass")
                            }
                            .keyboardShortcut("r", modifiers: [.command, .option])
                            .help("Read your classes straight from a browser page (⌥⌘R)")
                        }
                    }
                    ToolbarItem(placement: .primaryAction) {
                        // Pressing it reads a screenshot, which is how most work
                        // gets in. The rest of the ways are a chevron away.
                        Menu {
                            Button("From a screenshot…") { app.activeSheet = .screenshotImport }
                                .keyboardShortcut("i", modifiers: [.command, .shift])
                            if BrowserTabs.anyBrowserRunning {
                                Button("Read a browser page…") {
                                    app.importEntry = .browserPage
                                    app.activeSheet = .screenshotImport
                                }
                                .keyboardShortcut("r", modifiers: [.command, .option])
                            }
                            Divider()
                            Button("Type it in…") { app.presentQuickAdd() }
                                .keyboardShortcut("n", modifiers: .command)
                        } label: {
                            Label("Add", systemImage: "plus")
                        } primaryAction: {
                            app.activeSheet = .screenshotImport
                        }
                        .help("Add work — press to read a screenshot, or pick another way")
                    }
                }
        }
        .frame(minWidth: 940, minHeight: 620)
        // Dropping a screenshot anywhere in the window starts an import, so the
        // student never has to find the right button first.
        .onDrop(of: [.image, .fileURL], isTargeted: $isDropTargeted) { providers in
            guard app.activeSheet == nil else { return false }
            app.droppedProviders = providers
            app.activeSheet = .screenshotImport
            return true
        }
        .overlay {
            if isDropTargeted {
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(Theme.accent, style: StrokeStyle(lineWidth: 3, dash: [8, 5]))
                    .padding(6)
                    .allowsHitTesting(false)
            }
        }
        .sheet(item: $app.activeSheet) { sheet in
            switch sheet {
            case .onboarding: OnboardingView().environmentObject(app)
            case .quickAdd: QuickAddWindow().environmentObject(app)
            case .screenshotImport: ScreenshotImportView().environmentObject(app)
            }
        }
        .task {
            if !app.settings.hasCompletedOnboarding { app.activeSheet = .onboarding }
            await NotificationService.shared.refreshAuthorizationStatus()
            if NotificationService.shared.authorization == .notDetermined {
                await NotificationService.shared.requestAuthorization()
            }
            await app.rescheduleReminders()
            app.startAutoSync()
            if app.settings.classroomAutoSync { await app.syncAll() }
            await app.checkForUpdatesIfDue()
            registerHotkey()
            // Dev affordance, same shape as LOCKER_SEED: open a sheet on launch
            // so the import flow can be checked without clicking through.
            if let open = ProcessInfo.processInfo.environment["LOCKER_OPEN"],
               open == "import" || open == "windows" || open == "page" {
                app.activeSheet = .screenshotImport
            }
            if let tab = ProcessInfo.processInfo.environment["LOCKER_SETTINGS"],
               let settingsTab = SettingsTab(rawValue: tab) {
                app.settingsTab = settingsTab
                openSettings()
            }
            if let name = ProcessInfo.processInfo.environment["LOCKER_SECTION"],
               let section = AppSection(rawValue: name) {
                app.section = section
            }
        }
        .onChange(of: app.settings.globalHotkeyEnabled) { _, _ in registerHotkey() }
    }

    /// ⌃⌥Space opens the add box from anywhere.
    private func registerHotkey() {
        guard app.settings.globalHotkeyEnabled else {
            GlobalHotkey.shared.unregister()
            return
        }
        GlobalHotkey.shared.register {
            NSApp.activate(ignoringOtherApps: true)
            app.presentQuickAdd()
        }
    }

    @ViewBuilder
    private var detail: some View {
        switch app.section {
        case .today: TodayView()
        case .assignments: AssignmentsView()
        case .classes: ClassesView()
        case .focus: FocusView()
        case .flashcards: FlashcardsView()
        case .grades: GradesView()
        }
    }

    /// Sync state lives in the sidebar so it's visible without being loud.
    @ViewBuilder
    private var syncFooter: some View {
        switch app.syncStatus {
        case .syncing:
            footerLine {
                ProgressView().controlSize(.small)
                Text("Syncing…")
            }
        case .succeeded(let summary, let date):
            footerLine {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.done)
                Text(summary == "Already up to date"
                     ? "Synced \(date.formatted(date: .omitted, time: .shortened))"
                     : summary)
                    .lineLimit(1)
            }
        case .failed(let message):
            footerLine {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Theme.overdue)
                Text(message).lineLimit(2)
            }
        case .idle:
            EmptyView()
        }
    }

    private func footerLine<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        HStack(spacing: 6) {
            content()
            Spacer(minLength: 0)
        }
        .font(.system(size: 10))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }
}
