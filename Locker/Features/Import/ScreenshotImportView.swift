import SwiftUI
import SwiftData
import UniformTypeIdentifiers
import AppKit

/// Drop in a screenshot of an assignment, check what was read, then add it.
///
/// The review step is the point: everything here is a proposal, and nothing is
/// saved until it's confirmed. Each field shows the exact words it came from, so
/// a wrong reading is visible rather than buried.
struct ScreenshotImportView: View {
    @EnvironmentObject private var app: AppState
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \SchoolClass.sortIndex) private var classes: [SchoolClass]

    @State private var draft: ImportDraft?
    @State private var schedule: ScheduleDraft?
    @State private var secondSemesterStart = ScreenshotImportView.defaultSecondSemesterStart()
    @State private var engine: ExtractionEngine?
    @State private var isReading = false
    @State private var errorText: String?
    @State private var isTargeted = false
    /// Kept so the screenshot can be re-read the other way when detection is wrong.
    @State private var lastImage: CGImage?
    @State private var lastOCRText = ""
    @State private var lastLines: [OCRLine] = []

    // Editable copies, so a misread can be corrected before saving.
    @State private var title = ""
    @State private var notes = ""
    @State private var hasDueDate = false
    @State private var dueDate = Date()
    @State private var selectedClassID: PersistentIdentifier?
    @State private var type: AssignmentType = .homework
    @State private var maxPoints: Double?
    @State private var markDone = false
    @State private var matchNote = ""
    /// The teacher the screenshot named, kept so it can be saved onto the class.
    @State private var screenshotTeacher = ""

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if let schedule {
                scheduleReview(schedule)
            } else if draft == nil {
                dropZone
            } else {
                reviewForm
            }
            Divider()
            footer
        }
        .frame(width: 520, height: 620)
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 1) {
                Text("Add from a screenshot").font(.system(size: 13, weight: .semibold))
                Text(headerSubtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(12)
    }

    private var dropZone: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: isReading ? "text.viewfinder" : "photo.on.rectangle.angled")
                .font(.system(size: 30, weight: .light))
                .foregroundStyle(isTargeted ? AnyShapeStyle(Theme.accent) : AnyShapeStyle(.tertiary))
            if isReading {
                ProgressView().controlSize(.small)
                Text("Reading the screenshot…").font(.system(size: 12)).foregroundStyle(.secondary)
            } else {
                Text("Drop a screenshot here").font(Theme.display(15))
                Text("or paste one with ⌘V").font(.system(size: 12)).foregroundStyle(.secondary)
                Button("Choose a file…", action: chooseFile)
                    .controlSize(.small)
                    .padding(.top, 2)
            }
            if let errorText {
                Text(errorText)
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.overdue)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 30)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: Theme.cardCorner)
                .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
                .foregroundStyle(isTargeted ? Theme.accent : Color.primary.opacity(0.15))
                .padding(14)
        )
        .onDrop(of: [.image, .fileURL], isTargeted: $isTargeted) { providers in
            load(from: providers)
            return true
        }
        .onPasteCommand(of: [.image, .fileURL]) { providers in
            load(from: providers)
        }
        .onAppear { readClipboardIfImage() }
    }

    @ViewBuilder
    private var reviewForm: some View {
        if let draft {
            Form {
                Section("What will be added") {
                    TextField("Title", text: $title)

                    Picker("Class", selection: $selectedClassID) {
                        Text("None").tag(nil as PersistentIdentifier?)
                        ForEach(classes.filter { !$0.isArchived }) { schoolClass in
                            Text(schoolClass.name).tag(schoolClass.persistentModelID as PersistentIdentifier?)
                        }
                    }
                    if !matchNote.isEmpty {
                        Text(matchNote)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }

                    Picker("Type", selection: $type) {
                        ForEach(AssignmentType.allCases, id: \.self) { Text($0.label).tag($0) }
                    }

                    Toggle("Has a due date", isOn: $hasDueDate)
                    if hasDueDate {
                        DatePicker("Due", selection: $dueDate, displayedComponents: .date)
                    }

                    HStack {
                        Text("Out of")
                        TextField("Points", value: $maxPoints, format: .number).frame(width: 70)
                        Spacer()
                    }

                    Toggle("Already turned in", isOn: $markDone)
                }

                Section("Notes") {
                    TextEditor(text: $notes)
                        .font(.system(size: 12))
                        .frame(minHeight: 60)
                }

                Section {
                    ForEach(readings, id: \.label) { reading in
                        LabeledContent(reading.label) {
                            Text(reading.value)
                                .font(Theme.data(11))
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                        }
                    }
                } header: {
                    Text("Read from the screenshot")
                } footer: {
                    Text("The exact words found on screen. Anything not listed here wasn't used.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }

                if !draft.rejected.isEmpty {
                    Section {
                        ForEach(draft.rejected, id: \.name) { rejected in
                            VStack(alignment: .leading, spacing: 1) {
                                Text("\(rejected.name): “\(rejected.value)”")
                                    .font(.system(size: 11, weight: .medium))
                                Text(rejected.reason)
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                            }
                        }
                    } header: {
                        Text("Ignored")
                    } footer: {
                        Text("These matched no text in the screenshot, so they were dropped rather than saved.")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .formStyle(.grouped)
        }
    }

    private var readings: [(label: String, value: String)] {
        guard let draft else { return [] }
        return [
            ("Due", draft.dueDateText),
            ("Assigned", draft.assignedDateText),
            ("Points", draft.pointsText),
            ("Status", draft.statusText),
            ("Teacher", draft.teacher),
            ("Attached", draft.attachments.joined(separator: ", ")),
        ].filter { !$0.1.isEmpty }
    }

    private var footer: some View {
        HStack {
            if draft != nil, !lastOCRText.isEmpty {
                Button("This is a schedule", action: rereadAsSchedule)
                    .help("Read this screenshot as a list of classes instead")
            }
            if schedule != nil, lastImage != nil {
                Button("This is one assignment", action: rereadAsAssignment)
                    .help("Read this screenshot as a single assignment instead")
            }
            if draft != nil || schedule != nil {
                Button("Start over") {
                    draft = nil
                    schedule = nil
                    engine = nil
                    errorText = nil
                }
            }
            Spacer()
            Button("Cancel") { dismiss() }
            if schedule != nil {
                Button("Add \(selectedRowCount) class\(selectedRowCount == 1 ? "" : "es")", action: saveSchedule)
                    .buttonStyle(.borderedProminent)
                    .disabled(selectedRowCount == 0)
                    .keyboardShortcut(.defaultAction)
            } else {
                Button("Add assignment", action: save)
                    .buttonStyle(.borderedProminent)
                    .disabled(draft == nil || title.trimmingCharacters(in: .whitespaces).isEmpty)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(12)
    }

    private func chooseFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.png, .jpeg, .tiff, .image]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url,
              let image = NSImage(contentsOf: url) else { return }
        read(image)
    }

    private func readClipboardIfImage() {
        guard draft == nil, !isReading else { return }
        guard let images = NSPasteboard.general.readObjects(forClasses: [NSImage.self]) as? [NSImage],
              let first = images.first else { return }
        read(first)
    }

    private func load(from providers: [NSItemProvider]) {
        guard let provider = providers.first else { return }
        isReading = true
        errorText = nil

        if provider.canLoadObject(ofClass: NSImage.self) {
            _ = provider.loadObject(ofClass: NSImage.self) { object, _ in
                Task { @MainActor in
                    guard let image = object as? NSImage else {
                        finishWithError("That didn't come through as an image.")
                        return
                    }
                    read(image)
                }
            }
            return
        }

        _ = provider.loadObject(ofClass: URL.self) { url, _ in
            Task { @MainActor in
                guard let url, let image = NSImage(contentsOf: url) else {
                    finishWithError("That file couldn't be opened as an image.")
                    return
                }
                read(image)
            }
        }
    }

    private func read(_ image: NSImage, forcing forcedKind: ScreenshotKind? = nil) {
        isReading = true
        errorText = nil
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            finishWithError("That image couldn't be read.")
            return
        }

        lastImage = cgImage
        Task {
            let result = await ScreenshotExtractor.extract(from: cgImage, forcing: forcedKind)
            await MainActor.run {
                isReading = false
                switch result {
                case .success(let outcome):
                    switch outcome.content {
                    case .schedule(let found):
                        schedule = found
                        engine = outcome.engine
                    case .assignment(let found):
                        guard found.isUsable else {
                            errorText = "No assignment or schedule details were found in that screenshot."
                            return
                        }
                        apply(outcome, draft: found)
                    }
                    lastOCRText = outcome.ocrText
                    lastLines = outcome.lines
                case .failure(let error):
                    errorText = error.localizedDescription
                }
            }
        }
    }

    private func finishWithError(_ message: String) {
        isReading = false
        errorText = message
    }

    private func apply(_ outcome: ExtractionOutcome, draft incoming: ImportDraft) {
        draft = incoming
        engine = outcome.engine

        title = incoming.title
        type = incoming.type
        maxPoints = incoming.maxPoints
        markDone = incoming.isTurnedIn == true
        hasDueDate = incoming.dueAt != nil
        dueDate = incoming.dueAt ?? Date()
        screenshotTeacher = incoming.teacher
        applyClassMatch(className: incoming.className, teacher: incoming.teacher)

        var lines: [String] = []
        if !incoming.summary.isEmpty { lines.append(incoming.summary) }
        if !incoming.attachments.isEmpty { lines.append("Attached: " + incoming.attachments.joined(separator: ", ")) }
        if !incoming.teacher.isEmpty { lines.append("Posted by \(incoming.teacher)") }
        notes = lines.joined(separator: "\n")
    }

    /// Picks the class this assignment belongs to, and says how it decided.
    ///
    /// A screenshot usually names the teacher rather than the course, so the
    /// teacher recorded on each class is often the only way back to it.
    private func applyClassMatch(className: String, teacher: String) {
        let active = classes.filter { !$0.isArchived }
        let candidates = active.map {
            ClassMatcher.Candidate(id: $0.idString, name: $0.name, teacher: $0.teacher, aliases: $0.aliases)
        }

        switch ClassMatcher.match(className: className, teacher: teacher, in: candidates) {
        case .matched(let id, let reason):
            let matched = active.first { $0.idString == id }
            selectedClassID = matched?.persistentModelID
            matchNote = "Picked because it \(reason.rawValue)."

        case .ambiguous(let ids, let reason):
            // Two classes fit equally well, so choosing one would be a coin flip.
            selectedClassID = nil
            let names = active.filter { ids.contains($0.idString) }.map(\.name)
            matchNote = "More than one class \(reason.rawValue) (\(names.joined(separator: ", "))). Pick the right one."

        case .none:
            selectedClassID = nil
            matchNote = teacher.isEmpty
                ? ""
                : "No class is set up with that teacher yet. Choosing one here will remember it."
        }
    }

    /// Detection reads the text rather than the picture, and school software is
    /// endlessly inventive, so the student gets the final say on what this is.
    private func rereadAsSchedule() {
        guard !lastOCRText.isEmpty else { return }
        isReading = true
        errorText = nil
        Task {
            let found = await ScreenshotExtractor.readAsSchedule(ocrText: lastOCRText, lines: lastLines)
            await MainActor.run {
                isReading = false
                guard let found, !found.rows.isEmpty else {
                    errorText = ModelScheduleReader.isAvailable
                        ? "No classes could be picked out of that screenshot."
                        : "Reading an unfamiliar schedule layout needs Apple Intelligence, which is turned off."
                    return
                }
                draft = found.rows.isEmpty ? draft : nil
                schedule = found
            }
        }
    }

    private func rereadAsAssignment() {
        guard let image = lastImage else { return }
        schedule = nil
        let nsImage = NSImage(cgImage: image, size: .zero)
        read(nsImage, forcing: .assignment)
    }

    private var headerSubtitle: String {
        if schedule != nil { return "Found a schedule. Pick which classes to add." }
        if draft != nil { return engine?.explanation ?? "" }
        return "Works with Google Classroom, Skyward, Canvas — anything on screen."
    }

    private var selectedRowCount: Int {
        schedule?.rows.filter(\.include).count ?? 0
    }

    private var hasSemesterRows: Bool {
        schedule?.rows.contains { $0.semester != 0 } ?? false
    }

    /// Schools split the year around the new year, so that is the sensible
    /// starting guess for when the second timetable takes over.
    static func defaultSecondSemesterStart() -> Date {
        let calendar = Calendar.current
        let now = Date()
        var comps = calendar.dateComponents([.year], from: now)
        // Before the new year, the switch is next January; after it, this one.
        if (calendar.component(.month, from: now)) >= 7 { comps.year = (comps.year ?? 2026) + 1 }
        comps.month = 1
        comps.day = 5
        return calendar.date(from: comps) ?? now
    }

    @ViewBuilder
    private func scheduleReview(_ found: ScheduleDraft) -> some View {
        Form {
            Section {
                ForEach(Array(found.rows.enumerated()), id: \.element.id) { index, row in
                    HStack(spacing: 8) {
                        Toggle("", isOn: Binding(
                            get: { schedule?.rows[index].include ?? false },
                            set: { schedule?.rows[index].include = $0 }
                        ))
                        .labelsHidden()

                        VStack(alignment: .leading, spacing: 1) {
                            TextField("Class name", text: Binding(
                                get: { schedule?.rows[index].name ?? "" },
                                set: { schedule?.rows[index].name = $0 }
                            ))
                            .textFieldStyle(.plain)
                            .font(.system(size: 12, weight: .medium))

                            Text(row.sourceLine)
                                .font(Theme.data(10))
                                .foregroundStyle(.tertiary)
                                .lineLimit(1)
                        }

                        Spacer(minLength: 0)

                        // Editable, because an unfamiliar layout can put a room
                        // number or a start time where the period belongs.
                        HStack(spacing: 3) {
                            Text("P").font(Theme.data(10)).foregroundStyle(.secondary)
                            TextField("—", value: Binding(
                                get: { schedule?.rows[index].period },
                                set: { schedule?.rows[index].period = $0 }
                            ), format: .number)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 38)
                        }

                        Picker("", selection: Binding(
                            get: { schedule?.rows[index].semester ?? 0 },
                            set: { schedule?.rows[index].semester = $0 }
                        )) {
                            Text("All year").tag(0)
                            Text("Sem 1").tag(1)
                            Text("Sem 2").tag(2)
                        }
                        .labelsHidden()
                        .frame(width: 90)
                    }
                    .padding(.vertical, 1)
                }
            } header: {
                HStack {
                    Text("Classes found")
                    Spacer()
                    Button(selectedRowCount == found.rows.count ? "Deselect all" : "Select all") {
                        let turnOn = selectedRowCount != found.rows.count
                        for index in schedule?.rows.indices ?? (0..<0) {
                            schedule?.rows[index].include = turnOn
                        }
                    }
                    .buttonStyle(.link)
                    .font(.system(size: 11))
                }
            } footer: {
                Text("Each line shows the text it came from. Names and periods can be edited here, and days and times can be set afterwards in Classes.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            if let table = found.table, found.isColumnMapped {
                Section {
                    ScrollView(.horizontal, showsIndicators: true) {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(spacing: 8) {
                                ForEach(0..<table.columnCount, id: \.self) { column in
                                    Picker("", selection: Binding(
                                        get: { schedule?.roles[column] ?? .ignore },
                                        set: { newRole in
                                            guard var roles = schedule?.roles else { return }
                                            // A role belongs to one column at a time.
                                            if newRole != .ignore {
                                                for index in roles.indices where roles[index] == newRole {
                                                    roles[index] = .ignore
                                                }
                                            }
                                            roles[column] = newRole
                                            schedule?.roles = roles
                                            remapColumns()
                                        }
                                    )) {
                                        ForEach(ColumnRole.allCases) { role in
                                            Text(role.label).tag(role)
                                        }
                                    }
                                    .labelsHidden()
                                    .frame(width: 104)
                                }
                            }

                            ForEach(Array(table.rows.prefix(4).enumerated()), id: \.offset) { _, cells in
                                HStack(spacing: 8) {
                                    ForEach(0..<table.columnCount, id: \.self) { column in
                                        Text(column < cells.count ? cells[column] : "")
                                            .font(Theme.data(10))
                                            .foregroundStyle(.secondary)
                                            .lineLimit(1)
                                            .frame(width: 104, alignment: .leading)
                                    }
                                }
                            }
                        }
                        .padding(.vertical, 2)
                    }
                } header: {
                    Text("Columns")
                } footer: {
                    Text("Locker worked these out from the layout. If a column is labelled wrongly, change it here and the list above updates.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }

            if hasSemesterRows {
                Section {
                    DatePicker("Second semester starts", selection: $secondSemesterStart, displayedComponents: .date)
                } footer: {
                    Text("This schedule runs a different timetable each semester. Locker shows whichever one is running, so it needs to know when they change over.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
    }

    /// Rebuilds the class list after a column is reassigned.
    private func remapColumns() {
        guard let current = schedule, let table = current.table else { return }
        var rebuilt = current
        rebuilt.rows = TableScheduleBuilder.rows(from: table, roles: current.roles)
        schedule = rebuilt
    }

    private func saveSchedule() {
        guard let schedule else { return }
        let existing = app.allClasses(includeArchived: true)
        var created = 0

        for row in schedule.rows where row.include {
            let name = row.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { continue }

            // Re-importing a schedule shouldn't duplicate what is already set up.
            if existing.contains(where: { SyncMerger.namesMatch($0.name, name) && $0.semester == row.semester }) {
                continue
            }

            let schoolClass = SchoolClass(
                name: name,
                teacher: row.teacher,
                room: row.room,
                period: row.period,
                colorHex: ClassPalette.hex(forIndex: existing.count + created),
                daysMask: Weekdays.mask(from: row.weekdays ?? Weekdays.schoolWeek),
                startMinutes: row.startMinutes,
                endMinutes: row.endMinutes,
                semester: row.semester,
                sortIndex: row.period ?? (existing.count + created)
            )
            app.context.insert(schoolClass)
            created += 1
        }

        if hasSemesterRows {
            app.settings.secondSemesterStart = Calendar.current.startOfDay(for: secondSemesterStart)
        }
        app.save()
        Task { await app.rescheduleReminders() }
        dismiss()
    }

    private func save() {
        let assignment = Assignment(
            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
            schoolClass: classes.first { $0.persistentModelID == selectedClassID },
            dueAt: hasDueDate ? Calendar.current.startOfDay(for: dueDate) : nil,
            hasDueTime: false,
            type: type,
            notes: notes
        )
        assignment.maxScore = maxPoints
        if markDone { assignment.setDone(true) }

        // Teach the class its teacher, so the next screenshot from the same
        // teacher files itself without being asked.
        if let schoolClass = assignment.schoolClass,
           schoolClass.teacher.trimmingCharacters(in: .whitespaces).isEmpty,
           !screenshotTeacher.isEmpty {
            schoolClass.teacher = screenshotTeacher
        }

        app.context.insert(assignment)
        app.save()
        Task { await app.rescheduleReminders() }
        dismiss()
    }
}
