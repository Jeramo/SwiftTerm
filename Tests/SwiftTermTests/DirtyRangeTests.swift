import Testing
@testable import SwiftTerm

final class DirtyRangeTests {
    private let esc = "\u{1b}"

    @Test func testDECCRAMarksDestinationRowsDirty() {
        let (terminal, _) = TerminalTestHarness.makeTerminal(cols: 8, rows: 5)
        terminal.feed(text: "ABCDEFGH\r\n12345678\r\nabcdefgh\r\n87654321")
        terminal.clearUpdateRange()

        terminal.feed(text: "\(esc)[1;1;2;3;1;3;2;1$v")

        TerminalTestHarness.assertLineText(terminal.buffer, row: 2, equals: "aABCefgh")
        TerminalTestHarness.assertLineText(terminal.buffer, row: 3, equals: "81234321")
        assertDirtyRange(terminal, start: 2, end: 3)
    }

    @Test func testDECFRAMarksFilledRowsDirty() {
        let (terminal, _) = TerminalTestHarness.makeTerminal(cols: 8, rows: 5)
        terminal.feed(text: "ABCDEFGH\r\n12345678\r\nabcdefgh")
        terminal.clearUpdateRange()

        terminal.feed(text: "\(esc)[90;2;2;3;4$x")

        TerminalTestHarness.assertLineText(terminal.buffer, row: 1, equals: "1ZZZ5678")
        TerminalTestHarness.assertLineText(terminal.buffer, row: 2, equals: "aZZZefgh")
        assertDirtyRange(terminal, start: 1, end: 2)
    }

    @Test func testDECERAMarksErasedRowsDirty() {
        let (terminal, _) = TerminalTestHarness.makeTerminal(cols: 8, rows: 5)
        terminal.feed(text: "ABCDEFGH\r\n12345678\r\nabcdefgh")
        terminal.clearUpdateRange()

        terminal.feed(text: "\(esc)[2;2;3;4$z")

        TerminalTestHarness.assertLineText(terminal.buffer, row: 1, equals: "1   5678")
        TerminalTestHarness.assertLineText(terminal.buffer, row: 2, equals: "a   efgh")
        assertDirtyRange(terminal, start: 1, end: 2)
    }

    @Test func testDECSERAMarksErasedRowsDirty() {
        let (terminal, _) = TerminalTestHarness.makeTerminal(cols: 8, rows: 5)
        terminal.feed(text: "ABCDEFGH\r\n12345678\r\nabcdefgh")
        terminal.clearUpdateRange()

        terminal.feed(text: "\(esc)[2;2;3;4${")

        TerminalTestHarness.assertLineText(terminal.buffer, row: 1, equals: "1   5678")
        TerminalTestHarness.assertLineText(terminal.buffer, row: 2, equals: "a   efgh")
        assertDirtyRange(terminal, start: 1, end: 2)
    }

    private func assertDirtyRange(_ terminal: Terminal, start: Int, end: Int) {
        let range = terminal.getUpdateRange()
        #expect(range?.startY == start)
        #expect(range?.endY == end)
    }
}
