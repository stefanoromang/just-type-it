// Created by Stefano Roman Gunness · MIT License
// Standalone tests: works with Command Line Tools, without Xcode/XCTest.
import Foundation

private func XCTAssertTrue(_ value: Bool, _ message: String = "", file: StaticString = #filePath, line: UInt = #line) {
    guard value else { fatalError("Assertion failed: \(message)", file: (file), line: line) }
}
private func XCTAssertFalse(_ value: Bool, _ message: String = "", file: StaticString = #filePath, line: UInt = #line) {
    XCTAssertTrue(!value, message, file: file, line: line)
}
private func XCTAssertNil<T>(_ value: T?, file: StaticString = #filePath, line: UInt = #line) {
    XCTAssertTrue(value == nil, "Expected nil", file: file, line: line)
}
private func XCTAssertEqual<T: Equatable>(_ actual: T, _ expected: T, file: StaticString = #filePath, line: UInt = #line) {
    XCTAssertTrue(actual == expected, "Values differ", file: file, line: line)
}
private func XCTAssertLessThanOrEqual(_ actual: Int, _ expected: Int) { XCTAssertTrue(actual <= expected) }

@main
@MainActor
struct OutlookCompatibilityTests {
    static func main() {
        let tests = Self()
        tests.testHostedEditorSearchSurvivesSelfChildrenAndCycles()
        tests.testSearchStopsAtItsBudgets()
        tests.testRecipientSearchAndSecureFieldsAreNotProofread()
        tests.testCorrectionPreservesSignatureAndUnicode()
        tests.testCorrectionRejectsInvalidAndSplitUnicodeRanges()
        print("PASS: 5 Outlook compatibility regression tests")
    }
    func testHostedEditorSearchSurvivesSelfChildrenAndCycles() {
        let tree = [0: [1, 2], 1: [1], 2: [3], 3: [2, 4], 4: [5]]
        let editor = FocusedEditor.search(roots: [0], children: { tree[$0] ?? [] }, matches: { $0 == 5 })
        XCTAssertEqual(editor, 5)
    }

    func testSearchStopsAtItsBudgets() {
        var calls = 0
        let missing = FocusedEditor.search(roots: [0], maxNodes: 20, maxDepth: 10, children: { node in
            calls += 1
            return [node + 1]
        }, matches: { $0 == 100 })
        XCTAssertNil(missing)
        XCTAssertLessThanOrEqual(calls, 10)
        XCTAssertNil(FocusedEditor.search(roots: [0], maxNodes: 2, children: { [$0 + 1] }, matches: { $0 == 2 }))
    }

    func testRecipientSearchAndSecureFieldsAreNotProofread() {
        for label in ["To Recipients", "Cc Recipients", "Bcc Recipients", "Search", "Email Address", "URL", "Password"] {
            XCTAssertFalse(FocusedEditor.isTextField(role: "AXTextField", subrole: "", description: label), label)
        }
        XCTAssertFalse(FocusedEditor.isTextField(role: "AXTextField", subrole: "AXSecureTextField", description: ""))
        XCTAssertFalse(FocusedEditor.isTextField(role: "AXWebArea", subrole: "", description: "reading pane"))
        XCTAssertTrue(FocusedEditor.isTextField(role: "AXTextArea", subrole: "", description: ""))
        XCTAssertTrue(FocusedEditor.isTextField(role: "AXTextField", subrole: "", description: "Subject"))
    }

    func testCorrectionPreservesSignatureAndUnicode() {
        let text = "Hi 👋\nTheir going tomorow.\n\nStefano\u{00a0}Roman\nhttps://example.com"
        let range = (text as NSString).range(of: "tomorow")
        let expected = text.replacingOccurrences(of: "tomorow", with: "tomorrow")
        XCTAssertEqual(AccessibilityEdit.expectedText(text, range: range, original: "tomorow", replacement: "tomorrow"), expected)
        XCTAssertNil(AccessibilityEdit.expectedText(text, range: range, original: "different draft", replacement: "tomorrow"))
    }

    func testCorrectionRejectsInvalidAndSplitUnicodeRanges() {
        for range in [NSRange(location: NSNotFound, length: 0), NSRange(location: 9, length: 100), NSRange(location: 100, length: 1)] {
            XCTAssertNil(AccessibilityEdit.expectedText("Hi 👋", range: range, original: "", replacement: "text"))
        }
        XCTAssertNil(AccessibilityEdit.expectedText("👋", range: NSRange(location: 0, length: 1), original: "", replacement: "x"))
    }
}
