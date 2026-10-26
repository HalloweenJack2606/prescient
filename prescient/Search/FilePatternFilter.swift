import Foundation
import Darwin

struct FilePatternFilter: Sendable {
    let includePatterns: [String]
    let excludePatterns: [String]
    let excludeDirPatterns: [String]
    let allowsAllFiles: Bool

    nonisolated var grepIncludePatterns: [String] {
        includePatterns.map { pattern in
            if pattern.contains("/") {
                return URL(fileURLWithPath: pattern).lastPathComponent
            }

            return pattern
        }
    }

    nonisolated var grepExcludePatterns: [String] {
        excludePatterns.filter { !$0.contains("/") }
    }

    nonisolated var grepExcludeDirPatterns: [String] {
        excludeDirPatterns.filter { !$0.contains("/") }
    }

    nonisolated func includes(relativePath: String) -> Bool {
        guard !allowsAllFiles else {
            return true
        }

        let basename = URL(fileURLWithPath: relativePath).lastPathComponent

        return includePatterns.contains { pattern in
            if pattern.contains("/") {
                return pathMatches(pattern: pattern, value: relativePath)
            }

            return pathMatches(pattern: pattern, value: basename)
        }
    }

    nonisolated func excludes(relativePath: String) -> Bool {
        let basename = URL(fileURLWithPath: relativePath).lastPathComponent

        if isInExcludedDirectory(relativePath: relativePath) {
            return true
        }

        return excludePatterns.contains { pattern in
            if pattern.contains("/") {
                return pathMatches(pattern: pattern, value: relativePath)
            }

            return pathMatches(pattern: pattern, value: basename)
        }
    }

    nonisolated func excludesDirectory(relativePath: String) -> Bool {
        let normalizedPath = relativePath.trimmingCharacters(in: CharacterSet(charactersIn: "/"))

        guard !normalizedPath.isEmpty else {
            return false
        }

        let components = normalizedPath.split(separator: "/").map(String.init)

        return excludeDirPatterns.contains { pattern in
            if pattern.contains("/") {
                return pathMatches(pattern: pattern, value: normalizedPath)
                    || pathMatches(pattern: pattern, value: "\(normalizedPath)/")
                    || pathMatches(pattern: pattern, value: "\(normalizedPath)/_")
            }

            return components.contains { component in
                pathMatches(pattern: pattern, value: component)
            }
        }
    }

    nonisolated static func parse(includes: String, excludes: String) -> FilePatternFilter {
        let excludeTokens = tokens(from: excludes)
        let includePatterns = tokens(from: includes).map(normalizeInclude)
        let excludePatterns = excludeTokens.flatMap(normalizeExclude)
        let excludeDirPatterns = excludeTokens.flatMap(normalizeExcludeDirectory)

        return FilePatternFilter(
            includePatterns: includePatterns,
            excludePatterns: excludePatterns,
            excludeDirPatterns: excludeDirPatterns,
            allowsAllFiles: includePatterns.isEmpty || includePatterns.contains("*") || includePatterns.contains("*.*")
        )
    }

    nonisolated static func tokens(from text: String) -> [String] {
        text
            .split { character in
                character == "," || character == ";" || character.isWhitespace
            }
            .map { token in
                String(token).trimmingCharacters(in: .whitespacesAndNewlines)
            }
            .filter { !$0.isEmpty }
    }

    private nonisolated static func normalizeInclude(_ pattern: String) -> String {
        if pattern == "*" || pattern == "*.*" {
            return pattern
        }

        if pattern.contains("/") {
            return pattern
        }

        if pattern.contains("*") || pattern.contains("?") {
            return pattern
        }

        return "*.\(pattern.trimmingCharacters(in: CharacterSet(charactersIn: ".")))"
    }

    private nonisolated static func normalizeExclude(_ pattern: String) -> [String] {
        if pattern == "*" || pattern == "*.*" {
            return [pattern]
        }

        if pattern.hasSuffix("/") {
            return []
        }

        if pattern.hasPrefix("."), !pattern.contains("*"), !pattern.contains("?"), !pattern.contains("/") {
            return ["*\(pattern)"]
        }

        if pattern.contains("*") || pattern.contains("?") || pattern.contains(".") || pattern.contains("/") {
            return [pattern]
        }

        let extensionPattern = "*.\(pattern.trimmingCharacters(in: CharacterSet(charactersIn: ".")))"
        return [pattern, extensionPattern]
    }

    private nonisolated static func normalizeExcludeDirectory(_ pattern: String) -> [String] {
        let trimmedPattern = pattern.trimmingCharacters(in: CharacterSet(charactersIn: "/"))

        guard !trimmedPattern.isEmpty,
              trimmedPattern != "*",
              trimmedPattern != "*.*" else {
            return []
        }

        if pattern.hasSuffix("/"), trimmedPattern.contains("/") {
            return ["\(trimmedPattern)/*"]
        }

        if trimmedPattern.contains("/") {
            return [trimmedPattern]
        }

        return [trimmedPattern]
    }

    private nonisolated func isInExcludedDirectory(relativePath: String) -> Bool {
        let components = relativePath.split(separator: "/").map(String.init)

        guard components.count > 1 else {
            return false
        }

        let directoryComponents = components.dropLast()

        return excludeDirPatterns.contains { pattern in
            if pattern.contains("/") {
                return pathMatches(pattern: pattern, value: relativePath)
            }

            return directoryComponents.contains { component in
                pathMatches(pattern: pattern, value: component)
            }
        }
    }

    private nonisolated func pathMatches(pattern: String, value: String) -> Bool {
        fnmatch(pattern, value, FNM_PATHNAME) == 0
    }
}
