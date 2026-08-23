import SwiftUI
import SwiftData

struct ClassesView: View {
    @EnvironmentObject private var app: AppState
    @Query(sort: \SchoolClass.sortIndex) private var classes: [SchoolClass]
    @State private var editing: SchoolClass?
    @State private var showArchived = false

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
                    ForEach(visible) { schoolClass in
                        classCard(schoolClass)
                    }
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
        .onAppear {
            if let id = app.selectedClassID {
                editing = classes.first { $0.persistentModelID == id }
                app.selectedClassID = nil
            }
        }
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
        let openCount = schoolClass.assignments.filter { !$0.isDone }.count

        return Panel {
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
                            Chip(text: "Classroom", symbol: "arrow.triangle.2.circlepath", tint: Theme.accent)
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
        }
        .contextMenu {
            Button("Edit") { editing = schoolClass }
            Button(schoolClass.isArchived ? "Unarchive" : "Archive") {
                schoolClass.isArchived.toggle()
                app.save()
            }
            Divider()
            Button("Delete", role: .destructive) {
                app.context.delete(schoolClass)
                app.save()
            }
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
