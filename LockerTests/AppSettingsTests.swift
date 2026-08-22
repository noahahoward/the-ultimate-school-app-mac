import XCTest
import SwiftData
@testable import Locker

/// A freshly created settings row has to be usable immediately — the day view,
/// streaks, and reminders all read it before the student touches anything.
final class AppSettingsTests: XCTestCase {

    var container: ModelContainer!
    var context: ModelContext!

    override func setUpWithError() throws {
        container = try ModelContainer(
            for: Persistence.schema,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        context = ModelContext(container)
    }

    func testNewSettingsDefaultToAMondayThroughFridayWeek() throws {
        let settings = AppSettings.current(in: context)
        XCTAssertEqual(settings.schoolDaysMask, Weekdays.mask(from: Weekdays.schoolWeek))
        XCTAssertEqual(settings.schoolDays, Weekdays.schoolWeek)
    }

    func testScheduleConfigFromNewSettingsTreatsAWeekdayAsASchoolDay() throws {
        let settings = AppSettings.current(in: context)
        let friday = TestClock.date(2026, 8, 21)
        let sunday = TestClock.date(2026, 8, 23)

        XCTAssertTrue(ScheduleEngine.isSchoolDay(friday, config: settings.scheduleConfig, calendar: TestClock.calendar))
        XCTAssertFalse(ScheduleEngine.isSchoolDay(sunday, config: settings.scheduleConfig, calendar: TestClock.calendar))
    }

    func testSettingsRowIsCreatedOnceAndReused() throws {
        let first = AppSettings.current(in: context)
        first.studentName = "Sam"
        let second = AppSettings.current(in: context)
        XCTAssertEqual(second.studentName, "Sam")
        XCTAssertEqual(try context.fetch(FetchDescriptor<AppSettings>()).count, 1)
    }

    func testRemindersAreOnByDefault() throws {
        let settings = AppSettings.current(in: context)
        XCTAssertTrue(settings.reminderConfig.enabled)
        XCTAssertEqual(settings.reminderConfig.eveningBeforeMinutes, 19 * 60)
    }
}
