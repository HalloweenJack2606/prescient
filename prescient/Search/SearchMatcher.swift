import Foundation

nonisolated struct SearchMatcher: Sendable {
    struct InvalidPattern: LocalizedError {
        let pattern: String

        var errorDescription: String? {
            "Invalid regular expression: \(pattern)"
        }
    }

    private let expressions: [NSRegularExpression]

    init(texts: [String], caseSensitive: Bool, regex: Bool, wholeWord: Bool) throws {
        expressions = try texts.map { text in
            var pattern = regex ? text : NSRegularExpression.escapedPattern(for: text)

            if wholeWord {
                // NOTE: Mirrors grep -w: a match can't touch a word character on either side.
                pattern = "(?<!\\w)(?:\(pattern))(?!\\w)"
            }

            do {
                return try NSRegularExpression(pattern: pattern, options: caseSensitive ? [] : .caseInsensitive)
            } catch {
                throw InvalidPattern(pattern: text)
            }
        }
    }

    func matches(_ text: String) -> Bool {
        let range = NSRange(text.startIndex..., in: text)
        return expressions.contains { $0.firstMatch(in: text, range: range) != nil }
    }

    func ranges(in text: String) -> [Range<String.Index>] {
        let fullRange = NSRange(text.startIndex..., in: text)
        let ranges = expressions
            .flatMap { $0.matches(in: text, range: fullRange) }
            .compactMap { Range($0.range, in: text) }
            .filter { !$0.isEmpty }
            .sorted { $0.lowerBound < $1.lowerBound }

        return ranges.reduce(into: []) { merged, range in
            if let last = merged.last, range.lowerBound <= last.upperBound {
                merged[merged.count - 1] = last.lowerBound..<max(last.upperBound, range.upperBound)
            } else {
                merged.append(range)
            }
        }
    }
}
