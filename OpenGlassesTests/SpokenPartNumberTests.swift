import XCTest
@testable import OpenGlasses

/// Plan IH P0 — a number nothing knows is read back one character at a time.
final class SpokenPartNumberTests: XCTestCase {

    func testDigitsAndLetters() {
        XCTAssertEqual(SpokenPartNumber.spoken("14T65"), "one four T six five")
        XCTAssertEqual(SpokenPartNumber.spoken("ab9"), "A B nine")
    }

    func testDashesSlashesAndPointsAreSaidAndSeparateGroups() {
        XCTAssertEqual(SpokenPartNumber.spoken("62-23543-01"),
                       "six two, dash, two three five four three, dash, zero one")
        XCTAssertEqual(SpokenPartNumber.spoken("45/5"), "four five, slash, five")
        XCTAssertEqual(SpokenPartNumber.spoken("1.5A"), "one, point, five A")
    }

    func testOtherPunctuationOnlySeparates() {
        XCTAssertEqual(SpokenPartNumber.spoken(" #14 T65 "), "one four, T six five")
        XCTAssertEqual(SpokenPartNumber.spoken(""), "")
    }
}
