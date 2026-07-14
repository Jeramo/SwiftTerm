import Testing

@testable import SwiftTerm

@Suite(.serialized)
struct MouseTrackingTests {
    private let esc = "\u{1b}"

    @Test func resettingCoordinateEncodingKeepsTrackingEnabled() {
        for encodingMode in [1005, 1006, 1015, 1016] {
            let (terminal, _) = TerminalTestHarness.makeTerminal()
            terminal.feed(text: "\(esc)[?1003h")
            terminal.feed(text: "\(esc)[?\(encodingMode)h")
            terminal.feed(text: "\(esc)[?\(encodingMode)l")

            #expect(terminal.mouseMode == .anyEvent)
        }
    }

    @Test func resettingCoordinateEncodingStillReturnsToX10Encoding() {
        let (terminal, delegate) = TerminalTestHarness.makeTerminal()
        terminal.feed(text: "\(esc)[?1000h\(esc)[?1006h\(esc)[?1006l")
        delegate.clearSentData()

        let flags = terminal.encodeButton(
            button: 4,
            release: false,
            shift: false,
            meta: false,
            control: false
        )
        terminal.sendEvent(buttonFlags: flags, x: 10, y: 5, pixelX: 10, pixelY: 5)

        #expect(delegate.sentData.flatMap { $0 } == [0x1b, 0x5b, 0x4d, 96, 43, 38])
    }

    @Test func moshStyleModeReassertKeepsSgrMouseTracking() {
        let (terminal, delegate) = TerminalTestHarness.makeTerminal()
        terminal.feed(text: "\(esc)[?1003h\(esc)[?1006h")
        terminal.feed(text: "\(esc)[?1003l\(esc)[?1003h\(esc)[?1004l\(esc)[?1006l\(esc)[?1006h")
        #expect(terminal.mouseMode == .anyEvent)
        delegate.clearSentData()

        let flags = terminal.encodeButton(
            button: 4,
            release: false,
            shift: false,
            meta: false,
            control: false
        )
        terminal.sendEvent(buttonFlags: flags, x: 10, y: 5, pixelX: 10, pixelY: 5)

        let sent = String(decoding: delegate.sentData.flatMap { $0 }, as: UTF8.self)
        #expect(sent == "\(esc)[<64;11;6M")
    }

    @Test func resettingTrackingModeStillDisablesTracking() {
        let (terminal, _) = TerminalTestHarness.makeTerminal()
        terminal.feed(text: "\(esc)[?1003h\(esc)[?1006h\(esc)[?1003l")

        #expect(terminal.mouseMode == .off)
    }
}
