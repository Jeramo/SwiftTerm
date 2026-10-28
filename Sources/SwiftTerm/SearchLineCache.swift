//
//  SearchLineCache.swift
//  SwiftTerm
//
//  Ported from xterm.js search addon infrastructure.
//

import Foundation

/// A logical (possibly wrapped) line as text, the Character offset where each of
/// its rows starts, and the column where each Character starts, counted from the
/// first row, plus the column after the end
typealias LineCacheEntry = (lineAsString: String, lineOffsets: [Int], columns: [Int])

final class SearchLineCache {
    private enum Constants {
        static let linesCacheTimeToLive: TimeInterval = 15.0
    }

    private let terminal: Terminal
    private var linesCache: [LineCacheEntry?]?
    private var lastAccessTimestamp: TimeInterval = 0

    init (terminal: Terminal) {
        self.terminal = terminal
    }

    func initLinesCache () {
        let now = Date().timeIntervalSinceReferenceDate
        let bufferLineCount = terminal.displayBuffer.lines.count

        if let cache = linesCache {
            if now - lastAccessTimestamp >= Constants.linesCacheTimeToLive || cache.count != bufferLineCount {
                linesCache = nil
            }
        }

        if linesCache == nil {
            linesCache = Array(repeating: nil, count: bufferLineCount)
        }

        lastAccessTimestamp = now
    }

    func invalidate () {
        linesCache = nil
        lastAccessTimestamp = 0
    }

    func getLineFromCache (row: Int) -> LineCacheEntry? {
        guard let cache = linesCache, row >= 0, row < cache.count else {
            return nil
        }
        return cache[row]
    }

    func setLineInCache (row: Int, entry: LineCacheEntry) {
        guard row >= 0, row < (linesCache?.count ?? 0) else {
            return
        }
        linesCache?[row] = entry
    }

    func translateBufferLineToStringWithWrap (lineIndex: Int, trimRight: Bool) -> LineCacheEntry {
        let buffer = terminal.displayBuffer
        let cols = terminal.cols
        var text = ""
        var columns: [Int] = []
        var lineOffsets: [Int] = [0]
        var endColumn = 0
        var idx = lineIndex
        var rowStart = 0

        while idx >= 0 && idx < buffer.lines.count {
            let line = buffer.lines[idx]
            let nextLine = (idx + 1) < buffer.lines.count ? buffer.lines[idx + 1] : nil
            let lineWrapsToNext = nextLine?.isWrapped ?? false

            var end = min(line.count, cols)
            if !lineWrapsToNext && trimRight {
                end = min(end, line.getTrimmedLength())
            }
            // A wide character that did not fit leaves a blank before it wraps
            if lineWrapsToNext, let nextLine, end > 0 {
                let lastCell = line[end - 1]
                if lastCell.code == 0 && lastCell.width <= 1 && nextLine.getWidth(index: 0) == 2 {
                    end -= 1
                }
            }
            for col in 0..<end {
                let cell = line[col]
                if cell.width == 0 {
                    // the trailing half of a wide character
                    continue
                }
                let cellText = cell.code == 0 ? " " : terminal.getText(for: cell)
                // A skin tone or mark can merge with the Character before it ("a" + "🏽"),
                // which then spans both cells
                let merges = !text.isEmpty && (String(text.last!) + String(cellText.first!)).count == 1
                text += cellText
                for _ in 0..<max(cellText.count - (merges ? 1 : 0), 0) {
                    columns.append(rowStart + col)
                }
            }
            endColumn = rowStart + end

            if !lineWrapsToNext {
                break
            }
            lineOffsets.append(columns.count)
            idx += 1
            rowStart += cols
        }

        // Keep one column per Character even if segmentation moved across cells
        let count = text.count
        if columns.count > count {
            columns.removeLast(columns.count - count)
        }
        while columns.count < count {
            columns.append(columns.last ?? 0)
        }
        columns.append(endColumn)
        return (text, lineOffsets, columns)
    }
}
