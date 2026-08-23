import SwiftUI

/// The day drawn to scale.
///
/// Each class is a block whose height is its real duration and whose position is
/// its real time, so a glance answers "where am I in the day" without reading a
/// single number. A highlighter line marks the current moment.
struct DaySpine: View {
    var date: Date
    var classes: [SchoolClass]
    var config: ScheduleConfig
    var dueCountByClassID: [String: Int]
    var now: Date
    var onSelectClass: (SchoolClass) -> Void
    /// Supplied when the day can be stepped through; nil hides the controls.
    var onStep: ((Int) -> Void)?
    var isShowingToday = true

    private let timeGutter: CGFloat = 52
    private let railWidth: CGFloat = 3
    private let minimumBlockHeight: CGFloat = 34

    private var meeting: [SchoolClass] {
        ScheduleEngine.classes(meetingOn: date, from: classes, config: config)
    }

    private var isToday: Bool { Calendar.current.isDateInToday(date) }

    /// Timed classes drive the scale drawing; if any class has no time we fall
    /// back to an evenly spaced list rather than inventing a position for it.
    private var timed: [SchoolClass] {
        meeting.filter { $0.startMinutes != nil && $0.endMinutes != nil }
    }

    private var untimed: [SchoolClass] {
        meeting.filter { $0.startMinutes == nil || $0.endMinutes == nil }
    }

    private var window: (start: Int, end: Int)? {
        guard let first = timed.compactMap(\.startMinutes).min(),
              let last = timed.compactMap(\.endMinutes).max(), last > first else { return nil }
        return (first - 12, last + 12)
    }

    private var nowMinutes: Int { ScheduleEngine.minutesIntoDay(now) }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header

            if meeting.isEmpty {
                noClasses
            } else {
                if let window {
                    scaledTimeline(window: window)
                }
                if !untimed.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        if window != nil {
                            Text("No set time")
                                .font(Theme.eyebrow)
                                .foregroundStyle(.tertiary)
                        }
                        ForEach(untimed, id: \.persistentModelID) { schoolClass in
                            classRow(schoolClass, compact: true)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(DueFormat.dayText(date))
                .font(Theme.display(17, weight: .semibold))

            if let letter = ScheduleEngine.letter(for: date, config: config) {
                Text("\(letter.rawValue) day")
                    .font(Theme.data(11, weight: .bold))
                    .foregroundStyle(Theme.accent)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Theme.accent.opacity(0.14)))
            }
            Spacer(minLength: 0)

            if let onStep {
                HStack(spacing: 2) {
                    Button { onStep(-1) } label: { Image(systemName: "chevron.left") }
                        .help("The day before")
                    if !isShowingToday {
                        Button("Today") { onStep(0) }
                    }
                    Button { onStep(1) } label: { Image(systemName: "chevron.right") }
                        .help("The next day")
                }
                .buttonStyle(.borderless)
                .font(.system(size: 11))
            }
        }
    }

    private var noClasses: some View {
        HStack(spacing: 8) {
            Image(systemName: "moon.zzz")
                .foregroundStyle(.tertiary)
            Text(ScheduleEngine.isSchoolDay(date, config: config)
                 ? "No classes scheduled."
                 : "No school today.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
        }
        .padding(.vertical, 10)
    }

    // MARK: - The timeline

    private func scaledTimeline(window: (start: Int, end: Int)) -> some View {
        let span = CGFloat(window.end - window.start)
        // Roughly a point per minute, clamped so a 3-class day isn't stretched
        // thin and an 8-class day still fits without scrolling.
        let height = min(max(span * 0.92, 220), 460)

        func offset(forMinutes minutes: Int) -> CGFloat {
            CGFloat(minutes - window.start) / span * height
        }

        return ZStack(alignment: .topLeading) {
            // The rail itself.
            RoundedRectangle(cornerRadius: 2)
                .fill(Color.primary.opacity(0.08))
                .frame(width: railWidth, height: height)
                .offset(x: timeGutter)

            ForEach(timed, id: \.persistentModelID) { schoolClass in
                let start = schoolClass.startMinutes ?? 0
                let end = schoolClass.endMinutes ?? start
                let top = offset(forMinutes: start)
                let blockHeight = max(offset(forMinutes: end) - top, minimumBlockHeight)

                block(schoolClass, height: blockHeight)
                    .offset(y: top)
            }

            if isToday, nowMinutes >= window.start, nowMinutes <= window.end {
                nowLine.offset(y: offset(forMinutes: nowMinutes))
            }
        }
        .frame(height: height, alignment: .topLeading)
    }

    private func block(_ schoolClass: SchoolClass, height: CGFloat) -> some View {
        let color = Theme.classColor(schoolClass.colorHex)
        let isCurrent = isToday
            && (schoolClass.startMinutes ?? 0) <= nowMinutes
            && nowMinutes < (schoolClass.endMinutes ?? 0)

        return HStack(alignment: .top, spacing: 0) {
            Text(schoolClass.startMinutes.map { TimeFormatting.text(minutes: $0) } ?? "")
                .font(Theme.data(10))
                .foregroundStyle(isCurrent ? .primary : .secondary)
                .frame(width: timeGutter - 8, alignment: .trailing)
                .padding(.trailing, 8)
                .padding(.top, 1)

            RoundedRectangle(cornerRadius: 2)
                .fill(color)
                .frame(width: railWidth, height: height)

            classBody(schoolClass, isCurrent: isCurrent, color: color)
                .padding(.leading, 10)
                .frame(height: height, alignment: .top)
        }
        .contentShape(Rectangle())
        .onTapGesture { onSelectClass(schoolClass) }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(spokenDescription(schoolClass))
        .accessibilityAddTraits(.isButton)
    }

    /// What the block conveys visually — when it is, and what is due — said out loud.
    private func spokenDescription(_ schoolClass: SchoolClass) -> String {
        var parts = [schoolClass.name]
        if let range = schoolClass.timeRangeText { parts.append(range) }
        if let period = schoolClass.period { parts.append("period \(period)") }
        if let due = dueCountByClassID[schoolClass.idString], due > 0 {
            parts.append("\(due) due")
        }
        return parts.joined(separator: ", ")
    }

    private func classBody(_ schoolClass: SchoolClass, isCurrent: Bool, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Text(schoolClass.name)
                    .font(.system(size: 13, weight: isCurrent ? .semibold : .medium))
                    .lineLimit(1)

                if let count = dueCountByClassID[schoolClass.idString], count > 0 {
                    Text("\(count)")
                        .font(Theme.data(10, weight: .bold))
                        .foregroundStyle(color)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(Capsule().fill(color.opacity(0.16)))
                        .help("\(count) due for this class")
                }
            }

            if !schoolClass.room.isEmpty || schoolClass.period != nil {
                Text([schoolClass.period.map { "Period \($0)" }, schoolClass.room.isEmpty ? nil : schoolClass.room]
                        .compactMap { $0 }.joined(separator: " · "))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func classRow(_ schoolClass: SchoolClass, compact: Bool) -> some View {
        HStack(spacing: 10) {
            ClassDot(hex: schoolClass.colorHex)
            Text(schoolClass.name).font(.system(size: 13, weight: .medium))
            Spacer(minLength: 0)
            if let count = dueCountByClassID[schoolClass.idString], count > 0 {
                Text("\(count) due").font(.system(size: 11)).foregroundStyle(.secondary)
            }
        }
        .padding(.leading, timeGutter)
        .contentShape(Rectangle())
        .onTapGesture { onSelectClass(schoolClass) }
    }

    /// The current moment, in highlighter.
    private var nowLine: some View {
        HStack(spacing: 0) {
            Text(DueFormat.timeText(now))
                .font(Theme.data(9, weight: .bold))
                .foregroundStyle(Theme.highlighterDeep)
                .frame(width: timeGutter - 6, alignment: .trailing)
                .padding(.trailing, 6)

            Circle()
                .fill(Theme.highlighter)
                .frame(width: 7, height: 7)
                .offset(x: -2)

            Rectangle()
                .fill(Theme.highlighter)
                .frame(height: 1.5)
        }
        .offset(y: -3)
        .allowsHitTesting(false)
    }
}
