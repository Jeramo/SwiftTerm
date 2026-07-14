import Foundation
import Testing

@testable import SwiftTerm

@Suite(.serialized)
struct FocusReportTests {
    @Test func enablingFocusReportingSendsCurrentStateImmediately() {
        let (terminal, delegate) = TerminalTestHarness.makeTerminal()

        terminal.feed(text: "\u{1b}[?1004h")
        #expect(sentString(delegate) == "\u{1b}[I")

        delegate.clearSentData()
        terminal.setTerminalFocus(false)
        #expect(sentString(delegate) == "\u{1b}[O")

        delegate.clearSentData()
        terminal.setTerminalFocus(true)
        #expect(sentString(delegate) == "\u{1b}[I")
    }

    @Test func enablingWhileUnfocusedSendsFocusOutImmediately() {
        let (terminal, delegate) = TerminalTestHarness.makeTerminal()
        terminal.setTerminalFocus(false)
        delegate.clearSentData()

        terminal.feed(text: "\u{1b}[?1004h")

        #expect(sentString(delegate) == "\u{1b}[O")
    }

    @Test func focusChangesStaySilentWhenReportingIsDisabled() {
        let (terminal, delegate) = TerminalTestHarness.makeTerminal()
        terminal.setTerminalFocus(false)
        terminal.setTerminalFocus(true)
        #expect(delegate.sentData.isEmpty)

        terminal.feed(text: "\u{1b}[?1004h")
        delegate.clearSentData()
        terminal.feed(text: "\u{1b}[?1004l")
        terminal.setTerminalFocus(false)

        #expect(delegate.sentData.isEmpty)
    }

    private func sentString(_ delegate: TerminalTestDelegate) -> String {
        String(decoding: delegate.sentData.flatMap { $0 }, as: UTF8.self)
    }
}
