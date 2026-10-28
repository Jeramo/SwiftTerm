#if os(macOS) || os(iOS) || os(visionOS)
import CoreGraphics
import Foundation

/// Draws the Powerline separators (U+E0B0–E0BF) so they fill the cell from
/// top to bottom whatever font supplies them, as Ghostty and kitty do: a
/// font's glyph rarely matches the line height, leaving a notch between
/// segments of a prompt or status line.
struct PowerlineRenderer {
    static let lowerBoundary: UInt32 = 0xE0B0
    static let upperBoundary: UInt32 = 0xE0BF

    static func draw(codePoint: UInt32,
                     in context: CGContext,
                     cellOrigin: CGPoint,
                     cellSize: CGSize,
                     color: TTColor,
                     thickness: CGFloat) {
        let left = cellOrigin.x, right = cellOrigin.x + cellSize.width
        let bottom = cellOrigin.y, top = cellOrigin.y + cellSize.height
        let middle = (top + bottom) / 2
        let path = CGMutablePath()
        var filled = true
        switch codePoint {
        case 0xE0B0, 0xE0B1:  // right-pointing triangle, chevron
            path.addLines(between: [CGPoint(x: left, y: top), CGPoint(x: right, y: middle), CGPoint(x: left, y: bottom)])
            filled = codePoint == 0xE0B0
        case 0xE0B2, 0xE0B3:  // left-pointing triangle, chevron
            path.addLines(between: [CGPoint(x: right, y: top), CGPoint(x: left, y: middle), CGPoint(x: right, y: bottom)])
            filled = codePoint == 0xE0B2
        case 0xE0B4, 0xE0B5:  // right half circle, filled and outline
            path.move(to: CGPoint(x: left, y: top))
            path.addCurve(to: CGPoint(x: left, y: bottom), control1: CGPoint(x: right + cellSize.width * 0.33, y: top), control2: CGPoint(x: right + cellSize.width * 0.33, y: bottom))
            filled = codePoint == 0xE0B4
        case 0xE0B6, 0xE0B7:  // left half circle, filled and outline
            path.move(to: CGPoint(x: right, y: top))
            path.addCurve(to: CGPoint(x: right, y: bottom), control1: CGPoint(x: left - cellSize.width * 0.33, y: top), control2: CGPoint(x: left - cellSize.width * 0.33, y: bottom))
            filled = codePoint == 0xE0B6
        case 0xE0B8:  // lower left triangle
            path.addLines(between: [CGPoint(x: left, y: top), CGPoint(x: right, y: bottom), CGPoint(x: left, y: bottom)])
        case 0xE0BA:  // lower right triangle
            path.addLines(between: [CGPoint(x: right, y: top), CGPoint(x: right, y: bottom), CGPoint(x: left, y: bottom)])
        case 0xE0BC:  // upper left triangle
            path.addLines(between: [CGPoint(x: left, y: top), CGPoint(x: right, y: top), CGPoint(x: left, y: bottom)])
        case 0xE0BE:  // upper right triangle
            path.addLines(between: [CGPoint(x: left, y: top), CGPoint(x: right, y: top), CGPoint(x: right, y: bottom)])
        case 0xE0B9, 0xE0BF:  // backslash separator
            path.addLines(between: [CGPoint(x: left, y: top), CGPoint(x: right, y: bottom)])
            filled = false
        case 0xE0BB, 0xE0BD:  // forward slash separator
            path.addLines(between: [CGPoint(x: left, y: bottom), CGPoint(x: right, y: top)])
            filled = false
        default:
            return
        }
        context.saveGState()
        context.setShouldAntialias(true)
        context.setAllowsAntialiasing(true)
        context.clip(to: CGRect(origin: cellOrigin, size: cellSize))
        context.addPath(path)
        if filled {
            context.closePath()
            context.setFillColor(color.cgColor)
            context.fillPath()
        } else {
            context.setStrokeColor(color.cgColor)
            context.setLineWidth(thickness)
            context.setLineJoin(.miter)
            context.strokePath()
        }
        context.restoreGState()
    }
}
#endif

#if os(macOS) || os(iOS) || os(visionOS)
import CoreText

/// A Powerline Extra separator (U+E0C0–E0D4: flames, pixels, ice, honeycomb,
/// lego, trapezoids) drawn from the font but stretched to the cell, as Ghostty
/// does: the Nerd Font glyphs are one em tall, shorter than a terminal line
struct StretchedGlyphRenderItem {
    var column: Int
    let codePoint: UInt32
    /// Columns it may cover: two when the next cell is blank (see columns(in:at:cols:))
    let columns: Int
    let font: TTFont
    let foregroundColor: TTColor
}

extension PowerlineRenderer {
    /// How Nerd Fonts' patcher (and so Ghostty) sizes a glyph: stretched to
    /// the box or, with `fit`, scaled evenly; aligned to its start or end;
    /// `padding` is a fraction of a cell on every side; `maxRatio` caps the
    /// width over the height; `maxColumns` the columns it may take
    struct StretchRule {
        var alignEnd = false
        var fit = false
        var centered = false
        var padding: CGFloat = 0
        var maxRatio: CGFloat? = nil
        var maxColumns = 2
    }

    /// The rules from Ghostty's nerd_font_attributes.zig for U+E0C0–E0D4,
    /// with negative padding dropped as Ghostty does for stretched glyphs
    static func stretchRule(_ codePoint: UInt32) -> StretchRule?
    {
        switch codePoint {
        case 0xE0C0, 0xE0C1, 0xE0C8:
            return StretchRule()
        case 0xE0C2, 0xE0C3, 0xE0CA:
            return StretchRule(alignEnd: true)
        case 0xE0C4:
            return StretchRule(padding: 0.015, maxRatio: 0.86)
        case 0xE0C5:
            return StretchRule(alignEnd: true, padding: 0.015, maxRatio: 0.86)
        case 0xE0C6:
            return StretchRule(padding: 0.015, maxRatio: 0.78)
        case 0xE0C7:
            return StretchRule(alignEnd: true, padding: 0.015, maxRatio: 0.78)
        case 0xE0CC:
            return StretchRule(maxRatio: 0.85)
        case 0xE0CD:
            return StretchRule(maxRatio: 0.865)
        case 0xE0CE, 0xE0D0, 0xE0D1:
            return StretchRule(fit: true)
        case 0xE0CF:
            return StretchRule(fit: true, centered: true)
        case 0xE0D2:
            return StretchRule(maxRatio: 0.7, maxColumns: 1)
        case 0xE0D4:
            return StretchRule(alignEnd: true, maxRatio: 0.7, maxColumns: 1)
        default:
            return nil
        }
    }

    /// Separators other glyphs may run into, as Ghostty counts them
    static func isPowerline(_ code: Int32) -> Bool
    {
        switch code {
        case 0xE0B0...0xE0C8, 0xE0CA, 0xE0CC...0xE0D2, 0xE0D4:
            return true
        default:
            return false
        }
    }

    /// Ghostty's rule: a symbol may spread over the next cell when that one is
    /// blank or a separator, unless it is in the last column or follows
    /// another symbol (so a row of icons stays aligned)
    static func columns(in line: BufferLine, at col: Int, cols: Int) -> Int
    {
        if col >= cols - 1 {
            return 1
        }
        if col > 0 {
            let previous = line [col - 1].code
            if !isPowerline(previous) && ((0xE000...0xF8FF).contains(previous) || (0xF0000...0x10FFFD).contains(previous)) {
                return 1
            }
        }
        let next = line [col + 1].code
        return next == 0 || next == 32 || isPowerline(next) ? 2 : 1
    }

    /// Where a glyph whose ink box is `ink` lands in a cell `cellSize` wide
    /// and high (taking `columns` columns when the rule allows), relative to
    /// the cell's bottom-left corner
    static func stretchedRect(_ rule: StretchRule, ink: CGRect, columns: Int, cellSize: CGSize) -> CGRect
    {
        let width = min(columns, rule.maxColumns)
        let cw = cellSize.width, ch = cellSize.height
        func factors(_ columns: Int) -> (CGFloat, CGFloat) {
            ((CGFloat(columns) - 2 * rule.padding) * cw / ink.width, (1 - 2 * rule.padding) * ch / ink.height)
        }
        var (sx, sy) = factors(width)
        if rule.fit {
            // Scale down to fit, or up to cover one cell, keeping the shape
            var factor = min(sx, sy)
            if width > 1 && factor > 1 {
                let (sx1, sy1) = factors(1)
                factor = max(1, min(sx1, sy1))
            }
            sx = factor
            sy = factor
        }
        if let ratio = rule.maxRatio, ink.width * sx > ink.height * sy * ratio {
            sx = ink.height * sy * ratio / ink.width
        }
        let w = ink.width * sx, h = ink.height * sy
        let y = (rule.padding * ch + (ch - h - rule.padding * ch)) / 2
        let start = rule.padding * cw
        let end = CGFloat(width) * cw - w - rule.padding * cw
        let x: CGFloat
        if rule.centered {
            x = max(start, (start + cw - w - rule.padding * cw) / 2)
        } else {
            x = rule.alignEnd ? max(start, end) : start
        }
        return CGRect(x: x, y: y, width: w, height: h)
    }

    /// Draws the font's glyph for `item` stretched into its cell; nothing if
    /// no font in the cascade has it
    static func drawStretched(_ item: StretchedGlyphRenderItem, in context: CGContext, cellOrigin: CGPoint, cellSize: CGSize)
    {
        guard let rule = stretchRule(item.codePoint), let scalar = UnicodeScalar(item.codePoint) else {
            return
        }
        let text = String(scalar)
        var characters = Array(text.utf16)
        let face = CTFontCreateForString(item.font as CTFont, text as CFString, CFRange(location: 0, length: characters.count))
        var glyph: CGGlyph = 0
        guard CTFontGetGlyphsForCharacters(face, &characters, &glyph, 1), glyph != 0 else {
            return
        }
        var ink = CGRect.zero
        CTFontGetBoundingRectsForGlyphs(face, .horizontal, &glyph, &ink, 1)
        guard ink.width > 0, ink.height > 0 else {
            return
        }
        let target = stretchedRect(rule, ink: ink, columns: item.columns, cellSize: cellSize)
        let sx = target.width / ink.width, sy = target.height / ink.height
        context.saveGState()
        context.setShouldAntialias(true)
        context.setAllowsAntialiasing(true)
        context.setFillColor(item.foregroundColor.cgColor)
        context.translateBy(x: cellOrigin.x + target.minX - ink.minX * sx, y: cellOrigin.y + target.minY - ink.minY * sy)
        context.scaleBy(x: sx, y: sy)
        var position = CGPoint.zero
        CTFontDrawGlyphs(face, &glyph, &position, 1, context)
        context.restoreGState()
    }
}
#endif
