import Foundation
import Testing
@testable import ZephInk

/// The file is the truth: opening and saving a document must never change bytes the person didn't touch.
@MainActor
struct MarkdownDocumentTests {
    nonisolated static let fixtures = ["welcome.md", "crlf.md", "no-trailing-newline.md", "bom-unicode.md", "utf16-bom.md", "latin1.txt"]

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

    @Test(arguments: ["welcome.md", "crlf.md", "no-trailing-newline.md", "bom-unicode.md"])
    func theTextIsTheFile(_ name: String) throws {
        let original = try Self.fixture(name)
        let document = MarkdownDocument()
        try document.read(from: original, ofType: "net.daringfireball.markdown")
        let byteOrderMark = Data([0xEF, 0xBB, 0xBF])
        let text = original.starts(with: byteOrderMark) ? original.dropFirst(3) : original
        #expect(Data(document.storage.string.utf8) == text)
    }

    @Test func anEditKeepsTheFilesEncoding() throws {
        let original = try Self.fixture("latin1.txt")
        let document = MarkdownDocument()
        try document.read(from: original, ofType: "public.plain-text")
        #expect(document.storage.string.hasPrefix("Café au lait"))
        document.storage.append(NSAttributedString(string: "Encore\n"))
        let saved = try document.data(ofType: "public.plain-text")
        #expect(saved == original + Data("Encore\n".utf8))
        #expect(document.format.encoding == .windowsCP1252)
    }

    @Test func anEditToUTF16KeepsItsByteOrderMarkAndLineBreaks() throws {
        let original = try Self.fixture("utf16-bom.md")
        let document = MarkdownDocument()
        try document.read(from: original, ofType: "net.daringfireball.markdown")
        #expect(document.format.lineBreak == "\r\n")
        document.storage.append(NSAttributedString(string: "More\r\n"))
        let saved = try document.data(ofType: "net.daringfireball.markdown")
        #expect(saved.starts(with: [0xFF, 0xFE]))
        #expect(String(data: saved.dropFirst(2), encoding: .utf16LittleEndian)?.hasSuffix("✓\r\nMore\r\n") == true)
    }

    @Test func textTheEncodingCantHoldIsSavedAsUTF8() throws {
        let document = MarkdownDocument()
        try document.read(from: try Self.fixture("latin1.txt"), ofType: "public.plain-text")
        document.storage.append(NSAttributedString(string: "🖋️\n"))
        let saved = try document.data(ofType: "public.plain-text")
        #expect(String(data: saved, encoding: .utf8)?.hasSuffix("🖋️\n") == true)
        #expect(document.format.encoding == .utf8)
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

    @Test func lineBreaksAreFoundAndPastedTextFollowsThem() {
        #expect(FileText.lineBreak(in: "a\r\nb") == "\r\n")
        #expect(FileText.lineBreak(in: "a\rb") == "\r")
        #expect(FileText.lineBreak(in: "a\nb\r\n") == "\n")
        #expect(FileText.lineBreak(in: "no breaks") == "\n")
        let windows = FileText(encoding: .utf8, byteOrderMark: Data(), lineBreak: "\r\n")
        #expect(windows.normalizingLineBreaks("one\ntwo\rthree\r\nfour") == "one\r\ntwo\r\nthree\r\nfour")
        #expect(FileText.standard.normalizingLineBreaks("one\r\ntwo") == "one\ntwo")
    }
}

private final class BundleToken {}
