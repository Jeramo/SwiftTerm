import Testing
@testable import SwiftTerm

/// tmux redraws a cell whose cluster grew (a combining mark, ZWJ, skin tone,
/// second regional indicator or VS16 arrived) by moving the cursor back and
/// printing the whole cluster again. These sequences are copied from tmux
/// 3.5a and 3.7 output; each must leave the same screen as printing the
/// cluster once.
final class GraphemeRewriteTests {
    private func cell(_ terminal: Terminal, _ col: Int, _ row: Int = 0) -> (String, Int) {
        let cd = terminal.getCharData(col: col, row: row)!
        return (cd.code == 0 ? "\u{0}" : terminal.getText(for: cd), Int(cd.width))
    }

    private static let tmux35 = WidthMode.tmux(TmuxVersion(major: 3, minor: 5))

    @Test func testZwjClusterRewrittenWithCursorPosition() {
        let (t, _) = TerminalTestHarness.makeTerminal(cols: 20, rows: 2)
        let man = "\u{1F468}", woman = "\u{1F469}", girl = "\u{1F467}", zwj = "\u{200D}"
        t.feed(text: "\u{1b}[1;1H\(man)\u{1b}[1;1H\(man)\(zwj)\u{1b}[1;1H\(man)\(zwj)\(woman)"
            + "\u{1b}[1;1H\(man)\(zwj)\(woman)\(zwj)\u{1b}[1;1H\(man)\(zwj)\(woman)\(zwj)\(girl)X")
        #expect(cell(t, 0) == ("\(man)\(zwj)\(woman)\(zwj)\(girl)", 2))
        #expect(cell(t, 2) == ("X", 1))
        TerminalTestHarness.assertCursor(t.buffer, col: 3, row: 0)
    }

    @Test func testZwjClusterRewrittenWithBackspaces() {
        let (t, _) = TerminalTestHarness.makeTerminal(cols: 20, rows: 2)
        let man = "\u{1F468}", woman = "\u{1F469}", zwj = "\u{200D}"
        t.feed(text: "\(man)\u{8}\u{8}\(man)\(zwj)\u{8}\u{8}\(man)\(zwj)\(woman) |")
        #expect(cell(t, 0) == ("\(man)\(zwj)\(woman)", 2))
        #expect(cell(t, 3) == ("|", 1))
    }

    @Test func testFlagRewrittenAfterCursorMove() {
        let (t, _) = TerminalTestHarness.makeTerminal(cols: 20, rows: 2)
        // "flags: " then tmux 3.7's per-flag redraw
        t.feed(text: "flags: \u{1F1F8}\u{1b}[1;8H\u{1F1F8}\u{1F1EA}\u{1b}[1;10H\u{1F1FA}\u{1b}[1;10H\u{1F1FA}\u{1F1F8}\u{1b}[1;12H |")
        #expect(cell(t, 7) == ("\u{1F1F8}\u{1F1EA}", 2))
        #expect(cell(t, 9) == ("\u{1F1FA}\u{1F1F8}", 2))
        #expect(cell(t, 12) == ("|", 1))
    }

    @Test func testCombiningMarkRewrittenWithBackspace() {
        let (t, _) = TerminalTestHarness.makeTerminal(cols: 20, rows: 2)
        t.feed(text: "e\u{8}e\u{301} a\u{8}a\u{308} |")
        #expect(cell(t, 0) == ("e\u{301}", 1))
        #expect(cell(t, 2) == ("a\u{308}", 1))
        #expect(cell(t, 4) == ("|", 1))
    }

    @Test func testBaseCharacterDoesNotJoinClusterLeftBehindByCursorMove() {
        let (t, _) = TerminalTestHarness.makeTerminal(cols: 20, rows: 2)
        // The cluster ends in ZWJ; after moving away, a new emoji is a new cell
        t.feed(text: "\u{1F468}\u{200D}\u{1b}[1;6H\u{1F469}")
        #expect(cell(t, 0) == ("\u{1F468}\u{200D}", 2))
        #expect(cell(t, 5) == ("\u{1F469}", 2))
        TerminalTestHarness.assertCursor(t.buffer, col: 7, row: 0)
    }

    @Test func testCombiningMarkJoinsCellLeftOfCursor() {
        let (t, _) = TerminalTestHarness.makeTerminal(cols: 20, rows: 2)
        t.feed(text: "ab\u{1b}[1;2H\u{301}")
        #expect(cell(t, 0) == ("a\u{301}", 1))
        #expect(cell(t, 1) == ("b", 1))
    }

    @Test func testCombiningMarkAtColumnZeroIsDropped() {
        let (t, _) = TerminalTestHarness.makeTerminal(cols: 20, rows: 2)
        t.feed(text: "ab\r\u{301}")
        #expect(cell(t, 0) == ("a", 1))
        TerminalTestHarness.assertCursor(t.buffer, col: 0, row: 0)
    }

    @Test func testVs16WidensAfterRewrite() {
        let (t, _) = TerminalTestHarness.makeTerminal(cols: 20, rows: 2)
        // tmux 3.7: bare heart, then CUP back and heart + VS16
        t.feed(text: "\u{2764}\u{1b}[1;1H\u{2764}\u{FE0F}X")
        #expect(cell(t, 0) == ("\u{2764}\u{FE0F}", 2))
        #expect(cell(t, 2) == ("X", 1))
    }

    @Test func testCombiningAfterPendingWrap() {
        let (t, _) = TerminalTestHarness.makeTerminal(cols: 5, rows: 2)
        t.feed(text: "abcde\u{301}")
        #expect(cell(t, 4) == ("e\u{301}", 1))
        TerminalTestHarness.assertCursor(t.buffer, col: 5, row: 0)
    }

    @Test func testOverwritingHalfOfWideCharKeepsCurrentBackground() {
        // nvim inside tmux redraws over half of a wide cell with its own
        // background; the cleared half must not fall back to the default
        let (t, _) = TerminalTestHarness.makeTerminal(cols: 20, rows: 2)
        t.feed(text: "\u{1b}[44m\u{6F22}\u{1b}[1;2H\u{1b}[41m\u{2764}")
        #expect(cell(t, 0).1 == 1)
        #expect(t.getCharData(col: 0, row: 0)!.attribute.bg == .ansi256(code: 1))
        #expect(t.getCharData(col: 1, row: 0)!.attribute.bg == .ansi256(code: 1))

        t.feed(text: "\u{1b}[2;1H\u{1b}[44m\u{6F22}\u{1b}[2;1H\u{1b}[42m\u{2764}")
        #expect(cell(t, 1, 1).1 == 1)
        #expect(t.getCharData(col: 1, row: 1)!.attribute.bg == .ansi256(code: 2))
    }

    @Test func testClearedHalfOfWideCharKeepsOnlyTheBackground() {
        // like an erase (and Ghostty), the blank takes no inverse, underline or foreground
        let (t, _) = TerminalTestHarness.makeTerminal(cols: 20, rows: 2)
        t.feed(text: "\u{6F22}\u{1b}[1;2H\u{1b}[7;4;31;42m\u{2764}")
        let blank = t.getCharData(col: 0, row: 0)!.attribute
        #expect(blank.bg == .ansi256(code: 2))
        #expect(blank.fg == CharData.defaultAttr.fg)
        #expect(blank.style == CharData.defaultAttr.style)
        // the ASCII path too
        t.feed(text: "\u{1b}[0m\u{1b}[2;1H\u{6F22}\u{1b}[2;1H\u{1b}[7;43mz")
        let tail = t.getCharData(col: 1, row: 1)!.attribute
        #expect(tail.bg == .ansi256(code: 3))
        #expect(tail.style == CharData.defaultAttr.style)
    }

    @Test func testVs16WideningClearsTheWideCharItCovers() {
        // ☺ widens over the leading half of 中; 中's trailing half must not linger
        let (t, _) = TerminalTestHarness.makeTerminal(cols: 20, rows: 2)
        t.feed(text: "\u{263A}\u{4E2D}\u{6587}\u{1b}[1;2H\u{FE0F}")
        #expect(cell(t, 0) == ("\u{263A}\u{FE0F}", 2))
        #expect(cell(t, 1).1 == 0)
        #expect(cell(t, 2) == ("\u{0}", 1))
        #expect(cell(t, 3) == ("\u{6587}", 2))
        TerminalTestHarness.assertCursor(t.buffer, col: 2, row: 0)
    }

    @Test func testNothingJoinsAWideCharFromItsTrailingHalfInTmux() {
        // tmux drops the ZWJ when the cursor sits on 👨's trailing half, and 👩
        // then overwrites 👨
        let (t, _) = TerminalTestHarness.makeTerminal(cols: 20, rows: 2)
        t.widthMode = Self.tmux35
        t.feed(text: "\u{1F468}\u{1b}[1;2H\u{200D}\u{1F469}q")
        #expect(cell(t, 0) == ("\u{0}", 1))
        #expect(cell(t, 1) == ("\u{1F469}", 2))
        #expect(cell(t, 3) == ("q", 1))
    }

    @Test func testLoneSkinToneIsWide() {
        // tmux, zellij, glibc and Ghostty all give a standalone modifier 2 columns
        for mode in [WidthMode.unicode, .wcwidth(.glibc), Self.tmux35] {
            let (t, _) = TerminalTestHarness.makeTerminal(cols: 20, rows: 2)
            t.widthMode = mode
            t.feed(text: "\u{1F3FD}X")
            #expect(cell(t, 0) == ("\u{1F3FD}", 2), "\(mode)")
            #expect(cell(t, 2) == ("X", 1), "\(mode)")
        }
    }

    @Test func testSkinToneStillJoinsEmoji() {
        for mode in [WidthMode.unicode, Self.tmux35] {
            let (t, _) = TerminalTestHarness.makeTerminal(cols: 20, rows: 2)
            t.widthMode = mode
            t.feed(text: "\u{1F44D}\u{1F3FD}X")
            #expect(cell(t, 0) == ("\u{1F44D}\u{1F3FD}", 2), "\(mode)")
            #expect(cell(t, 2) == ("X", 1), "\(mode)")
        }
    }

    @Test func testSkinToneAfterAsciiStandsAlone() {
        // "a🏽" is three columns in Ghostty, tmux, zellij, nvim, vim and glibc
        for mode in [WidthMode.unicode, .wcwidth(.glibc), Self.tmux35] {
            let (t, _) = TerminalTestHarness.makeTerminal(cols: 20, rows: 2)
            t.widthMode = mode
            t.feed(text: "a\u{1F3FD}|")
            #expect(cell(t, 0) == ("a", 1), "\(mode)")
            #expect(cell(t, 1) == ("\u{1F3FD}", 2), "\(mode)")
            #expect(cell(t, 3) == ("|", 1), "\(mode)")
        }
    }
}
