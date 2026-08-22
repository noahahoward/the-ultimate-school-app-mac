import SwiftUI

/// A quiet surface. Everything in Locker sits on one of these so the only
/// saturated color on screen belongs to a class or to something urgent.
struct Panel<Content: View>: View {
    var padding: CGFloat = 16
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: Theme.cardCorner, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.cardCorner, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.07))
            )
    }
}

struct SectionHeading: View {
    var title: String
    var count: Int?
    var accent: Color = .secondary

    var body: some View {
        HStack(spacing: 8) {
            Text(title.uppercased())
                .font(Theme.eyebrow)
                .foregroundStyle(accent)
            if let count, count > 0 {
                Text("\(count)")
                    .font(Theme.data(11, weight: .semibold))
                    .foregroundStyle(accent.opacity(0.9))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1)
                    .background(Capsule().fill(accent.opacity(0.13)))
            }
            Spacer(minLength: 0)
        }
    }
}

/// The color chip that identifies a class everywhere it appears.
struct ClassDot: View {
    var hex: String
    var size: CGFloat = 8

    var body: some View {
        Circle()
            .fill(Theme.classColor(hex))
            .frame(width: size, height: size)
    }
}

struct Chip: View {
    var text: String
    var symbol: String?
    var tint: Color = .secondary

    var body: some View {
        HStack(spacing: 4) {
            if let symbol { Image(systemName: symbol).font(.system(size: 9, weight: .semibold)) }
            Text(text).font(.system(size: 11, weight: .medium))
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 7)
        .padding(.vertical, 2)
        .background(Capsule().fill(tint.opacity(0.12)))
    }
}

/// Empty states are an invitation to do the next thing, never a celebration.
struct EmptyState: View {
    var symbol: String
    var title: String
    var message: String
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 26, weight: .light))
                .foregroundStyle(.tertiary)
            Text(title)
                .font(Theme.display(15))
            Text(message)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 300)
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .padding(.top, 2)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 36)
    }
}

/// The completion control. Deliberately large enough to hit without aiming.
struct CompletionToggle: View {
    var isDone: Bool
    var tint: Color
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .strokeBorder(isDone ? Theme.done : tint.opacity(0.5), lineWidth: 1.5)
                    .frame(width: 17, height: 17)
                if isDone {
                    Circle().fill(Theme.done).frame(width: 17, height: 17)
                    Image(systemName: "checkmark")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.white)
                }
            }
            .contentShape(Rectangle())
            .frame(width: 26, height: 26)
        }
        .buttonStyle(.plain)
        .help(isDone ? "Mark as not done" : "Mark as done")
    }
}

/// A labelled statistic. The number is the point, so it gets the rounded face.
struct StatTile: View {
    var value: String
    var label: String
    var tint: Color = .primary
    var symbol: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 5) {
                if let symbol {
                    Image(systemName: symbol)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(tint)
                }
                Text(value)
                    .font(Theme.display(22, weight: .bold))
                    .foregroundStyle(tint)
            }
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Wraps a destructive-ish confirmation so views don't each roll their own.
struct ConfirmButton: View {
    var title: String
    var message: String
    var confirmTitle: String
    var role: ButtonRole? = .destructive
    var action: () -> Void

    @State private var isPresented = false

    var body: some View {
        Button(title, role: role) { isPresented = true }
            .confirmationDialog(message, isPresented: $isPresented) {
                Button(confirmTitle, role: role, action: action)
                Button("Cancel", role: .cancel) {}
            }
    }
}
