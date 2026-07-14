import Testing

@testable import SwiftTerm

@Suite(.serialized)
struct AlternateScrollModeTests {
    private let esc = "\u{1b}"

    @Test func decsetAndDecrstTrackAlternateScrollMode() {
        let (terminal, _) = TerminalTestHarness.makeTerminal()

        #expect(!terminal.alternateScrollMode)
        terminal.feed(text: "\(esc)[?1007h")
        #expect(terminal.alternateScrollMode)
        terminal.feed(text: "\(esc)[?1007l")
        #expect(!terminal.alternateScrollMode)
    }

    @Test func decrqmReportsAlternateScrollMode() {
        let (terminal, delegate) = TerminalTestHarness.makeTerminal()

        terminal.feed(text: "\(esc)[?1007$p")
        #expect(sentString(delegate) == "\(esc)[?1007;2$y")

        terminal.feed(text: "\(esc)[?1007h")
        delegate.clearSentData()
        terminal.feed(text: "\(esc)[?1007$p")
        #expect(sentString(delegate) == "\(esc)[?1007;1$y")
    }

    @Test func fullResetDisablesAlternateScrollMode() {
        let (terminal, _) = TerminalTestHarness.makeTerminal()
        terminal.feed(text: "\(esc)[?1007h")

        terminal.resetToInitialState()

        #expect(!terminal.alternateScrollMode)
    }

    private func sentString(_ delegate: TerminalTestDelegate) -> String {
        String(decoding: delegate.sentData.flatMap { $0 }, as: UTF8.self)
    }
}
