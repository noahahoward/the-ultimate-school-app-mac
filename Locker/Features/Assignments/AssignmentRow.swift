import SwiftUI

struct AssignmentRow: View {
    @EnvironmentObject private var app: AppState
    @Bindable var assignment: Assignment
    var showDueDate = true
    var showClass = true

    private var tint: Color {
        assignment.schoolClass.map { Theme.classColor($0.colorHex) } ?? .secondary
    }

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            CompletionToggle(isDone: assignment.isDone, tint: tint) {
                withAnimation(.snappy(duration: 0.15)) {
                    assignment.setDone(!assignment.isDone)
                }
                app.save()
                Task { await app.rescheduleReminders() }
            }

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    if assignment.priority == .high {
                        Image(systemName: "exclamationmark.2")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(Theme.overdue)
                    }
                    Text(assignment.title)
                        .font(.system(size: 13))
                        .strikethrough(assignment.isDone, color: .secondary)
                        .foregroundStyle(assignment.isDone ? .secondary : .primary)
                        .lineLimit(1)
                }

                HStack(spacing: 8) {
                    if showClass, let schoolClass = assignment.schoolClass {
                        HStack(spacing: 4) {
                            ClassDot(hex: schoolClass.colorHex, size: 6)
                            Text(schoolClass.name)
                        }
                    }
                    Text(assignment.type.label)
                    if showDueDate, assignment.dueAt != nil {
                        Text(DueFormat.text(for: assignment.dueAt, hasTime: assignment.hasDueTime))
                            .foregroundStyle(DueFormat.urgency(for: assignment.dueAt).color)
                    }
                    if let minutes = assignment.estimatedMinutes {
                        Text(DueFormat.minutesText(minutes))
                    }
                    if assignment.isMissingFromSource {
                        Text("removed upstream")
                            .foregroundStyle(Theme.overdue)
                            .help("This is gone from Google Classroom. It was kept here in case you still need it.")
                    }
                }
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }

            Spacer(minLength: 0)

            if let percent = assignment.percentScore {
                Text(String(format: "%.0f%%", percent))
                    .font(Theme.data(11, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 6)
        .contentShape(Rectangle())
        .contextMenu {
            Button(assignment.isDone ? "Mark as not done" : "Mark as done") {
                assignment.setDone(!assignment.isDone)
                app.save()
            }
            if let url = assignment.externalRefs.compactMap(\.url).first, let link = URL(string: url) {
                Button("Open in Google Classroom") { NSWorkspace.shared.open(link) }
            }
            Divider()
            Button("Due today") { setDue(daysFromNow: 0) }
            Button("Due tomorrow") { setDue(daysFromNow: 1) }
            Button("Due next week") { setDue(daysFromNow: 7) }
            Divider()
            Button("Delete", role: .destructive) {
                app.context.delete(assignment)
                app.save()
            }
        }
    }

    private func setDue(daysFromNow: Int) {
        let calendar = Calendar.current
        let base = calendar.startOfDay(for: Date())
        guard let day = calendar.date(byAdding: .day, value: daysFromNow, to: base) else { return }
        if let startMinutes = assignment.schoolClass?.startMinutes {
            assignment.dueAt = ScheduleEngine.date(day, atMinutes: startMinutes)
            assignment.hasDueTime = true
        } else {
            assignment.dueAt = day
            assignment.hasDueTime = false
        }
        app.save()
        Task { await app.rescheduleReminders() }
    }
}
