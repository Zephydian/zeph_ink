import Foundation
import Observation

/// The numbers the status bar shows for one document: its words and characters, and the selection's.
/// Words are counted the way macOS splits text into words, so markdown symbols (`##`, `**`, `-`) don't
/// count, and neither do the addresses of links.
@Observable
final class DocumentStats {
    private(set) var words = 0
    private(set) var characters = 0
    /// The selection's words, or nil with nothing selected.
    private(set) var selectedWords: Int?
    /// The word-count goal, if one is set.
    var goal: Int?

    /// About how long reading takes, at 230 words a minute (at least a minute).
    var readingMinutes: Int { max(1, Int((Double(words) / 230).rounded())) }

    @ObservationIgnored private var pending: DispatchWorkItem?

    /// Counts again a moment after typing pauses, so long documents stay smooth to type in.
    func textDidChange(_ text: @escaping () -> String) {
        pending?.cancel()
        let count = DispatchWorkItem { [weak self] in self?.count(text()) }
        pending = count
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: count)
    }

    func count(_ text: String) {
        let (words, characters) = Self.measure(text)
        if self.words != words { self.words = words }
        if self.characters != characters { self.characters = characters }
    }

    func selectionDidChange(_ selected: String?) {
        let words = selected.flatMap { $0.isEmpty ? nil : Self.measure($0).words }
        if selectedWords != words { selectedWords = words }
    }

    /// Words, and characters other than spaces and line breaks, leaving out link addresses.
    static func measure(_ text: String) -> (words: Int, characters: Int) {
        let readable = text.replacingOccurrences(of: #"\]\([^)\s]*\)"#, with: "]", options: .regularExpression)
        var words = 0
        readable.enumerateSubstrings(in: readable.startIndex..., options: [.byWords, .substringNotRequired]) { _, _, _, _ in
            words += 1
        }
        let characters = readable.unicodeScalars.reduce(0) { $0 + (CharacterSet.whitespacesAndNewlines.contains($1) ? 0 : 1) }
        return (words, characters)
    }
}

/// Word-count goals, one per saved file, kept in the app's settings (never in the file itself).
enum WordGoals {
    private static let key = "wordGoals"

    static func goal(for url: URL?) -> Int? {
        guard let path = url?.standardizedFileURL.path else { return nil }
        return (UserDefaults.standard.dictionary(forKey: key) as? [String: Int])?[path]
    }

    static func set(_ goal: Int?, for url: URL?) {
        guard let path = url?.standardizedFileURL.path else { return }
        var goals = UserDefaults.standard.dictionary(forKey: key) as? [String: Int] ?? [:]
        goals[path] = goal.flatMap { $0 > 0 ? $0 : nil }
        UserDefaults.standard.set(goals, forKey: key)
    }
}
