import Foundation
import SwiftUI
import SwiftData
import AppKit

/// A pomodoro-style timer that survives view redraws and records what it finished.
@MainActor
final class FocusTimer: ObservableObject {

    @Published private(set) var phase: FocusPhase = .focus
    @Published private(set) var remaining: Int = 25 * 60
    @Published private(set) var isRunning = false
    @Published private(set) var completedFocusRuns = 0
    @Published var linkedAssignmentID: PersistentIdentifier?

    private var total: Int = 25 * 60
    private var ticker: Timer?
    private var startedAt: Date?
    private var settings: AppSettings?
    private var onFinish: ((FocusPhase, Date, Int, Int) -> Void)?

    var progress: Double {
        total > 0 ? Double(total - remaining) / Double(total) : 0
    }

    var timeText: String {
        String(format: "%d:%02d", remaining / 60, remaining % 60)
    }

    var phaseLabel: String {
        switch phase {
        case .focus: "Focus"
        case .shortBreak: "Break"
        case .longBreak: "Long break"
        }
    }

    func configure(settings: AppSettings, onFinish: @escaping (FocusPhase, Date, Int, Int) -> Void) {
        self.settings = settings
        self.onFinish = onFinish
        if !isRunning, startedAt == nil { reset(to: .focus) }
    }

    // MARK: - Controls

    func start() {
        guard !isRunning else { return }
        isRunning = true
        if startedAt == nil { startedAt = Date() }
        ticker?.invalidate()
        ticker = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
    }

    func pause() {
        isRunning = false
        ticker?.invalidate()
        ticker = nil
    }

    func toggle() { isRunning ? pause() : start() }

    /// Stops early and still records the minutes that were actually put in.
    func stop() {
        pause()
        recordSession(completed: false)
        reset(to: .focus)
        completedFocusRuns = 0
    }

    func skip() {
        pause()
        recordSession(completed: false)
        advance()
    }

    func reset(to phase: FocusPhase) {
        self.phase = phase
        total = duration(for: phase)
        remaining = total
        startedAt = nil
    }

    private func tick() {
        guard remaining > 0 else { finish(); return }
        remaining -= 1
        if remaining == 0 { finish() }
    }

    private func finish() {
        pause()
        recordSession(completed: true)
        if settings?.focusChimeEnabled ?? true { NSSound(named: "Glass")?.play() }
        if phase == .focus { completedFocusRuns += 1 }
        advance()
    }

    private func advance() {
        switch phase {
        case .focus:
            let sessions = settings?.sessionsBeforeLongBreak ?? 4
            reset(to: completedFocusRuns > 0 && completedFocusRuns % sessions == 0 ? .longBreak : .shortBreak)
        case .shortBreak, .longBreak:
            reset(to: .focus)
        }
    }

    private func recordSession(completed: Bool) {
        guard let startedAt else { return }
        let elapsed = total - remaining
        // Anything shorter than a minute is noise, not a study session.
        guard elapsed >= 60 else { self.startedAt = nil; return }
        onFinish?(phase, startedAt, total, elapsed)
        self.startedAt = nil
    }

    private func duration(for phase: FocusPhase) -> Int {
        let settings = settings
        switch phase {
        case .focus: return (settings?.focusMinutes ?? 25) * 60
        case .shortBreak: return (settings?.shortBreakMinutes ?? 5) * 60
        case .longBreak: return (settings?.longBreakMinutes ?? 15) * 60
        }
    }
}
