import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct AssignmentsView: View {
    enum Layout: String, CaseIterable { case list, week }
    enum Filter: String, CaseIterable {
        case open, all, done
        var label: String {
            switch self {
            case .open: "Open"
            case .all: "All"
            case .done: "Done"
            }
        }
    }

    @EnvironmentObject private var app: AppState
    @Query private var assignments: [Assignment]
    @Query(sort: \SchoolClass.sortIndex) private var classes: [SchoolClass]

    @State private var layout: Layout = .list
    @State private var filter: Filter = .open
    @State private var classFilter: PersistentIdentifier?
    @State private var search = ""
    @State private var editing: Assignment?
    @State private var weekOffset = 0

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            content
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .navigationTitle("Assignments")
        .searchable(text: $search, placement: .toolbar, prompt: "Search assignments")
        .sheet(item: $editing) { AssignmentEditor(assignment: $0).environmentObject(app) }
    }

    // MARK: - Chrome

    private var toolbar: some View {
        HStack(spacing: 12) {
            Picker("", selection: $layout) {
                Label("List", systemImage: "list.bullet").tag(Layout.list)
                Label("Week", systemImage: "calendar").tag(Layout.week)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 130)

            if layout == .list {
                Picker("", selection: $filter) {
                    ForEach(Filter.allCases, id: \.self) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 170)
            } else {
                HStack(spacing: 2) {
                    Button { weekOffset -= 1 } label: { Image(systemName: "chevron.left") }
                    Button("This week") { weekOffset = 0 }
                        .disabled(weekOffset == 0)
                    Button { weekOffset += 1 } label: { Image(systemName: "chevron.right") }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            Picker("", selection: $classFilter) {
                Text("All classes").tag(nil as PersistentIdentifier?)
                ForEach(classes.filter { !$0.isArchived }) { schoolClass in
                    Text(schoolClass.name).tag(schoolClass.persistentModelID as PersistentIdentifier?)
                }
            }
            .labelsHidden()
            .frame(width: 160)

            Spacer()

            Button {
                app.presentQuickAdd()
            } label: {
                Label("Add", systemImage: "plus")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
        }
        .padding(.horizontal, Theme.gutter)
        .padding(.vertical, 10)
    }

    @ViewBuilder
    private var content: some View {
        switch layout {
        case .list: listLayout
        case .week: weekLayout
        }
    }

    // MARK: - Filtering

    private var filtered: [Assignment] {
        assignments.filter { assignment in
            switch filter {
            case .open where assignment.isDone: return false
            case .done where !assignment.isDone: return false
            default: break
            }
            if let classFilter, assignment.schoolClass?.persistentModelID != classFilter { return false }
            if !search.isEmpty {
                let haystack = assignment.title + " " + assignment.notes + " " + (assignment.schoolClass?.name ?? "")
                if !haystack.localizedCaseInsensitiveContains(search) { return false }
            }
            return true
        }
    }

    // MARK: - List

    private var listLayout: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: Theme.gutter) {
                if filtered.isEmpty {
                    Panel {
                        EmptyState(
                            symbol: "checklist",
                            title: search.isEmpty ? "Nothing here yet" : "No matches",
                            message: search.isEmpty
                                ? "Add work from Today, or connect Google Classroom in Settings."
                                : "Try a different search.",
                            actionTitle: search.isEmpty ? "Add work" : nil,
                            action: search.isEmpty ? { app.presentQuickAdd() } : nil
                        )
                    }
                } else {
                    ForEach(buckets, id: \.title) { bucket in
                        VStack(alignment: .leading, spacing: 8) {
                            SectionHeading(title: bucket.title, count: bucket.items.count, accent: bucket.tint)
                            Panel(padding: 6) {
                                VStack(spacing: 0) {
                                    ForEach(Array(bucket.items.enumerated()), id: \.element.persistentModelID) { index, item in
                                        if index > 0 { Divider().padding(.leading, 34) }
                                        AssignmentRow(assignment: item)
                                            .onTapGesture { editing = item }
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .padding(Theme.gutter)
        }
    }

    private struct Bucket {
        var title: String
        var items: [Assignment]
        var tint: Color
    }

    /// Grouped by how soon it matters, which is the only ordering that helps
    /// when the list gets long.
    private var buckets: [Bucket] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())

        func sortKey(_ assignment: Assignment) -> Date { assignment.dueAt ?? .distantFuture }
        let sorted = filtered.sorted { sortKey($0) < sortKey($1) }

        var overdue: [Assignment] = [], week: [Assignment] = [], later: [Assignment] = [], undated: [Assignment] = []
        for assignment in sorted {
            guard let dueAt = assignment.dueAt else { undated.append(assignment); continue }
            let day = calendar.startOfDay(for: dueAt)
            if day < today, !assignment.isDone { overdue.append(assignment) }
            else if let horizon = calendar.date(byAdding: .day, value: 7, to: today), day <= horizon { week.append(assignment) }
            else { later.append(assignment) }
        }

        return [
            Bucket(title: "Overdue", items: overdue, tint: Theme.overdue),
            Bucket(title: "Next 7 days", items: week, tint: Theme.highlighterDeep),
            Bucket(title: "Later", items: later, tint: .secondary),
            Bucket(title: "No due date", items: undated, tint: .secondary),
        ].filter { !$0.items.isEmpty }
    }

    // MARK: - Week grid

    private var weekDays: [Date] {
        let calendar = Calendar.current
        let start = calendar.dateInterval(of: .weekOfYear, for: Date())?.start ?? Date()
        let shifted = calendar.date(byAdding: .day, value: weekOffset * 7, to: start) ?? start
        return (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: shifted) }
    }

    private var weekLayout: some View {
        ScrollView {
            HStack(alignment: .top, spacing: 10) {
                ForEach(weekDays, id: \.self) { day in
                    weekColumn(day)
                }
            }
            .padding(Theme.gutter)
        }
    }

    private func weekColumn(_ day: Date) -> some View {
        let calendar = Calendar.current
        let items = filtered
            .filter { $0.dueAt.map { calendar.isDate($0, inSameDayAs: day) } ?? false }
            .sorted { ($0.dueAt ?? .distantFuture) < ($1.dueAt ?? .distantFuture) }
        let isToday = calendar.isDateInToday(day)
        let letter = ScheduleEngine.letter(for: day, config: app.scheduleConfig)

        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 5) {
                Text(day.formatted(.dateTime.weekday(.abbreviated)))
                    .font(Theme.eyebrow)
                    .foregroundStyle(isToday ? Theme.highlighterDeep : .secondary)
                Text(day.formatted(.dateTime.day()))
                    .font(Theme.data(11, weight: .semibold))
                    .foregroundStyle(isToday ? .primary : .secondary)
                if let letter {
                    Text(letter.rawValue)
                        .font(Theme.data(9, weight: .bold))
                        .foregroundStyle(Theme.accent)
                }
                Spacer(minLength: 0)
            }

            VStack(spacing: 4) {
                ForEach(items) { assignment in
                    weekCard(assignment)
                }
                if items.isEmpty {
                    Text("—")
                        .font(.system(size: 11))
                        .foregroundStyle(.quaternary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 6)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(6)
            .background(
                RoundedRectangle(cornerRadius: Theme.corner, style: .continuous)
                    .fill(isToday ? Theme.highlighter.opacity(0.10) : Color(nsColor: .controlBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.corner, style: .continuous)
                    .strokeBorder(isToday ? Theme.highlighter.opacity(0.5) : Color.primary.opacity(0.07))
            )
            .dropDestination(for: String.self) { ids, _ in
                move(assignmentIDs: ids, to: day)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func weekCard(_ assignment: Assignment) -> some View {
        let tint = assignment.schoolClass.map { Theme.classColor($0.colorHex) } ?? .secondary
        return HStack(alignment: .top, spacing: 5) {
            RoundedRectangle(cornerRadius: 1.5)
                .fill(tint)
                .frame(width: 3)
            VStack(alignment: .leading, spacing: 1) {
                Text(assignment.title)
                    .font(.system(size: 11, weight: .medium))
                    .strikethrough(assignment.isDone, color: .secondary)
                    .lineLimit(2)
                if let schoolClass = assignment.schoolClass {
                    Text(schoolClass.name)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(5)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 6).fill(tint.opacity(0.08)))
        .contentShape(Rectangle())
        .onTapGesture { editing = assignment }
        .draggable(assignment.idString)
    }

    /// Drag a card onto another day to reschedule it.
    private func move(assignmentIDs: [String], to day: Date) -> Bool {
        let calendar = Calendar.current
        var moved = false
        for id in assignmentIDs {
            guard let assignment = assignments.first(where: { $0.idString == id }) else { continue }
            let target = calendar.startOfDay(for: day)
            if assignment.hasDueTime, let existing = assignment.dueAt {
                let minutes = ScheduleEngine.minutesIntoDay(existing)
                assignment.dueAt = ScheduleEngine.date(target, atMinutes: minutes)
            } else if let startMinutes = assignment.schoolClass?.startMinutes {
                assignment.dueAt = ScheduleEngine.date(target, atMinutes: startMinutes)
                assignment.hasDueTime = true
            } else {
                assignment.dueAt = target
            }
            moved = true
        }
        if moved {
            app.save()
            Task { await app.rescheduleReminders() }
        }
        return moved
    }
}
