import Foundation

/// How a text file is stored: its encoding, its byte order mark and its line breaks. Zeph#Ink reads a
/// file's text with this and writes it back the same way, so a file keeps its encoding and line
/// breaks whatever is typed into it.
nonisolated struct FileText: Equatable {
    var encoding: String.Encoding
    /// The bytes before the text that mark its encoding, if the file had them.
    var byteOrderMark: Data
    /// What new lines are made of: the first line break in the file, or `\n` if it has none.
    var lineBreak: String

    /// How new documents are stored: UTF-8 without a byte order mark, with `\n` line breaks.
    static let standard = FileText(encoding: .utf8, byteOrderMark: Data(), lineBreak: "\n")

    private static let marks: [(Data, String.Encoding)] = [
        (Data([0xEF, 0xBB, 0xBF]), .utf8),
        (Data([0xFF, 0xFE]), .utf16LittleEndian),
        (Data([0xFE, 0xFF]), .utf16BigEndian),
    ]

    /// Reads a file's text and how it's stored. Text without a byte order mark is read as UTF-8 if it
    /// is valid UTF-8, otherwise as the most likely single-byte encoding (Windows Latin 1, then Mac Roman).
    static func decode(_ data: Data) throws -> (text: String, format: FileText) {
        for (mark, encoding) in marks where data.starts(with: mark) {
            // Foundation would drop the mark silently while decoding, so take it off first and keep it.
            guard let text = String(data: data.dropFirst(mark.count), encoding: encoding) else { break }
            return (text, FileText(encoding: encoding, byteOrderMark: mark, lineBreak: lineBreak(in: text)))
        }
        if let text = String(data: data, encoding: .utf8) {
            return (text, FileText(encoding: .utf8, byteOrderMark: Data(), lineBreak: lineBreak(in: text)))
        }
        for encoding in [String.Encoding.windowsCP1252, .macOSRoman] {
            if let text = String(data: data, encoding: encoding) {
                return (text, FileText(encoding: encoding, byteOrderMark: Data(), lineBreak: lineBreak(in: text)))
            }
        }
        throw CocoaError(.fileReadInapplicableStringEncoding)
    }

    /// The text as this file stores it. Text the encoding can't hold (an emoji in a Latin 1 file)
    /// is saved as UTF-8 instead, rather than losing characters, and `format` says so.
    func encode(_ text: String) -> (data: Data, format: FileText) {
        if let data = text.data(using: encoding, allowLossyConversion: false) {
            return (byteOrderMark + data, self)
        }
        let format = FileText(encoding: .utf8, byteOrderMark: Data(), lineBreak: lineBreak)
        return (Data(text.utf8), format)
    }

    /// The first line break in the text: `\r\n`, `\r` or `\n`.
    static func lineBreak(in text: String) -> String {
        let ns = text as NSString
        let found = ns.rangeOfCharacter(from: CharacterSet(charactersIn: "\r\n"))
        guard found.location != NSNotFound, ns.character(at: found.location) == 0x0D else { return "\n" }
        return found.location + 1 < ns.length && ns.character(at: found.location + 1) == 0x0A ? "\r\n" : "\r"
    }

    /// Text with every line break changed to `lineBreak`, for pasting into a file that uses another kind.
    func normalizingLineBreaks(_ text: String) -> String {
        // Swift counts "\r\n" as one character, so look at the scalars to find any "\r".
        guard text.unicodeScalars.contains("\r") || lineBreak != "\n" else { return text }
        let unified = text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        return lineBreak == "\n" ? unified : unified.replacingOccurrences(of: "\n", with: lineBreak)
    }
}
