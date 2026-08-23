import SwiftUI
import SwiftData

struct ClassesView: View {
    @EnvironmentObject private var app: AppState
    @Query(sort: \SchoolClass.sortIndex) private var classes: [SchoolClass]
    @State private var expandedResources: Set<String> = []
    @State private var editingAssignment: Assignment?
    @State private var editing: SchoolClass?
    @State private var showArchived = false
    @State private var pendingDeletion: SchoolClass?

    private var visible: [SchoolClass] {
        classes.filter { showArchived || !$0.isArchived }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.gutter) {
                if visible.isEmpty {
                    Panel {
                        EmptyState(
                            symbol: "calendar.badge.plus",
                            title: "No classes yet",
                            message: "Add your classes so assignments can be sorted and the day view knows your schedule.",
                            actionTitle: "Add a class",
                            action: addClass
                        )
                    }
                } else {
                    arranged
                }
            }
            .padding(Theme.gutter)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .navigationTitle("Classes")
        .toolbar {
            ToolbarItem {
                Menu {
                    Toggle("Show archived classes", isOn: $showArchived)
                } label: {
                    Label("Options", systemImage: "ellipsis.circle")
                }
            }
            ToolbarItem {
                // Spelled out, because the window already has a "+" that adds
                // work — two plus icons side by side say nothing about which.
                Button("New Class", action: addClass)
            }
        }
        .sheet(item: $editing) { ClassEditor(schoolClass: $0).environmentObject(app) }
        .sheet(item: $editingAssignment) { AssignmentEditor(assignment: $0).environmentObject(app) }
        .confirmationDialog(
            "Delete \(pendingDeletion?.name ?? "this class")?",
            isPresented: Binding(get: { pendingDeletion != nil }, set: { if !$0 { pendingDeletion = nil } }),
            titleVisibility: .visible
        ) {
            Button("Delete the class and its work", role: .destructive) {
                guard let schoolClass = pendingDeletion else { return }
                app.context.delete(schoolClass)
                app.save()
                pendingDeletion = nil
            }
            Button("Archive it instead") {
                pendingDeletion?.isArchived = true
                app.save()
                pendingDeletion = nil
            }
            Button("Cancel", role: .cancel) { pendingDeletion = nil }
        } message: {
            // Deleting cascades to everything attached to the class, and there
            // is no undo, so the count is spelled out before it happens.
            let assignments = pendingDeletion?.assignments.count ?? 0
            Text(assignments == 0
                 ? "This can't be undone. Archiving keeps it out of the way instead."
                 : "This also deletes \(assignments) assignment\(assignments == 1 ? "" : "s") and any grades recorded for it. This can't be undone.")
        }
        .onAppear {
            if let id = app.selectedClassID {
                editing = classes.first { $0.persistentModelID == id }
                app.selectedClassID = nil
            }
        }
    }

    // MARK: - Arrangement

    /// Period order within a semester, which is the order the day happens in.
    private func inOrder(_ group: [SchoolClass]) -> [SchoolClass] {
        group.sorted {
            ($0.period ?? 99, $0.name.lowercased()) < ($1.period ?? 99, $1.name.lowercased())
        }
    }

    private func semesterLabel(_ semester: Int) -> String {
        switch semester {
        case 1: "Semester 1"
        case 2: "Semester 2"
        default: "All year"
        }
    }

    /// Term is the outer grouping and letter days sit inside it, because a
    /// school can run both: two timetables a year, each alternating A and B.
    /// Treating them as alternatives hid whichever one came second.
    @ViewBuilder
    private var arranged: some View {
        let semesters = Set(visible.map(\.semester)).sorted()
        if semesters == [0] {
            group(visible, heading: nil)
        } else {
            ForEach(semesters, id: \.self) { semester in
                let inTerm = visible.filter { $0.semester == semester }
                if !inTerm.isEmpty {
                    group(inTerm, heading: semesterLabel(semester))
                }
            }
        }
    }

    @ViewBuilder
    private func group(_ inTerm: [SchoolClass], heading: String?) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if let heading {
                SectionHeading(title: heading, count: inTerm.count)
            }

            if app.settings.scheduleKind == .alternatingAB {
                let everyDay = inOrder(inTerm.filter { $0.abDesignation == .both })
                ForEach(everyDay) { classCard($0) }

                HStack(alignment: .top, spacing: Theme.gutter) {
                    dayColumn(.a, in: inTerm)
                    dayColumn(.b, in: inTerm)
                }
            } else {
                ForEach(inOrder(inTerm)) { classCard($0) }
            }
        }
    }

    private func dayColumn(_ designation: ABDesignation, in inTerm: [SchoolClass]) -> some View {
        let group = inOrder(inTerm.filter { $0.abDesignation == designation })
        let letter = designation == .a ? "A" : "B"

        return VStack(alignment: .leading, spacing: 8) {
            SectionHeading(title: "\(letter) days", count: group.count, accent: Theme.accent)

            ForEach(group) { classCard($0) }

            if group.isEmpty {
                Text("Drag a class here to put it on \(letter) days.")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 18)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: Theme.cardCorner, style: .continuous)
                .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [5, 4]))
                .foregroundStyle(Color.primary.opacity(0.12))
        )
        .dropDestination(for: String.self) { ids, _ in
            move(ids, to: designation)
        }
    }

    /// Dropping a class into a column is how its day gets set when the schedule
    /// itself didn't say.
    private func move(_ ids: [String], to designation: ABDesignation) -> Bool {
        var moved = false
        for id in ids {
            guard let schoolClass = classes.first(where: { $0.idString == id }) else { continue }
            schoolClass.abDesignation = designation
            moved = true
        }
        if moved {
            app.save()
            Task { await app.rescheduleReminders() }
        }
        return moved
    }

    private func addClass() {
        let created = SchoolClass(
            name: "",
            colorHex: ClassPalette.hex(forIndex: classes.count),
            daysMask: Weekdays.mask(from: Weekdays.schoolWeek),
            sortIndex: classes.count
        )
        app.context.insert(created)
        app.save()
        editing = created
    }

    private func classCard(_ schoolClass: SchoolClass) -> some View {
        let openCount = schoolClass.assignments.filter { !$0.isDone && !$0.isResource }.count
        let resources = schoolClass.assignments
            .filter(\.isResource)
            .sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }

        // One stack, not two loose views: Panel styles whatever it is handed,
        // and a pair of them would each come out as a card of its own.
        return Panel {
            VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 12) {
                RoundedRectangle(cornerRadius: 3)
                    .fill(Theme.classColor(schoolClass.colorHex))
                    .frame(width: 4, height: 40)

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(schoolClass.name.isEmpty ? "Untitled class" : schoolClass.name)
                            .font(Theme.display(15, weight: .semibold))
                        if schoolClass.isArchived { Chip(text: "Archived") }
                        if schoolClass.isLinked {
                            Chip(text: "Classroom", symbol: "link", tint: Theme.accent)
                        }
                    }

                    Text(detailLine(schoolClass))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)

                    HStack(spacing: 6) {
                        ForEach(1...7, id: \.self) { weekday in
                            let meets = schoolClass.meetingDays.contains(weekday)
                            Text(Weekdays.letter(weekday))
                                .font(Theme.data(10, weight: meets ? .bold : .regular))
                                .foregroundStyle(meets ? AnyShapeStyle(Theme.classColor(schoolClass.colorHex)) : AnyShapeStyle(.quaternary))
                                .frame(width: 15)
                        }
                        if app.settings.scheduleKind == .alternatingAB, schoolClass.abDesignation != .both {
                            Chip(text: schoolClass.abDesignation.label, tint: Theme.accent)
                        }
                    }
                    .padding(.top, 2)
                }

                Spacer(minLength: 0)

                VStack(alignment: .trailing, spacing: 4) {
                    Text("\(openCount)")
                        .font(Theme.display(18, weight: .bold))
                    Text("open")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture { editing = schoolClass }

            if !resources.isEmpty { resourceShelf(resources, for: schoolClass) }
            }
        }
        .draggable(schoolClass.idString)
        .contextMenu {
            if app.settings.scheduleKind == .alternatingAB {
                Picker("Meets on", selection: Binding(
                    get: { schoolClass.abDesignation },
                    set: { schoolClass.abDesignation = $0; app.save() }
                )) {
                    ForEach(ABDesignation.allCases, id: \.self) { Text($0.label).tag($0) }
                }
                Divider()
            }
            Button("Edit") { editing = schoolClass }
            Button(schoolClass.isArchived ? "Unarchive" : "Archive") {
                schoolClass.isArchived.toggle()
                app.save()
            }
            Divider()
            Button("Delete", role: .destructive) { pendingDeletion = schoolClass }
        }
    }

    /// The things a class hands out to be kept rather than done.
    @ViewBuilder
    private func resourceShelf(_ resources: [Assignment], for schoolClass: SchoolClass) -> some View {
        let open = expandedResources.contains(schoolClass.idString)

        Divider().padding(.vertical, 6)

        Button {
            if open { expandedResources.remove(schoolClass.idString) }
            else { expandedResources.insert(schoolClass.idString) }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: open ? "chevron.down" : "chevron.right")
                    .font(.system(size: 9, weight: .semibold))
                Text("\(resources.count) resource\(resources.count == 1 ? "" : "s")")
                    .font(.system(size: 11, weight: .medium))
                Spacer(minLength: 0)
            }
            .foregroundStyle(.secondary)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)

        if open {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(resources) { resource in
                    HStack(spacing: 6) {
                        Image(systemName: resource.type.symbol)
                            .font(.system(size: 10))
                            .foregroundStyle(.tertiary)
                        Text(resource.title)
                            .font(.system(size: 11))
                            .lineLimit(1)
                        Spacer(minLength: 0)
                        if let link = resource.externalRefs.first?.url, let url = URL(string: link) {
                            Link("Open", destination: url).font(.system(size: 10))
                        }
                    }
                    .contentShape(Rectangle())
                    .onTapGesture { editingAssignment = resource }
                }
            }
            .padding(.top, 4)
            .padding(.leading, 14)
        }
    }

    private func detailLine(_ schoolClass: SchoolClass) -> String {
        var parts: [String] = []
        if let period = schoolClass.period { parts.append("Period \(period)") }
        if let range = schoolClass.timeRangeText { parts.append(range) }
        if !schoolClass.room.isEmpty { parts.append(schoolClass.room) }
        if !schoolClass.teacher.isEmpty { parts.append(schoolClass.teacher) }
        return parts.isEmpty ? "No schedule set" : parts.joined(separator: " · ")
    }
}
