import SwiftUI
import SwiftData

struct TodayView: View {
    @EnvironmentObject private var app: AppState
    @Query private var assignments: [Assignment]
    @Query private var classes: [SchoolClass]
    @Query private var decks: [Deck]

    @State private var now = Date()
    @State private var quickText = ""
    @State private var editing: Assignment?

    private let clock = Timer.publish(every: 30, on: .main, in: .common).autoconnect()

    var body: some View {
        ScrollView {
            HStack(alignment: .top, spacing: Theme.gutter) {
                VStack(alignment: .leading, spacing: Theme.gutter) {
                    Panel {
                        DaySpine(
                            date: now,
                            classes: activeClasses,
                            config: app.scheduleConfig,
                            dueCountByClassID: dueCountByClass,
                            now: now,
                            onSelectClass: { app.selectedClassID = $0.persistentModelID; app.section = .classes }
                        )
                    }
                    statsCard
                }
                .frame(width: 330)

                VStack(alignment: .leading, spacing: Theme.gutter) {
                    quickAddField
                    workQueue
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(Theme.gutter)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .navigationTitle("Today")
        .onReceive(clock) { now = $0 }
        .sheet(item: $editing) { assignment in
            AssignmentEditor(assignment: assignment)
                .environmentObject(app)
        }
    }

    // MARK: - Data

    private var activeClasses: [SchoolClass] { classes.filter { !$0.isArchived } }

    private var open: [Assignment] {
        assignments.filter { !$0.isDone }
    }

    private var dueCountByClass: [String: Int] {
        var counts: [String: Int] = [:]
        let calendar = Calendar.current
        for assignment in open {
            guard let dueAt = assignment.dueAt, calendar.isDate(dueAt, inSameDayAs: now),
                  let id = assignment.schoolClass?.idString else { continue }
            counts[id, default: 0] += 1
        }
        return counts
    }

    private struct Group: Identifiable {
        var id: String { title }
        var title: String
        var items: [Assignment]
        var tint: Color
    }

    private var groups: [Group] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now)
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: today) ?? today
        let weekEnd = calendar.date(byAdding: .day, value: 7, to: today) ?? today

        func day(_ assignment: Assignment) -> Date? {
            assignment.dueAt.map { calendar.startOfDay(for: $0) }
        }

        let overdue = open.filter { guard let d = day($0) else { return false }; return d < today }
        let dueToday = open.filter { day($0) == today }
        let dueTomorrow = open.filter { day($0) == tomorrow }
        let thisWeek = open.filter {
            guard let d = day($0) else { return false }
            return d > tomorrow && d <= weekEnd
        }
        let undated = open.filter { $0.dueAt == nil }

        return [
            Group(title: "Overdue", items: overdue, tint: Theme.overdue),
            Group(title: "Today", items: dueToday, tint: Theme.highlighterDeep),
            Group(title: "Tomorrow", items: dueTomorrow, tint: .secondary),
            Group(title: "This week", items: thisWeek, tint: .secondary),
            Group(title: "No due date", items: undated, tint: .secondary),
        ].filter { !$0.items.isEmpty }
    }

    private var streak: StreakSummary {
        Streaks.summary(
            completionDates: assignments.compactMap(\.completedAt),
            config: app.scheduleConfig,
            now: now
        )
    }

    private var dueCardCount: Int {
        decks.reduce(0) { $0 + $1.dueCards(asOf: now).count }
    }

    private var focusMinutesToday: Int {
        let calendar = Calendar.current
        return assignments
            .flatMap(\.focusSessions)
            .filter { calendar.isDate($0.startedAt, inSameDayAs: now) && $0.phase == .focus }
            .reduce(0) { $0 + $1.completedMinutes }
    }

    // MARK: - Pieces

    private var quickAddField: some View {
        Panel(padding: 12) {
            HStack(spacing: 10) {
                Image(systemName: "plus.circle.fill")
                    .foregroundStyle(Theme.accent)
                    .font(.system(size: 15))

                TextField("Add work — try “bio lab report due fri”", text: $quickText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .onSubmit(submitQuickAdd)

                if !quickText.isEmpty {
                    Button("Add", action: submitQuickAdd)
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                }
            }
        }
    }

    private func submitQuickAdd() {
        guard !quickText.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        app.addAssignment(fromQuickAdd: quickText)
        quickText = ""
    }

    private var statsCard: some View {
        Panel {
            HStack(alignment: .top, spacing: 12) {
                StatTile(
                    value: "\(streak.current)",
                    label: streak.current == 1 ? "day streak" : "day streak",
                    tint: streak.current > 0 ? Theme.highlighterDeep : .secondary,
                    symbol: streak.current > 0 ? "flame.fill" : nil
                )
                Divider().frame(height: 34)
                StatTile(value: "\(open.count)", label: "open")
                Divider().frame(height: 34)
                StatTile(
                    value: focusMinutesToday > 0 ? "\(focusMinutesToday)" : "—",
                    label: "min focused"
                )
                if dueCardCount > 0 {
                    Divider().frame(height: 34)
                    StatTile(value: "\(dueCardCount)", label: "cards due", tint: Theme.accent)
                }
            }
        }
    }

    @ViewBuilder
    private var workQueue: some View {
        if groups.isEmpty {
            Panel {
                EmptyState(
                    symbol: "tray",
                    title: "Nothing on the list",
                    message: "Add work with the box above, or connect Google Classroom in Settings to pull it in automatically."
                )
            }
        } else {
            ForEach(groups) { group in
                VStack(alignment: .leading, spacing: 8) {
                    SectionHeading(title: group.title, count: group.items.count, accent: group.tint)
                    Panel(padding: 6) {
                        VStack(spacing: 0) {
                            ForEach(Array(sorted(group.items).enumerated()), id: \.element.persistentModelID) { index, assignment in
                                if index > 0 { Divider().padding(.leading, 34) }
                                AssignmentRow(assignment: assignment, showDueDate: group.title != "No due date")
                                    .onTapGesture { editing = assignment }
                            }
                        }
                    }
                }
            }
        }
    }

    private func sorted(_ items: [Assignment]) -> [Assignment] {
        items.sorted { lhs, rhs in
            if lhs.priority != rhs.priority { return lhs.priority > rhs.priority }
            switch (lhs.dueAt, rhs.dueAt) {
            case let (l?, r?) where l != r: return l < r
            case (nil, .some): return false
            case (.some, nil): return true
            default: return lhs.title < rhs.title
            }
        }
    }
}
