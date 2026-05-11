//
//  iOSCaretView.swift
//
// Implements the caret in the iOS caret view
//
//  Created by Miguel de Icaza on 3/20/20.
//

#if os(iOS) || os(visionOS)
import Foundation
import UIKit
import CoreText
import CoreGraphics

// The CaretView is used to show the cursor
class CaretView: UIView {
    weak var terminal: TerminalView?
    var ctline: CTLine?
    var bgColor: CGColor
    var tracksFocus = true

    // Cached identity of whatever CharData built the current `ctline`, so
    // setText(ch:) can short-circuit when the cursor hasn't actually moved
    // onto a different cell. AppleTerminalView.updateCursorPosition() calls
    // setText every step() — without this cache that allocates a fresh
    // NSAttributedString + CTLine + fires setNeedsDisplay on every frame
    // during streaming output, even though the cell at the cursor is
    // almost always identical to the prior frame's. Sentinel value -1 is
    // outside the valid 0..<CharData.maxRune range so the first real call
    // always misses and primes the cache.
    private var cachedCharCode: Int32 = -1
    private var cachedCharAttribute: Attribute?
    private var cachedCharFg: UIColor?
    private var cachedCharBg: UIColor?
    
    public init (frame: CGRect, cursorStyle: CursorStyle, terminal: TerminalView)
    {
        style = cursorStyle
        bgColor = caretColor.cgColor
        self.terminal = terminal
        super.init(frame: frame)
        layer.isOpaque = false
        isUserInteractionEnabled = false
        updateView()
    }
    
    @objc func foreground () {
        updateCursorStyle()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    var style: CursorStyle {
        didSet {
            updateCursorStyle ()
        }
    }

    override func willMove(toWindow newWindow: UIWindow?) {
        if newWindow != nil {
            updateCursorStyle()
        }
    }
    
    override func didMoveToWindow() {
        // Always remove first. Without this, a view-pool recycle path that
        // re-attaches the same caret to a new window (without a nil pass in
        // between, or with two non-nil transitions back to back) would
        // stack duplicate observer registrations — each foreground
        // notification would then fire `foreground` N times.
        let name = NSNotification.Name(rawValue: UIApplication.willEnterForegroundNotification.rawValue)
        NotificationCenter.default.removeObserver(self, name: name, object: nil)
        if window != nil {
            NotificationCenter.default.addObserver(self, selector: #selector(foreground), name: name, object: nil)
        }
        updateCursorStyle ();
    }
    
    func updateAnimation (to: Bool) {
        layer.removeAllAnimations()
        self.layer.opacity = 1
        if window == nil {
            return
        }
        if to {
            UIView.animate(withDuration: 0.7, delay: 0, options: [.autoreverse, .repeat, .curveEaseIn], animations: {
                self.layer.opacity = 0.0
            }, completion: { [weak self] done in
                // Attempt again, could be the window transitioning
                if done {
                    self?.updateAnimation(to: to)
                }
            })
        }
    }
    
    func setText (ch: CharData) {
        let fg = caretColor
        let bg = caretTextColor ?? terminal?.nativeForegroundColor ?? TTColor.black
        if ch.code == cachedCharCode &&
           ch.attribute == cachedCharAttribute &&
           fg == cachedCharFg &&
           bg == cachedCharBg {
            // Cell at the cursor is bit-identical to the last paint —
            // ctline still holds the correct shaped glyph. Skip the
            // NSAttributedString + CTLine allocation and the redraw.
            return
        }
        let character = terminal?.terminal.getCharacter(for: ch) ?? " "
        let res = NSAttributedString (
            string: String (character),
            attributes: terminal?.getAttributedValue(ch.attribute, usingFg: fg, andBg: bg))
        ctline = CTLineCreateWithAttributedString(res)
        cachedCharCode = ch.code
        cachedCharAttribute = ch.attribute
        cachedCharFg = fg
        cachedCharBg = bg
        setNeedsDisplay(bounds)
    }

    /// Drop the caret-glyph cache so the next setText(ch:) call rebuilds.
    /// Call from any path that changes what the cached glyph would have
    /// rendered to — most importantly font swaps, since the CTLine has the
    /// font baked in and a stale glyph would persist into the new font's
    /// metric. The fg/bg comparison in setText handles palette changes
    /// inherently.
    func invalidateCharCache() {
        cachedCharCode = -1
        cachedCharAttribute = nil
        cachedCharFg = nil
        cachedCharBg = nil
    }
    
    func updateCursorStyle () {
        switch style {
        case .blinkUnderline, .blinkBlock, .blinkBar:
            updateAnimation(to: true)
        case .steadyBar, .steadyBlock, .steadyUnderline:
            updateAnimation(to: false)
        }
        updateView()
    }
    
    func disableAnimations() {
        layer.removeAllAnimations()
        layer.opacity = 1
    }
    
    public var defaultCaretColor = UIColor.gray
    
    public var caretColor: UIColor = UIColor.gray {
        didSet {
            bgColor = caretColor.cgColor
            updateView()
        }
    }

    public var defaultCaretTextColor: UIColor? = nil
    public var caretTextColor: UIColor? = nil {
        didSet {
            updateView()
        }
    }

    func updateView() {
        setNeedsDisplay()
    }

    override public func draw (_ dirtyRect: CGRect) {
        guard let context = UIGraphicsGetCurrentContext () else {
            return
        }
        context.scaleBy (x: 1, y: -1)
        context.translateBy(x: 0, y: -frame.height)

        drawCursor(in: context, hasFocus: tracksFocus ? (superview?.isFirstResponder ?? true) : true)
    }

}
#endif
