import XCTest
@testable import Locker

@MainActor
final class UpdateServiceTests: XCTestCase {

    func testRepoSlugAcceptsTheFormsPeopleActuallyPaste() {
        XCTAssertEqual(UpdateService.normalizeRepo("owner/Locker"), "owner/Locker")
        XCTAssertEqual(UpdateService.normalizeRepo("https://github.com/owner/Locker"), "owner/Locker")
        XCTAssertEqual(UpdateService.normalizeRepo("https://github.com/owner/Locker.git"), "owner/Locker")
        XCTAssertEqual(UpdateService.normalizeRepo("github.com/owner/Locker/"), "owner/Locker")
        XCTAssertEqual(UpdateService.normalizeRepo("git@github.com:owner/Locker.git"), "owner/Locker")
        XCTAssertEqual(UpdateService.normalizeRepo("https://github.com/owner/Locker/releases"), "owner/Locker")
    }

    func testTheConfiguredDefaultRepoIsUsable() {
        XCTAssertEqual(
            UpdateService.normalizeRepo(UpdateService.defaultRepo),
            "noahahoward/the-ultimate-school-app-mac"
        )
        XCTAssertEqual(
            UpdateService.normalizeRepo("https://github.com/noahahoward/the-ultimate-school-app-mac/"),
            "noahahoward/the-ultimate-school-app-mac"
        )
    }

    func testRepoSlugRejectsGarbage() {
        XCTAssertEqual(UpdateService.normalizeRepo(""), "")
        XCTAssertEqual(UpdateService.normalizeRepo("   "), "")
        XCTAssertEqual(UpdateService.normalizeRepo("Locker"), "")
    }

    func testTagsBecomeVersions() {
        XCTAssertEqual(UpdateService.version(fromTag: "v1.2.3"), "1.2.3")
        XCTAssertEqual(UpdateService.version(fromTag: "1.2.3"), "1.2.3")
        XCTAssertEqual(UpdateService.version(fromTag: " V2.0 "), "2.0")
    }

    func testVersionComparisonIsNumericNotAlphabetical() {
        XCTAssertTrue(UpdateService.isNewer("1.10.0", than: "1.9.0"))
        XCTAssertTrue(UpdateService.isNewer("2.0", than: "1.9.9"))
        XCTAssertTrue(UpdateService.isNewer("1.0.1", than: "1.0"))
        XCTAssertFalse(UpdateService.isNewer("1.0", than: "1.0"))
        XCTAssertFalse(UpdateService.isNewer("1.0", than: "1.0.0"))
        XCTAssertFalse(UpdateService.isNewer("0.9", than: "1.0"))
    }
}
