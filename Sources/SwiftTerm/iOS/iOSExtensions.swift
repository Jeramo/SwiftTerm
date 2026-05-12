//
//  File.swift
//  
//
//  Created by Miguel de Icaza on 6/29/21.
//
#if os(iOS) || os(visionOS)
import Foundation
import UIKit

extension UIColor {
    func getTerminalColor () -> Color {
        var red: CGFloat = 0.0, green: CGFloat = 0.0, blue: CGFloat = 0.0, alpha: CGFloat = 1.0
        self.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        
        func clamp (_ v: CGFloat) -> CGFloat {
            return min (max (v, 0.0), 1.0)
        }
        return Color(red: UInt16 (clamp (red)*65535), green: UInt16(clamp (green)*65535), blue: UInt16(clamp (blue)*65535))
    }

    func inverseColor() -> UIColor {
        var red: CGFloat = 0.0, green: CGFloat = 0.0, blue: CGFloat = 0.0, alpha: CGFloat = 1.0
        self.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        return UIColor (red: 1.0 - red, green: 1.0 - green, blue: 1.0 - blue, alpha: alpha)
    }

    /// Returns a dimmed version of the color (SGR 2 faint/dim attribute) by
    /// blending 50 % toward `background`. The result is fully opaque so that
    /// adjacent box-drawing characters tile without visible seams.
    func dimmedColor (towards background: UIColor) -> UIColor {
        var fRed: CGFloat = 0.0, fGreen: CGFloat = 0.0, fBlue: CGFloat = 0.0, fAlpha: CGFloat = 1.0
        self.getRed(&fRed, green: &fGreen, blue: &fBlue, alpha: &fAlpha)
        var bRed: CGFloat = 0.0, bGreen: CGFloat = 0.0, bBlue: CGFloat = 0.0, bAlpha: CGFloat = 1.0
        background.getRed(&bRed, green: &bGreen, blue: &bBlue, alpha: &bAlpha)
        // Force alpha = 1.0 to match the documented invariant. Was: fAlpha,
        // which silently preserved any translucency on the foreground and
        // produced visible seams between adjacent box-drawing cells if any
        // upstream code ever set a translucent fg.
        return UIColor (red: (fRed + bRed) * 0.5,
                        green: (fGreen + bGreen) * 0.5,
                        blue: (fBlue + bBlue) * 0.5,
                        alpha: 1.0)
    }

    static func make (red: CGFloat, green: CGFloat, blue: CGFloat, alpha: CGFloat) -> TTColor
    {
        // Was hard-coding alpha to 1.0, silently dropping the passed value.
        // macOS's MacExtensions.make(red:green:blue:alpha:) forwards alpha
        // correctly via NSColor(deviceRed:green:blue:alpha:), so iOS callers
        // that wanted translucent colors got opaque ones with no warning.
        return UIColor(red: red,
                       green: green,
                       blue: blue,
                       alpha: alpha)
    }
  
    static func make (hue: CGFloat, saturation: CGFloat, brightness: CGFloat, alpha: CGFloat) -> TTColor
    {
        return UIColor(hue: hue,
                       saturation: saturation,
                       brightness: brightness,
                       alpha: alpha)
    }
    
    static func make (color: Color) -> UIColor
    {
        UIColor (red: CGFloat (color.red) / 65535.0,
                 green: CGFloat (color.green) / 65535.0,
                 blue: CGFloat (color.blue) / 65535.0,
                 alpha: 1.0)
    }
    
    static func transparent () -> UIColor {
        return UIColor.clear
    }
}

extension UIImage {
    /// Cross-platform parity helper for the Mac NSImage(cgImage:size:)
    /// initializer. UIImage has no built-in init that takes both a
    /// CGImage and a point size — its convenience inits expose a
    /// `scale` factor instead. Map the caller's intended point size
    /// to the equivalent scale: UIImage.size = pixelDim / scale, so
    /// scale = pixelDim / pointDim makes the resulting UIImage
    /// report `size` as its point dimensions.
    ///
    /// Was: `self.init(cgImage: cgImage, scale: -1, orientation: .up)`.
    /// Negative scale is undefined for UIImage (the docs only specify
    /// positive values), and the `size` argument was ignored entirely
    /// — so callers in AppleTerminalView.swift (terminal images:
    /// Sixel, kitty graphics, iTerm protocol) got an arbitrary-scale
    /// UIImage whose `.size` did not match `size`. On macOS the
    /// NSExtensions counterpart respected `size` correctly, so the
    /// two platforms produced different geometry from the same call.
    public convenience init (cgImage: CGImage, size: CGSize) {
        let pixelW = CGFloat(cgImage.width)
        let pixelH = CGFloat(cgImage.height)
        let resolvedScale: CGFloat
        if size.width > 0, size.height > 0 {
            // Take the larger of the two axis scales so the result
            // fits within `size` on both axes (never exceeds it).
            // Clamp to >= 1: UIImage with scale < 1 effectively
            // upscales the bitmap, which produces blurry inline
            // terminal images.
            resolvedScale = max(1.0, max(pixelW / size.width, pixelH / size.height))
        } else {
            resolvedScale = 1.0
        }
        self.init(cgImage: cgImage, scale: resolvedScale, orientation: .up)
    }
}

extension NSAttributedString {
    func fuzzyHasSelectionBackground (_ ret: Bool) -> Bool
    {
        return ret
    }
}
#endif

