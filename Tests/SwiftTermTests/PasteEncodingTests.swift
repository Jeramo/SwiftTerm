import XCTest
@testable import SwiftTerm

final class PasteEncodingTests: XCTestCase {
    func testPlainPastePreservesUTF8Bytes() {
        let text = "printf 'café 👋'\n"

        XCTAssertEqual(
            EscapeSequences.pastePayload(text, bracketed: false),
            Array(text.utf8)
        )
    }

    func testBracketedPasteWrapsUTF8Bytes() {
        let text = "first line\nsecond line"
        let expected = EscapeSequences.bracketedPasteStart
            + Array(text.utf8)
            + EscapeSequences.bracketedPasteEnd

        XCTAssertEqual(
            EscapeSequences.pastePayload(text, bracketed: true),
            expected
        )
    }

    func testBracketedPasteStripsEmbeddedEscapeInjection() {
        let injected = "safe\u{1B}[201~echo injected"
        let sanitized = "safe[201~echo injected"
        let expected = EscapeSequences.bracketedPasteStart
            + Array(sanitized.utf8)
            + EscapeSequences.bracketedPasteEnd

        let payload = EscapeSequences.pastePayload(injected, bracketed: true)

        XCTAssertEqual(payload, expected)
        XCTAssertEqual(payload.filter { $0 == ControlCodes.ESC }.count, 2)
    }
}
