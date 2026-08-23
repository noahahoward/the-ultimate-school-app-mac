import SwiftUI
import SwiftData

@main
struct LockerApp: App {
    private let container = Persistence.container()
    @StateObject private var app: AppState
    @StateObject private var focusTimer = FocusTimer()

    /// Scene-level preferences are kept in defaults, not SwiftData.
    ///
    /// A `Binding` built fresh inside `body` over a SwiftData model gave the
    /// scene a new dependency on every evaluation, so each pass invalidated the
    /// scene list and re-ran itself until the main thread's stack overflowed.
    /// `@AppStorage` hands the scene a stable binding instead.
    @AppStorage("menuBarEnabled") private var menuBarEnabled = true

    init() {
        let container = self.container
        _app = StateObject(wrappedValue: AppState(container: container))
    }

    var body: some Scene {
        WindowGroup(id: "main") {
            ContentView()
                .environmentObject(app)
                .environmentObject(focusTimer)
                .modelContainer(container)
                .onAppear(perform: configureFocusTimer)
        }
        .defaultSize(width: 1100, height: 720)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Add Work…") { app.presentQuickAdd() }
                    .keyboardShortcut("n", modifiers: .command)
            }
            CommandGroup(after: .appInfo) {
                CheckForUpdatesMenuItem(app: app)
            }
            CommandMenu("Sync") {
                Button("Read a Browser Page…") {
                    app.importEntry = .browserPage
                    app.activeSheet = .screenshotImport
                }
                .keyboardShortcut("r", modifiers: [.command, .option])

                Button("Add from a Screenshot…") { app.activeSheet = .screenshotImport }
                    .keyboardShortcut("i", modifiers: [.command, .shift])

                Divider()

                Button("Sync Now") { Task { await app.syncAll() } }
                    .keyboardShortcut("r", modifiers: .command)
            }
        }

        Settings {
            SettingsView()
                .environmentObject(app)
                .modelContainer(container)
        }

        MenuBarExtra(isInserted: $menuBarEnabled) {
            MenuBarContent()
                .environmentObject(app)
                .modelContainer(container)
        } label: {
            MenuBarLabel()
                .environmentObject(app)
                .modelContainer(container)
        }
    }

    /// Focus sessions are written back into the same store the rest of the app uses.
    private func configureFocusTimer() {
        let timer = focusTimer
        let state = app
        timer.configure(settings: state.settings) { phase, startedAt, planned, elapsed in
            let session = FocusSession(startedAt: startedAt, plannedSeconds: planned, phase: phase)
            session.completedSeconds = elapsed
            session.endedAt = Date()
            session.wasCompleted = elapsed >= planned
            if let id = timer.linkedAssignmentID {
                session.assignment = state.allAssignments().first { $0.persistentModelID == id }
            }
            state.context.insert(session)
            state.save()
        }
    }
}


/// Opens Settings on the Updates tab and starts a check.
///
/// `openSettings` is only available to views, which is why this is a view rather
/// than a plain button in the command group. It replaces a private
/// `showSettingsWindow:` selector that was never a supported entry point.
private struct CheckForUpdatesMenuItem: View {
    @Environment(\.openSettings) private var openSettings
    let app: AppState

    var body: some View {
        Button("Check for Updates…") {
            app.settingsTab = .updates
            openSettings()
            Task {
                let repo = app.settings.updateRepo.isEmpty
                    ? UpdateService.defaultRepo : app.settings.updateRepo
                await UpdateService.shared.check(repo: repo)
            }
        }
    }
}
