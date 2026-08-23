import SwiftUI
import SwiftData

struct ClassEditor: View {
    @EnvironmentObject private var app: AppState
    @Environment(\.dismiss) private var dismiss
    @Bindable var schoolClass: SchoolClass

    @State private var aliasText: String = ""
    @State private var hasTimes: Bool
    @State private var startTime: Date
    @State private var endTime: Date

    init(schoolClass: SchoolClass) {
        self.schoolClass = schoolClass
        let hasTimes = schoolClass.startMinutes != nil
        _hasTimes = State(initialValue: hasTimes)
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        _startTime = State(initialValue: ScheduleEngine.date(today, atMinutes: schoolClass.startMinutes ?? 8 * 60))
        _endTime = State(initialValue: ScheduleEngine.date(today, atMinutes: schoolClass.endMinutes ?? 8 * 60 + 50))
    }

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section {
                    TextField("Name", text: $schoolClass.name)
                    TextField("Teacher", text: $schoolClass.teacher)
                    TextField("Room", text: $schoolClass.room)
                    TextField("Period", value: $schoolClass.period, format: .number)
                        .help("Optional. Used to order classes that have no set time.")
                }

                Section {
                    TextField("Short names", text: $aliasText)
                        .help("Comma separated. Typing any of these in the add box picks this class.")
                    Text("Comma separated, e.g. “bio, biology”. Typing one of these in the add box picks this class.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                } header: {
                    Text("Nicknames")
                }

                Section("Color") {
                    LazyVGrid(columns: Array(repeating: GridItem(.fixed(26), spacing: 8), count: 10), spacing: 8) {
                        ForEach(ClassPalette.hexes, id: \.self) { hex in
                            Circle()
                                .fill(Theme.classColor(hex))
                                .frame(width: 22, height: 22)
                                .overlay(
                                    Circle()
                                        .strokeBorder(.primary, lineWidth: schoolClass.colorHex == hex ? 2 : 0)
                                )
                                .onTapGesture { schoolClass.colorHex = hex }
                        }
                    }
                    .padding(.vertical, 2)
                }

                Section("Meets") {
                    HStack(spacing: 6) {
                        ForEach(2...6, id: \.self) { weekday in dayToggle(weekday) }
                        Divider().frame(height: 18)
                        ForEach([7, 1], id: \.self) { weekday in dayToggle(weekday) }
                    }

                    if app.settings.scheduleKind == .alternatingAB {
                        Picker("On", selection: abBinding) {
                            ForEach(ABDesignation.allCases, id: \.self) { Text($0.label).tag($0) }
                        }
                        .pickerStyle(.segmented)
                    }

                    Toggle("Set a time", isOn: $hasTimes)
                    if hasTimes {
                        DatePicker("Starts", selection: $startTime, displayedComponents: .hourAndMinute)
                        DatePicker("Ends", selection: $endTime, displayedComponents: .hourAndMinute)
                    }
                }

                Section("Grading") {
                    Picker("Mode", selection: gradingBinding) {
                        ForEach(GradingMode.allCases, id: \.self) { Text($0.label).tag($0) }
                    }
                    HStack {
                        Text("Goal")
                        Slider(value: $schoolClass.goalPercent, in: 60...100, step: 1)
                        Text(String(format: "%.0f%%", schoolClass.goalPercent))
                            .font(Theme.data(12))
                            .frame(width: 42, alignment: .trailing)
                    }
                }

                if schoolClass.isLinked {
                    Section("Google Classroom") {
                        Text("Linked. New assignments arrive automatically; your edits here stay put.")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .formStyle(.grouped)

            Divider()

            HStack {
                Button(schoolClass.isArchived ? "Unarchive" : "Archive") {
                    schoolClass.isArchived.toggle()
                }
                Spacer()
                Button("Done") { commit() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(12)
        }
        .frame(width: 460, height: 620)
        .onAppear { aliasText = schoolClass.aliases.joined(separator: ", ") }
        .onDisappear(perform: commit)
    }

    private func dayToggle(_ weekday: Int) -> some View {
        let isOn = schoolClass.meetingDays.contains(weekday)
        return Button {
            var days = schoolClass.meetingDays
            if isOn { days.remove(weekday) } else { days.insert(weekday) }
            schoolClass.meetingDays = days
        } label: {
            Text(Weekdays.letter(weekday))
                .font(Theme.data(12, weight: .semibold))
                .frame(width: 26, height: 24)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(isOn ? Theme.classColor(schoolClass.colorHex).opacity(0.85) : Color.primary.opacity(0.07))
                )
                .foregroundStyle(isOn ? .white : .secondary)
        }
        .buttonStyle(.plain)
    }

    private var abBinding: Binding<ABDesignation> {
        Binding(get: { schoolClass.abDesignation }, set: { schoolClass.abDesignation = $0 })
    }

    private var gradingBinding: Binding<GradingMode> {
        Binding(get: { schoolClass.gradingMode }, set: { schoolClass.gradingMode = $0 })
    }

    private func commit() {
        // "New Class" inserts the row before it is filled in, so closing the
        // editor without typing anything would leave a nameless class sitting
        // in the list forever.
        if schoolClass.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           schoolClass.assignments.isEmpty {
            app.context.delete(schoolClass)
            app.save()
            dismiss()
            return
        }

        schoolClass.aliases = aliasText
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        if hasTimes {
            schoolClass.startMinutes = ScheduleEngine.minutesIntoDay(startTime)
            schoolClass.endMinutes = ScheduleEngine.minutesIntoDay(endTime)
        } else {
            schoolClass.startMinutes = nil
            schoolClass.endMinutes = nil
        }
        app.save()
        Task { await app.rescheduleReminders() }
        dismiss()
    }
}
