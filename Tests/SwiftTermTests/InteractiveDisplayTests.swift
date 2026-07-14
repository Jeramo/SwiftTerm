#if os(macOS) || os(iOS)
#if os(macOS)
import AppKit
#else
import UIKit
#endif
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

    @Test func streamedOutputUsesOneCoalescedFrame() async throws {
        let view = makeView()

        view.feed(text: "one")
        view.feed(text: "two")

        #expect(view.pendingDisplay)
        #expect(view.terminal.getUpdateRange() != nil)

        try await Task.sleep(for: .milliseconds(40))

        #expect(!view.pendingDisplay)
        #expect(view.terminal.getUpdateRange() == nil)
    }

    @Test func synchronizedOutputStillCommitsAtomically() async throws {
        let view = makeView()
        let escape = "\u{1b}"

        view.feed(text: "\(escape)[?2026ha")
        #expect(view.terminal.synchronizedOutputActive)
        #expect(view.terminal.getUpdateRange() != nil)

        view.feed(text: "\(escape)[?2026l")
        #expect(!view.terminal.synchronizedOutputActive)
        #expect(view.pendingDisplay)
        #expect(view.terminal.getUpdateRange() != nil)

        try await Task.sleep(for: .milliseconds(40))

        #expect(!view.pendingDisplay)
        #expect(view.terminal.getUpdateRange() == nil)
    }

#if os(iOS)
    @Test func terminalSurfaceStaysOpaque() {
        let view = makeView()
        #expect(view.isOpaque)
    }
#endif
}
#endif
