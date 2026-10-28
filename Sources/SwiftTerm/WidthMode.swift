//
//  WidthMode.swift
//
//  How many columns a character takes is decided by the program that
//  positions the cursor, not by the terminal: a shell measures with
//  wcwidth(3), tmux with its own rules, zellij and mosh-server per code
//  point. When the terminal measures differently, every later character on
//  the line lands in the wrong column. WidthMode picks whose rules to follow.
//

/// The width rules the terminal follows for new output; see `Terminal.widthMode`.
public enum WidthMode: Equatable, Sendable {
    /// Grapheme clusters measured the way Ghostty, kitty and WezTerm measure
    /// them, which is how modern TUIs (Claude Code, Ink, neovim with mode
    /// 2027) lay out text. This is the default, and what `DECSET 2027` selects.
    ///
    /// The trade-off is line editing in a plain shell: readline and zle
    /// measure one code point at a time with the host's wcwidth(3), so editing
    /// a line holding 👍🏽, a ZWJ family, ❤️, a flag or some Indic text puts
    /// the cursor in the wrong column. `.wcwidth` gets those right.
    case unicode

    /// One code point at a time with a wcwidth(3) table: what readline, zle,
    /// mosh-server and tmux 3.3 and older measure with, and (but for a few
    /// rare code points) zellij. `DECRST 2027` selects it, with the table last
    /// used.
    ///
    /// zellij measures with Rust's unicode-width, which differs from glibc on
    /// a few rare code points that are not modelled: the Arabic number signs
    /// U+0600–0605, U+06DD, U+070F and U+08E2, the Hangul fillers U+3164 and
    /// U+FFA0, U+3248–324F, the Egyptian hieroglyph format controls
    /// U+13430–13438 and Ahom U+1171E.
    case wcwidth (WcwidthTable)

    /// tmux's rules for the attached server's version.
    case tmux (TmuxVersion)
}

/// Whose wcwidth(3) a `WidthMode.wcwidth` measures with: the program's host.
public enum WcwidthTable: Equatable, Sendable {
    /// glibc 2.41: Linux
    case glibc
    /// macOS libc, which gives Indic spacing marks (as in हि) no column of
    /// their own, and one column to the Yijing symbols and to what is newer
    /// than its tables (recent CJK extensions, a few emoji)
    case darwin
}

/// The tmux server version a `WidthMode.tmux` follows.
public struct TmuxVersion: Equatable, Sendable {
    public var major: Int
    public var minor: Int

    /// Whether this tmux was built with utf8proc: Homebrew's is, Debian's and
    /// Ubuntu's are not. It measures spacing marks (as in हि) as part of the
    /// letter before them instead of a column of their own.
    public var utf8proc: Bool

    /// tmux 3.6's `variation-selector-always-wide` server option, on unless
    /// changed (`tmux show -gv variation-selector-always-wide`): VS16 makes
    /// the character before it two columns wide. tmux before 3.6 always does.
    public var variationSelectorAlwaysWide: Bool

    public init (major: Int, minor: Int, utf8proc: Bool = false, variationSelectorAlwaysWide: Bool = true)
    {
        self.major = major
        self.minor = minor
        self.utf8proc = utf8proc
        self.variationSelectorAlwaysWide = variationSelectorAlwaysWide
    }

    /// Parses `tmux -V` output such as "tmux 3.5a", "tmux next-3.6" or "3.4".
    ///
    /// "tmux master" is read as the newest version known here, 3.7. OpenBSD's
    /// own tmux ("tmux openbsd-7.6") is a snapshot between releases and is
    /// read as 3.5. psmux, the Windows clone, answers "psmux 3.3.8" and is read
    /// as 3.3, but its screen reaches the client through ConPTY, which measures
    /// ❤️ and a regional indicator as two columns each; no mode matches that.
    public init? (_ version: String, utf8proc: Bool = false, variationSelectorAlwaysWide: Bool = true)
    {
        let name = version.lowercased ()
        if name.contains ("openbsd") {
            self.init (major: 3, minor: 5, utf8proc: utf8proc, variationSelectorAlwaysWide: variationSelectorAlwaysWide)
            return
        }
        if name.contains ("master") {
            self.init (major: 3, minor: 7, utf8proc: utf8proc, variationSelectorAlwaysWide: variationSelectorAlwaysWide)
            return
        }
        let digits = name.drop { !$0.isNumber }
        let parts = digits.split (separator: ".", maxSplits: 1)
        guard let major = parts.first.flatMap ({ Int ($0) }) else {
            return nil
        }
        let minor = parts.count > 1 ? Int (parts [1].prefix { $0.isNumber }) ?? 0 : 0
        self.init (major: major, minor: minor, utf8proc: utf8proc, variationSelectorAlwaysWide: variationSelectorAlwaysWide)
    }
}

/// The resolved rules for a WidthMode, kept by the terminal so printing does
/// not switch on versions.
struct WidthRules: Equatable {
    enum Base {
        /// UnicodeUtil.columnWidth: Unicode East Asian Width plus emoji presentation
        case unicode
        /// glibc 2.41 wcwidth(3)
        case glibc
        /// utf8proc_charwidth
        case utf8proc
        /// macOS wcwidth(3)
        case darwin
    }

    enum Combine {
        /// Ghostty's grapheme joining
        case unicode
        /// Only zero-width code points join the cell before them
        case wcwidth
        /// tmux 3.4 and 3.5 (screen_write_combine)
        case tmux34
        /// tmux 3.6 and later
        case tmux36
    }

    var base: Base
    var combine: Combine
    /// tmux's fixed widths (utf8_force_wide, utf8_default_width_cache) apply
    var tmuxWidths: Bool
    /// tmux measures a lone regional indicator 2 columns wide before 3.6, 1 after
    var regionalIndicatorWidth: Int
    /// tmux stops joining once a cell would hold more than this many UTF-8 bytes
    var maxCellBytes: Int
    /// tmux makes the character before a VS16 two columns wide
    var vs16Widens = true

    init (_ mode: WidthMode)
    {
        switch mode {
        case .unicode:
            self.init (base: .unicode, combine: .unicode, tmuxWidths: false, regionalIndicatorWidth: 2, maxCellBytes: .max)
        case .wcwidth (let table):
            self.init (base: table == .darwin ? .darwin : .glibc, combine: .wcwidth, tmuxWidths: false, regionalIndicatorWidth: 1, maxCellBytes: .max)
        case .tmux (let version):
            let base: Base = version.utf8proc ? .utf8proc : .glibc
            if (version.major, version.minor) < (3, 4) {
                // tmux 3.3 joins only zero-width characters and has no width table
                self.init (base: base, combine: .wcwidth, tmuxWidths: false, regionalIndicatorWidth: 1, maxCellBytes: 21)
            } else if (version.major, version.minor) < (3, 6) {
                self.init (base: base, combine: .tmux34, tmuxWidths: true, regionalIndicatorWidth: 2, maxCellBytes: 21)
            } else {
                self.init (base: base, combine: .tmux36, tmuxWidths: true, regionalIndicatorWidth: 1, maxCellBytes: 32)
                vs16Widens = version.variationSelectorAlwaysWide
            }
        }
    }

    private init (base: Base, combine: Combine, tmuxWidths: Bool, regionalIndicatorWidth: Int, maxCellBytes: Int)
    {
        self.base = base
        self.combine = combine
        self.tmuxWidths = tmuxWidths
        self.regionalIndicatorWidth = regionalIndicatorWidth
        self.maxCellBytes = maxCellBytes
    }
}

/// Tables copied from tmux's sources.
struct TmuxWidthData {
    typealias Range = UnicodeUtil.LH

    /// Emoji modifier bases tmux always draws two columns wide
    /// (utf8_force_wide in 3.4/3.5, utf8_default_width_cache in 3.6+)
    static let wideBases: [Range] = [
        Range(lo: 0x261D, hi: 0x261D),
        Range(lo: 0x26F9, hi: 0x26F9),
        Range(lo: 0x270A, hi: 0x270D),
        Range(lo: 0x1F385, hi: 0x1F385),
        Range(lo: 0x1F3C2, hi: 0x1F3C4),
        Range(lo: 0x1F3C7, hi: 0x1F3C7),
        Range(lo: 0x1F3CA, hi: 0x1F3CC),
        Range(lo: 0x1F442, hi: 0x1F443),
        Range(lo: 0x1F446, hi: 0x1F450),
        Range(lo: 0x1F466, hi: 0x1F469),
        Range(lo: 0x1F46B, hi: 0x1F46E),
        Range(lo: 0x1F470, hi: 0x1F478),
        Range(lo: 0x1F47C, hi: 0x1F47C),
        Range(lo: 0x1F481, hi: 0x1F483),
        Range(lo: 0x1F485, hi: 0x1F487),
        Range(lo: 0x1F48F, hi: 0x1F48F),
        Range(lo: 0x1F491, hi: 0x1F491),
        Range(lo: 0x1F4AA, hi: 0x1F4AA),
        Range(lo: 0x1F574, hi: 0x1F575),
        Range(lo: 0x1F57A, hi: 0x1F57A),
        Range(lo: 0x1F590, hi: 0x1F590),
        Range(lo: 0x1F595, hi: 0x1F596),
        Range(lo: 0x1F645, hi: 0x1F647),
        Range(lo: 0x1F64B, hi: 0x1F64F),
        Range(lo: 0x1F6A3, hi: 0x1F6A3),
        Range(lo: 0x1F6B4, hi: 0x1F6B6),
        Range(lo: 0x1F6C0, hi: 0x1F6C0),
        Range(lo: 0x1F6CC, hi: 0x1F6CC),
        Range(lo: 0x1F90C, hi: 0x1F90C),
        Range(lo: 0x1F90F, hi: 0x1F90F),
        Range(lo: 0x1F918, hi: 0x1F91F),
        Range(lo: 0x1F926, hi: 0x1F926),
        Range(lo: 0x1F930, hi: 0x1F939),
        Range(lo: 0x1F93D, hi: 0x1F93E),
        Range(lo: 0x1F977, hi: 0x1F977),
        Range(lo: 0x1F9B5, hi: 0x1F9B6),
        Range(lo: 0x1F9B8, hi: 0x1F9B9),
        Range(lo: 0x1F9BB, hi: 0x1F9BB),
        Range(lo: 0x1F9CD, hi: 0x1F9CF),
        Range(lo: 0x1F9D1, hi: 0x1F9DD),
        Range(lo: 0x1FAC3, hi: 0x1FAC5),
        Range(lo: 0x1FAF0, hi: 0x1FAF8),
    ]

    /// Bases a skin tone joins in tmux 3.6+ (utf8_should_combine)
    static let modifierBases: [Range] = [
        Range(lo: 0x1F44B, hi: 0x1F450),
        Range(lo: 0x1F466, hi: 0x1F469),
        Range(lo: 0x1F46E, hi: 0x1F46E),
        Range(lo: 0x1F470, hi: 0x1F478),
        Range(lo: 0x1F47C, hi: 0x1F47C),
        Range(lo: 0x1F481, hi: 0x1F483),
        Range(lo: 0x1F485, hi: 0x1F487),
        Range(lo: 0x1F4AA, hi: 0x1F4AA),
        Range(lo: 0x1F575, hi: 0x1F575),
        Range(lo: 0x1F57A, hi: 0x1F57A),
        Range(lo: 0x1F590, hi: 0x1F590),
        Range(lo: 0x1F595, hi: 0x1F596),
        Range(lo: 0x1F645, hi: 0x1F647),
        Range(lo: 0x1F64B, hi: 0x1F64F),
        Range(lo: 0x1F6B4, hi: 0x1F6B6),
        Range(lo: 0x1F926, hi: 0x1F926),
        Range(lo: 0x1F937, hi: 0x1F939),
        Range(lo: 0x1F93D, hi: 0x1F93E),
        Range(lo: 0x1F9B5, hi: 0x1F9B6),
        Range(lo: 0x1F9B8, hi: 0x1F9B9),
        Range(lo: 0x1F9CD, hi: 0x1F9CF),
        Range(lo: 0x1F9D1, hi: 0x1F9DF),
    ]
}
