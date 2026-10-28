//
//  CellLayout.swift
//
//  Places CoreText's glyphs in the terminal's cells. CoreText lays a line
//  out with its own advances; the terminal decided where every character
//  goes, so each glyph is moved to the cell its text belongs to, keeping the
//  offset CoreText gave it within that cell.
//
#if os(macOS) || os(iOS) || os(visionOS)
import CoreGraphics
import CoreText
import Foundation

/// A glyph run of a segment with every glyph placed in its cell
struct PlacedRun {
    let font: TTFont
    /// The run's attributes as CoreText keeps them; bridged to Swift only to draw decorations
    let attributes: NSDictionary
    let foregroundColor: TTColor?
    var glyphs: [CGGlyph] = []
    var positions: [CGPoint] = []
    /// Glyphs of a cell holding more characters than fit its columns (tmux
    /// joins what follows a ZWJ): drawn at `position` scaled by `scale` about
    /// `origin`, the cell's left edge on the middle of the line
    var fitted: [(glyph: CGGlyph, position: CGPoint, origin: CGPoint, scale: CGFloat)] = []
    /// The left edge of every column the run's cells cover, for underline and strike-through
    var decorations: [CGPoint] = []

    static let underlineKey = NSAttributedString.Key.underlineStyle.rawValue as NSString
    static let strikethroughKey = NSAttributedString.Key.strikethroughStyle.rawValue as NSString
    static let foregroundKey = NSAttributedString.Key.foregroundColor.rawValue as NSString
    static let fontKey = NSAttributedString.Key.font.rawValue as NSString

    init (_ run: CTRun)
    {
        attributes = CTRunGetAttributes (run) as NSDictionary
        font = attributes [PlacedRun.fontKey] as! TTFont
        foregroundColor = attributes [PlacedRun.foregroundKey] as? TTColor
    }

    /// Underlined or struck through
    var decorated: Bool {
        attributes [PlacedRun.underlineKey] != nil || attributes [PlacedRun.strikethroughKey] != nil
    }
}

enum CellLayout {
    /// Characters of right-to-left scripts and the controls that start right-to-left text
    static func isRightToLeft (_ value: UInt32) -> Bool
    {
        switch value {
        case 0x0590...0x08FF, 0xFB1D...0xFDFF, 0xFE70...0xFEFF, 0x10800...0x10FFF, 0x1E800...0x1EFFF:
            return true
        case 0x200F, 0x202B, 0x202E, 0x2067:
            return true
        default:
            return false
        }
    }

    /// Whether CoreText would draw the end of one cell and the start of the
    /// next as one emoji: a skin tone, and where the terminal measures per
    /// code point, a second regional indicator or an emoji after a ZWJ (with
    /// grapheme widths those never end up in two cells)
    static func emojiJoins (_ last: Unicode.Scalar, _ first: Unicode.Scalar, perCodePoint: Bool) -> Bool
    {
        if first.value >= 0x1F3FB && first.value <= 0x1F3FF {
            return true
        }
        guard perCodePoint else {
            return false
        }
        if UnicodeUtil.isRegionalIndicator (last) && UnicodeUtil.isRegionalIndicator (first) {
            return true
        }
        return last.value == 0x200D && first.properties.isEmoji
    }

    /// Whether `text` holds a skin tone that does not follow an emoji it
    /// modifies (tmux joins é🏽 into one cell): one grapheme cluster that
    /// still draws as two glyphs
    static func hasStrayModifier (_ text: String) -> Bool
    {
        var previous: Unicode.Scalar? = nil
        for scalar in text.unicodeScalars {
            if scalar.value >= 0x1F3FB && scalar.value <= 0x1F3FF && !(previous?.properties.isEmojiModifierBase ?? false) {
                return true
            }
            previous = scalar
        }
        return false
    }

    /// Paragraph style that keeps a line left to right: right-to-left text is
    /// laid out in place instead of the whole line being reordered
    static let leftToRight: CTParagraphStyle = {
        var direction = CTWritingDirection.leftToRight
        return withUnsafeBytes (of: &direction) { bytes in
            var setting = CTParagraphStyleSetting (spec: .baseWritingDirection, valueSize: MemoryLayout<CTWritingDirection>.size, value: bytes.baseAddress!)
            return CTParagraphStyleCreate (&setting, 1)
        }
    }()

    /// The last cell starting at or before UTF-16 offset `index`, searching from `hint`
    private static func cell (at index: Int, in cells: [ViewLineCell], from hint: Int) -> Int
    {
        var cell = hint
        if cell >= cells.count || cells [cell].start > index {
            var low = 0, high = cells.count - 1
            cell = 0
            while low <= high {
                let middle = (low + high) / 2
                if cells [middle].start <= index {
                    cell = middle
                    low = middle + 1
                } else {
                    high = middle - 1
                }
            }
        }
        while cell + 1 < cells.count && cells [cell + 1].start <= index {
            cell += 1
        }
        return cell
    }

    /// The common case: one glyph per cell, each at its cell's column. Nil
    /// when a run has more or fewer glyphs than characters.
    private static func placePlain (_ segment: ViewLineSegment, runs: [CTRun], lineOrigin: CGPoint, baseline: CGFloat, cellWidth: CGFloat) -> [PlacedRun]?
    {
        let cells = segment.cells
        var placed: [PlacedRun] = []
        placed.reserveCapacity (runs.count)
        for run in runs {
            let count = CTRunGetGlyphCount (run)
            let range = CTRunGetStringRange (run)
            guard range.length == count, range.location + count <= cells.count else {
                return nil
            }
            if count == 0 {
                continue
            }
            var result = PlacedRun (run)
            result.glyphs = [CGGlyph] (repeating: 0, count: count)
            result.positions = [CGPoint] (repeating: .zero, count: count)
            CTRunGetGlyphs (run, CFRange (), &result.glyphs)
            CTRunGetPositions (run, CFRange (), &result.positions)
            let decorated = result.decorated
            for i in 0..<count {
                let cell = cells [range.location + i]
                let left = lineOrigin.x + CGFloat (cell.column) * cellWidth
                result.positions [i] = CGPoint (x: left, y: baseline + result.positions [i].y)
                if decorated {
                    for k in 0..<cell.width {
                        result.decorations.append (CGPoint (x: left + CGFloat (k) * cellWidth, y: baseline))
                    }
                }
            }
            placed.append (result)
        }
        return placed
    }

    /// Places a segment's glyphs in its cells.
    ///
    /// Each cell's glyphs go to its column at the offsets CoreText gave them.
    /// Cells CoreText shaped together form a unit placed from its first
    /// column: a glyph drawn out of its cells' order (हि split over two cells)
    /// ties the cells in between, and a cell whose first character has no
    /// glyph of its own (a conjunct or lam-alef drawn by the cell before)
    /// joins the one before. With `reorder`, right-to-left runs are mirrored
    /// within their own columns, and `columnMap` (logical column to drawn
    /// column, created on demand) records where their cells went.
    static func place (_ segment: ViewLineSegment, lineOrigin: CGPoint, baseline: CGFloat, cellSize: CGSize, reorder: Bool, columns: Int, columnMap: inout [Int]?) -> [PlacedRun]
    {
        let cells = segment.cells
        let n = cells.count
        guard n > 0, let runs = CTLineGetGlyphRuns (CTLineCreateWithAttributedString (segment.attributedString)) as? [CTRun] else {
            return []
        }
        let cellWidth = cellSize.width
        if segment.plain && !segment.hasRightToLeft, let placed = placePlain (segment, runs: runs, lineOrigin: lineOrigin, baseline: baseline, cellWidth: cellWidth) {
            return placed
        }

        // Which cell each glyph belongs to, and where each cell's glyphs start
        struct CellState {
            var origin = CGFloat.infinity
            /// Drawn with the cell after it
            var joined = false
            /// The cell's first character has a glyph of its own
            var hasBase: Bool
            var rightToLeft = false
            var head = 0
            var unitOrigin = CGFloat.infinity
            var unitWidth = 0
        }
        var state = [CellState] (repeating: CellState (hasBase: segment.plain), count: n)
        var anyRightToLeft = false
        var owners: [Int] = []
        owners.reserveCapacity (runs.reduce (0) { $0 + CTRunGetGlyphCount ($1) })
        for run in runs {
            let count = CTRunGetGlyphCount (run)
            if count == 0 {
                continue
            }
            let isRightToLeft = CTRunGetStatus (run).contains (.rightToLeft)
            anyRightToLeft = anyRightToLeft || isRightToLeft
            let first = owners.count
            withIndices (run, count) { indices in
                var hint = 0
                var reach = -1
                for i in 0..<count {
                    let index = indices [i]
                    let c = cell (at: index, in: cells, from: hint)
                    hint = c
                    // Text between cells breaks shaping and draws nothing
                    guard cells [c].start <= index && index < cells [c].end else {
                        owners.append (-1)
                        continue
                    }
                    owners.append (c)
                    if index == cells [c].start {
                        state [c].hasBase = true
                    }
                    if reach >= 0 && (isRightToLeft ? c > reach : c < reach) {
                        for k in min (c, reach)..<max (c, reach) {
                            state [k].joined = true
                        }
                    } else {
                        reach = c
                    }
                }
            }
            withPositions (run, count) { positions in
                for i in 0..<count where owners [first + i] >= 0 {
                    let c = owners [first + i]
                    state [c].origin = min (state [c].origin, positions [i].x)
                    state [c].rightToLeft = state [c].rightToLeft || isRightToLeft
                }
            }
        }

        // Units: a cell and the cells drawn with it
        for c in 0..<n {
            if c > 0 && (state [c - 1].joined || !state [c].hasBase) {
                let h = state [c - 1].head
                state [c].head = h
                state [h].unitOrigin = min (state [h].unitOrigin, state [c].origin)
            } else {
                state [c].head = c
                state [c].unitOrigin = state [c].origin
            }
            state [state [c].head].unitWidth += cells [c].width
        }

        // Right-to-left runs: units in CoreText's visual order, packed into the same columns
        var visualStart: [Int]? = nil
        if reorder && anyRightToLeft {
            var heads: [Int] = []
            var key: [CGFloat] = []
            var previous: CGFloat = -.infinity
            for c in 0..<n where state [c].head == c {
                previous = state [c].unitOrigin == .infinity ? previous : state [c].unitOrigin
                heads.append (c)
                key.append (previous)
            }
            // Only the stretch around the right-to-left units is out of order
            if let first = heads.firstIndex (where: { state [$0].rightToLeft }), let last = heads.lastIndex (where: { state [$0].rightToLeft }) {
                var low = first, high = last
                var lowest = key [first...last].min ()!, highest = key [first...last].max ()!
                while high + 1 < heads.count && key [high + 1] < highest {
                    high += 1
                    lowest = min (lowest, key [high])
                }
                while low > 0 && key [low - 1] > lowest {
                    low -= 1
                    highest = max (highest, key [low])
                }
                let order = (low...high).sorted { a, b in
                    if key [a] != key [b] {
                        return key [a] < key [b]
                    }
                    // Glyphs at the same place: right to left ones go in reverse
                    return state [heads [a]].rightToLeft && state [heads [b]].rightToLeft ? a > b : a < b
                }
                var start = cells.map (\.column)
                var column = cells [heads [low]].column
                for i in order {
                    start [heads [i]] = column
                    column += state [heads [i]].unitWidth
                }
                var map = columnMap ?? Array (0..<columns)
                var offset = 0
                for c in 0..<n {
                    offset = state [c].head == c ? 0 : offset
                    for k in 0..<cells [c].width where cells [c].column + k < columns {
                        map [cells [c].column + k] = start [state [c].head] + offset + k
                    }
                    offset += cells [c].width
                }
                columnMap = map
                visualStart = start
            }
        }

        // Cells holding several characters that do not fit are shrunk to their ink
        var scale: [CGFloat]? = nil
        var inkStart: [CGFloat] = []
        if segment.hasSeveral {
            inkStart = [CGFloat] (repeating: .infinity, count: n)
            var inkEnd = [CGFloat] (repeating: -.infinity, count: n)
            var first = 0
            for run in runs {
                let count = CTRunGetGlyphCount (run)
                let font = (CTRunGetAttributes (run) as NSDictionary) [kCTFontAttributeName as String] as! CTFont
                var glyphs = [CGGlyph] (repeating: 0, count: count)
                CTRunGetGlyphs (run, CFRange (), &glyphs)
                withPositions (run, count) { positions in
                    for i in 0..<count where owners [first + i] >= 0 && cells [owners [first + i]].several {
                        let h = state [owners [first + i]].head
                        var bounds = CGRect.zero
                        CTFontGetBoundingRectsForGlyphs (font, .horizontal, &glyphs [i], &bounds, 1)
                        if bounds.isEmpty {
                            continue
                        }
                        inkStart [h] = min (inkStart [h], positions [i].x + bounds.minX)
                        inkEnd [h] = max (inkEnd [h], positions [i].x + bounds.maxX)
                    }
                }
                first += count
            }
            var factors = [CGFloat] (repeating: 1, count: n)
            for h in 0..<n where inkStart [h] < inkEnd [h] {
                let room = CGFloat (state [h].unitWidth) * cellWidth
                let ink = inkEnd [h] - inkStart [h]
                if ink > room + 0.5 {
                    factors [h] = room / ink
                }
            }
            scale = factors
        }

        let middle = lineOrigin.y + cellSize.height / 2
        var placed: [PlacedRun] = []
        placed.reserveCapacity (runs.count)
        var first = 0
        for ctRun in runs {
            let count = CTRunGetGlyphCount (ctRun)
            if count == 0 {
                continue
            }
            var run = PlacedRun (ctRun)
            var glyphs = [CGGlyph] (repeating: 0, count: count)
            CTRunGetGlyphs (ctRun, CFRange (), &glyphs)
            // Usually every glyph is drawn as it is and keeps its place in the arrays
            let inPlace = scale == nil && !owners [first..<first + count].contains (-1)
            if inPlace {
                run.positions = [CGPoint] (repeating: .zero, count: count)
            }
            let decorated = run.decorated
            var lastHead = -1
            withPositions (ctRun, count) { positions in
                for i in 0..<count where owners [first + i] >= 0 {
                    let h = state [owners [first + i]].head
                    let left = lineOrigin.x + CGFloat (visualStart? [h] ?? cells [h].column) * cellWidth
                    let position = CGPoint (x: left + positions [i].x - state [h].unitOrigin, y: baseline + positions [i].y)
                    if inPlace {
                        run.positions [i] = position
                    } else if let factor = scale? [h], factor < 1 {
                        run.fitted.append ((glyphs [i], CGPoint (x: positions [i].x - inkStart [h], y: baseline + positions [i].y), CGPoint (x: left, y: middle), factor))
                    } else {
                        run.glyphs.append (glyphs [i])
                        run.positions.append (position)
                    }
                    if decorated && h != lastHead {
                        lastHead = h
                        for k in 0..<state [h].unitWidth {
                            run.decorations.append (CGPoint (x: left + CGFloat (k) * cellWidth, y: baseline))
                        }
                    }
                }
            }
            if inPlace {
                run.glyphs = glyphs
            }
            placed.append (run)
            first += count
        }
        return placed
    }

    /// The run's string indices, without copying them when CoreText can lend them
    private static func withIndices (_ run: CTRun, _ count: Int, _ body: (UnsafePointer<CFIndex>) -> Void)
    {
        if let indices = CTRunGetStringIndicesPtr (run) {
            body (indices)
        } else {
            var indices = [CFIndex] (repeating: 0, count: count)
            CTRunGetStringIndices (run, CFRange (), &indices)
            indices.withUnsafeBufferPointer { body ($0.baseAddress!) }
        }
    }

    /// The run's glyph positions, without copying them when CoreText can lend them
    private static func withPositions (_ run: CTRun, _ count: Int, _ body: (UnsafePointer<CGPoint>) -> Void)
    {
        if let positions = CTRunGetPositionsPtr (run) {
            body (positions)
        } else {
            var positions = [CGPoint] (repeating: .zero, count: count)
            CTRunGetPositions (run, CFRange (), &positions)
            positions.withUnsafeBufferPointer { body ($0.baseAddress!) }
        }
    }
}
#endif
