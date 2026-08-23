import SwiftUI
import SwiftData

struct FocusView: View {
    @EnvironmentObject private var app: AppState
    @EnvironmentObject private var timer: FocusTimer
    @Query(filter: #Predicate<Assignment> { !$0.isResource }) private var assignments: [Assignment]
    @Query private var sessions: [FocusSession]

    private var openAssignments: [Assignment] {
        assignments
            .filter { !$0.isDone }
            .sorted { ($0.dueAt ?? .distantFuture) < ($1.dueAt ?? .distantFuture) }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: Theme.gutter) {
                Panel(padding: 24) {
                    VStack(spacing: 18) {
                        Text(timer.phaseLabel.uppercased())
                            .font(Theme.eyebrow)
                            .foregroundStyle(timer.phase == .focus ? Theme.highlighterDeep : Theme.accent)

                        dial

                        if let assignment = linkedAssignment {
                            HStack(spacing: 6) {
                                if let schoolClass = assignment.schoolClass {
                                    ClassDot(hex: schoolClass.colorHex, size: 7)
                                }
                                Text(assignment.title)
                                    .font(.system(size: 12, weight: .medium))
                                Button {
                                    timer.linkedAssignmentID = nil
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundStyle(.tertiary)
                                }
                                .buttonStyle(.plain)
                            }
                        }

                        controls
                    }
                    .frame(maxWidth: .infinity)
                }

                Panel {
                    HStack(spacing: 12) {
                        StatTile(value: "\(minutesToday)", label: "min today")
                        Divider().frame(height: 34)
                        StatTile(value: "\(minutesThisWeek)", label: "min this week")
                        Divider().frame(height: 34)
                        StatTile(value: "\(timer.completedFocusRuns)", label: "runs in a row")
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    SectionHeading(title: "Work on")
                    Panel(padding: 6) {
                        if openAssignments.isEmpty {
                            EmptyState(
                                symbol: "checkmark.circle",
                                title: "Nothing open",
                                message: "Add work to pick something to focus on."
                            )
                        } else {
                            VStack(spacing: 0) {
                                ForEach(Array(openAssignments.prefix(8).enumerated()), id: \.element.persistentModelID) { index, assignment in
                                    if index > 0 { Divider().padding(.leading, 12) }
                                    pickerRow(assignment)
                                }
                            }
                        }
                    }
                }
            }
            .padding(Theme.gutter)
            .frame(maxWidth: 620)
            .frame(maxWidth: .infinity)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .navigationTitle("Focus")
    }

    // MARK: - Pieces

    private var dial: some View {
        ZStack {
            Circle()
                .stroke(Color.primary.opacity(0.08), lineWidth: 10)
            Circle()
                .trim(from: 0, to: timer.progress)
                .stroke(
                    timer.phase == .focus ? Theme.highlighter : Theme.accent,
                    style: StrokeStyle(lineWidth: 10, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .animation(.linear(duration: 0.9), value: timer.progress)

            VStack(spacing: 2) {
                Text(timer.timeText)
                    .font(Theme.display(46, weight: .bold))
                    .monospacedDigit()
                Text(timer.isRunning ? "Running" : "Paused")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: 190, height: 190)
    }

    private var controls: some View {
        HStack(spacing: 10) {
            Button(timer.isRunning ? "Pause" : "Start") { timer.toggle() }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .keyboardShortcut(.space, modifiers: [])

            Button("Skip") { timer.skip() }
                .buttonStyle(.bordered)
                .controlSize(.large)

            Button("Stop") { timer.stop() }
                .buttonStyle(.bordered)
                .controlSize(.large)
        }
    }

    private func pickerRow(_ assignment: Assignment) -> some View {
        let isLinked = timer.linkedAssignmentID == assignment.persistentModelID
        return HStack(spacing: 8) {
            if let schoolClass = assignment.schoolClass { ClassDot(hex: schoolClass.colorHex, size: 7) }
            Text(assignment.title).font(.system(size: 12))
            Spacer(minLength: 0)
            if let dueAt = assignment.dueAt {
                Text(DueFormat.text(for: dueAt, hasTime: assignment.hasDueTime))
                    .font(.system(size: 11))
                    .foregroundStyle(DueFormat.urgency(for: dueAt).color)
            }
            if isLinked {
                Image(systemName: "timer").font(.system(size: 11)).foregroundStyle(Theme.accent)
            }
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 8)
        .contentShape(Rectangle())
        .background(isLinked ? Theme.accent.opacity(0.08) : .clear)
        .onTapGesture {
            timer.linkedAssignmentID = isLinked ? nil : assignment.persistentModelID
        }
    }

    // MARK: - Data

    private var linkedAssignment: Assignment? {
        guard let id = timer.linkedAssignmentID else { return nil }
        return assignments.first { $0.persistentModelID == id }
    }

    private var minutesToday: Int {
        let calendar = Calendar.current
        return sessions
            .filter { calendar.isDateInToday($0.startedAt) && $0.phase == .focus }
            .reduce(0) { $0 + $1.completedMinutes }
    }

    private var minutesThisWeek: Int {
        let calendar = Calendar.current
        guard let week = calendar.dateInterval(of: .weekOfYear, for: Date()) else { return 0 }
        return sessions
            .filter { week.contains($0.startedAt) && $0.phase == .focus }
            .reduce(0) { $0 + $1.completedMinutes }
    }
}
