#if os(macOS) || os(iOS)
#if os(macOS)
import AppKit
#else
import UIKit
#endif
import Testing
@testable import SwiftTerm

#if os(iOS)
private final class DisplayInvalidationCountingTerminalView: TerminalView {
    var displayInvalidationCount = 0

    override func setNeedsDisplay(_ rect: CGRect) {
        displayInvalidationCount += 1
        super.setNeedsDisplay(rect)
    }
}
#endif

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

        try await Task.sleep(nanoseconds: 40_000_000)

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

        try await Task.sleep(nanoseconds: 40_000_000)

        #expect(!view.pendingDisplay)
        #expect(view.terminal.getUpdateRange() == nil)
    }

#if os(iOS)
    @Test func terminalSurfaceStaysOpaque() {
        let view = makeView()
        #expect(view.isOpaque)
    }

    @Test func scrollingUsesContentOffsetAsTheSingleCGInvalidationPath() {
        let view = DisplayInvalidationCountingTerminalView(
            frame: CGRect(x: 0, y: 0, width: 800, height: 480)
        )
        view.contentSize = CGSize(width: 800, height: 960)
        view.layoutSubviews()
        view.displayInvalidationCount = 0

        view.contentOffset = CGPoint(x: 0, y: 1)
        #expect(view.displayInvalidationCount == 1)

        // UIScrollView lays out again when its bounds origin changes. The CG
        // renderer must not enqueue the same full redraw a second time here;
        // contentOffset.didSet above owns scroll invalidation.
        view.layoutSubviews()
        #expect(view.displayInvalidationCount == 1)
    }
#endif
}
#endif
