import SwiftUI
import SwiftData

struct GradesView: View {
    @EnvironmentObject private var app: AppState
    @Query(sort: \SchoolClass.sortIndex) private var classes: [SchoolClass]
    @State private var expanded: Set<PersistentIdentifier> = []

    private var active: [SchoolClass] { classes.filter { !$0.isArchived } }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.gutter) {
                if active.isEmpty {
                    Panel {
                        EmptyState(
                            symbol: "chart.bar",
                            title: "No classes to grade",
                            message: "Add your classes, then enter scores on assignments to track where you stand."
                        )
                    }
                } else {
                    overview
                    ForEach(active) { schoolClass in
                        ClassGradeCard(
                            schoolClass: schoolClass,
                            isExpanded: expanded.contains(schoolClass.persistentModelID),
                            toggle: {
                                let id = schoolClass.persistentModelID
                                if expanded.contains(id) { expanded.remove(id) } else { expanded.insert(id) }
                            }
                        )
                    }
                }
            }
            .padding(Theme.gutter)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .navigationTitle("Grades")
    }

    private var percents: [Double] {
        active.compactMap { GradeMath.percent(for: $0) }
    }

    @ViewBuilder
    private var overview: some View {
        if !percents.isEmpty {
            Panel {
                HStack(spacing: 12) {
                    StatTile(
                        value: String(format: "%.2f", GradeCalculator.gpa(percents: percents) ?? 0),
                        label: "GPA (unweighted)"
                    )
                    Divider().frame(height: 34)
                    StatTile(
                        value: String(format: "%.1f%%", percents.reduce(0, +) / Double(percents.count)),
                        label: "average"
                    )
                    Divider().frame(height: 34)
                    StatTile(value: "\(percents.count)", label: "classes graded")
                }
            }
        }
    }
}

/// Grade math bridged from the pure calculator to the SwiftData models.
enum GradeMath {
    static func items(for schoolClass: SchoolClass) -> [GradeItem] {
        schoolClass.assignments.compactMap { assignment in
            guard let score = assignment.score, let maxScore = assignment.maxScore, maxScore > 0 else { return nil }
            return GradeItem(score: score, maxScore: maxScore, categoryID: assignment.gradeCategory?.idString)
        }
    }

    static func percent(for schoolClass: SchoolClass) -> Double? {
        GradeCalculator.percent(
            items: items(for: schoolClass),
            categories: schoolClass.gradeCategories.map(\.def),
            mode: schoolClass.gradingMode
        )
    }
}

private struct ClassGradeCard: View {
    @EnvironmentObject private var app: AppState
    @Bindable var schoolClass: SchoolClass
    var isExpanded: Bool
    var toggle: () -> Void

    @State private var whatIfWeight: Double = 20

    private var percent: Double? { GradeMath.percent(for: schoolClass) }
    private var tint: Color { Theme.classColor(schoolClass.colorHex) }

    var body: some View {
        Panel {
            VStack(alignment: .leading, spacing: 12) {
                header

                if isExpanded {
                    Divider()
                    if schoolClass.gradingMode == .weightedCategories { categories }
                    graded
                    whatIf
                }
            }
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 3).fill(tint).frame(width: 4, height: 34)

            VStack(alignment: .leading, spacing: 2) {
                Text(schoolClass.name.isEmpty ? "Untitled class" : schoolClass.name)
                    .font(Theme.display(15, weight: .semibold))
                Text(gradedCount == 0
                     ? "No scores entered yet"
                     : "\(gradedCount) graded · goal \(Int(schoolClass.goalPercent))%")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)

            if let percent {
                VStack(alignment: .trailing, spacing: 0) {
                    Text(GradeCalculator.letter(for: percent))
                        .font(Theme.display(22, weight: .bold))
                        .foregroundStyle(percent >= schoolClass.goalPercent ? Theme.done : .primary)
                    Text(String(format: "%.1f%%", percent))
                        .font(Theme.data(11))
                        .foregroundStyle(.secondary)
                }
            } else {
                Text("—").font(Theme.display(22, weight: .bold)).foregroundStyle(.quaternary)
            }

            Button {
                withAnimation(.snappy(duration: 0.18)) { toggle() }
            } label: {
                Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .contentShape(Rectangle())
        .onTapGesture { withAnimation(.snappy(duration: 0.18)) { toggle() } }
    }

    private var gradedCount: Int { GradeMath.items(for: schoolClass).count }

    private var categories: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                SectionHeading(title: "Categories")
                Button("Add") {
                    let category = GradeCategory(
                        name: "Category",
                        weight: 0,
                        schoolClass: schoolClass,
                        sortIndex: schoolClass.gradeCategories.count
                    )
                    app.context.insert(category)
                    app.save()
                }
                .buttonStyle(.link)
                .font(.system(size: 11))
            }

            if schoolClass.gradeCategories.isEmpty {
                Text("Add categories like Tests 40%, Homework 20% to match the syllabus. Without them, Locker just totals the points.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            } else {
                let results = GradeCalculator.breakdown(
                    items: GradeMath.items(for: schoolClass),
                    categories: schoolClass.gradeCategories.map(\.def)
                )
                ForEach(schoolClass.gradeCategories.sorted { $0.sortIndex < $1.sortIndex }) { category in
                    let result = results.first { $0.category.id == category.idString }
                    HStack(spacing: 8) {
                        TextField("Name", text: Binding(
                            get: { category.name },
                            set: { category.name = $0; app.save() }
                        ))
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 150)

                        TextField("Weight", value: Binding(
                            get: { category.weight },
                            set: { category.weight = $0; app.save() }
                        ), format: .number)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 56)
                        Text("%").foregroundStyle(.secondary).font(.system(size: 11))

                        Spacer(minLength: 0)

                        Text(result?.percent.map { String(format: "%.1f%%", $0) } ?? "—")
                            .font(Theme.data(11))
                            .foregroundStyle(.secondary)

                        Button {
                            app.context.delete(category)
                            app.save()
                        } label: {
                            Image(systemName: "trash").foregroundStyle(.tertiary)
                        }
                        .buttonStyle(.plain)
                    }
                }

                let total = schoolClass.gradeCategories.reduce(0) { $0 + $1.weight }
                if abs(total - 100) > 0.01 {
                    Text("Weights add up to \(Int(total))%. That's fine — categories with no work yet are left out of the math.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var graded: some View {
        let scored = schoolClass.assignments
            .filter { $0.score != nil && ($0.maxScore ?? 0) > 0 }
            .sorted { ($0.dueAt ?? .distantPast) > ($1.dueAt ?? .distantPast) }

        return VStack(alignment: .leading, spacing: 6) {
            SectionHeading(title: "Scores")
            if scored.isEmpty {
                Text("Open an assignment and enter a score to start tracking this class.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            } else {
                ForEach(scored.prefix(12)) { assignment in
                    HStack(spacing: 8) {
                        Text(assignment.title).font(.system(size: 12)).lineLimit(1)
                        Spacer(minLength: 0)
                        if let category = assignment.gradeCategory {
                            Text(category.name).font(.system(size: 10)).foregroundStyle(.tertiary)
                        }
                        Text("\(format(assignment.score))/\(format(assignment.maxScore))")
                            .font(Theme.data(11))
                            .foregroundStyle(.secondary)
                        Text(assignment.percentScore.map { String(format: "%.0f%%", $0) } ?? "")
                            .font(Theme.data(11, weight: .medium))
                            .frame(width: 40, alignment: .trailing)
                    }
                }
            }
        }
    }

    private func format(_ value: Double?) -> String {
        guard let value else { return "—" }
        return value == value.rounded() ? String(Int(value)) : String(format: "%.1f", value)
    }

    /// "What do I need on the final?" — the question every student actually asks.
    private var whatIf: some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionHeading(title: "What do I need")
            if let percent {
                HStack(spacing: 8) {
                    Text("If the next big one is worth")
                        .font(.system(size: 12))
                    TextField("", value: $whatIfWeight, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 50)
                    Text("% of the grade:").font(.system(size: 12))
                }

                let target = schoolClass.goalPercent
                if let needed = GradeCalculator.scoreNeeded(
                    toReach: target, currentPercent: percent, assessmentWeight: whatIfWeight
                ) {
                    Text(neededText(needed, target: target))
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(needed > 100 ? Theme.overdue : Theme.done)
                }
            } else {
                Text("Enter a few scores first and this will tell you what the next test needs to be.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func neededText(_ needed: Double, target: Double) -> String {
        let goal = String(format: "%.0f%%", target)
        if needed > 100 {
            return String(
                format: "A %@ isn't reachable — even a perfect score lands you at %.1f%%.",
                goal, projected(perfect: true)
            )
        }
        if needed <= 0 {
            return "You're already at \(goal) even if you score a zero."
        }
        return String(format: "You need %.0f%% to finish at %@.", needed, goal)
    }

    private func projected(perfect: Bool) -> Double {
        guard let percent else { return 0 }
        let weight = whatIfWeight
        return percent * (100 - weight) / 100 + (perfect ? 100 : 0) * weight / 100
    }
}
