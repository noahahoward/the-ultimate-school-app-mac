import SwiftUI
import SwiftData

struct SettingsView: View {
    @EnvironmentObject private var app: AppState

    var body: some View {
        TabView(selection: $app.settingsTab) {
            GeneralSettings()
                .tabItem { Label("General", systemImage: "gearshape") }.tag(SettingsTab.general)
            LookSettings()
                .tabItem { Label("Look", systemImage: "paintpalette") }.tag(SettingsTab.look)
            ScheduleSettings()
                .tabItem { Label("Schedule", systemImage: "calendar") }.tag(SettingsTab.schedule)
            ReminderSettings()
                .tabItem { Label("Reminders", systemImage: "bell") }.tag(SettingsTab.reminders)
            SyncSettings()
                .tabItem { Label("Sync", systemImage: "arrow.triangle.2.circlepath") }.tag(SettingsTab.sync)
            UpdateSettings()
                .tabItem { Label("Updates", systemImage: "arrow.down.circle") }.tag(SettingsTab.updates)
        }
        .frame(width: 560, height: 470)
    }
}

// MARK: - Look

/// Colour and type are the first things anyone changes, and the reason an app
/// feels like theirs rather than issued to them.
private struct LookSettings: View {
    @EnvironmentObject private var app: AppState

    /// Eight across, so fifteen colours and the custom well fill two rows
    /// exactly with no stray one sitting on its own.
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 8)

    var body: some View {
        Form {
            Section("Accent") {
                LazyVGrid(columns: columns, spacing: 10) {
                    ForEach(Theme.Accent.allCases) { accent in
                        Button {
                            choose(accent.hex)
                        } label: {
                            swatch(Color(hex: accent.hex),
                                   label: accent.label,
                                   isChosen: app.settings.accentHex.caseInsensitiveCompare(accent.hex) == .orderedSame)
                        }
                        .buttonStyle(.plain)
                    }

                    VStack(spacing: 4) {
                        ColorPicker("", selection: Binding(
                            get: { Color(hex: app.settings.accentHex) },
                            set: { choose($0.hexString) }
                        ), supportsOpacity: false)
                        .labelsHidden()
                        .frame(height: 34)
                        Text("Custom")
                            .font(.system(size: 10))
                            .foregroundStyle(app.settings.namedAccent == nil ? .primary : .secondary)
                    }
                }
                .padding(.vertical, 4)
            }

            Section("Headings") {
                Picker("Type", selection: Binding(
                    get: { app.settings.typeStyle },
                    set: {
                        app.settings.typeStyle = $0
                        app.applyAppearance()
                        app.save()
                    }
                )) {
                    ForEach(Theme.TypeStyle.allCases) { style in
                        Text(style.label).tag(style)
                    }
                }
                .pickerStyle(.segmented)

                HStack(spacing: 14) {
                    Text("Tuesday").font(Theme.display(19, weight: .bold))
                    Text("3").font(Theme.display(19, weight: .bold))
                        .foregroundStyle(Theme.accent)
                    Text("due").font(.system(size: 11)).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            Section("Appearance") {
                Picker("Mode", selection: Binding(
                    get: { app.settings.appearanceRaw },
                    set: { app.settings.appearanceRaw = $0; app.save() }
                )) {
                    Text("System").tag("system")
                    Text("Light").tag("light")
                    Text("Dark").tag("dark")
                }
                .pickerStyle(.segmented)
            }

            Section("Class colours") {
                Text("Each class carries its own colour, set when you open it.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private func swatch(_ color: Color, label: String, isChosen: Bool) -> some View {
        VStack(spacing: 4) {
            ZStack {
                Circle().fill(color).frame(width: 26, height: 26)
                if isChosen {
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.white)
                }
            }
            .overlay(
                Circle()
                    .strokeBorder(Color.primary.opacity(isChosen ? 0.5 : 0), lineWidth: 2)
                    .frame(width: 32, height: 32)
            )
            .frame(height: 34)
            Text(label)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .contentShape(Rectangle())
    }

    private func choose(_ hex: String) {
        app.settings.accentHex = hex
        app.applyAppearance()
        app.save()
    }
}

// MARK: - General

private struct GeneralSettings: View {
    @EnvironmentObject private var app: AppState
    @AppStorage("menuBarEnabled") private var menuBarEnabled = true

    var body: some View {
        Form {
            Section("Focus timer") {
                Stepper("Focus: \(app.settings.focusMinutes) min",
                        value: binding(\.focusMinutes), in: 5...90, step: 5)
                Stepper("Short break: \(app.settings.shortBreakMinutes) min",
                        value: binding(\.shortBreakMinutes), in: 1...30)
                Stepper("Long break: \(app.settings.longBreakMinutes) min",
                        value: binding(\.longBreakMinutes), in: 5...45, step: 5)
                Stepper("Long break after \(app.settings.sessionsBeforeLongBreak) runs",
                        value: binding(\.sessionsBeforeLongBreak), in: 2...8)
                Toggle("Play a sound when a timer ends", isOn: binding(\.focusChimeEnabled))
            }

            Section("Menu bar") {
                Toggle("Show Locker in the menu bar", isOn: $menuBarEnabled)
                Text("The menu bar item shows your next class and what's due today.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            Section("Shortcut") {
                Toggle("Add work from anywhere with ⌃⌥Space", isOn: binding(\.globalHotkeyEnabled))
            }
        }
        .formStyle(.grouped)
    }

    private func binding<T>(_ keyPath: ReferenceWritableKeyPath<AppSettings, T>) -> Binding<T> {
        Binding(
            get: { app.settings[keyPath: keyPath] },
            set: { app.settings[keyPath: keyPath] = $0; app.save() }
        )
    }
}

// MARK: - Schedule

private struct ScheduleSettings: View {
    @EnvironmentObject private var app: AppState
    @State private var breakStart = Date()
    @State private var breakEnd = Date()

    var body: some View {
        Form {
            Section("Type") {
                Picker("Schedule", selection: Binding(
                    get: { app.settings.scheduleKind },
                    set: { app.settings.scheduleKind = $0; app.save() }
                )) {
                    ForEach(ScheduleKind.allCases, id: \.self) { Text($0.label).tag($0) }
                }
            }

            if app.settings.scheduleKind == .alternatingAB {
                Section("A / B days") {
                    let letter = ScheduleEngine.letter(for: Date(), config: app.scheduleConfig)
                    LabeledContent("Today is", value: letter.map { "\($0.rawValue) day" } ?? "not a school day")

                    HStack(spacing: 8) {
                        Text("Fix the letters:")
                        Button("Today is an A day") { reanchor(isA: true) }
                        Button("Today is a B day") { reanchor(isA: false) }
                    }
                    Text("Use this after a snow day or an assembly throws the rotation off.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }

            Section("School year") {
                DatePicker("First day", selection: Binding(
                    get: { app.settings.firstDayOfSchool ?? Date() },
                    set: { app.settings.firstDayOfSchool = $0; app.save() }
                ), displayedComponents: .date)

                // An unset end date used to display as today, so nudging the
                // picker would end the school year this morning and turn every
                // day after it into a non-school day.
                DatePicker("Last day", selection: Binding(
                    get: { app.settings.lastDayOfSchool ?? ScheduleSettings.defaultLastDay() },
                    set: { app.settings.lastDayOfSchool = $0; app.save() }
                ), displayedComponents: .date)

                if app.settings.lastDayOfSchool == nil {
                    Text("Not set yet — Locker treats every weekday as a school day.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }

            Section("Days off") {
                HStack {
                    Text("\(app.settings.noSchoolDays.count) day\(app.settings.noSchoolDays.count == 1 ? "" : "s") marked")
                    Spacer()
                    Button("Mark today off") { markOff(from: Date(), to: Date()) }
                    Button("Clear all") {
                        app.settings.noSchoolDays = []
                        app.save()
                    }
                    .disabled(app.settings.noSchoolDays.isEmpty)
                }

                // Breaks are weeks, not days. Marking one off a day at a time
                // meant opening Settings every morning of the holidays.
                DatePicker("Break from", selection: $breakStart, displayedComponents: .date)
                DatePicker("until", selection: $breakEnd, displayedComponents: .date)
                HStack {
                    Spacer()
                    Button("Mark this break off") { markOff(from: breakStart, to: breakEnd) }
                        .disabled(breakEnd < breakStart)
                }

                Text("Days off don't break your streak and don't advance the A/B rotation.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    /// The end of the current school year: the coming June, not today.
    static func defaultLastDay(now: Date = Date(), calendar: Calendar = .current) -> Date {
        var comps = calendar.dateComponents([.year], from: now)
        // Before June the year ends this calendar year; after it, the next one.
        if calendar.component(.month, from: now) >= 6 { comps.year = (comps.year ?? 2026) + 1 }
        comps.month = 6
        comps.day = 5
        return calendar.date(from: comps) ?? now
    }

    /// Adds every school day in a range, skipping any already marked.
    private func markOff(from start: Date, to end: Date) {
        let calendar = Calendar.current
        let days = ScheduleEngine.schoolDays(from: start, to: end, config: app.scheduleConfig, calendar: calendar)
        var marked = app.settings.noSchoolDays
        for day in days where !marked.contains(where: { calendar.isDate($0, inSameDayAs: day) }) {
            marked.append(day)
        }
        app.settings.noSchoolDays = marked.sorted()
        app.save()
    }

    private func reanchor(isA: Bool) {
        app.settings.abAnchorDate = Calendar.current.startOfDay(for: Date())
        app.settings.abAnchorIsA = isA
        app.save()
    }
}

// MARK: - Reminders

private struct ReminderSettings: View {
    @EnvironmentObject private var app: AppState
    @StateObject private var notifications = NotificationService.shared

    var body: some View {
        Form {
            Section {
                Toggle("Remind me about due work", isOn: Binding(
                    get: { app.settings.remindersEnabled },
                    set: { app.settings.remindersEnabled = $0; app.save(); reschedule() }
                ))

                if notifications.authorization != .authorized {
                    HStack {
                        Text("Notifications aren't allowed yet.")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("Allow") {
                            Task { await notifications.requestAuthorization(); reschedule() }
                        }
                    }
                } else {
                    HStack {
                        Text("\(notifications.scheduledCount) reminder\(notifications.scheduledCount == 1 ? "" : "s") scheduled")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("Send a test") { Task { await notifications.sendTestNotification() } }
                    }
                }
            }

            Section("When") {
                Toggle("The night before", isOn: bool(\.eveningBeforeEnabled))
                if app.settings.eveningBeforeEnabled { timeRow("at", keyPath: \.eveningBeforeMinutes) }

                Toggle("The morning it's due", isOn: bool(\.morningOfEnabled))
                if app.settings.morningOfEnabled { timeRow("at", keyPath: \.morningOfMinutes) }

                Toggle("Before the due time", isOn: bool(\.hoursBeforeEnabled))
                if app.settings.hoursBeforeEnabled {
                    Stepper("\(app.settings.hoursBeforeCount) hour\(app.settings.hoursBeforeCount == 1 ? "" : "s") ahead",
                            value: int(\.hoursBeforeCount), in: 1...12)
                    Text("Only applies when an assignment has an actual time, not just a date.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }

                Toggle("Extra heads-up for tests and projects", isOn: bool(\.bigDealLeadDaysEnabled))
                if app.settings.bigDealLeadDaysEnabled {
                    Stepper("\(app.settings.bigDealLeadDays) day\(app.settings.bigDealLeadDays == 1 ? "" : "s") ahead",
                            value: int(\.bigDealLeadDays), in: 1...14)
                }
            }

            Section("Classes") {
                Toggle("Remind me before a class starts", isOn: bool(\.classStartRemindersEnabled))
                if app.settings.classStartRemindersEnabled {
                    Stepper("\(app.settings.classStartLeadMinutes) min before",
                            value: int(\.classStartLeadMinutes), in: 1...60, step: 5)
                }
            }
        }
        .formStyle(.grouped)
        .task { await notifications.refreshAuthorizationStatus() }
    }

    private func timeRow(_ label: String, keyPath: ReferenceWritableKeyPath<AppSettings, Int>) -> some View {
        DatePicker(
            label,
            selection: Binding(
                get: {
                    ScheduleEngine.date(Calendar.current.startOfDay(for: Date()),
                                        atMinutes: app.settings[keyPath: keyPath])
                },
                set: {
                    app.settings[keyPath: keyPath] = ScheduleEngine.minutesIntoDay($0)
                    app.save()
                    reschedule()
                }
            ),
            displayedComponents: .hourAndMinute
        )
    }

    private func bool(_ keyPath: ReferenceWritableKeyPath<AppSettings, Bool>) -> Binding<Bool> {
        Binding(
            get: { app.settings[keyPath: keyPath] },
            set: { app.settings[keyPath: keyPath] = $0; app.save(); reschedule() }
        )
    }

    private func int(_ keyPath: ReferenceWritableKeyPath<AppSettings, Int>) -> Binding<Int> {
        Binding(
            get: { app.settings[keyPath: keyPath] },
            set: { app.settings[keyPath: keyPath] = $0; app.save(); reschedule() }
        )
    }

    private func reschedule() {
        Task { await app.rescheduleReminders() }
    }
}

// MARK: - Sync

private struct SyncSettings: View {
    @EnvironmentObject private var app: AppState
    @State private var clientSecret: String = ""
    @State private var isWorking = false

    private var source: ClassroomSource { app.classroom }

    var body: some View {
        Form {
            Section("Google Classroom") {
                if source.isConnected {
                    LabeledContent("Signed in as", value: app.settings.classroomConnectedEmail.isEmpty
                                   ? "your school account" : app.settings.classroomConnectedEmail)
                    if let last = app.settings.classroomLastSyncAt {
                        LabeledContent("Last sync", value: last.formatted(date: .abbreviated, time: .shortened))
                    }
                    if !app.settings.classroomLastSyncSummary.isEmpty {
                        LabeledContent("Result", value: app.settings.classroomLastSyncSummary)
                    }
                    Toggle("Sync automatically while Locker is open", isOn: Binding(
                        get: { app.settings.classroomAutoSync },
                        set: { app.settings.classroomAutoSync = $0; app.save() }
                    ))
                    HStack {
                        Button("Sync now") {
                            Task { isWorking = true; await app.sync(source); isWorking = false }
                        }
                        .disabled(isWorking)
                        Spacer()
                        Button("Disconnect", role: .destructive) { app.disconnect(source) }
                    }
                } else {
                    Text("Pull classes and assignments straight from Google Classroom. Locker only ever reads — it can't turn anything in or change your work.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)

                    TextField("OAuth client ID", text: Binding(
                        get: { app.settings.googleClientID },
                        set: { app.settings.googleClientID = $0.trimmingCharacters(in: .whitespaces); app.save() }
                    ))
                    SecureField("Client secret", text: $clientSecret)
                        .onChange(of: clientSecret) { _, value in
                            Keychain.set(value, for: Keychain.googleClientSecret)
                        }

                    Button(isWorking ? "Waiting for Google…" : "Connect") {
                        Task { isWorking = true; await app.connect(source); isWorking = false }
                    }
                    .disabled(!source.isConfigured || isWorking)

                    Text("Setup steps are in SETUP-GOOGLE.md next to the app.")
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                }

                if case .failed(let message) = app.syncStatus {
                    Text(message)
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.overdue)
                        .textSelection(.enabled)
                }
            }

            Section("How syncing behaves") {
                Text("""
                     New assignments appear automatically, and turning something in on Classroom checks it off here. \
                     Your notes, priorities, and time estimates are never overwritten. If something is deleted on \
                     Classroom, Locker keeps it and marks it instead.
                     """)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .onAppear { clientSecret = Keychain.get(Keychain.googleClientSecret) ?? "" }
    }
}

// MARK: - Updates

private struct UpdateSettings: View {
    @EnvironmentObject private var app: AppState
    @StateObject private var updates = UpdateService.shared

    private var repo: String {
        app.settings.updateRepo.isEmpty ? UpdateService.defaultRepo : app.settings.updateRepo
    }

    var body: some View {
        Form {
            Section {
                LabeledContent("Installed version", value: "\(updates.currentVersion) (\(updates.currentBuild))")

                // An empty field falls back to the repo built into the app, so the
                // placeholder shows that rather than looking unconfigured.
                TextField("Update repository", text: Binding(
                    get: { app.settings.updateRepo },
                    set: { app.settings.updateRepo = $0; app.save() }
                ), prompt: Text(UpdateService.defaultRepo.isEmpty
                                ? "owner/repo or a github.com link"
                                : UpdateService.defaultRepo))

                LabeledContent("Checking", value: UpdateService.normalizeRepo(repo).isEmpty
                               ? "not set" : UpdateService.normalizeRepo(repo))

                Toggle("Check automatically once a day", isOn: Binding(
                    get: { app.settings.autoCheckForUpdates },
                    set: { app.settings.autoCheckForUpdates = $0; app.save() }
                ))
            }

            Section("Status") {
                statusRow

                HStack {
                    Button("Check for updates") {
                        Task {
                            app.settings.lastUpdateCheckAt = Date()
                            app.save()
                            await updates.check(repo: repo)
                        }
                    }
                    .disabled(isBusy || UpdateService.normalizeRepo(repo).isEmpty)

                    if case .available(let update) = updates.state {
                        Button("Install \(update.version)") {
                            Task { await updates.downloadAndInstall(update) }
                        }
                        .buttonStyle(.borderedProminent)
                        Button("Release notes") { updates.openReleasePage(update) }
                    }

                    if case .readyToRelaunch = updates.state {
                        Button("Relaunch now") { updates.relaunch() }
                            .buttonStyle(.borderedProminent)
                    }
                    Spacer()
                }
            }
        }
        .formStyle(.grouped)
    }

    private var isBusy: Bool {
        switch updates.state {
        case .checking, .downloading: true
        default: false
        }
    }

    @ViewBuilder
    private var statusRow: some View {
        switch updates.state {
        case .idle:
            Text(UpdateService.normalizeRepo(repo).isEmpty
                 ? "Add the repository above to enable updates."
                 : "Not checked yet.")
                .font(.system(size: 11)).foregroundStyle(.secondary)
        case .checking:
            HStack(spacing: 6) { ProgressView().controlSize(.small); Text("Checking…").font(.system(size: 11)) }
        case .upToDate(let date):
            Text("Up to date, checked \(date.formatted(date: .omitted, time: .shortened)).")
                .font(.system(size: 11)).foregroundStyle(.secondary)
        case .available(let update):
            VStack(alignment: .leading, spacing: 3) {
                Text("Version \(update.version) is available.")
                    .font(.system(size: 12, weight: .medium))
                if !update.notes.isEmpty {
                    Text(update.notes.prefix(400))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }
        case .downloading(let progress):
            ProgressView(value: progress) { Text("Downloading…").font(.system(size: 11)) }
        case .readyToRelaunch:
            Text("Update installed. Relaunch to use it.")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Theme.done)
        case .failed(let message):
            Text(message)
                .font(.system(size: 11))
                .foregroundStyle(Theme.overdue)
                .textSelection(.enabled)
        }
    }
}
