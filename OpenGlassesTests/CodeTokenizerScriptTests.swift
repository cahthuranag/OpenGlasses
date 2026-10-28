import XCTest
@testable import OpenGlasses

/// Plan JY P0 — a letter of a non-Latin interface script separates code tokens, so a model number
/// written against Chinese, Cyrillic or Arabic text without a space is still the model number.
/// Latin text is read as before. Model numbers are invented.
final class CodeTokenizerScriptTests: XCTestCase {

    func testHanLettersSeparateACode() {
        XCTAssertEqual(CodeTokenizer.words(in: "型号ABC123的"), ["型号", "ABC123", "的"])
        XCTAssertEqual(CodeTokenizer.codeTokens(from: "型号ABC123的"), ["ABC123"])
        XCTAssertTrue(CodeTokenizer.contains("型号ABC123的", token: "ABC123"))
        XCTAssertTrue(CodeTokenizer.contains("型号ABC123的", token: "abc123"))
    }

    func testCyrillicAndArabicLettersSeparateACode() {
        XCTAssertEqual(CodeTokenizer.codeTokens(from: "модельABC123"), ["ABC123"])
        XCTAssertTrue(CodeTokenizer.contains("модельABC123", token: "ABC123"))
        XCTAssertEqual(CodeTokenizer.codeTokens(from: "طرازABC123"), ["ABC123"])
        XCTAssertTrue(CodeTokenizer.contains("طرازABC123", token: "ABC123"))
    }

    func testKanaAndHangulSeparateACode() {
        XCTAssertEqual(CodeTokenizer.codeTokens(from: "カタカナーXR40"), ["XR40"], "the prolonged-sound mark too")
        XCTAssertEqual(CodeTokenizer.codeTokens(from: "온도ABC12를"), ["ABC12"])
    }

    func testADecimalBesideHanIsADecimal() {
        XCTAssertEqual(CodeTokenizer.words(in: "温度0.28度"), ["温度", "0.28", "度"])
    }

    /// Unchanged for text without those scripts: a code is still not found inside a longer one,
    /// and Greek unit letters stay part of their word as they always have.
    func testLatinTextIsReadAsBefore() {
        XCTAssertEqual(CodeTokenizer.words(in: "E5 code 0.28 and 1,5 SLP99UH090XV48CK"),
                       ["E5", "code", "0.28", "and", "1,5", "SLP99UH090XV48CK"])
        XCTAssertFalse(CodeTokenizer.contains("E50", token: "E5"))
        XCTAssertTrue(CodeTokenizer.contains("code E5 means", token: "E5"))
        XCTAssertEqual(CodeTokenizer.words(in: "10Ω 10μF"), ["10Ω", "10μF"])
        XCTAssertEqual(CodeTokenizer.words(in: "café Ærø"), ["café", "Ærø"])
    }

    /// A token that is itself in such a script keeps whole-word boundaries within that script.
    func testATokenInTheSameScriptIsStillAWholeWord() {
        XCTAssertFalse(CodeTokenizer.contains("новаямодель", token: "модель"))
        XCTAssertTrue(CodeTokenizer.contains("нова модель", token: "модель"))
        XCTAssertTrue(CodeTokenizer.contains("ABC123модель", token: "модель"))
    }
}
