import SwiftUI
import SwiftData

/// One pass through a deck's due cards.
struct ReviewSession: View {
    @EnvironmentObject private var app: AppState
    @Environment(\.dismiss) private var dismiss
    @Bindable var deck: Deck

    @State private var queue: [Card] = []
    @State private var index = 0
    @State private var isRevealed = false
    @State private var reviewed = 0

    private var current: Card? {
        queue.indices.contains(index) ? queue[index] : nil
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            Divider()

            if let card = current {
                cardFace(card)
                Divider()
                ratingBar(card)
            } else {
                finished
            }
        }
        .frame(width: 540, height: 460)
        .onAppear(perform: load)
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 1) {
                Text(deck.name).font(.system(size: 13, weight: .semibold))
                Text(queue.isEmpty ? "Nothing due" : "\(min(index + 1, queue.count)) of \(queue.count)")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Close") { finish() }
        }
        .padding(12)
    }

    private func cardFace(_ card: Card) -> some View {
        VStack(spacing: 14) {
            Spacer()
            Text(card.front)
                .font(Theme.display(24, weight: .semibold))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 30)

            if isRevealed {
                Divider().frame(width: 120)
                Text(card.back)
                    .font(.system(size: 16))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 30)
            }
            Spacer()

            if !isRevealed {
                Button("Show answer") { isRevealed = true }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .keyboardShortcut(.space, modifiers: [])
                    .padding(.bottom, 20)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .onTapGesture { if !isRevealed { isRevealed = true } }
    }

    private func ratingBar(_ card: Card) -> some View {
        HStack(spacing: 8) {
            ForEach(ReviewRating.allCases, id: \.self) { rating in
                Button {
                    rate(card, as: rating)
                } label: {
                    VStack(spacing: 1) {
                        Text(rating.label).font(.system(size: 12, weight: .medium))
                        Text(SM2Scheduler.previewLabel(rating: rating, state: card.srsState))
                            .font(Theme.data(9))
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                }
                .buttonStyle(.bordered)
                .tint(tint(for: rating))
                .keyboardShortcut(KeyEquivalent(Character("\(rating.rawValue + 1)")), modifiers: [])
            }
        }
        .padding(12)
        .opacity(isRevealed ? 1 : 0.35)
        .disabled(!isRevealed)
    }

    private func tint(for rating: ReviewRating) -> Color {
        switch rating {
        case .again: Theme.overdue
        case .hard: Theme.highlighterDeep
        case .good: Theme.accent
        case .easy: Theme.done
        }
    }

    private var finished: some View {
        VStack(spacing: 10) {
            Spacer()
            Image(systemName: "checkmark.circle")
                .font(.system(size: 30, weight: .light))
                .foregroundStyle(Theme.done)
            Text(reviewed > 0 ? "\(reviewed) card\(reviewed == 1 ? "" : "s") reviewed" : "Nothing due right now")
                .font(Theme.display(16))
            Text(reviewed > 0
                 ? "They'll come back around when it's time to see them again."
                 : "Come back later, or add more cards to this deck.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Spacer()
            Button("Done") { finish() }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .padding(.bottom, 24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Logic

    private func load() {
        queue = deck.dueCards().sorted { ($0.dueAt ?? .distantPast) < ($1.dueAt ?? .distantPast) }
        index = 0
        isRevealed = false
    }

    private func rate(_ card: Card, as rating: ReviewRating) {
        let outcome = SM2Scheduler.apply(rating: rating, to: card.srsState)
        card.srsState = outcome.state
        card.dueAt = outcome.dueAt
        card.lastReviewedAt = Date()

        let log = ReviewLog(rating: rating, intervalAfterDays: outcome.state.intervalDays, card: card)
        app.context.insert(log)
        app.save()
        reviewed += 1

        // "Again" means it comes back before the session ends, not tomorrow.
        if rating == .again {
            queue.append(card)
        }
        index += 1
        isRevealed = false
    }

    private func finish() {
        app.save()
        dismiss()
    }
}
