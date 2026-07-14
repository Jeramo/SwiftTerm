#if os(macOS)
import AppKit
import Testing
@testable import SwiftTerm

@MainActor
struct CursorRenderingTests {
    private func makeView() -> TerminalView {
        let view = TerminalView(
            frame: CGRect(x: 0, y: 0, width: 800, height: 480)
        )
        view.updateDisplay(notifyAccessibility: false)
        return view
    }

    @Test func cursorVisibilityWaitsForDisplayCommit() throws {
        let view = makeView()
        let caret = try #require(view.caretView)

        #expect(caret.superview === view)

        view.terminal.hideCursor()
        #expect(caret.superview === view)

        view.updateDisplay(notifyAccessibility: false)
        #expect(caret.superview == nil)

        view.terminal.showCursor()
        #expect(caret.superview == nil)

        view.updateDisplay(notifyAccessibility: false)
        #expect(caret.superview === view)
    }

    @Test func synchronizedRedrawNeverPresentsIntermediateCursor() throws {
        let view = makeView()
        let caret = try #require(view.caretView)
        let originalFrame = caret.frame
        let esc = "\u{1b}"

        view.feed(text: "\(esc)[?2026h\(esc)[?25l\(esc)[12;30Hworking")

        #expect(view.terminal.synchronizedOutputActive)
        view.updateDisplay(notifyAccessibility: false)
        #expect(caret.superview === view)
        #expect(caret.frame == originalFrame)

        view.feed(text: "\(esc)[?25h\(esc)[?2026l")

        #expect(!view.terminal.synchronizedOutputActive)
        #expect(caret.superview === view)
        #expect(caret.frame == originalFrame)

        view.updateDisplay(notifyAccessibility: false)
        #expect(caret.superview === view)
        #expect(caret.frame != originalFrame)
    }

    @Test func tuiShowThenCursorDiffNeverRevealsStaleCaret() throws {
        let view = makeView()
        let caret = try #require(view.caretView)
        let esc = "\u{1b}"

        view.terminal.hideCursor()
        view.updateDisplay(notifyAccessibility: false)
        #expect(caret.superview == nil)
        let hiddenFrame = caret.frame

        view.feed(text: "\(esc)[?25h\(esc)[5;5Hone\(esc)[15;30Htwo\(esc)[2;2H")

        #expect(caret.superview == nil)
        #expect(caret.frame == hiddenFrame)

        view.updateDisplay(notifyAccessibility: false)
        #expect(caret.superview === view)
        #expect(caret.frame != hiddenFrame)
    }
}
#endif
