import SwiftUI
import SwiftData

/// First launch: enough to make Today useful, and not one field more.
struct OnboardingView: View {
    @EnvironmentObject private var app: AppState
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \SchoolClass.sortIndex) private var classes: [SchoolClass]

    @State private var step = 0
    @State private var newClassName = ""
    @State private var newClassSemester = 0

    var body: some View {
        VStack(spacing: 0) {
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            Divider()
            footer
        }
        .frame(width: 560, height: 480)
    }

    @ViewBuilder
    private var content: some View {
        switch step {
        case 0: welcome
        case 1: scheduleStep
        default: classesStep
        }
    }

    private var welcome: some View {
        VStack(spacing: 14) {
            Spacer()
            Image(systemName: "graduationcap.fill")
                .font(.system(size: 40))
                .foregroundStyle(Theme.accent)
            Text("Locker")
                .font(Theme.display(30, weight: .bold))
            Text("Everything due, all in one place.\nPoint Locker at the page your work is on and it reads the rest.")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Spacer()
        }
        .padding(30)
    }

    private var scheduleStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            stepHeader("How does your schedule work?", "This decides how the day view lays out.")

            Picker("", selection: scheduleBinding) {
                ForEach(ScheduleKind.allCases, id: \.self) { Text($0.label).tag($0) }
            }
            .pickerStyle(.radioGroup)
            .labelsHidden()

            DatePicker(
                "First day of school",
                selection: Binding(
                    get: { app.settings.firstDayOfSchool ?? Date() },
                    set: { app.settings.firstDayOfSchool = $0; syncAnchor() }
                ),
                displayedComponents: .date
            )

            if app.settings.scheduleKind == .alternatingAB {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Is \(firstDayText) an A day or a B day?")
                        .font(.system(size: 12, weight: .medium))
                    Picker("", selection: anchorBinding) {
                        Text("A day").tag(true)
                        Text("B day").tag(false)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    Text("Everything after it alternates from there. If the letters ever drift after a day off, you can reset this in Settings.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.top, 4)
            }

            Spacer()
        }
        .padding(30)
        .onAppear {
            if app.settings.firstDayOfSchool == nil {
                app.settings.firstDayOfSchool = Calendar.current.startOfDay(for: Date())
            }
            syncAnchor()
        }
    }

    private var classesStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            stepHeader("Add your classes",
                       "Fastest is to let Locker read your timetable. You can always correct it after.")

            VStack(spacing: 8) {
                if BrowserTabs.anyBrowserRunning {
                    Button {
                        startImport(.browserPage)
                    } label: {
                        onboardingAction("Read my timetable from a browser page",
                                         "Open it in a tab and Locker reads it straight off",
                                         "doc.text.magnifyingglass")
                    }
                    .buttonStyle(.plain)
                }

                Button {
                    startImport(nil)
                } label: {
                    onboardingAction("Read it from a screenshot",
                                     "Pick a window, or choose a picture or PDF",
                                     "camera.viewfinder")
                }
                .buttonStyle(.plain)
            }

            Divider()

            Text("Or type them in")
                .font(.system(size: 12, weight: .medium))

            HStack(spacing: 8) {
                TextField("Class name", text: $newClassName)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(addClass)
                Picker("", selection: $newClassSemester) {
                    ForEach(SemesterChoice.all, id: \.value) { Text($0.label).tag($0.value) }
                }
                .labelsHidden()
                .frame(width: 116)
                Button("Add", action: addClass)
                    .disabled(newClassName.trimmingCharacters(in: .whitespaces).isEmpty)
            }

            if classes.isEmpty {
                Text("No classes yet.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            } else {
                ScrollView {
                    VStack(spacing: 4) {
                        ForEach(classes) { schoolClass in
                            HStack(spacing: 8) {
                                ClassDot(hex: schoolClass.colorHex)
                                Text(schoolClass.name)
                                    .font(.system(size: 12))
                                Spacer()
                                Picker("", selection: Binding(
                                    get: { schoolClass.semester },
                                    set: { schoolClass.semester = $0; app.save() }
                                )) {
                                    ForEach(SemesterChoice.all, id: \.value) { Text($0.label).tag($0.value) }
                                }
                                .labelsHidden()
                                .frame(width: 108)
                                Button {
                                    app.context.delete(schoolClass)
                                    app.save()
                                } label: {
                                    Image(systemName: "xmark.circle.fill").foregroundStyle(.tertiary)
                                }
                                .buttonStyle(.plain)
                            }
                            .padding(.vertical, 3)
                        }
                    }
                }
                .frame(maxHeight: 150)
            }

            Spacer()
        }
        .padding(30)
    }

    /// One of the ways in, drawn as a row rather than a plain button so the
    /// choice reads at a glance.
    private func onboardingAction(_ title: String, _ subtitle: String, _ symbol: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 15))
                .foregroundStyle(Theme.accent)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.system(size: 13, weight: .medium))
                Text(subtitle).font(.system(size: 11)).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Theme.accent.opacity(0.08))
        )
        .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    /// Leaves onboarding and opens the importer.
    ///
    /// Both live in the one sheet slot, so the first has to be gone before the
    /// second is asked for, or they fight over it.
    private func startImport(_ entry: ImportEntry?) {
        app.settings.hasCompletedOnboarding = true
        app.importEntry = entry
        app.save()
        dismiss()
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(350))
            app.activeSheet = .screenshotImport
        }
    }

    private func stepHeader(_ title: String, _ subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(Theme.display(19, weight: .semibold))
            Text(subtitle).font(.system(size: 12)).foregroundStyle(.secondary)
        }
    }

    private var footer: some View {
        HStack {
            if step > 0 {
                Button("Back") { step -= 1 }
            }
            Spacer()
            Text("\(step + 1) of 3")
                .font(Theme.data(11))
                .foregroundStyle(.tertiary)
            Spacer()
            Button(step == 2 ? "Start using Locker" : "Continue") {
                if step == 2 { finish() } else { step += 1 }
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.defaultAction)
        }
        .padding(12)
    }

    private var scheduleBinding: Binding<ScheduleKind> {
        Binding(
            get: { app.settings.scheduleKind },
            set: { kind in
                app.settings.scheduleKind = kind
                if kind == .alternatingAB, app.settings.abAnchorDate == nil {
                    app.settings.abAnchorDate = Calendar.current.startOfDay(for: Date())
                }
            }
        )
    }

    private var anchorBinding: Binding<Bool> {
        Binding(
            get: { app.settings.abAnchorIsA },
            set: { isA in
                app.settings.abAnchorIsA = isA
                syncAnchor()
            }
        )
    }

    /// The letters are counted from the first day of school, not from today.
    /// Today may be a weekend, a holiday, or the middle of August.
    private func syncAnchor() {
        let day = app.settings.firstDayOfSchool ?? Date()
        app.settings.abAnchorDate = Calendar.current.startOfDay(for: day)
    }

    private var firstDayText: String {
        guard let day = app.settings.firstDayOfSchool else { return "your first day" }
        return day.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
    }

    private func addClass() {
        let name = newClassName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        let created = SchoolClass(
            name: name,
            colorHex: ClassPalette.hex(forIndex: classes.count),
            daysMask: Weekdays.mask(from: Weekdays.schoolWeek),
            semester: newClassSemester,
            sortIndex: classes.count
        )
        app.context.insert(created)
        app.save()
        newClassName = ""
    }

    private func finish() {
        app.settings.hasCompletedOnboarding = true
        app.save()
        dismiss()
    }
}

/// How a class is offered: all year, or one half of it.
enum SemesterChoice {
    static let all: [(value: Int, label: String)] = [
        (0, "All year"), (1, "Semester 1"), (2, "Semester 2"),
    ]
}
