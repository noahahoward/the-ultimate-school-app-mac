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
    @State private var engine: ExtractionEngine?
    @State private var isReading = false
    @State private var errorText: String?
    @State private var isTargeted = false

    // Editable copies, so a misread can be corrected before saving.
    @State private var title = ""
    @State private var notes = ""
    @State private var hasDueDate = false
    @State private var dueDate = Date()
    @State private var selectedClassID: PersistentIdentifier?
    @State private var type: AssignmentType = .homework
    @State private var maxPoints: Double?
    @State private var markDone = false

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if draft == nil { dropZone } else { reviewForm }
            Divider()
            footer
        }
        .frame(width: 520, height: 620)
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 1) {
                Text("Add from a screenshot").font(.system(size: 13, weight: .semibold))
                Text(draft == nil
                     ? "Works with Google Classroom, Skyward, Canvas — anything on screen."
                     : (engine?.explanation ?? ""))
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
            if draft != nil {
                Button("Start over") {
                    draft = nil
                    engine = nil
                    errorText = nil
                }
            }
            Spacer()
            Button("Cancel") { dismiss() }
            Button("Add assignment", action: save)
                .buttonStyle(.borderedProminent)
                .disabled(draft == nil || title.trimmingCharacters(in: .whitespaces).isEmpty)
                .keyboardShortcut(.defaultAction)
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

    private func read(_ image: NSImage) {
        isReading = true
        errorText = nil
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            finishWithError("That image couldn't be read.")
            return
        }

        Task {
            let result = await ScreenshotExtractor.extract(from: cgImage)
            await MainActor.run {
                isReading = false
                switch result {
                case .success(let outcome):
                    guard outcome.draft.isUsable else {
                        errorText = "No assignment details were found in that screenshot."
                        return
                    }
                    apply(outcome)
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

    private func apply(_ outcome: ExtractionOutcome) {
        let incoming = outcome.draft
        draft = incoming
        engine = outcome.engine

        title = incoming.title
        type = incoming.type
        maxPoints = incoming.maxPoints
        markDone = incoming.isTurnedIn == true
        hasDueDate = incoming.dueAt != nil
        dueDate = incoming.dueAt ?? Date()
        selectedClassID = matchClass(named: incoming.className, teacher: incoming.teacher)?.persistentModelID

        var lines: [String] = []
        if !incoming.summary.isEmpty { lines.append(incoming.summary) }
        if !incoming.attachments.isEmpty { lines.append("Attached: " + incoming.attachments.joined(separator: ", ")) }
        if !incoming.teacher.isEmpty { lines.append("Posted by \(incoming.teacher)") }
        notes = lines.joined(separator: "\n")
    }

    /// Matches the screenshot's class against one already set up, by name or by
    /// the teacher who posted it.
    private func matchClass(named name: String, teacher: String) -> SchoolClass? {
        let active = classes.filter { !$0.isArchived }
        if !name.isEmpty, let match = active.first(where: { SyncMerger.namesMatch($0.name, name) }) { return match }
        if !teacher.isEmpty, let match = active.first(where: {
            !$0.teacher.isEmpty && $0.teacher.localizedCaseInsensitiveContains(teacher)
        }) { return match }
        return nil
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

        app.context.insert(assignment)
        app.save()
        Task { await app.rescheduleReminders() }
        dismiss()
    }
}
