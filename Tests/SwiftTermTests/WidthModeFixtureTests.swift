import Foundation
import Testing
@testable import SwiftTerm

/// Output recorded from the programs each width mode is for, replayed into a
/// terminal set to that mode. Every row's text, the column each cell starts
/// at, and the cursor must come out as the program left its own screen;
/// otherwise later output lands in the wrong columns.
///
/// Each `<name>.screen` holds `SIZE cols rows`, `CURSOR x y` (-1 when the
/// program does not report it), `T<row> text` and `C<row>` with the start
/// column of each cell followed by the row's extent. The programs and how
/// their screens were read are in Fixtures/README.md.
final class WidthModeFixtureTests {
    static let directory = "Fixtures/widths"

    static func names (_ set: String) -> [String] {
        guard let urls = Bundle.module.urls(forResourcesWithExtension: "rec", subdirectory: "\(directory)/\(set)") else {
            return []
        }
        return urls.map { $0.deletingPathExtension().lastPathComponent }.sorted()
    }

    private struct Screen {
        var cols = 0
        var rows = 0
        var cursor: [Int] = []
        var text: [Int: String] = [:]
        var starts: [Int: [Int]] = [:]
        var tabs: Set<Int> = []
    }

    private func load (_ set: String, _ name: String, _ ext: String) throws -> Data {
        let url = try #require(Bundle.module.url(forResource: name, withExtension: ext, subdirectory: "\(Self.directory)/\(set)"))
        return try Data(contentsOf: url)
    }

    private func expected (_ set: String, _ name: String) throws -> Screen {
        var screen = Screen()
        for line in String(decoding: try load(set, name, "screen"), as: UTF8.self).split(separator: "\n", omittingEmptySubsequences: false) {
            // Split on the byte: a space followed by a skin tone or a Thai vowel is one Character
            let space = line.utf8.firstIndex(of: UInt8(ascii: " "))
            let tag = String(space.map { line[..<$0] } ?? line[...])
            let rest = space.map { String(line[line.utf8.index(after: $0)...]) } ?? ""
            let numbers = rest.split(separator: " ").compactMap { Int($0) }
            if tag == "SIZE" {
                screen.cols = numbers[0]
                screen.rows = numbers[1]
            } else if tag == "CURSOR" {
                screen.cursor = numbers
            } else if let row = Int(tag.dropFirst()) {
                if tag.first == "T" {
                    screen.text[row] = Self.trimmed(Self.expandTabs(rest))
                    if rest.contains("\t") {
                        screen.tabs.insert(row)
                    }
                } else if tag.first == "C" {
                    screen.starts[row] = numbers
                }
            }
        }
        return screen
    }

    private static func trimmed (_ text: String) -> String {
        var text = text
        while text.hasSuffix(" ") {
            text.removeLast()
        }
        return text
    }

    // tmux keeps tabs in its grid and capture-pane prints them
    private static func expandTabs (_ text: String) -> String {
        var out = ""
        var column = 0
        for ch in text {
            if ch == "\t" {
                let n = 8 - column % 8
                out += String(repeating: " ", count: n)
                column += n
            } else {
                out.append(ch)
                column += 1
            }
        }
        return out
    }

    // tmux 3.7 keeps a tab as one cell; on the client it is blank columns.
    // `positions` are the cell starts followed by the row's extent.
    private static func expandTabCells (_ positions: [Int]) -> [Int] {
        var out: [Int] = []
        for (start, next) in zip(positions, positions.dropFirst()) {
            // nothing but a tab is wider than two columns
            out += next - start > 2 ? Array(start..<next) : [start]
        }
        return out
    }

    /// Rows where tmux's own grid (capture-pane, copy mode) holds something it
    /// never sent its client, so no attached terminal can show it. Each value
    /// is what the client was sent; the recorded row must still differ.
    static let clientRows: [String: [Int: (text: String, starts: [Int]?)]] = [
        // tmux 3.5a: ASCII written over the right half of a wide character
        // in column 0 leaves the wide character in tmux's grid, because the
        // loop in screen_write_collect_end stops before column 0 (3.7 checks
        // it). tmux sent only the ASCII, which erases the wide character on
        // the client; tmux 3.7b records these rows as the client shows them.
        "tmux35/e07_cursor_right_half": [0: (" |", nil)],
        "tmux35/s04_cursor_in_wide_tail": [2: (" x\u{6587}", nil)],
        "tmux35/t08_textbase_edit": [0: (" Q|b", nil)],
        "tmux35/s19_vs16_widen_over_wide": [
            0: ("\u{2764}\u{FE0F}Z", [0, 2]),
            // and below: VS16 widened ☺ over half of 中; tmux keeps the
            // other half as padding of no character, the client a blank
            1: ("\u{263A}\u{FE0F} \u{6587}", [0, 2, 3]),
        ],
        "tmux37/s19_vs16_widen_over_wide": [1: ("\u{263A}\u{FE0F} \u{6587}", [0, 2, 3])],
        // tmux 3.7b: a VS16 that would widen the last column is added to the
        // grid but not drawn ("part of this character is obscured" in
        // screen_write_combine), so the client never receives it
        "tmux37/e09_vs16_last": [0: ("abcdefghijk\u{2764}", nil)],
        "tmux37/m06_vs": [0: ("\u{231A}\u{FE0E}|a\u{FE0F}|\u{2764}\u{FE0F}|\u{2764}\u{FE0E}|\u{263A}", nil)],
        "tmux37/s01_pendingwrap_combining": [2: ("           \u{2764}", nil)],
        "tmux37/s17_wrap_wide_vs16_lastcol": [0: ("          \u{263A}\u{263A}", nil), 2: ("           \u{2764}", nil)],
        "tmux37/s28_keycap_lastcol_thai_lastcol": [0: ("           1", nil)],
    ]

    private func check (_ set: String, _ name: String, _ mode: WidthMode) throws {
        let want = try expected(set, name)
        let (terminal, _) = TerminalTestHarness.makeTerminal(cols: want.cols, rows: want.rows)
        terminal.widthMode = mode
        terminal.feed(byteArray: Array(try load(set, name, "rec")))
        let client = Self.clientRows["\(set)/\(name)"] ?? [:]
        for row in 0..<want.rows {
            let line = try #require(terminal.getLine(row: row))
            var text = ""
            for col in 0..<want.cols where line[col].width != 0 {
                text += line[col].code == 0 ? " " : terminal.getText(for: line[col])
            }
            var wantText = want.text[row]
            var wantStarts = want.starts[row].map { want.tabs.contains(row) ? Self.expandTabCells($0) : Array($0.dropLast()) }
            if let sent = client[row] {
                #expect(sent.text != wantText, "\(set)/\(name) row \(row) no longer differs from tmux's grid")
                wantText = sent.text
                wantStarts = sent.starts ?? wantStarts
            }
            #expect(Self.trimmed(text) == wantText, "\(set)/\(name) row \(row) text")
            if let positions = want.starts[row], let extent = positions.last, let wantStarts {
                let starts = (0..<min(extent, want.cols)).filter { line[$0].width != 0 }
                #expect(starts == wantStarts, "\(set)/\(name) row \(row) cell columns")
                // and nothing written past the row's end, which the text alone would not show
                let written = (0..<want.cols).filter { line[$0].width != 0 && line[$0].code != 0 && terminal.getText(for: line[$0]) != " " }
                    .map { $0 + Int(line[$0].width) }.max() ?? 0
                #expect(written <= extent, "\(set)/\(name) row \(row) has text up to column \(written), past \(extent)")
            }
        }
        if want.cursor.count == 2 && want.cursor[0] >= 0 {
            let cursor = terminal.getCursorLocation()
            #expect([cursor.x, cursor.y] == want.cursor, "\(set)/\(name) cursor")
        }
    }

    @Test func testFixturesArePresent() {
        #expect(Self.names("tmux35").count == 76)
        #expect(Self.names("tmux37").count == 76)
        #expect(Self.names("shell").count == 7)
        #expect(!Self.names("zellij").isEmpty)
        #expect(!Self.names("mosh").isEmpty)
        #expect(Self.names("mosh-darwin").count == 14)
        #expect(Self.names("shell-wcwidth").count == 10)
    }

    /// tmux 3.5a on Debian 13 (glibc widths), what tmux sent a client
    @Test(arguments: WidthModeFixtureTests.names("tmux35"))
    func testTmux35 (_ name: String) throws {
        try check("tmux35", name, .tmux(TmuxVersion(major: 3, minor: 5)))
    }

    /// tmux 3.7b from Homebrew on macOS (utf8proc widths)
    @Test(arguments: WidthModeFixtureTests.names("tmux37"))
    func testTmux37 (_ name: String) throws {
        try check("tmux37", name, .tmux(TmuxVersion(major: 3, minor: 7, utf8proc: true)))
    }

    /// zellij 0.43.1, measured per code point
    @Test(arguments: WidthModeFixtureTests.names("zellij"))
    func testZellij (_ name: String) throws {
        try check("zellij", name, .wcwidth(.glibc))
    }

    /// mosh 1.4.0: mosh-client drawing mosh-server's glibc-measured screen
    @Test(arguments: WidthModeFixtureTests.names("mosh"))
    func testMosh (_ name: String) throws {
        try check("mosh", name, .wcwidth(.glibc))
    }

    /// mosh 1.4.0 with mosh-server on macOS, which measures with macOS's wcwidth
    @Test(arguments: WidthModeFixtureTests.names("mosh-darwin"))
    func testMoshDarwin (_ name: String) throws {
        try check("mosh-darwin", name, .wcwidth(.darwin))
    }

    /// bash and zsh editing lines holding 👍🏽, a ZWJ family, flags, ❤️ and
    /// Hindi: readline and zle measure per code point, so only `.wcwidth` keeps
    /// their cursor where they think it is (the trade-off of `.unicode`)
    @Test(arguments: WidthModeFixtureTests.names("shell-wcwidth"))
    func testShellWcwidth (_ name: String) throws {
        try check("shell-wcwidth", name, .wcwidth(.glibc))
    }

    /// bash, zsh and fish editing a line over ssh, without a multiplexer
    @Test(arguments: WidthModeFixtureTests.names("shell"))
    func testShell (_ name: String) throws {
        try check("shell", name, .unicode)
    }
}
