import Foundation
import Testing
@testable import ZephInk

/// The file is the truth: opening and saving a document must never change bytes the person didn't touch.
@MainActor
struct MarkdownDocumentTests {
    nonisolated static let fixtures = ["welcome.md", "crlf.md", "no-trailing-newline.md", "bom-unicode.md"]

    private static func fixture(_ name: String) throws -> Data {
        let url = try #require(Bundle(for: BundleToken.self).url(forResource: name, withExtension: nil, subdirectory: "Fixtures"))
        return try Data(contentsOf: url)
    }

    @Test(arguments: fixtures)
    func savingWithoutChangesKeepsEveryByte(_ name: String) throws {
        let original = try Self.fixture(name)
        let document = MarkdownDocument()
        try document.read(from: original, ofType: "net.daringfireball.markdown")
        #expect(try document.data(ofType: "net.daringfireball.markdown") == original)
    }

    @Test(arguments: fixtures)
    func theTextIsTheFile(_ name: String) throws {
        let original = try Self.fixture(name)
        let document = MarkdownDocument()
        try document.read(from: original, ofType: "net.daringfireball.markdown")
        let byteOrderMark = Data([0xEF, 0xBB, 0xBF])
        let text = original.starts(with: byteOrderMark) ? original.dropFirst(3) : original
        #expect(Data(document.storage.string.utf8) == text)
    }

    @Test func anEditKeepsTheByteOrderMark() throws {
        let document = MarkdownDocument()
        try document.read(from: Data([0xEF, 0xBB, 0xBF]) + Data("# Title\n".utf8), ofType: "net.daringfireball.markdown")
        #expect(document.storage.string == "# Title\n")
        document.storage.append(NSAttributedString(string: "More.\n"))
        #expect(try document.data(ofType: "net.daringfireball.markdown") == Data([0xEF, 0xBB, 0xBF]) + Data("# Title\nMore.\n".utf8))
    }

    @Test func savingAnEditWritesTheNewText() throws {
        let document = MarkdownDocument()
        try document.read(from: Data("# Title\n".utf8), ofType: "net.daringfireball.markdown")
        document.storage.append(NSAttributedString(string: "\nMore text.\n"))
        #expect(try document.data(ofType: "net.daringfireball.markdown") == Data("# Title\n\nMore text.\n".utf8))
    }

    @Test func textThatIsNotUTF8IsRefused() {
        let document = MarkdownDocument()
        #expect(throws: CocoaError.self) {
            try document.read(from: Data([0xFF, 0xFE, 0x00, 0xD8]), ofType: "net.daringfireball.markdown")
        }
    }
}

private final class BundleToken {}
