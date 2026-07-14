#if os(macOS) || os(iOS)
#if os(macOS)
import AppKit
#else
import UIKit
#endif
import Dispatch
import Testing
@testable import SwiftTerm

@MainActor
struct InteractiveDisplayTests {
    private func makeView() -> TerminalView {
        let view = TerminalView(
            frame: CGRect(x: 0, y: 0, width: 800, height: 480)
        )
        view.updateDisplay(notifyAccessibility: false)
        return view
    }

    @Test func recentInputEchoCommitsWithoutFrameDelay() {
        let view = makeView()

        view.send(data: [0x61][...])
        view.feed(text: "a")

        #expect(view.lastUserInputUptimeNs > 0)
        #expect(!view.pendingDisplay)
        #expect(view.terminal.getUpdateRange() == nil)
    }

    @Test func oneInputOnlyBypassesCoalescingOnce() {
        let view = makeView()

        view.send(data: [0x61][...])
        view.feed(text: "a")
        #expect(!view.pendingDisplay)

        view.feed(text: "command output")

        #expect(view.pendingDisplay)
        #expect(view.terminal.getUpdateRange() != nil)
        view.updateDisplay(notifyAccessibility: false)
    }

    @Test func unrelatedOutputStillUsesFrameCoalescing() {
        let view = makeView()
        let now = DispatchTime.now().uptimeNanoseconds
        view.lastUserInputUptimeNs = now - view.interactiveInputDisplayWindowNs - 1

        view.feed(text: "background output")

        #expect(view.pendingDisplay)
        #expect(view.terminal.getUpdateRange() != nil)
        view.updateDisplay(notifyAccessibility: false)
    }

    @Test func synchronizedEchoCommitsOnlyAfterEndMarker() {
        let view = makeView()
        let escape = "\u{1b}"

        view.send(data: [0x61][...])
        view.feed(text: "\(escape)[?2026ha")

        #expect(view.terminal.synchronizedOutputActive)
        #expect(view.terminal.getUpdateRange() != nil)

        view.feed(text: "\(escape)[?2026l")

        #expect(!view.terminal.synchronizedOutputActive)
        #expect(!view.pendingDisplay)
        #expect(view.terminal.getUpdateRange() == nil)
    }

#if os(iOS)
    @Test func pendingFrameAlwaysRewakesDisplayLink() {
        let view = makeView()
        view.pendingDisplay = true
        view.link.isPaused = true

        view.queuePendingDisplay()

        #expect(!view.link.isPaused)
        view.updateDisplay(notifyAccessibility: false)
    }
#endif
}
#endif
