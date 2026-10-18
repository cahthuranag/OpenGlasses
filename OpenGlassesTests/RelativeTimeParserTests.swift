import XCTest
@testable import OpenGlasses

/// The sentence side of the relative-time guard: what "in 15 minutes" reads as, and every shape
/// that must read as nothing at all, because a wrong override is worse than none.
final class RelativeTimeParserTests: XCTestCase {

    private func reminder(_ text: String) -> TimeInterval? {
        RelativeTimeParser.duration(in: text, anchors: .reminder)
    }

    private func timer(_ text: String) -> TimeInterval? {
        RelativeTimeParser.duration(in: text, anchors: .timer)
    }

    // MARK: - The phrases the guard exists for

    func testTheCorePhrases() {
        let cases: [(String, TimeInterval)] = [
            ("remind me in 15 minutes", 900),
            ("in an hour", 3600),
            ("in half an hour", 1800),
            ("in 2 hours and 30 minutes", 9000),
            ("in 90 seconds", 90),
            ("in a minute", 60),
            ("in one minute", 60),
            ("in 1 hour", 3600),
        ]
        for (text, expected) in cases {
            XCTAssertEqual(reminder(text), expected, text)
        }
    }

    func testSpelledNumbersOneToSixty() {
        let words = ["one", "two", "three", "four", "five", "six", "seven", "eight", "nine", "ten",
                     "eleven", "twelve", "thirteen", "fourteen", "fifteen", "sixteen", "seventeen",
                     "eighteen", "nineteen"]
        for (index, word) in words.enumerated() {
            XCTAssertEqual(reminder("in \(word) minutes"), TimeInterval((index + 1) * 60), word)
        }
        let tens = ["twenty": 20, "thirty": 30, "forty": 40, "fifty": 50, "sixty": 60]
        for (word, value) in tens {
            XCTAssertEqual(reminder("in \(word) minutes"), TimeInterval(value * 60), word)
            guard value < 60 else { continue }
            for (unitIndex, unit) in words.prefix(9).enumerated() {
                let total = value + unitIndex + 1
                XCTAssertEqual(reminder("in \(word) \(unit) minutes"), TimeInterval(total * 60),
                               "\(word) \(unit)")
                XCTAssertEqual(reminder("in \(word)-\(unit) minutes"), TimeInterval(total * 60),
                               "\(word)-\(unit)")
            }
        }
    }

    func testEveryDigitAmountOneToSixty() {
        for n in 1...60 {
            XCTAssertEqual(reminder("in \(n) minutes"), TimeInterval(n * 60), "\(n)")
            XCTAssertEqual(reminder("in \(n) seconds"), TimeInterval(n), "\(n)s")
        }
    }

    func testTwentyFiveAndFriends() {
        XCTAssertEqual(reminder("remind me to check the oven in twenty five minutes"), 1500)
        XCTAssertEqual(reminder("in forty five seconds"), 45)
        XCTAssertEqual(reminder("in a hundred seconds"), 100)
        XCTAssertEqual(reminder("in ninety seconds"), 90)
    }

    func testHalvesAndQuarters() {
        XCTAssertEqual(reminder("in an hour and a half"), 5400)
        XCTAssertEqual(reminder("in one and a half hours"), 5400)
        XCTAssertEqual(reminder("in 2 and a half minutes"), 150)
        XCTAssertEqual(reminder("in two hours and a half"), 9000)
        XCTAssertEqual(reminder("in half a minute"), 30)
        XCTAssertEqual(reminder("in half hour"), 1800)
        XCTAssertEqual(reminder("in a quarter of an hour"), 900)
        XCTAssertEqual(reminder("in quarter of an hour"), 900)
        XCTAssertEqual(reminder("in three quarters of an hour"), 2700)
        XCTAssertEqual(reminder("in 1.5 hours"), 5400)
    }

    func testCompoundDurations() {
        XCTAssertEqual(reminder("in 1 hour 15 minutes"), 4500)
        XCTAssertEqual(reminder("in an hour and 5 minutes"), 3900)
        XCTAssertEqual(reminder("in 2 minutes and 30 seconds"), 150)
        XCTAssertEqual(reminder("in 1 hour, 2 minutes and 3 seconds"), 3723)
    }

    func testAbbreviationsAndPossessives() {
        XCTAssertEqual(reminder("in 15 mins"), 900)
        XCTAssertEqual(reminder("in 2 hrs"), 7200)
        XCTAssertEqual(reminder("in 30 secs"), 30)
        XCTAssertEqual(reminder("in an hour's time"), 3600)
        XCTAssertEqual(reminder("in 15 minutes' time"), 900)
        XCTAssertEqual(reminder("In 15 Minutes."), 900)
    }

    func testHedgesBeforeTheAmount() {
        XCTAssertEqual(reminder("in about 20 minutes"), 1200)
        XCTAssertEqual(reminder("in another 10 minutes"), 600)
        XCTAssertEqual(reminder("in exactly an hour"), 3600)
    }

    func testFromNowCountsWithoutAnAnchor() {
        XCTAssertEqual(reminder("remind me 15 minutes from now"), 900)
        XCTAssertEqual(reminder("in 15 minutes from now"), 900)
        XCTAssertEqual(timer("a timer going off 10 minutes from now"), 600)
    }

    func testTheReminderActionAfterTheDuration() {
        XCTAssertEqual(reminder("remind me in 10 minutes to call Mum"), 600)
        XCTAssertEqual(reminder("in an hour and a half to stretch"), 5400)
        XCTAssertEqual(reminder("in 2 hours and then again later"), 7200)
    }

    func testTheSameDurationTwiceIsStillOne() {
        XCTAssertEqual(reminder("in 15 minutes, yes in 15 minutes"), 900)
    }

    func testArticleNounsAreNotDurations() {
        XCTAssertEqual(reminder("remind me in 10 minutes, I'm in a meeting"), 600)
        XCTAssertEqual(reminder("put it in an envelope in 5 minutes"), 300)
    }

    // MARK: - Timer phrasings

    func testTimerPhrasings() {
        XCTAssertEqual(timer("set a timer for 15 minutes"), 900)
        XCTAssertEqual(timer("set a 10 minute timer"), 600)
        XCTAssertEqual(timer("set a 10-minute timer"), 600)
        XCTAssertEqual(timer("set a ten minute timer for the pasta"), 600)
        XCTAssertEqual(timer("timer for an hour and a half"), 5400)
        XCTAssertEqual(timer("set a timer to go off in 90 seconds"), 90)
        XCTAssertEqual(timer("set a timer for 10 minutes until the pasta is done"), 600)
        XCTAssertEqual(timer("set a timer for 10 minutes to check the roast in the oven"), 600)
    }

    func testForIsOnlyATimerAnchor() {
        XCTAssertNil(reminder("remind me to stretch for 10 minutes"))
        XCTAssertNil(reminder("a 10 minute timer"))
        XCTAssertEqual(reminder("remind me in an hour to stretch for 10 minutes"), 3600)
    }

    // MARK: - What must be nil

    func testVagueAmountsAreNil() {
        for text in ["in a bit", "in a few minutes", "in a couple of minutes", "in a while",
                     "in a minute or two", "in a moment", "in a second", "in a sec",
                     "in a little while", "remind me in a few", "in an hour or two",
                     "in 10 or 15 minutes", "in a jiffy"] {
            XCTAssertNil(reminder(text), text)
            XCTAssertNil(timer(text), text)
        }
    }

    func testANumberWithoutAUnitIsNil() {
        for text in ["15", "in 15", "set a timer for 15", "remind me in fifteen",
                     "remind me in 15 to call", "in an hour and 30"] {
            XCTAssertNil(reminder(text), text)
            XCTAssertNil(timer(text), text)
        }
    }

    func testAnUnanchoredDurationIsNil() {
        for text in ["15 minutes", "the pasta needs 10 minutes", "within 15 minutes",
                     "in the next 15 minutes", "remind me after 15 minutes", "minutes"] {
            XCTAssertNil(reminder(text), text)
        }
        XCTAssertNil(timer("the pasta needs 10 minutes"))
    }

    func testCalendarUnitsAreNil() {
        for text in ["in 2 days", "in a day", "in a week", "in 3 months", "in a year",
                     "in 2 hours and 3 days", "in a fortnight"] {
            XCTAssertNil(reminder(text), text)
        }
    }

    func testTwoDifferentDurationsAreNil() {
        XCTAssertNil(timer("set a timer for 10 minutes and remind me in an hour"))
        XCTAssertNil(reminder("don't remind me in 15 minutes, remind me in 20 minutes"))
        XCTAssertNil(timer("set a timer for 15, no, for 20 minutes and then in 5 minutes"))
    }

    func testAnUncertainPhraseSpoilsTheSentence() {
        XCTAssertNil(reminder("in 2 days, or in 15 minutes"))
        XCTAssertNil(reminder("in a few minutes or in 15 minutes"))
    }

    func testPhrasesAnchoredToSomethingElseAreNil() {
        for text in ["remind me in 15 minutes before the meeting",
                     "in 10 minutes after lunch",
                     "in 5 minutes past 3",
                     "in 15 minutes from the start",
                     "in 10 minutes to 3",
                     "in 10 minutes to five"] {
            XCTAssertNil(reminder(text), text)
        }
        XCTAssertNil(timer("set a timer for an hour after the roast goes in"))
    }

    func testAbsoluteTimesAreNil() {
        for text in ["remind me at 3pm", "remind me tomorrow", "remind me at 3:30",
                     "remind me tomorrow in 2 hours", "remind me in an hour, at 5 pm",
                     "in 2 hours tonight", "on Friday in an hour", "in an hour at noon",
                     "in 2 hours at 4 p.m.", "remind me at 9 o'clock in 10 minutes"] {
            XCTAssertNil(reminder(text), text)
        }
    }

    func testDegenerateInputIsNil() {
        for text in ["", "   ", "in", "in zero minutes", "in 0 seconds", "in 2 minutes and 3 hours",
                     "in half a second", "in 99999999 minutes", "half"] {
            XCTAssertNil(reminder(text), text)
        }
    }

    func testOtherLanguagesAreNil() {
        for text in ["recuérdame en 15 minutos", "erinnere mich in 15 Minuten",
                     "rappelle-moi dans 15 minutes", "herinner me over 15 minuten",
                     "15分後にリマインドして", "15분 후에 알려줘"] {
            XCTAssertNil(reminder(text), text)
        }
    }

    func testTheWordAmIsNotAClockTime() {
        XCTAssertEqual(reminder("remind me in 10 minutes, I am leaving"), 600)
        XCTAssertEqual(reminder("remind me in 15 minutes to take 2 pills"), 900)
    }
}
