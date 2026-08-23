import SwiftUI
import SwiftData

struct FlashcardsView: View {
    @EnvironmentObject private var app: AppState
    @Query(sort: \Deck.sortIndex) private var decks: [Deck]
    @Query(sort: \SchoolClass.sortIndex) private var classes: [SchoolClass]

    @State private var editingDeck: Deck?
    @State private var reviewingDeck: Deck?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.gutter) {
                if decks.isEmpty {
                    Panel {
                        EmptyState(
                            symbol: "rectangle.on.rectangle",
                            title: "No decks yet",
                            message: "Make a deck for a unit or a vocab list. Locker spaces the cards out so they stick.",
                            actionTitle: "New deck",
                            action: addDeck
                        )
                    }
                } else {
                    ForEach(decks) { deck in
                        deckCard(deck)
                    }
                }
            }
            .padding(Theme.gutter)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .navigationTitle("Flashcards")
        .toolbar {
            ToolbarItem {
                Button("New Deck", action: addDeck)
            }
        }
        .sheet(item: $editingDeck) { DeckEditor(deck: $0).environmentObject(app) }
        .sheet(item: $reviewingDeck) { ReviewSession(deck: $0).environmentObject(app) }
    }

    private func addDeck() {
        let deck = Deck(name: "New deck")
        deck.sortIndex = decks.count
        app.context.insert(deck)
        app.save()
        editingDeck = deck
    }

    private func deckCard(_ deck: Deck) -> some View {
        let due = deck.dueCards().count
        let tint = deck.schoolClass.map { Theme.classColor($0.colorHex) } ?? Theme.accent

        return Panel {
            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        if let schoolClass = deck.schoolClass { ClassDot(hex: schoolClass.colorHex) }
                        Text(deck.name.isEmpty ? "Untitled deck" : deck.name)
                            .font(Theme.display(15, weight: .semibold))
                    }
                    Text("\(deck.cards.count) card\(deck.cards.count == 1 ? "" : "s")"
                         + (due > 0 ? " · \(due) ready to review" : " · nothing due"))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 0)

                Button("Edit") { editingDeck = deck }
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                Button(due > 0 ? "Review \(due)" : "Review") { reviewingDeck = deck }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .disabled(deck.cards.isEmpty)
                    .tint(tint)
            }
        }
        .contextMenu {
            Button("Edit") { editingDeck = deck }
            Button("Delete", role: .destructive) {
                app.context.delete(deck)
                app.save()
            }
        }
    }
}

struct DeckEditor: View {
    @EnvironmentObject private var app: AppState
    @Environment(\.dismiss) private var dismiss
    @Bindable var deck: Deck
    @Query(sort: \SchoolClass.sortIndex) private var classes: [SchoolClass]

    @State private var newFront = ""
    @State private var newBack = ""
    @State private var bulkText = ""
    @State private var showBulk = false

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section {
                    TextField("Deck name", text: $deck.name)
                    Picker("Class", selection: classBinding) {
                        Text("None").tag(nil as PersistentIdentifier?)
                        ForEach(classes.filter { !$0.isArchived }) { schoolClass in
                            Text(schoolClass.name).tag(schoolClass.persistentModelID as PersistentIdentifier?)
                        }
                    }
                }

                Section("Add a card") {
                    TextField("Front", text: $newFront)
                    TextField("Back", text: $newBack)
                    HStack {
                        Button("Add card", action: addCard)
                            .disabled(newFront.trimmingCharacters(in: .whitespaces).isEmpty)
                        Spacer()
                        Button(showBulk ? "Hide paste box" : "Paste a list") { showBulk.toggle() }
                    }
                    if showBulk {
                        Text("One card per line, front and back separated by a comma, tab, or hyphen.")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                        TextEditor(text: $bulkText)
                            .font(Theme.data(11))
                            .frame(height: 90)
                        Button("Add \(parsedBulk.count) cards", action: addBulk)
                            .disabled(parsedBulk.isEmpty)
                    }
                }

                Section("Cards (\(deck.cards.count))") {
                    if deck.cards.isEmpty {
                        Text("No cards yet.").foregroundStyle(.secondary)
                    } else {
                        ForEach(deck.cards.sorted { $0.createdAt < $1.createdAt }) { card in
                            HStack(alignment: .top, spacing: 10) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(card.front).font(.system(size: 12, weight: .medium))
                                    Text(card.back).font(.system(size: 11)).foregroundStyle(.secondary)
                                }
                                Spacer(minLength: 0)
                                if let dueAt = card.dueAt {
                                    Text(DueFormat.text(for: dueAt, hasTime: false))
                                        .font(Theme.data(10))
                                        .foregroundStyle(.tertiary)
                                }
                                Button {
                                    app.context.delete(card)
                                    app.save()
                                } label: {
                                    Image(systemName: "trash").foregroundStyle(.tertiary)
                                }
                                .buttonStyle(.plain)
                            }
                            .padding(.vertical, 2)
                        }
                    }
                }
            }
            .formStyle(.grouped)

            Divider()
            HStack {
                Spacer()
                Button("Done") { app.save(); dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(12)
        }
        .frame(width: 480, height: 620)
    }

    private var classBinding: Binding<PersistentIdentifier?> {
        Binding(
            get: { deck.schoolClass?.persistentModelID },
            set: { id in deck.schoolClass = classes.first { $0.persistentModelID == id } }
        )
    }

    private func addCard() {
        let card = Card(front: newFront.trimmingCharacters(in: .whitespaces),
                        back: newBack.trimmingCharacters(in: .whitespaces),
                        deck: deck)
        app.context.insert(card)
        app.save()
        newFront = ""
        newBack = ""
    }

    /// Accepts the shapes people actually paste: comma, tab, or hyphen separated.
    private var parsedBulk: [(String, String)] {
        bulkText
            .split(whereSeparator: \.isNewline)
            .compactMap { line in
                for separator in ["\t", " - ", " — ", ","] {
                    if let range = line.range(of: separator) {
                        let front = line[..<range.lowerBound].trimmingCharacters(in: .whitespaces)
                        let back = line[range.upperBound...].trimmingCharacters(in: .whitespaces)
                        if !front.isEmpty, !back.isEmpty { return (front, back) }
                    }
                }
                return nil
            }
    }

    private func addBulk() {
        for (front, back) in parsedBulk {
            app.context.insert(Card(front: front, back: back, deck: deck))
        }
        app.save()
        bulkText = ""
    }
}
