import SwiftUI
import SwiftData

struct AssignmentEditor: View {
    @EnvironmentObject private var app: AppState
    @Environment(\.dismiss) private var dismiss
    @Bindable var assignment: Assignment

    @Query(sort: \SchoolClass.sortIndex) private var classes: [SchoolClass]

    @State private var hasDueDate: Bool
    @State private var dueDate: Date
    @State private var includeTime: Bool
    @State private var repeatCount = 0
    @State private var isConfirmingDelete = false

    init(assignment: Assignment) {
        self.assignment = assignment
        _hasDueDate = State(initialValue: assignment.dueAt != nil)
        _dueDate = State(initialValue: assignment.dueAt ?? Date())
        _includeTime = State(initialValue: assignment.hasDueTime)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Form {
                Section {
                    TextField("Title", text: $assignment.title)

                    Picker("Class", selection: classBinding) {
                        Text("None").tag(nil as PersistentIdentifier?)
                        ForEach(classes.filter { !$0.isArchived }) { schoolClass in
                            Text(schoolClass.name).tag(schoolClass.persistentModelID as PersistentIdentifier?)
                        }
                    }

                    Picker("Kind", selection: Binding(
                        get: { assignment.isResource },
                        set: { isResource in
                            assignment.isResource = isResource
                            // Nothing to hand in, so nothing to be late for.
                            if isResource {
                                hasDueDate = false
                                assignment.dueAt = nil
                                repeatCount = 0
                            }
                        }
                    )) {
                        Text("Work to do").tag(false)
                        Text("Resource").tag(true)
                    }
                    .pickerStyle(.segmented)

                    Picker("Type", selection: typeBinding) {
                        ForEach(AssignmentType.allCases, id: \.self) { type in
                            Label(type.label, systemImage: type.symbol).tag(type)
                        }
                    }

                    Picker("Priority", selection: priorityBinding) {
                        ForEach(Priority.allCases, id: \.self) { priority in
                            Text(priority.label).tag(priority)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                // A resource is never due, never repeats, never scored — so
                // none of that is asked about.
                if !assignment.isResource {
                    Section("Due") {
                        Toggle("Has a due date", isOn: $hasDueDate)
                        if hasDueDate {
                            DatePicker(
                                "Due",
                                selection: $dueDate,
                                displayedComponents: includeTime ? [.date, .hourAndMinute] : [.date]
                            )
                            Toggle("Due at a specific time", isOn: $includeTime)
                        }
                    }

                    Section("Repeat") {
                        Stepper(repeatCount == 0
                                ? "Doesn't repeat"
                                : "Also add \(repeatCount) more, a week apart",
                                value: $repeatCount, in: 0...Recurrence.maximumRepeats)
                            .disabled(!hasDueDate)
                        if !hasDueDate {
                            Text("Give it a due date to repeat it.")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }
                    }

                    Section("Planning") {
                        TextField("Estimated minutes", value: $assignment.estimatedMinutes, format: .number)
                        Toggle("Mute reminders for this", isOn: $assignment.remindersSuppressed)
                    }

                    Section("Grade") {
                        HStack {
                            TextField("Score", value: $assignment.score, format: .number)
                            Text("/")
                                .foregroundStyle(.secondary)
                            TextField("Out of", value: $assignment.maxScore, format: .number)
                        }
                        if let percent = assignment.percentScore {
                            LabeledContent("Percent", value: DueFormat.percentText(percent))
                        }
                    }
                }

                Section("Notes") {
                    TextEditor(text: $assignment.notes)
                        .font(.system(size: 12))
                        .frame(minHeight: 70)
                }
            }
            .formStyle(.grouped)

            Divider()

            HStack {
                Button("Delete", role: .destructive) { isConfirmingDelete = true }
                    .confirmationDialog(
                        "Delete “\(assignment.title)”?",
                        isPresented: $isConfirmingDelete,
                        titleVisibility: .visible
                    ) {
                        Button("Delete", role: .destructive) {
                            app.context.delete(assignment)
                            app.save()
                            dismiss()
                        }
                        Button("Cancel", role: .cancel) {}
                    } message: {
                        Text("This can't be undone.")
                    }
                if let url = assignment.externalRefs.compactMap(\.url).first, let link = URL(string: url) {
                    Button("Open in Classroom") { NSWorkspace.shared.open(link) }
                }
                Spacer()
                Button("Done") { commit() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(12)
        }
        .frame(width: 440, height: 560)
        .onDisappear(perform: commit)
    }

    private var classBinding: Binding<PersistentIdentifier?> {
        Binding(
            get: { assignment.schoolClass?.persistentModelID },
            set: { id in assignment.schoolClass = classes.first { $0.persistentModelID == id } }
        )
    }

    /// Copies the assignment forward a week at a time. Made once, here, rather
    /// than by a rule the app has to keep evaluating forever.
    private func addRepeats() {
        guard repeatCount > 0, hasDueDate else { return }
        let dates = Recurrence.weekly(
            after: dueDate,
            count: repeatCount,
            notLaterThan: app.settings.lastDayOfSchool
        )
        for date in dates {
            let copy = Assignment(
                title: assignment.title,
                schoolClass: assignment.schoolClass,
                dueAt: date,
                hasDueTime: assignment.hasDueTime,
                type: assignment.type,
                priority: assignment.priority,
                notes: assignment.notes,
                estimatedMinutes: assignment.estimatedMinutes
            )
            copy.maxScore = assignment.maxScore
            copy.gradeCategory = assignment.gradeCategory
            app.context.insert(copy)
        }
        repeatCount = 0
    }

    private var typeBinding: Binding<AssignmentType> {
        Binding(get: { assignment.type }, set: { assignment.type = $0 })
    }

    private var priorityBinding: Binding<Priority> {
        Binding(get: { assignment.priority }, set: { assignment.priority = $0 })
    }

    private func commit() {
        assignment.dueAt = hasDueDate ? dueDate : nil
        assignment.hasDueTime = hasDueDate && includeTime
        addRepeats()
        app.save()
        Task { await app.rescheduleReminders() }
        dismiss()
    }
}
