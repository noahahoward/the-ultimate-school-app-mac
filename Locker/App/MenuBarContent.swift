import SwiftUI
import SwiftData

/// The menu bar extra: the next thing happening, and what's due today.
struct MenuBarContent: View {
    @EnvironmentObject private var app: AppState
    @Query(filter: #Predicate<Assignment> { !$0.isResource }) private var assignments: [Assignment]
    @Query private var classes: [SchoolClass]

    @Environment(\.openWindow) private var openWindow

    private var dueToday: [Assignment] {
        assignments
            .filter { !$0.isDone }
            .filter { $0.dueAt.map { Calendar.current.isDateInToday($0) } ?? false }
            .sorted { ($0.dueAt ?? .distantFuture) < ($1.dueAt ?? .distantFuture) }
    }

    private var overdue: [Assignment] {
        let today = Calendar.current.startOfDay(for: Date())
        return assignments.filter { !$0.isDone && ($0.dueAt.map { $0 < today } ?? false) }
    }

    private var nextClass: SchoolClass? {
        ScheduleEngine.nowAndNext(
            at: Date(),
            from: classes.filter { !$0.isArchived },
            config: app.scheduleConfig
        ).next
    }

    private var currentClass: SchoolClass? {
        ScheduleEngine.nowAndNext(
            at: Date(),
            from: classes.filter { !$0.isArchived },
            config: app.scheduleConfig
        ).now
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let currentClass {
                menuLine(label: "Now", value: currentClass.name, hex: currentClass.colorHex)
            }
            if let nextClass {
                menuLine(
                    label: "Next",
                    value: nextClass.name + (nextClass.startMinutes.map { " · \(TimeFormatting.text(minutes: $0))" } ?? ""),
                    hex: nextClass.colorHex
                )
            }
            if currentClass != nil || nextClass != nil { Divider() }

            if overdue.isEmpty && dueToday.isEmpty {
                Text("Nothing due today")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
            } else {
                ForEach(overdue.prefix(3)) { assignment in
                    toggleLine(assignment, suffix: "overdue", tint: Theme.overdue)
                }
                ForEach(dueToday.prefix(6)) { assignment in
                    toggleLine(assignment, suffix: nil, tint: .primary)
                }
            }

            Divider()

            Button("Add work…") { app.presentQuickAdd() }
                .keyboardShortcut("n")
            Button("Open Locker") {
                NSApp.activate(ignoringOtherApps: true)
                openWindow(id: "main")
            }
            Divider()
            Button("Quit Locker") { NSApp.terminate(nil) }
        }
        .frame(width: 260)
    }

    private func menuLine(label: String, value: String, hex: String) -> some View {
        HStack(spacing: 6) {
            ClassDot(hex: hex, size: 7)
            Text(label).font(Theme.eyebrow).foregroundStyle(.tertiary)
            Text(value).font(.system(size: 12, weight: .medium)).lineLimit(1)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
    }

    private func toggleLine(_ assignment: Assignment, suffix: String?, tint: Color) -> some View {
        Button {
            assignment.setDone(true)
            app.save()
            Task { await app.rescheduleReminders() }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "circle")
                Text(assignment.title).lineLimit(1)
                if let suffix {
                    Text(suffix).foregroundStyle(tint)
                }
            }
        }
        .help("Mark as done")
    }
}

/// The compact label shown in the menu bar itself.
struct MenuBarLabel: View {
    @EnvironmentObject private var app: AppState
    @Query(filter: #Predicate<Assignment> { !$0.isResource }) private var assignments: [Assignment]

    private var openToday: Int {
        let today = Calendar.current.startOfDay(for: Date())
        return assignments.filter { assignment in
            guard !assignment.isDone, let dueAt = assignment.dueAt else { return false }
            return Calendar.current.startOfDay(for: dueAt) <= today
        }.count
    }

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: "graduationcap.fill")
            if openToday > 0 { Text("\(openToday)") }
        }
    }
}
