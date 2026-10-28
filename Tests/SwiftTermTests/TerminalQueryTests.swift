import Testing
@testable import SwiftTerm

/// Replies to the queries tmux, zellij and neovim send at startup, checked
/// against the byte-exact answers Ghostty and xterm give.
final class TerminalQueryTests {
    private func replies(_ input: String, setup: ((Terminal) -> Void)? = nil) -> [String] {
        let (terminal, delegate) = TerminalTestHarness.makeTerminal()
        setup?(terminal)
        terminal.feed(text: input)
        return delegate.sentData.map { String(decoding: $0, as: UTF8.self) }
    }

    private func hex(_ text: String) -> String {
        text.utf8.map { String(format: "%02X", $0) }.joined()
    }

    // MARK: XTVERSION

    @Test func testXtversionReportsNameAndVersion() {
        // kitty and foot use name(version); tmux shows it as client_termtype
        #expect(replies("\u{1b}[>q") == ["\u{1b}P>|SwiftTerm(1.13.0)\u{1b}\\"])
        #expect(replies("\u{1b}[>0q") == ["\u{1b}P>|SwiftTerm(1.13.0)\u{1b}\\"])
    }

    @Test func testXtversionTextUsesHostNameAndStaysPrintable() {
        #expect(Terminal.xtversionText(name: "Pling", version: "2.6.10") == "Pling(2.6.10)")
        // an escape in a host string must not terminate the DCS
        #expect(Terminal.xtversionText(name: "Bad\u{1b}\\", version: "1\u{7}") == "Bad\\(1)")
        #expect(Terminal.xtversionText(name: String(repeating: "x", count: 300), version: "1").count == 100)
    }

    @Test func testXtversionIgnoresOtherParameters() {
        #expect(replies("\u{1b}[>1q").isEmpty)
    }

    @Test func testXtversionDoesNotChangeCursorStyle() {
        let (terminal, _) = TerminalTestHarness.makeTerminal()
        terminal.feed(text: "\u{1b}[6 q\u{1b}[>q")
        #expect(terminal.options.cursorStyle == .steadyBar)
    }

    // MARK: XTGETTCAP

    @Test func testXtgettcapBooleanCapability() {
        #expect(replies("\u{1b}P+q5463\u{1b}\\") == ["\u{1b}P1+r5463\u{1b}\\"])
    }

    @Test func testXtgettcapRepliesOncePerCapability() {
        // neovim asks for these four at once and parses one capability per reply
        let sent = replies("\u{1b}P+q5463;524742;73657472676266;73657472676262\u{1b}\\")
        #expect(sent == [
            "\u{1b}P1+r5463\u{1b}\\",
            "\u{1b}P1+r524742=38\u{1b}\\",
            "\u{1b}P1+r\(hex("setrgbf"))=\(hex("\u{1b}[38:2:%p1%d:%p2%d:%p3%dm"))\u{1b}\\",
            "\u{1b}P1+r\(hex("setrgbb"))=\(hex("\u{1b}[48:2:%p1%d:%p2%d:%p3%dm"))\u{1b}\\",
        ])
    }

    @Test func testXtgettcapClipboardValueIsDecoded() {
        // neovim only enables its OSC 52 clipboard when Ms starts with ESC ] 52
        let sent = replies("\u{1b}P+q\(hex("Ms"))\u{1b}\\")
        #expect(sent == ["\u{1b}P1+r4D73=\(hex("\u{1b}]52;%p1%s;%p2%s\u{07}"))\u{1b}\\"])
    }

    @Test func testXtgettcapTerminalNameAndColors() {
        let sent = replies("\u{1b}P+q\(hex("TN"));\(hex("colors"))\u{1b}\\") { terminal in
            terminal.options.termName = "xterm-256color"
        }
        #expect(sent == [
            "\u{1b}P1+r544E=\(hex("xterm-256color"))\u{1b}\\",
            "\u{1b}P1+r\(hex("colors"))=323536\u{1b}\\",
        ])
    }

    @Test func testXtgettcapAcceptsLowercaseHex() {
        #expect(replies("\u{1b}P+q\(hex("Smulx").lowercased())\u{1b}\\")
            == ["\u{1b}P1+r\(hex("Smulx"))=\(hex("\u{1b}[4:%p1%dm"))\u{1b}\\"])
    }

    @Test func testXtgettcapSkipsUnknownAndMalformedNames() {
        // unknown name, odd length, non-hex, empty: no reply for any (as Ghostty)
        let sent = replies("\u{1b}P+q\(hex("bogus"));545;zz;;5463\u{1b}\\")
        #expect(sent == ["\u{1b}P1+r5463\u{1b}\\"])
    }

    @Test func testXtgettcapDropsOversizedRequest() {
        let padding = String(repeating: "5463;", count: 1000)
        #expect(replies("\u{1b}P+q\(padding)5463\u{1b}\\").isEmpty)
    }

    @Test func testXtgettcapDoesNotDisturbSixelOrDecrqss() {
        let sent = replies("\u{1b}P+q5463\u{1b}\\\u{1b}P$qr\u{1b}\\")
        #expect(sent == ["\u{1b}P1+r5463\u{1b}\\", "\u{1b}P1$r1;24r\u{1b}\\"])
    }

    // MARK: DECRQSS

    @Test func testDecrqssSgrReportsUndercurl() {
        // neovim's extended underline probe, verbatim
        #expect(replies("\u{1b}[0m\u{1b}[4:3m\u{1b}P$qm\u{1b}\\") == ["\u{1b}P1$r0;4:3m\u{1b}\\"])
    }

    @Test func testDecrqssSgrReportsPlainUnderline() {
        #expect(replies("\u{1b}[4m\u{1b}P$qm\u{1b}\\") == ["\u{1b}P1$r0;4m\u{1b}\\"])
        #expect(replies("\u{1b}[21m\u{1b}P$qm\u{1b}\\") == ["\u{1b}P1$r0;4:2m\u{1b}\\"])
    }

    @Test func testDecrqssSgrReportsTruecolorInColonForm() {
        // neovim's truecolor probe, verbatim
        #expect(replies("\u{1b}[0m\u{1b}[48;2;1;2;3m\u{1b}P$qm\u{1b}\\") == ["\u{1b}P1$r0;48:2::1:2:3m\u{1b}\\"])
        #expect(replies("\u{1b}[1;38;2;100;200;255m\u{1b}P$qm\u{1b}\\") == ["\u{1b}P1$r0;1;38:2::100:200:255m\u{1b}\\"])
    }

    @Test func testDecrqssSgrReportsPaletteColors() {
        #expect(replies("\u{1b}[31;102m\u{1b}P$qm\u{1b}\\") == ["\u{1b}P1$r0;31;102m\u{1b}\\"])
        #expect(replies("\u{1b}[38;5;208;48;5;17m\u{1b}P$qm\u{1b}\\") == ["\u{1b}P1$r0;38:5:208;48:5:17m\u{1b}\\"])
    }

    @Test func testDecrqssSgrReportsUnderlineColor() {
        #expect(replies("\u{1b}[4:3m\u{1b}[58:2::255:0:0m\u{1b}P$qm\u{1b}\\") == ["\u{1b}P1$r0;4:3;58:2::255:0:0m\u{1b}\\"])
        #expect(replies("\u{1b}[4m\u{1b}[58;5;196m\u{1b}P$qm\u{1b}\\") == ["\u{1b}P1$r0;4;58:5:196m\u{1b}\\"])
    }

    @Test func testDecrqssReportsCursorStyle() {
        #expect(replies("\u{1b}[5 q\u{1b}P$q q\u{1b}\\") == ["\u{1b}P1$r5 q\u{1b}\\"])
        #expect(replies("\u{1b}[4 q\u{1b}P$q q\u{1b}\\") == ["\u{1b}P1$r4 q\u{1b}\\"])
    }

    // MARK: DECRQM

    @Test func testDecrqmSynchronizedOutputIgnoresAutomaticSync() {
        // Entering the alternate screen starts an internal sync that the
        // application did not ask for; neovim asks right after ?1049h.
        #expect(replies("\u{1b}[?1049h\u{1b}[?2026$p") == ["\u{1b}[?2026;2$y"])
        #expect(replies("\u{1b}[?1049h\u{1b}[?2026h\u{1b}[?2026$p") == ["\u{1b}[?2026;1$y"])
        #expect(replies("\u{1b}[?2026h\u{1b}[?2026l\u{1b}[?2026$p") == ["\u{1b}[?2026;2$y"])
    }

    @Test func testDecrqmAlternateScreen() {
        #expect(replies("\u{1b}[?1049$p") == ["\u{1b}[?1049;2$y"])
        #expect(replies("\u{1b}[?1049h\u{1b}[?1049$p\u{1b}[?1047$p") == ["\u{1b}[?1049;1$y", "\u{1b}[?1047;1$y"])
    }

    @Test func testDecrqmGraphemeClusteringReportsTheWidthMode() {
        // Mode 2027 is on in the default (grapheme) widths; DECRST switches to
        // per-code-point widths and DECSET back
        #expect(replies("\u{1b}[?2027$p") == ["\u{1b}[?2027;1$y"])
        #expect(replies("\u{1b}[?2027l\u{1b}[?2027$p") == ["\u{1b}[?2027;2$y"])
        #expect(replies("\u{1b}[?2027l\u{1b}[?2027h\u{1b}[?2027$p") == ["\u{1b}[?2027;1$y"])
        #expect(replies("\u{1b}[?2027$p", setup: { $0.widthMode = .wcwidth(.darwin) }) == ["\u{1b}[?2027;2$y"])
        // Attached to tmux the widths are tmux's: permanently reset, DECSET ignored
        let tmux = WidthMode.tmux(TmuxVersion(major: 3, minor: 5))
        #expect(replies("\u{1b}[?2027h\u{1b}[?2027$p", setup: { $0.widthMode = tmux }) == ["\u{1b}[?2027;4$y"])
    }

    @Test func testFullResetUndoesModeTwentyTwentySeven() {
        // As in Ghostty: RIS puts grapheme clustering back
        #expect(replies("\u{1b}[?2027l\u{1b}c\u{1b}[?2027$p") == ["\u{1b}[?2027;1$y"])
        // The mode the host chose is context and survives; a program's change does not
        let (terminal, _) = TerminalTestHarness.makeTerminal()
        terminal.widthMode = .wcwidth(.darwin)
        terminal.feed(text: "\u{1b}[?2027h\u{1b}c")
        #expect(terminal.widthMode == .wcwidth(.darwin))
        let tmux = WidthMode.tmux(TmuxVersion(major: 3, minor: 5))
        terminal.widthMode = tmux
        terminal.feed(text: "\u{1b}c")
        #expect(terminal.widthMode == tmux)
    }

    @Test func testBidirectionalSupportMode() {
        // BDSM (ANSI mode 8): set, the terminal draws right-to-left text in
        // visual order; reset by an application that orders it itself
        #expect(replies("\u{1b}[8$p") == ["\u{1b}[8;1$y"])
        #expect(replies("\u{1b}[8l\u{1b}[8$p") == ["\u{1b}[8;2$y"])
        #expect(replies("\u{1b}[8l\u{1b}[8h\u{1b}[8$p") == ["\u{1b}[8;1$y"])
        #expect(replies("\u{1b}[8l\u{1b}c\u{1b}[8$p") == ["\u{1b}[8;1$y"])
    }

    @Test func testDecsetGraphemeClusteringSwitchesTheWidthMode() {
        let (terminal, _) = TerminalTestHarness.makeTerminal()
        terminal.feed(text: "\u{1b}[?2027l")
        #expect(terminal.widthMode == .wcwidth(.glibc))
        terminal.feed(text: "\u{1b}[?2027h")
        #expect(terminal.widthMode == .unicode)
        // DECRST goes back to the table the app chose
        terminal.widthMode = .wcwidth(.darwin)
        terminal.feed(text: "\u{1b}[?2027h\u{1b}[?2027l")
        #expect(terminal.widthMode == .wcwidth(.darwin))
        let tmux = WidthMode.tmux(TmuxVersion(major: 3, minor: 7, utf8proc: true))
        terminal.widthMode = tmux
        terminal.feed(text: "\u{1b}[?2027l\u{1b}[?2027h")
        #expect(terminal.widthMode == tmux)
    }

    @Test func testDecrqmColorSchemeUpdates() {
        #expect(replies("\u{1b}[?2031$p") == ["\u{1b}[?2031;2$y"])
        #expect(replies("\u{1b}[?2031h\u{1b}[?2031$p") == ["\u{1b}[?2031;1$y"])
        #expect(replies("\u{1b}[?2031h\u{1b}[?2031l\u{1b}[?2031$p") == ["\u{1b}[?2031;2$y"])
    }

    // MARK: Color scheme (CSI ? 996 n, DECSET 2031)

    @Test func testColorSchemeQueryFollowsBackground() {
        #expect(replies("\u{1b}[?996n") { $0.backgroundColor = Color(red: 0x1414, green: 0x1616, blue: 0x1b1b) }
            == ["\u{1b}[?997;1n"])
        #expect(replies("\u{1b}[?996n") { $0.backgroundColor = Color(red: 0xfafa, green: 0xf8f8, blue: 0xf0f0) }
            == ["\u{1b}[?997;2n"])
    }

    @Test func testColorSchemeNotifiesOnlyWhenSubscribedAndFlipped() {
        let (terminal, delegate) = TerminalTestHarness.makeTerminal()
        terminal.backgroundColor = Color(red: 0xffff, green: 0xffff, blue: 0xffff)
        #expect(delegate.sentData.isEmpty)

        terminal.feed(text: "\u{1b}[?2031h")
        terminal.backgroundColor = Color(red: 0xeeee, green: 0xeeee, blue: 0xeeee)
        #expect(delegate.sentData.isEmpty)

        terminal.backgroundColor = Color(red: 0, green: 0, blue: 0)
        #expect(delegate.sentData.map { String(decoding: $0, as: UTF8.self) } == ["\u{1b}[?997;1n"])

        delegate.clearSentData()
        terminal.feed(text: "\u{1b}[?2031l")
        terminal.backgroundColor = Color(red: 0xffff, green: 0xffff, blue: 0xffff)
        #expect(delegate.sentData.isEmpty)
    }

    // MARK: Cursor position reports

    @Test func testCursorPositionReportAtPendingWrap() {
        // After filling a 12-column row the cursor waits past the edge; xterm
        // reports column 12, which shells use to measure the prompt
        let (terminal, delegate) = TerminalTestHarness.makeTerminal(cols: 12, rows: 4)
        terminal.feed(text: "abcdefghijkl\u{1b}[6n\u{1b}[?6n")
        #expect(delegate.sentData.map { String(decoding: $0, as: UTF8.self) } == ["\u{1b}[1;12R", "\u{1b}[?1;12;1R"])

        delegate.clearSentData()
        terminal.feed(text: "\u{1b}[2;5H\u{1b}[6n")
        #expect(delegate.sentData.map { String(decoding: $0, as: UTF8.self) } == ["\u{1b}[2;5R"])
    }

    // MARK: XTQMODKEYS

    @Test func testXtqmodkeysReportsModifyOtherKeysOff() {
        // vim enables modifyOtherKeys and then asks; SwiftTerm does not implement it
        #expect(replies("\u{1b}[>4;2m\u{1b}[?4m") == ["\u{1b}[>4;0m"])
        #expect(replies("\u{1b}[?1m").isEmpty)
    }

    @Test func testColorSchemeIgnoresApplicationOsc11() {
        // the subscriber changed the color itself; only host theme switches count
        #expect(replies("\u{1b}[?2031h\u{1b}]11;#ffffff\u{1b}\\").isEmpty)
    }

    @Test func testColorSchemeUpdatesEndWithReset() {
        #expect(replies("\u{1b}[?2031h\u{1b}c\u{1b}[?2031$p") == ["\u{1b}[?2031;2$y"])
    }

    // MARK: Device attributes

    @Test func testTertiaryDeviceAttributes() {
        #expect(replies("\u{1b}[=c") == ["\u{1b}P!|00000000\u{1b}\\"])
        #expect(replies("\u{1b}[=0c") == ["\u{1b}P!|00000000\u{1b}\\"])
    }

    @Test func testStartupQueriesAreEachAnsweredOnce() throws {
        // tmux 3.7's attach burst
        let sent = replies("\u{1b}[?2031h\u{1b}[?996n\u{1b}[c\u{1b}[>c\u{1b}[>q\u{1b}]10;?\u{1b}\\\u{1b}]11;?\u{1b}\\")
        try #require(sent.count == 6)
        #expect(sent[0] == "\u{1b}[?997;1n")
        #expect(sent[1].hasPrefix("\u{1b}[?65;"))
        #expect(sent[2] == "\u{1b}[>65;20;1c")
        #expect(sent[3] == "\u{1b}P>|SwiftTerm(1.13.0)\u{1b}\\")
        #expect(sent[4].hasPrefix("\u{1b}]10;rgb:"))
        #expect(sent[5].hasPrefix("\u{1b}]11;rgb:"))
    }

    // MARK: OSC reply terminator

    @Test func testOscColorRepliesUseTheQueryTerminator() throws {
        let sent = replies("\u{1b}]11;?\u{07}\u{1b}]11;?\u{1b}\\\u{1b}]4;1;?\u{07}\u{1b}]4;1;?\u{1b}\\") {
            $0.backgroundColor = Color(red: 0x1111, green: 0x2222, blue: 0x3333)
        }
        try #require(sent.count == 4)
        #expect(sent[0] == "\u{1b}]11;rgb:1111/2222/3333\u{07}")
        #expect(sent[1] == "\u{1b}]11;rgb:1111/2222/3333\u{1b}\\")
        #expect(sent[2].hasPrefix("\u{1b}]4;1;rgb:") && sent[2].hasSuffix("\u{07}"))
        #expect(sent[3].hasPrefix("\u{1b}]4;1;rgb:") && sent[3].hasSuffix("\u{1b}\\"))
    }
}
