#if os(iOS) || os(visionOS)
import UIKit
import Testing
@testable import SwiftTerm

@MainActor
struct LinkTapTests {
    private func makeView() -> (LinkTestTerminalView, LinkTestDelegate) {
        let view = LinkTestTerminalView(frame: CGRect(x: 0, y: 0, width: 800, height: 480))
        view.getTerminal().resize(cols: 80, rows: 24)
        let delegate = LinkTestDelegate()
        view.terminalDelegate = delegate
        return (view, delegate)
    }

    private func tap(_ view: TerminalView, col: Int, row: Int = 0) {
        let gesture = LinkTestTap()
        gesture.point = CGPoint(x: (CGFloat(col) + 0.5) * view.cellDimension.width,
                                y: (CGFloat(row) + 0.5) * view.cellDimension.height)
        view.addGestureRecognizer(gesture)
        view.singleTap(gesture)
        view.removeGestureRecognizer(gesture)
    }

    @Test func visibleURLTapOpensWithoutKeyboardOrHover() {
        let (view, delegate) = makeView()
        view.feed(text: "Read https://example.com/docs.")
        #expect(!view.isFirstResponder)
        #expect(view.linkHighlightRange == nil)

        tap(view, col: 12)

        #expect(delegate.links == ["https://example.com/docs"])
        #expect(!view.isFirstResponder)
    }

    @Test func osc8TapPreservesFullURLAndParameters() {
        let (view, delegate) = makeView()
        let url = "https://example.com/path;parameter?key=value;other#section"
        view.feed(text: "\u{1b}]8;id=docs;\(url)\u{1b}\\Open docs\u{1b}]8;;\u{1b}\\")

        tap(view, col: 4)

        #expect(delegate.links == [url])
        #expect(delegate.params == [["id": "docs"]])
    }

    @Test func linksTakePriorityOverMultiplexerMouseReporting() {
        let (view, delegate) = makeView()
        view.testFirstResponder = true
        view.feed(text: "\u{1b}[?1049h\u{1b}[?1000h\u{1b}[?1006hhttps://example.com/docs\u{1b}[?2026l")
        #expect(view.getTerminal().mouseMode.sendButtonPress())

        tap(view, col: 12)

        #expect(delegate.links == ["https://example.com/docs"])
        #expect(delegate.sent.isEmpty)

        tap(view, col: 40)

        #expect(delegate.links.count == 1)
        #expect(!delegate.sent.isEmpty)
    }

    @Test func wrappedURLTapOpensFromContinuationRow() {
        let (view, delegate) = makeView()
        view.getTerminal().resize(cols: 20, rows: 24)
        let url = "https://example.com/long/path/to/documentation"
        view.feed(text: url)

        tap(view, col: 3, row: 1)

        #expect(delegate.links == [url])
    }

    @Test func ordinaryTextTapStillFocusesKeyboard() {
        let (view, delegate) = makeView()
        view.feed(text: "ordinary terminal text")

        tap(view, col: 5)

        #expect(delegate.links.isEmpty)
        #expect(view.isFirstResponder)
    }

    @Test func disabledLinkReportingDoesNotActivateLinks() {
        let (view, delegate) = makeView()
        view.linkReporting = .none
        view.feed(text: "https://example.com")

        tap(view, col: 5)

        #expect(delegate.links.isEmpty)
        #expect(view.isFirstResponder)
    }

    @Test func explicitLinkReportingSkipsVisibleURLs() {
        let (view, delegate) = makeView()
        view.linkReporting = .explicit
        view.feed(text: "https://example.com\r\n\u{1b}]8;;https://example.com/docs\u{7}Docs\u{1b}]8;;\u{7}")

        tap(view, col: 5)
        #expect(delegate.links.isEmpty)
        tap(view, col: 1, row: 1)
        #expect(delegate.links == ["https://example.com/docs"])
    }

    @Test(arguments: ["tmux-default", "tmux-hyperlinks", "zellij-default", "zellij-hyperlinks"])
    func capturedMultiplexerOutputOpensVisibleLinks(_ fixture: String) throws {
        let (view, delegate) = makeView()
        let file = try #require(Bundle.module.url(forResource: fixture, withExtension: "ansi", subdirectory: "Fixtures"))
        view.feed(byteArray: Array(try Data(contentsOf: file))[...])
        // Commit the automatic alternate-screen repaint snapshot before tapping.
        view.feed(text: "\u{1b}[?2026l")
        #expect(view.getTerminal().mouseMode.sendButtonPress())
        delegate.sent.removeAll()

        var urls = ["https://example.com/plain?a=1;b=2",
                    "https://example.com/" + String(repeating: "wrapped-segment/", count: 5) + "page?query=value;more=1"]
        if fixture == "tmux-hyperlinks" {
            urls.append("https://example.com/docs;edition=2?foo=1;bar=2#section")
        } else if fixture == "zellij-hyperlinks" {
            // Zellij 0.45.1 truncates OSC 8 targets at a semicolon upstream.
            urls.append("https://example.com/docs")
        }
        for url in urls {
            let position = try #require((0..<24).lazy.compactMap { row -> Position? in
                for col in 0..<80 {
                    let position = Position(col: col, row: row)
                    if view.getTerminal().link(at: .screen(position), mode: .explicitAndImplicit) == url {
                        return position
                    }
                }
                return nil
            }.first, "Expected URL in \(fixture): \(url)")
            tap(view, col: position.col, row: position.row + view.getTerminal().displayBuffer.yDisp)
            #expect(delegate.links.last == url)
        }
        #expect(delegate.sent.isEmpty)
    }
}

private final class LinkTestTerminalView: TerminalView {
    var testFirstResponder = false
    override var isFirstResponder: Bool { testFirstResponder }
    override func becomeFirstResponder() -> Bool {
        testFirstResponder = true
        return true
    }
}

private final class LinkTestTap: UITapGestureRecognizer {
    var point = CGPoint.zero
    override var state: UIGestureRecognizer.State {
        get { .ended }
        set {}
    }
    override func location(in view: UIView?) -> CGPoint { point }
}

private final class LinkTestDelegate: TerminalViewDelegate {
    var links: [String] = []
    var params: [[String: String]] = []
    var sent: [UInt8] = []
    func requestOpenLink(source: TerminalView, link: String, params: [String: String]) {
        links.append(link)
        self.params.append(params)
    }
    func send(source: TerminalView, data: ArraySlice<UInt8>) { sent.append(contentsOf: data) }
    func sizeChanged(source: TerminalView, newCols: Int, newRows: Int) {}
    func setTerminalTitle(source: TerminalView, title: String) {}
    func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {}
    func scrolled(source: TerminalView, position: Double) {}
    func bell(source: TerminalView) {}
    func clipboardCopy(source: TerminalView, content: Data) {}
    func iTermContent(source: TerminalView, content: ArraySlice<UInt8>) {}
    func rangeChanged(source: TerminalView, startY: Int, endY: Int) {}
}
#endif
