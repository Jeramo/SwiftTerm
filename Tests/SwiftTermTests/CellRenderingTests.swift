#if os(macOS)
import AppKit
import Testing
@testable import SwiftTerm

/// Renders lines through the CoreText path (the one iOS uses too). Cells
/// that fit their columns must draw inside them and on their own: rendering
/// the line with one cell blanked must change pixels in that cell's columns
/// only, and must change some.
@MainActor
struct CellRenderingTests {
    private static let tmux35 = WidthMode.tmux(TmuxVersion(major: 3, minor: 5))
    private static let esc = "\u{1b}"

    private func makeView(_ mode: WidthMode, _ text: String, cols: Int = 16) -> TerminalView {
        let font = NSFont(name: "Menlo", size: 20)!
        let view = TerminalView(frame: CGRect(x: 0, y: 0, width: 800, height: 200), font: font)
        view.nativeBackgroundColor = .black
        view.nativeForegroundColor = .white
        view.getTerminal().widthMode = mode
        view.frame = CGRect(x: 0, y: 0, width: view.cellDimension.width * CGFloat(cols), height: view.cellDimension.height * 3)
        view.getTerminal().resize(cols: cols, rows: 3)
        view.feed(text: text)
        return view
    }

    /// The glyph runs of row 0 as drawn
    private func placed(_ mode: WidthMode, _ text: String, cols: Int) -> (view: TerminalView, runs: [PlacedRun], segments: [ViewLineSegment]) {
        let view = makeView(mode, text, cols: cols)
        let buffer = view.terminal.displayBuffer
        let info = view.buildAttributedString(row: buffer.yDisp, line: buffer.lines[buffer.yDisp], cols: buffer.cols, cellLayout: true)
        var map: [Int]? = nil
        let runs = info.segments.flatMap {
            CellLayout.place($0, lineOrigin: .zero, baseline: 0, cellSize: view.cellDimension, reorder: $0.hasRightToLeft && view.terminal.implicitBidi, columns: buffer.cols, columnMap: &map)
        }
        return (view, runs, info.segments)
    }

    private struct Rendering {
        let pixels: [UInt32]
        let width: Int
        let columnPixels: CGFloat
    }

    private func render(_ mode: WidthMode, _ text: String, cols: Int = 16) -> Rendering {
        let view = makeView(mode, text + "\(Self.esc)[?25l", cols: cols)
        view.updateDisplay(notifyAccessibility: false)
        let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds)!
        view.cacheDisplay(in: view.bounds, to: rep)
        var pixels = [UInt32](repeating: 0, count: rep.pixelsWide * rep.pixelsHigh)
        let data = rep.bitmapData!
        let samples = rep.bitsPerPixel / 8
        for y in 0..<rep.pixelsHigh {
            for x in 0..<rep.pixelsWide {
                var value: UInt32 = 0
                for k in 0..<min(samples, 4) {
                    value = value << 8 | UInt32(data[y * rep.bytesPerRow + x * samples + k])
                }
                pixels[y * rep.pixelsWide + x] = value
            }
        }
        return Rendering(pixels: pixels, width: rep.pixelsWide, columnPixels: view.cellDimension.width * CGFloat(rep.pixelsWide) / view.bounds.width)
    }

    /// Each non-blank cell of row 0: start column and width
    private func cells(_ mode: WidthMode, _ text: String) -> [(column: Int, width: Int, text: String)] {
        let (t, _) = TerminalTestHarness.makeTerminal(cols: 16, rows: 3)
        t.widthMode = mode
        t.feed(text: text)
        let line = t.getLine(row: 0)!
        return (0..<t.cols).compactMap { col in
            let cd = line[col]
            guard cd.width > 0, cd.code != 0, cd.code != 32 else {
                return nil
            }
            return (col, Int(cd.width), t.getText(for: cd))
        }
    }

    private func checkCellsDrawAlone(_ mode: WidthMode, _ text: String, together: [(column: Int, width: Int)] = []) {
        let full = render(mode, text)
        // Cells CoreText shapes as one (a conjunct across two cells) are checked as one
        let units = cells(mode, text).filter { cell in !together.contains { cell.column >= $0.column && cell.column < $0.column + $0.width } } +
            together.map { (column: $0.column, width: $0.width, text: "columns \($0.column)..<\($0.column + $0.width)") }
        for cell in units {
            let blanked = render(mode, text + "\(Self.esc)[1;\(cell.column + 1)H" + String(repeating: " ", count: cell.width))
            let low = CGFloat(cell.column) * full.columnPixels - 1
            let high = CGFloat(cell.column + cell.width) * full.columnPixels + 1
            var inside = 0
            var outside: [Int] = []
            for i in 0..<full.pixels.count where full.pixels[i] != blanked.pixels[i] {
                let x = CGFloat(i % full.width)
                if x >= low && x < high {
                    inside += 1
                } else {
                    outside.append(Int(x / full.columnPixels))
                }
            }
            #expect(inside > 0, "\(mode) \(text.debugDescription): \(cell.text.debugDescription) at column \(cell.column) draws nothing")
            #expect(outside.isEmpty, "\(mode) \(text.debugDescription): \(cell.text.debugDescription) at column \(cell.column) draws in columns \(Set(outside).sorted())")
        }
    }

    @Test func testTmuxCellsWithSeveralCharactersFitTheirColumns() {
        // tmux keeps these in one two-column cell
        checkCellsDrawAlone(Self.tmux35, "\u{1F1F8}\u{1F1EA}\u{1F1FA}\u{1F1F8} ok|")
        checkCellsDrawAlone(Self.tmux35, "\u{E9}\u{1F3FD} ok|")
        checkCellsDrawAlone(Self.tmux35, "\u{1F469}\u{200D}\u{4E2D}AB|")
        checkCellsDrawAlone(Self.tmux35, "\u{2192}\u{1F1FA}\u{1F1F8} ok|")
    }

    @Test func testPerCodePointCellsAreNotShapedTogether() {
        // CoreText would draw 👍🏽, a family or a flag as one glyph across the cells
        checkCellsDrawAlone(.wcwidth(.glibc), "x\u{1F44D}\u{1F3FD}|ok|")
        checkCellsDrawAlone(.wcwidth(.glibc), "x\u{1F468}\u{200D}\u{1F469}\u{200D}\u{1F467}|ok|")
        checkCellsDrawAlone(.wcwidth(.glibc), "x\u{1F44D}\(Self.esc)[1m\u{1F3FD}\(Self.esc)[m|ok|")
        // A lone regional indicator is wider than its column, so check the glyphs
        let flag = placed(.wcwidth(.glibc), "\u{1F1F8}\u{1F1EA}", cols: 2)
        let width = flag.view.cellDimension.width
        #expect(flag.runs.flatMap(\.positions).map(\.x) == [0, width])
    }

    @Test func testGraphemeCellsDrawAlone() {
        checkCellsDrawAlone(.unicode, "x\u{1F44D}\u{1F3FD}|ok|")
        checkCellsDrawAlone(.unicode, "a\u{1F3FD}\u{1F469}\u{200D}\u{4E2D}|")
        checkCellsDrawAlone(.unicode, "\u{E9}\u{301}\u{E9}|\u{0E2A}\u{0E27}\u{0E31}\u{0E2A}|")
        checkCellsDrawAlone(.unicode, "\u{1F468}\u{200D}\u{1F469}\u{200D}\u{1F467}|\u{1F1F8}\u{1F1EA}|")
    }

    @Test func testIndicWordsFitTheirCells() {
        // Spacing marks and conjuncts take a column, as in Ghostty, so these
        // words fit the cells they were given and nothing overlaps the next one
        checkCellsDrawAlone(.unicode, "\u{09AC}\u{09BE}\u{0982}\u{09B2}\u{09BE} \u{0995}\u{09CD}\u{09B7}|")   // বাংলা ক্ষ
        checkCellsDrawAlone(.unicode, "\u{0939}\u{093F}\u{0928}\u{094D}\u{0926}\u{0940}|")   // हिन्दी
        // ශ්‍රී ලංකා: ශ්‍ and රී are two cells CoreText draws as one conjunct
        checkCellsDrawAlone(.unicode, "\u{0DC1}\u{0DCA}\u{200D}\u{0DBB}\u{0DD3} \u{0DBD}\u{0D82}\u{0D9A}\u{0DCF}|", together: [(0, 2)])
    }

    @Test func testOnlyCellsHoldingSeveralCharactersShrink() {
        // One cluster is never shrunk, however wide its glyph; a tmux cell
        // holding two is
        #expect(placed(.unicode, "\u{1F44D}\u{1F3FD}", cols: 2).runs.allSatisfy { $0.fitted.isEmpty })
        #expect(placed(.wcwidth(.glibc), "\u{2764}\u{FE0F}x", cols: 2).runs.allSatisfy { $0.fitted.isEmpty })
        #expect(placed(.unicode, "\u{09AC}\u{09BE}\u{0982}\u{09B2}\u{09BE}", cols: 2).runs.allSatisfy { $0.fitted.isEmpty })
        #expect(placed(Self.tmux35, "\u{1F469}\u{200D}\u{4E2D}", cols: 2).runs.contains { !$0.fitted.isEmpty })
        #expect(placed(Self.tmux35, "\u{E9}\u{1F3FD}", cols: 2).runs.contains { !$0.fitted.isEmpty })
    }

    @Test func testConjunctsAreShapedAcrossCells() {
        // क्ष is two cells; CoreText draws it as one conjunct, no virama
        for mode in [WidthMode.unicode, .wcwidth(.glibc)] {
            let conjunct = placed(mode, "\u{915}\u{94D}\u{937}", cols: 2)
            #expect(!conjunct.segments.contains { ($0.attributedString.string).contains("\u{200B}") }, "\(mode)")
            let natural = CTLineCreateWithAttributedString(NSAttributedString(string: "\u{915}\u{94D}\u{937}", attributes: [.font: conjunct.view.fontSet.normal]))
            #expect(conjunct.runs.map(\.glyphs.count).reduce(0, +) == CTLineGetGlyphCount(natural), "\(mode)")
        }
    }

    // MARK: right to left

    private func pixels(_ mode: WidthMode, _ text: String) -> [UInt32] {
        render(mode, text).pixels
    }

    @Test func testHebrewIsMirroredWithinItsColumns() {
        // Drawn as an application ordering it itself (BDSM reset) would write it
        #expect(pixels(.unicode, "a\u{5D0}\u{5D1}\u{5D2}b") == pixels(.unicode, "\(Self.esc)[8la\u{5D2}\u{5D1}\u{5D0}b"))
        #expect(pixels(.unicode, "a\u{5D0}\u{5D1}\u{5D2}b") != pixels(.unicode, "a\u{5D2}\u{5D1}\u{5D0}b"))
        // A number after Hebrew is part of the right-to-left run, as bidi has it
        #expect(pixels(.unicode, "a\u{5D0}\u{5D1}2") == pixels(.unicode, "\(Self.esc)[8la2\u{5D1}\u{5D0}"))
    }

    @Test func testRightToLeftWordsInLeftToRightText() {
        // Words swap, the spaces between them follow; the line stays left to right
        #expect(pixels(.unicode, "ab \u{5D0}\u{5D1}\u{5D2} \u{5D3}\u{5D4} cd") == pixels(.unicode, "\(Self.esc)[8lab \u{5D4}\u{5D3} \u{5D2}\u{5D1}\u{5D0} cd"))
        // A line starting with Hebrew keeps its left-to-right columns
        #expect(pixels(.unicode, "\u{5D0}\u{5D1}.txt ok") == pixels(.unicode, "\(Self.esc)[8l\u{5D1}\u{5D0}.txt ok"))
    }

    @Test func testArabicIsJoinedAndMirrored() {
        let word = "\u{633}\u{644}\u{627}\u{645}"  // سلام
        let isolated = "\u{633}\u{200C}\u{644}\u{200C}\u{627}\u{200C}\u{645}"
        // The letters join...
        #expect(pixels(.unicode, word) != pixels(.unicode, isolated))
        // ...and run right to left
        #expect(pixels(.unicode, isolated) == pixels(.unicode, "\(Self.esc)[8l\u{645}\u{200C}\u{627}\u{200C}\u{644}\u{200C}\u{633}"))
    }

    @Test func testCursorFollowsMirroredText() {
        let view = makeView(.unicode, "a\u{5D0}\u{5D1}\u{5D2}b\(Self.esc)[1;2H")
        view.updateDisplay(notifyAccessibility: false)
        // א is the first Hebrew letter, drawn rightmost of the three
        #expect(view.caretView!.frame.origin.x == view.cellDimension.width * 3)
    }

    // MARK: cursor and Powerline

    @Test func testBlockCursorCoversAWideCharacter() {
        let view = makeView(.unicode, "\u{4E2D}a\(Self.esc)[1;1H")
        view.updateDisplay(notifyAccessibility: false)
        #expect(view.caretView!.frame.width == view.cellDimension.width * 2)
        view.feed(text: "\(Self.esc)[1;3H")
        view.updateDisplay(notifyAccessibility: false)
        #expect(view.caretView!.frame.width == view.cellDimension.width)
    }

    @Test func testPowerlineExtraGlyphsStretchToTheCell() {
        let cell = CGSize(width: 8, height: 16)
        let ink = CGRect(x: 1, y: -2, width: 10, height: 10)
        // A flame covers both columns it may take, top to bottom
        #expect(PowerlineRenderer.stretchedRect(PowerlineRenderer.stretchRule(0xE0C0)!, ink: ink, columns: 2, cellSize: cell) == CGRect(x: 0, y: 0, width: 16, height: 16))
        // A trapezoid stays in its cell, against its right edge
        #expect(PowerlineRenderer.stretchedRect(PowerlineRenderer.stretchRule(0xE0D4)!, ink: ink, columns: 2, cellSize: cell) == CGRect(x: 0, y: 0, width: 8, height: 16))
        // Pixels keep their shape: no wider than 0.86 of the height
        let pixels = PowerlineRenderer.stretchedRect(PowerlineRenderer.stretchRule(0xE0C4)!, ink: ink, columns: 2, cellSize: cell)
        #expect(abs(pixels.width - pixels.height * 0.86) < 0.001)
        #expect(PowerlineRenderer.stretchRule(0xE0B0) == nil)
    }

    @Test func testPowerlineExtraGlyphTakesTheNextBlankCell() {
        func columns(_ text: String) -> Int {
            let (t, _) = TerminalTestHarness.makeTerminal(cols: 8, rows: 1)
            t.feed(text: text)
            return PowerlineRenderer.columns(in: t.getLine(row: 0)!, at: 1, cols: t.cols)
        }
        #expect(columns("a\u{E0C0} b") == 2)
        #expect(columns("a\u{E0C0}\u{E0B0}") == 2)
        #expect(columns("a\u{E0C0}b") == 1)
        // After another icon it keeps to one cell, so icons stay aligned
        #expect(columns("\u{F07C}\u{E0C0} b") == 1)
        #expect(columns("\u{E0B0}\u{E0C0} b") == 2)
    }

    @Test func testInverseVideoSwapsTheDefaultColors() {
        let view = makeView(.unicode, "")
        let attributes = view.getAttributes(Attribute(fg: .defaultColor, bg: .defaultColor, style: .inverse), withUrl: false)!
        #expect(attributes[.backgroundColor] as? NSColor == view.nativeForegroundColor)
        #expect(attributes[.foregroundColor] as? NSColor == view.nativeBackgroundColor)
    }

    @Test func testSelectionHandlesFollowMirroredText() {
        let view = makeView(.unicode, "a\u{5D0}\u{5D1}\u{5D2}b")
        let row = view.terminal.displayBuffer.yDisp
        // Selecting אבג (columns 1..<4): it is drawn גבא, so its start is the
        // right edge of א (drawn in column 3) and its end the left edge of ג
        #expect(view.selectionHandleColumn(row: row, column: 1, start: true) == 4)
        #expect(view.selectionHandleColumn(row: row, column: 4, start: false) == 1)
        // Left-to-right text keeps its handles where they were
        #expect(view.selectionHandleColumn(row: row, column: 0, start: true) == 0)
        #expect(view.selectionHandleColumn(row: row, column: 5, start: false) == 5)
    }

    @Test func testPowerlineSeparatorFillsTheCellHeight() {
        let view = makeView(.unicode, "\u{E0B0}\(Self.esc)[?25l")
        view.updateDisplay(notifyAccessibility: false)
        let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds)!
        view.cacheDisplay(in: view.bounds, to: rep)
        let scale = CGFloat(rep.pixelsWide) / view.bounds.width
        let height = Int(view.cellDimension.height * scale)
        func ink(_ x: Int, _ y: Int) -> Bool {
            (rep.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB)?.brightnessComponent ?? 0) > 0.5
        }
        // The triangle's left edge runs from the top of the cell to the bottom
        #expect(ink(1, 1))
        #expect(ink(1, height - 2))
        #expect(ink(Int(view.cellDimension.width * scale) - 2, height / 2))
    }
}
#endif
