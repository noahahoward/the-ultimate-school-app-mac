import SwiftUI
import SwiftData

/// The fast path: one field, one line, live feedback on what will be created.
struct QuickAddWindow: View {
    @EnvironmentObject private var app: AppState
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \SchoolClass.sortIndex) private var classes: [SchoolClass]

    @State private var text = ""
    @FocusState private var isFocused: Bool

    private var parsed: ParsedQuickAdd {
        QuickAddParser.parse(text, classes: classes.filter { !$0.isArchived }.map(\.classRef))
    }

    private var matchedClass: SchoolClass? {
        guard let id = parsed.classID else { return nil }
        return classes.first { $0.idString == id }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 17))
                    .foregroundStyle(Theme.accent)

                TextField("What's due?", text: $text)
                    .textFieldStyle(.plain)
                    .font(.system(size: 17))
                    .focused($isFocused)
                    .onSubmit(submit)
            }
            .padding(14)

            if !text.trimmingCharacters(in: .whitespaces).isEmpty {
                Divider()
                preview
            } else {
                Divider()
                hints
            }
        }
        .frame(width: 470)
        .background(.regularMaterial)
        .onAppear {
            text = app.quickAddSeedText
            app.quickAddSeedText = ""
            isFocused = true
        }
    }

    private var preview: some View {
        HStack(spacing: 8) {
            Text(parsed.title)
                .font(.system(size: 13, weight: .medium))
                .lineLimit(1)

            if let matchedClass {
                Chip(text: matchedClass.name, tint: Theme.classColor(matchedClass.colorHex))
            }
            Chip(text: parsed.type.label, symbol: parsed.type.symbol)
            if parsed.dueAt != nil {
                Chip(
                    text: DueFormat.text(for: parsed.dueAt, hasTime: parsed.hasDueTime),
                    symbol: "calendar",
                    tint: DueFormat.urgency(for: parsed.dueAt).color
                )
            }
            if parsed.priority == .high {
                Chip(text: "High", symbol: "exclamationmark.2", tint: Theme.overdue)
            }
            if let minutes = parsed.estimatedMinutes {
                Chip(text: DueFormat.minutesText(minutes), symbol: "clock")
            }

            Spacer(minLength: 0)

            Button("Add", action: submit)
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private var hints: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("Type it the way you'd say it")
                .font(Theme.eyebrow)
                .foregroundStyle(.tertiary)
            Text("bio lab report due fri · alg quiz tomorrow 8am · !! essay next tue 90m")
                .font(Theme.data(11))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private func submit() {
        guard app.addAssignment(fromQuickAdd: text) != nil else { return }
        text = ""
        dismiss()
    }
}
