import Foundation
import Testing
@testable import SwiftTerm

final class WidthModeTests {
    private static let tmux35 = WidthMode.tmux(TmuxVersion(major: 3, minor: 5))
    private static let tmux37 = WidthMode.tmux(TmuxVersion(major: 3, minor: 7, utf8proc: true))

    private func terminal(_ mode: WidthMode, _ text: String) -> Terminal {
        let (t, _) = TerminalTestHarness.makeTerminal(cols: 20, rows: 2)
        t.widthMode = mode
        t.feed(text: text)
        return t
    }

    /// Every cell that starts a character on row 0: column, text, width
    private func cells(_ t: Terminal) -> [String] {
        let line = t.getLine(row: 0)!
        var out: [String] = []
        for col in 0..<t.cols where line[col].width != 0 && line[col].code != 0 {
            out.append("\(col):\(t.getText(for: line[col])):\(line[col].width)")
        }
        return out
    }

    @Test func testTmuxVersionParsesTmuxV() {
        #expect(TmuxVersion("tmux 3.5a") == TmuxVersion(major: 3, minor: 5))
        #expect(TmuxVersion("tmux 3.7b", utf8proc: true) == TmuxVersion(major: 3, minor: 7, utf8proc: true))
        #expect(TmuxVersion("tmux next-3.6") == TmuxVersion(major: 3, minor: 6))
        #expect(TmuxVersion("3.4") == TmuxVersion(major: 3, minor: 4))
        #expect(TmuxVersion("tmux master") == TmuxVersion(major: 3, minor: 7))
        #expect(TmuxVersion("tmux openbsd-7.6") == TmuxVersion(major: 3, minor: 5))
        #expect(TmuxVersion("psmux 3.3.8") == TmuxVersion(major: 3, minor: 3))
        #expect(TmuxVersion("tmux 3.6", variationSelectorAlwaysWide: false) == TmuxVersion(major: 3, minor: 6, variationSelectorAlwaysWide: false))
        #expect(TmuxVersion("no version here") == nil)
    }

    @Test func testDefaultIsUnicode() {
        let (t, _) = TerminalTestHarness.makeTerminal(cols: 20, rows: 2)
        #expect(t.widthMode == .unicode)
    }

    // MARK: unicode (Ghostty)

    @Test func testUnicodeKeepsTextStyleModifierBasesNarrow() {
        // A shell measures ✌ with wcwidth, 1 column; so does Ghostty
        #expect(cells(terminal(.unicode, "\u{270C}|")) == ["0:\u{270C}:1", "1:|:1"])
        #expect(cells(terminal(.unicode, "\u{261D}|")) == ["0:\u{261D}:1", "1:|:1"])
    }

    @Test func testUnicodeVs16OnlyWidensEmoji() {
        #expect(cells(terminal(.unicode, "a\u{FE0F}|")) == ["0:a\u{FE0F}:1", "1:|:1"])
        #expect(cells(terminal(.unicode, "\u{2764}\u{FE0F}|")) == ["0:\u{2764}\u{FE0F}:2", "2:|:1"])
    }

    @Test func testUnicodeSkinToneJoinsOnlyModifierBases() {
        #expect(cells(terminal(.unicode, "\u{E9}\u{1F3FD}|")) == ["0:\u{E9}:1", "1:\u{1F3FD}:2", "3:|:1"])
        #expect(cells(terminal(.unicode, "\u{1F44D}\u{1F3FD}|")) == ["0:\u{1F44D}\u{1F3FD}:2", "2:|:1"])
    }

    @Test func testUnicodeKeepsAZwjSequenceInOneCell() {
        let family = "\u{1F468}\u{200D}\u{1F469}\u{200D}\u{1F467}\u{200D}\u{1F466}"
        #expect(cells(terminal(.unicode, family + "x")) == ["0:\(family):2", "2:x:1"])
    }

    @Test func testUnicodeDoesNotJoinTextAfterAZwj() {
        #expect(cells(terminal(.unicode, "\u{1F469}\u{200D}\u{4E2D}|")) == ["0:\u{1F469}\u{200D}:2", "2:\u{4E2D}:2", "4:|:1"])
    }

    @Test func testUnicodeSpacingMarksAndConjunctsTakeAColumn() {
        // As in Ghostty: a spacing mark or a conjunct's consonant joins the
        // cluster and makes it two columns; a nonspacing mark does not
        #expect(cells(terminal(.unicode, "\u{939}\u{93F}|")) == ["0:\u{939}\u{93F}:2", "2:|:1"])           // हि
        #expect(cells(terminal(.unicode, "\u{939}\u{902}|")) == ["0:\u{939}\u{902}:1", "1:|:1"])           // हं
        #expect(cells(terminal(.unicode, "\u{915}\u{94D}\u{937}|")) == ["0:\u{915}\u{94D}\u{937}:2", "2:|:1"])   // क्ष
        #expect(cells(terminal(.unicode, "\u{E01}\u{E33}|")) == ["0:\u{E01}\u{E33}:2", "2:|:1"])           // กำ
        // Alone, a spacing mark takes its own column
        #expect(cells(terminal(.unicode, "\u{93F}|")) == ["0:\u{93F}:1", "1:|:1"])
        // Tamil, Kannada and Sinhala viramas do not join a conjunct in Unicode's rules
        #expect(cells(terminal(.unicode, "\u{BA4}\u{BCD}\u{BA4}\u{BBE}|")) == ["0:\u{BA4}\u{BCD}:1", "1:\u{BA4}\u{BBE}:2", "3:|:1"])   // த்தா
        // Per code point, the spacing mark has its own cell
        #expect(cells(terminal(.wcwidth(.glibc), "\u{939}\u{93F}|")) == ["0:\u{939}:1", "1:\u{93F}:1", "2:|:1"])
    }

    // MARK: wcwidth (zellij, mosh)

    @Test func testWcwidthMeasuresEachCodePoint() {
        #expect(cells(terminal(.wcwidth(.glibc), "\u{1F44D}\u{1F3FD}|")) == ["0:\u{1F44D}:2", "2:\u{1F3FD}:2", "4:|:1"])
        #expect(cells(terminal(.wcwidth(.glibc), "\u{1F468}\u{200D}\u{1F469}|")) == ["0:\u{1F468}\u{200D}:2", "2:\u{1F469}:2", "4:|:1"])
        #expect(cells(terminal(.wcwidth(.glibc), "\u{1F1F8}\u{1F1EA}|")) == ["0:\u{1F1F8}:1", "1:\u{1F1EA}:1", "2:|:1"])
    }

    @Test func testWcwidthDarwinGivesSpacingMarksNoColumn() {
        // macOS's wcwidth measures हि as one column, glibc's as two
        #expect(cells(terminal(.wcwidth(.darwin), "\u{939}\u{93F}|")) == ["0:\u{939}\u{93F}:1", "1:|:1"])
        #expect(cells(terminal(.wcwidth(.glibc), "\u{939}\u{93F}|")) == ["0:\u{939}:1", "1:\u{93F}:1", "2:|:1"])
    }

    @Test func testWcwidthVs16DoesNotWiden() {
        #expect(cells(terminal(.wcwidth(.glibc), "\u{2764}\u{FE0F}|")) == ["0:\u{2764}\u{FE0F}:1", "1:|:1"])
    }

    // MARK: tmux

    @Test func testTmuxForcesModifierBasesWide() {
        #expect(cells(terminal(Self.tmux35, "\u{270C}|")) == ["0:\u{270C}:2", "2:|:1"])
        #expect(cells(terminal(Self.tmux37, "\u{270C}|")) == ["0:\u{270C}:2", "2:|:1"])
        #expect(cells(terminal(.wcwidth(.glibc), "\u{270C}|")) == ["0:\u{270C}:1", "1:|:1"])
    }

    @Test func testTmuxJoinsTheCharacterAfterAZwj() {
        // tmux keeps joining while the cell ends in a ZWJ; nothing is dropped
        #expect(cells(terminal(Self.tmux35, "\u{1F469}\u{200D}\u{4E2D}|")) == ["0:\u{1F469}\u{200D}\u{4E2D}:2", "2:|:1"])
        let sinhala = "\u{0DB4}\u{0DCA}\u{200D}\u{0DBB}\u{0DC1}\u{0DCA}\u{0DB1}\u{0DBA}"
        let t = terminal(Self.tmux35, sinhala + "|")
        #expect(t.getCursorLocation().x == 5)
        #expect(t.getText(start: Position(col: 0, row: 0), end: Position(col: 5, row: 0)) == sinhala + "|")
    }

    @Test func testTmux35CapsACellAt21Bytes() {
        let family = "\u{1F468}\u{200D}\u{1F469}\u{200D}\u{1F467}\u{200D}\u{1F466}"
        #expect(cells(terminal(Self.tmux35, family + "x")) == ["0:\u{1F468}\u{200D}\u{1F469}\u{200D}\u{1F467}\u{200D}:2", "2:\u{1F466}:2", "4:x:1"])
        #expect(cells(terminal(Self.tmux37, family + "x")) == ["0:\(family):2", "2:x:1"])
    }

    @Test func testTmux35MergesARunOfRegionalIndicators() {
        let flags = "\u{1F1F8}\u{1F1EA}\u{1F1F3}\u{1F1F4}"
        #expect(cells(terminal(Self.tmux35, flags + "|")) == ["0:\(flags):2", "2:|:1"])
        #expect(cells(terminal(Self.tmux37, flags + "|")) == ["0:\u{1F1F8}\u{1F1EA}:2", "2:\u{1F1F3}\u{1F1F4}:2", "4:|:1"])
    }

    @Test func testTmux35SkinToneWidensANarrowNonAsciiCell() {
        #expect(cells(terminal(Self.tmux35, "\u{E9}\u{1F3FD}|")) == ["0:\u{E9}\u{1F3FD}:2", "2:|:1"])
        #expect(cells(terminal(Self.tmux37, "\u{E9}\u{1F3FD}|")) == ["0:\u{E9}:1", "1:\u{1F3FD}:2", "3:|:1"])
    }

    @Test func testTmuxVs16WidensUnlessTheOptionIsOff() {
        #expect(cells(terminal(Self.tmux37, "\u{2764}\u{FE0F}|")) == ["0:\u{2764}\u{FE0F}:2", "2:|:1"])
        let off = WidthMode.tmux(TmuxVersion(major: 3, minor: 7, utf8proc: true, variationSelectorAlwaysWide: false))
        #expect(cells(terminal(off, "\u{2764}\u{FE0F}|")) == ["0:\u{2764}\u{FE0F}:1", "1:|:1"])
        // tmux 3.5 has no option and always widens
        let old = WidthMode.tmux(TmuxVersion(major: 3, minor: 5, variationSelectorAlwaysWide: false))
        #expect(cells(terminal(old, "\u{2764}\u{FE0F}|")) == ["0:\u{2764}\u{FE0F}:2", "2:|:1"])
    }

    @Test func testTmux37IgnoresHangulFiller() {
        #expect(cells(terminal(Self.tmux37, "\u{3164}x")) == ["0:x:1"])
    }

    // MARK: switching, copy, search

    @Test func testSwitchingModeOnlyChangesNewOutput() {
        let (t, _) = TerminalTestHarness.makeTerminal(cols: 20, rows: 2)
        t.feed(text: "\u{270C}")
        t.widthMode = Self.tmux35
        t.feed(text: "\u{270C}")
        t.widthMode = .unicode
        t.feed(text: "\u{270C}|")
        #expect(cells(t) == ["0:\u{270C}:1", "1:\u{270C}:2", "3:\u{270C}:1", "4:|:1"])
    }

    @Test func testCopyTurnsUnwrittenCellsIntoSpaces() {
        for mode in [WidthMode.unicode, .wcwidth(.glibc), Self.tmux35] {
            let t = terminal(mode, "ab\u{1b}[3C\u{1F3FD}|")
            #expect(t.getText(start: Position(col: 0, row: 0), end: Position(col: 20, row: 0)) == "ab   \u{1F3FD}|", "\(mode)")
        }
    }

    @Test func testSearchHighlightsEveryColumnOfTheMatch() {
        for mode in [WidthMode.unicode, .wcwidth(.glibc), Self.tmux35] {
            let t = terminal(mode, "xa\u{1F3FD}y")
            let service = SearchService(terminal: t)
            #expect(service.findNext(term: "a\u{1F3FD}") == SearchResult(term: "a\u{1F3FD}", col: 1, row: 0, size: 3), "\(mode)")
        }
    }
}
