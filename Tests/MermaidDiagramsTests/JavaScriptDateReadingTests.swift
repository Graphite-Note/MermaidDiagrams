/**
 * File: JavaScriptDateReadingTests.swift
 * --------------------------------------
 * Layer: Tests
 * Description: The date forms JavaScript's `new Date(text)` reads beyond ISO 8601, as V8's legacy date parser reads them.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 19/11/2026
 */

import XCTest
@testable import MermaidDiagrams

final class JavaScriptDateReadingTests: XCTestCase {
    /// `[year, month, day, hour, minute, second, millisecond]`, then the offset from UTC in minutes when the text names one.
    private func fields(_ text: String) -> [Int64]? {
        guard let reading = JavaScriptDateReading.read(text) else { return nil }
        return [reading.year, reading.month, reading.day, reading.hour, reading.minute, reading.second, reading.millisecond] + (reading.offsetMinutes.map { [$0] } ?? [])
    }

    func testMonthNamesAreReadByTheirFirstThreeLettersWhereverTheyStand() {
        XCTAssertEqual(fields("March 7, 2014"), [2014, 3, 7, 0, 0, 0, 0])
        XCTAssertEqual(fields("Mar 7 2014"), [2014, 3, 7, 0, 0, 0, 0])
        XCTAssertEqual(fields("7 March 2014"), [2014, 3, 7, 0, 0, 0, 0])
        XCTAssertEqual(fields("2014 March 7"), [2014, 3, 7, 0, 0, 0, 0])
        XCTAssertEqual(fields("Febtember 7 2014"), [2014, 2, 7, 0, 0, 0, 0], "A month name may be longer than its three letters")
        XCTAssertEqual(fields("DECEMBER 25, 2020"), [2020, 12, 25, 0, 0, 0, 0])
        XCTAssertEqual(fields("7-Mar-2014"), [2014, 3, 7, 0, 0, 0, 0])
        XCTAssertEqual(fields("March 2014"), [2014, 3, 1, 0, 0, 0, 0])
    }

    func testNumbersWithoutAMonthNameAreMonthDayYearUnlessTheFirstIsNotADay() {
        XCTAssertEqual(fields("3/7/2014"), [2014, 3, 7, 0, 0, 0, 0])
        XCTAssertEqual(fields("03-07-2014"), [2014, 3, 7, 0, 0, 0, 0])
        XCTAssertEqual(fields("2014/3/7"), [2014, 3, 7, 0, 0, 0, 0])
        XCTAssertEqual(fields("2014 3 7"), [2014, 3, 7, 0, 0, 0, 0])
        XCTAssertEqual(fields("0"), [2000, 1, 1, 0, 0, 0, 0])
        XCTAssertEqual(fields("2014"), [2014, 1, 1, 0, 0, 0, 0])
    }

    func testAnUnwrittenYearIs2001AndTwoDigitYearsAre2000To2049OrTheNineteenFifties() {
        XCTAssertEqual(fields("March 7"), [2001, 3, 7, 0, 0, 0, 0], "V8's default year, as new Date(\"March 7\") has")
        XCTAssertEqual(fields("7/3"), [2001, 7, 3, 0, 0, 0, 0])
        XCTAssertEqual(fields("Mar 7, 14"), [2014, 3, 7, 0, 0, 0, 0])
        XCTAssertEqual(fields("Mar 7, 49"), [2049, 3, 7, 0, 0, 0, 0])
        XCTAssertEqual(fields("Mar 7, 50"), [1950, 3, 7, 0, 0, 0, 0])
        XCTAssertEqual(fields("Mar 7, 99"), [1999, 3, 7, 0, 0, 0, 0])
        XCTAssertEqual(fields("Mar 7, 100"), [100, 3, 7, 0, 0, 0, 0])
    }

    func testTimesAreReadWithAMPMSecondsAndFractions() {
        XCTAssertEqual(fields("March 7, 2014 10:30"), [2014, 3, 7, 10, 30, 0, 0])
        XCTAssertEqual(fields("March 7, 2014 10:30:15"), [2014, 3, 7, 10, 30, 15, 0])
        XCTAssertEqual(fields("March 7, 2014 10:30:15.25"), [2014, 3, 7, 10, 30, 15, 250])
        XCTAssertEqual(fields("March 7, 2014 10:30:15.2504"), [2014, 3, 7, 10, 30, 15, 250])
        XCTAssertEqual(fields("March 7, 2014 10:30 PM"), [2014, 3, 7, 22, 30, 0, 0])
        XCTAssertEqual(fields("March 7, 2014 12:00 AM"), [2014, 3, 7, 0, 0, 0, 0])
        XCTAssertEqual(fields("March 7, 2014 12:30 pm"), [2014, 3, 7, 12, 30, 0, 0])
        XCTAssertEqual(fields("March 7, 2014 24:00"), [2014, 3, 7, 24, 0, 0, 0], "A 24th hour is allowed alone")
        XCTAssertNil(fields("March 7, 2014 24:01"))
        XCTAssertNil(fields("March 7, 2014 13:00 PM"), "PM needs an hour of twelve at most")
        XCTAssertEqual(fields("March 7, 2014 10:61"), [2014, 3, 7, 10, 0, 0, 0], "61 is no minute: V8 takes it for a third date number, which a named month leaves out")
    }

    func testZonesAndOffsetsAreReadAfterATimeOrUTC() {
        XCTAssertEqual(fields("Fri, 07 Mar 2014 10:00:00 GMT"), [2014, 3, 7, 10, 0, 0, 0, 0])
        XCTAssertEqual(fields("Fri Mar 07 2014 10:00:00 GMT+0100"), [2014, 3, 7, 10, 0, 0, 0, 60])
        XCTAssertEqual(fields("Fri Mar 07 2014 10:00:00 GMT-0530 (Newfoundland)"), [2014, 3, 7, 10, 0, 0, 0, -330], "A parenthesis is skipped")
        XCTAssertEqual(fields("7 Mar 2014 10:30 PST"), [2014, 3, 7, 10, 30, 0, 0, -480])
        XCTAssertEqual(fields("7 Mar 2014 10:30 EDT"), [2014, 3, 7, 10, 30, 0, 0, -240])
        XCTAssertEqual(fields("7 Mar 2014 10:30 UTC"), [2014, 3, 7, 10, 30, 0, 0, 0])
        XCTAssertEqual(fields("7 Mar 2014 10:30 +05:30"), [2014, 3, 7, 10, 30, 0, 0, 330])
        XCTAssertEqual(fields("7 Mar 2014 10:30 GMT-8"), [2014, 3, 7, 10, 30, 0, 0, -480])
        XCTAssertNil(fields("7 Mar 2014 10:30 GMT-12345"))
    }

    func testWordsBeforeTheFirstNumberAreIgnoredAndAfterItAreRefused() {
        XCTAssertEqual(fields("Fri, 07 Mar 2014"), [2014, 3, 7, 0, 0, 0, 0])
        XCTAssertEqual(fields("foo 2014"), [2014, 1, 1, 0, 0, 0, 0])
        XCTAssertNil(fields("2014 foo"))
        XCTAssertNil(fields("7 Mar 2014 Fri"), "A day name after a number")
        XCTAssertNil(fields("foo2014"), "A number must not follow a word without a separator")
        XCTAssertNil(fields("March"))
        XCTAssertNil(fields("10:30"), "A time alone has no date")
        XCTAssertNil(fields(""))
        XCTAssertNil(fields("   "))
    }

    func testImpossibleDatesAndExtraNumbersAreRefused() {
        XCTAssertNil(fields("March 32, 2014"))
        XCTAssertNil(fields("13/7/2014"))
        XCTAssertNil(fields("0/7/2014"))
        XCTAssertNil(fields("1/2/3/4"))
        XCTAssertNil(fields("1 2 3 4"))
        XCTAssertEqual(fields("2/30/2014"), [2014, 2, 30, 0, 0, 0, 0], "V8 reads the day; the 30th of February is rolled over when the date is made")
    }

    func testHostileTextsAreBoundedAndNeverCrash() {
        for text in [String(repeating: "(", count: 5_000), String(repeating: "1:", count: 5_000), String(repeating: "Mar ", count: 5_000),
                     String(repeating: "9", count: 100_000), String(repeating: "+", count: 10_000), String(decoding: [0, 0xFFFF, 0xD800, 0x41] as [UInt16], as: UTF16.self), String(repeating: "7/", count: 3_000)] {
            _ = JavaScriptDateReading.read(text)
        }
    }

    func testGanttSchedulesAFallbackDateOnTheWallClockOrAtItsOffset() throws {
        let utc = try GanttScheduling.zone("UTC")
        XCTAssertEqual(GanttFallbackDate.parse("Fri, 07 Mar 2014 10:00:00 GMT", zone: utc), try GanttScheduling.time(2014, 3, 7, 10))
        let paris = try GanttScheduling.zone("Europe/Paris")
        XCTAssertEqual(GanttFallbackDate.parse("Fri, 07 Mar 2014 10:00:00 GMT", zone: paris), try GanttScheduling.time(2014, 3, 7, 11), "Ten at Greenwich is eleven in Paris")
        XCTAssertEqual(GanttFallbackDate.parse("Mar 7 2014 10:00 GMT+0100", zone: utc), try GanttScheduling.time(2014, 3, 7, 9))
        XCTAssertEqual(GanttFallbackDate.parse("March 7, 2014 10:00", zone: paris), try GanttScheduling.time(2014, 3, 7, 10), "Without a zone: the wall clock")
        XCTAssertNil(GanttFallbackDate.parse("Mar 7, 20000", zone: utc), "Mermaid refuses a year past 10,000")
    }
}
