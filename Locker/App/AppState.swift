import Foundation
import SwiftUI
import SwiftData

/// Top-level destinations in the sidebar.
enum AppSection: String, CaseIterable, Identifiable, Hashable {
    case today, assignments, classes, focus, flashcards, grades

    var id: String { rawValue }

    var title: String {
        switch self {
        case .today: "Today"
        case .assignments: "Assignments"
        case .classes: "Classes"
        case .focus: "Focus"
        case .flashcards: "Flashcards"
        case .grades: "Grades"
        }
    }

    var symbol: String {
        switch self {
        case .today: "sun.max"
        case .assignments: "checklist"
        case .classes: "calendar"
        case .focus: "timer"
        case .flashcards: "rectangle.on.rectangle"
        case .grades: "chart.bar"
        }
    }
}

enum SettingsTab: String, CaseIterable, Identifiable, Hashable {
    case general, schedule, reminders, sync, updates
    var id: String { rawValue }
}

/// SwiftUI honours only one `.sheet` per view, so every modal goes through here.
enum ActiveSheet: String, Identifiable {
    case onboarding, quickAdd, screenshotImport
    var id: String { rawValue }
}

enum SyncStatus: Equatable {
    case idle
    case syncing
    case succeeded(String, Date)
    case failed(String)
}

/// App-wide coordination: navigation, the settings row, syncing, and reminders.
@MainActor
final class AppState: ObservableObject {

    @Published var section: AppSection = .today
    @Published var activeSheet: ActiveSheet?
    @Published var settingsTab: SettingsTab = .general
    @Published var quickAddSeedText = ""
    /// Set when a screenshot is dropped on the window, consumed by the import sheet.
    @Published var droppedProviders: [NSItemProvider] = []
    @Published var syncStatus: SyncStatus = .idle
    @Published var selectedClassID: PersistentIdentifier?
    @Published var lastError: String?

    let context: ModelContext
    let settings: AppSettings
    private(set) lazy var classroom: ClassroomSource = {
        let source = ClassroomSource(clientIDProvider: { [weak self] in self?.settings.googleClientID ?? "" })
        source.connectedEmailHandler = { [weak self] email in
            Task { @MainActor in
                self?.settings.classroomConnectedEmail = email ?? ""
                self?.save()
            }
        }
        return source
    }()

    var sources: [ImportSource] { [classroom] }

    private var autoSyncTask: Task<Void, Never>?

    init(container: ModelContainer) {
        self.context = ModelContext(container)
        self.settings = AppSettings.current(in: context)
        DemoSeed.populateIfEmpty(context: context, settings: settings)
    }

    // MARK: - Persistence helpers

    func save() {
        do {
            try context.save()
        } catch {
            lastError = "Couldn't save: \(error.localizedDescription)"
        }
    }

    func allClasses(includeArchived: Bool = false) -> [SchoolClass] {
        let all = (try? context.fetch(FetchDescriptor<SchoolClass>())) ?? []
        return all
            .filter { includeArchived || !$0.isArchived }
            .sorted { ScheduleEngine.ordering($0, $1) }
    }

    func allAssignments() -> [Assignment] {
        (try? context.fetch(FetchDescriptor<Assignment>())) ?? []
    }

    var classRefs: [ClassRef] { allClasses().map(\.classRef) }

    var scheduleConfig: ScheduleConfig { settings.scheduleConfig }

    // MARK: - Quick add

    func presentQuickAdd(seed: String = "") {
        quickAddSeedText = seed
        activeSheet = .quickAdd
    }

    /// Turns a typed line into a saved assignment. Returns nil when there's nothing to add.
    @discardableResult
    func addAssignment(fromQuickAdd text: String, now: Date = Date()) -> Assignment? {
        let parsed = QuickAddParser.parse(text, classes: classRefs, now: now)
        guard !parsed.title.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }

        let matchedClass = parsed.classID.flatMap { id in allClasses().first { $0.idString == id } }
        let assignment = Assignment(
            title: parsed.title,
            schoolClass: matchedClass,
            dueAt: resolveDueDate(parsed, schoolClass: matchedClass),
            hasDueTime: parsed.hasDueTime || (parsed.dueAt != nil && matchedClass?.startMinutes != nil),
            type: parsed.type,
            priority: parsed.priority,
            estimatedMinutes: parsed.estimatedMinutes
        )
        context.insert(assignment)
        save()
        Task { await rescheduleReminders() }
        return assignment
    }

    /// An all-day due date becomes "when that class meets", which is when it's
    /// actually collected. Without a class it stays an all-day deadline.
    private func resolveDueDate(_ parsed: ParsedQuickAdd, schoolClass: SchoolClass?) -> Date? {
        guard let dueAt = parsed.dueAt else { return nil }
        guard !parsed.hasDueTime, let startMinutes = schoolClass?.startMinutes else { return dueAt }
        return ScheduleEngine.date(dueAt, atMinutes: startMinutes)
    }

    // MARK: - Reminders

    func rescheduleReminders() async {
        let service = NotificationService.shared
        await service.refreshAuthorizationStatus()
        guard settings.remindersEnabled, service.authorization == .authorized else {
            if !settings.remindersEnabled { service.cancelAll() }
            return
        }

        let config = settings.reminderConfig
        var requests: [NotificationService.Request] = []

        for assignment in allAssignments() {
            guard !assignment.isDone, let subject = assignment.reminderSubject else { continue }
            let plans = ReminderScheduler.plans(for: subject, config: config)
            for plan in plans {
                requests.append(NotificationService.Request(
                    id: "\(assignment.idString).\(plan.kind.rawValue)",
                    title: reminderTitle(for: assignment, kind: plan.kind),
                    body: reminderBody(for: assignment, kind: plan.kind),
                    fireAt: plan.fireAt
                ))
            }
        }

        if settings.classStartRemindersEnabled {
            requests.append(contentsOf: classStartRequests())
        }

        await service.reschedule(requests)
    }

    private func reminderTitle(for assignment: Assignment, kind: ReminderKind) -> String {
        switch kind {
        case .bigDealLead: "\(assignment.type.label) coming up"
        case .eveningBefore: "Due tomorrow"
        case .morningOf: "Due today"
        case .hoursBefore: "Due soon"
        }
    }

    private func reminderBody(for assignment: Assignment, kind: ReminderKind) -> String {
        var parts = [assignment.title]
        if let name = assignment.schoolClass?.name { parts.append("· \(name)") }
        if kind == .bigDealLead, let dueAt = assignment.dueAt {
            let days = Calendar.current.dateComponents(
                [.day], from: Calendar.current.startOfDay(for: Date()),
                to: Calendar.current.startOfDay(for: dueAt)
            ).day ?? 0
            parts.append("· in \(days) day\(days == 1 ? "" : "s")")
        }
        return parts.joined(separator: " ")
    }

    /// Reminders for the next two weeks of classes, which is plenty of runway
    /// given the app reschedules on every launch and change.
    private func classStartRequests() -> [NotificationService.Request] {
        var requests: [NotificationService.Request] = []
        let classes = allClasses()
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())

        for offset in 0..<14 {
            guard let day = calendar.date(byAdding: .day, value: offset, to: today) else { continue }
            let meeting = ScheduleEngine.classes(meetingOn: day, from: classes, config: scheduleConfig)
            for schoolClass in meeting {
                guard let startMinutes = schoolClass.startMinutes else { continue }
                let start = ScheduleEngine.date(day, atMinutes: startMinutes)
                let fireAt = start.addingTimeInterval(Double(-settings.classStartLeadMinutes) * 60)
                guard fireAt > Date() else { continue }
                requests.append(NotificationService.Request(
                    id: "class.\(schoolClass.idString).\(offset)",
                    title: schoolClass.name,
                    body: schoolClass.room.isEmpty
                        ? "Starts in \(settings.classStartLeadMinutes) min"
                        : "Starts in \(settings.classStartLeadMinutes) min · \(schoolClass.room)",
                    fireAt: fireAt
                ))
            }
        }
        return requests
    }

    // MARK: - Sync

    func connect(_ source: ImportSource) async {
        do {
            try await source.connect()
            await sync(source)
        } catch {
            syncStatus = .failed(error.localizedDescription)
        }
    }

    func disconnect(_ source: ImportSource) {
        source.disconnect()
        settings.classroomLastSyncSummary = ""
        settings.classroomLastSyncAt = nil
        save()
        syncStatus = .idle
    }

    func syncAll() async {
        for source in sources where source.isConnected {
            await sync(source)
        }
    }

    func sync(_ source: ImportSource) async {
        guard source.isConnected else { return }
        syncStatus = .syncing
        do {
            let payload = try await source.fetch()
            let report = try SyncMerger.merge(payload, from: source.sourceID, into: context)
            let now = Date()
            settings.classroomLastSyncAt = now
            settings.classroomLastSyncSummary = report.summary
            save()
            syncStatus = .succeeded(report.summary, now)
            await rescheduleReminders()
        } catch {
            syncStatus = .failed(error.localizedDescription)
        }
    }

    /// Re-syncs every half hour while the app is open.
    func startAutoSync() {
        autoSyncTask?.cancel()
        autoSyncTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 30 * 60 * 1_000_000_000)
                guard let self, self.settings.classroomAutoSync else { continue }
                await self.syncAll()
            }
        }
    }

    // MARK: - Updates

    func checkForUpdatesIfDue() async {
        guard settings.autoCheckForUpdates else { return }
        let repo = settings.updateRepo.isEmpty ? UpdateService.defaultRepo : settings.updateRepo
        guard !UpdateService.normalizeRepo(repo).isEmpty else { return }
        if let last = settings.lastUpdateCheckAt, Date().timeIntervalSince(last) < 24 * 3600 { return }

        settings.lastUpdateCheckAt = Date()
        save()
        await UpdateService.shared.check(repo: repo)
    }
}
