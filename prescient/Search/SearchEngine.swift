import Foundation

struct SearchQuery: Sendable {
    let texts: [String]
    let filePatterns: FilePatternFilter
    let recursive: Bool
    let caseSensitive: Bool
    let regex: Bool
    let wholeWord: Bool
    let fileNamesOnly: Bool
    let matcher: SearchMatcher

    init(texts: [String], filePatterns: FilePatternFilter, recursive: Bool, caseSensitive: Bool, regex: Bool, wholeWord: Bool, fileNamesOnly: Bool) throws {
        self.texts = texts
        self.filePatterns = filePatterns
        self.recursive = recursive
        self.caseSensitive = caseSensitive
        self.regex = regex
        self.wholeWord = wholeWord
        self.fileNamesOnly = fileNamesOnly
        matcher = try SearchMatcher(texts: texts, caseSensitive: caseSensitive, regex: regex, wholeWord: wholeWord)
    }
}

enum SearchEngine {
    nonisolated static func grepCommand(_ query: SearchQuery, folder: String) -> String {
        let arguments = grepArguments(query, folder: URL(fileURLWithPath: folder))

        guard !arguments.isEmpty else {
            return ""
        }

        return ([URL(fileURLWithPath: "/usr/bin/grep").path] + arguments)
            .map(shellQuoted)
            .joined(separator: " ")
    }

    nonisolated static func fileNameSearchCommand(_ query: SearchQuery, folder: String) -> String {
        let activeTexts = normalizedSearchTexts(query.texts)

        guard !folder.isEmpty, !activeTexts.isEmpty else {
            return ""
        }

        let grepArguments = matchOptions(query) + activeTexts.flatMap { ["-e", $0] }

        return "\(URL(fileURLWithPath: "/usr/bin/find").path) \(shellQuoted(folder)) -type f | \(URL(fileURLWithPath: "/usr/bin/grep").path) \(grepArguments.map(shellQuoted).joined(separator: " "))"
    }

    nonisolated static func countSearchableFiles(folder: URL, filePatterns: FilePatternFilter, recursive: Bool) -> Int {
        searchableFiles(folder: folder, filePatterns: filePatterns, recursive: recursive).count
    }

    // NOTE: Returns grep's error message when it fails, e.g. on a pattern it can't parse.
    nonisolated static func run(
        _ query: SearchQuery,
        folder: URL,
        onResult: @escaping @Sendable (GrepResult) async -> Void
    ) async -> String? {
        if query.fileNamesOnly {
            await searchFileNames(query, folder: folder, onResult: onResult)
            return nil
        }

        return await search(query, folder: folder, onResult: onResult)
    }

    private nonisolated static func searchFileNames(
        _ query: SearchQuery,
        folder: URL,
        onResult: @escaping @Sendable (GrepResult) async -> Void
    ) async {
        for file in SearchableFiles(folder: folder, filePatterns: query.filePatterns, recursive: query.recursive) {
            let fileName = file.url.lastPathComponent

            guard query.matcher.matches(fileName) else {
                continue
            }

            await onResult(
                GrepResult(
                    filePath: file.relativePath,
                    absoluteFilePath: file.url.standardizedFileURL.path,
                    line: nil,
                    text: fileName
                )
            )
        }
    }

    private nonisolated static func searchableFiles(folder: URL, filePatterns: FilePatternFilter, recursive: Bool) -> [URL] {
        SearchableFiles(folder: folder, filePatterns: filePatterns, recursive: recursive).map(\.url)
    }

    private nonisolated static func search(
        _ query: SearchQuery,
        folder: URL,
        onResult: @escaping @Sendable (GrepResult) async -> Void
    ) async -> String? {
        let processBox = GrepProcessBox()

        return await withTaskCancellationHandler {
            await runGrep(query, folder: folder, processBox: processBox, onResult: onResult)
        } onCancel: {
            processBox.terminate()
        }
    }

    private nonisolated static func runGrep(
        _ query: SearchQuery,
        folder: URL,
        processBox: GrepProcessBox,
        onResult: @escaping @Sendable (GrepResult) async -> Void
    ) async -> String? {
        let process = Process()
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        let filePatterns = query.filePatterns
        let arguments = grepArguments(query, folder: folder)

        guard !arguments.isEmpty else {
            return nil
        }

        process.executableURL = URL(fileURLWithPath: "/usr/bin/grep")
        process.arguments = arguments
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        do {
            try process.run()
        } catch {
            return error.localizedDescription
        }

        processBox.set(process)
        defer {
            processBox.clear()
            try? outputPipe.fileHandleForReading.close()
            try? errorPipe.fileHandleForReading.close()
        }

        var partialLine = ""
        let folderPath = folder.standardizedFileURL.path

        while !Task.isCancelled {
            let data = outputPipe.fileHandleForReading.availableData

            if data.isEmpty {
                break
            }

            partialLine += String(decoding: data, as: UTF8.self)

            while let newlineRange = partialLine.range(of: "\n") {
                let line = String(partialLine[..<newlineRange.lowerBound])
                partialLine.removeSubrange(...newlineRange.lowerBound)
                await emit(line: line, folderPath: folderPath, filePatterns: filePatterns, onResult: onResult)
            }
        }

        if !Task.isCancelled, !partialLine.isEmpty {
            await emit(line: partialLine, folderPath: folderPath, filePatterns: filePatterns, onResult: onResult)
        }

        process.waitUntilExit()

        // NOTE: Exit status 2 is a grep error; -s keeps unreadable-file noise out of stderr.
        guard !Task.isCancelled, process.terminationStatus == 2 else {
            return nil
        }

        let message = String(decoding: errorPipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return message.isEmpty ? nil : message
    }

    private nonisolated static func emit(
        line: String,
        folderPath: String,
        filePatterns: FilePatternFilter,
        onResult: @escaping @Sendable (GrepResult) async -> Void
    ) async {
        guard let result = parse(line: line, folderPath: folderPath),
              filePatterns.includes(relativePath: result.filePath),
              !filePatterns.excludes(relativePath: result.filePath) else {
            return
        }

        await onResult(result)
    }

    private nonisolated static func parse(line: String, folderPath: String) -> GrepResult? {
        let parts = line.split(separator: ":", maxSplits: 2, omittingEmptySubsequences: false)

        guard parts.count == 3,
              let lineNumber = Int(parts[1]) else {
            return nil
        }

        let absoluteFilePath = String(parts[0])
        let filePath = relativePath(from: absoluteFilePath, folderPath: folderPath)

        return GrepResult(
            filePath: filePath,
            absoluteFilePath: absoluteFilePath,
            line: lineNumber,
            text: String(parts[2])
        )
    }

    fileprivate nonisolated static func relativePath(from path: String, folderPath: String) -> String {
        let normalizedFolder = folderPath.hasSuffix("/") ? folderPath : "\(folderPath)/"

        if path.hasPrefix(normalizedFolder) {
            return String(path.dropFirst(normalizedFolder.count))
        }

        if path == folderPath {
            return URL(fileURLWithPath: path).lastPathComponent
        }

        return path
    }

    private nonisolated static func grepArguments(_ query: SearchQuery, folder: URL) -> [String] {
        let activeTexts = normalizedSearchTexts(query.texts)
        let filePatterns = query.filePatterns
        let recursive = query.recursive

        guard !activeTexts.isEmpty else {
            return []
        }

        var arguments = [
            "-n",
            "-H",
            "-I",
            "-s",
            "--line-buffered",
            "--exclude-dir=.git",
            "--exclude-dir=.build",
            "--exclude-dir=DerivedData"
        ] + matchOptions(query)

        if recursive {
            arguments.insert("-R", at: 0)
        }

        if recursive, !filePatterns.allowsAllFiles {
            arguments.append(contentsOf: filePatterns.grepIncludePatterns.map { "--include=\($0)" })
        }

        if recursive {
            arguments.append(contentsOf: filePatterns.grepExcludePatterns.map { "--exclude=\($0)" })
            arguments.append(contentsOf: filePatterns.grepExcludeDirPatterns.map { "--exclude-dir=\($0)" })
        }

        for text in activeTexts {
            arguments.append("-e")
            arguments.append(text)
        }

        if recursive {
            arguments.append(folder.path)
        } else {
            let files = searchableFiles(folder: folder, filePatterns: filePatterns, recursive: false)

            guard !files.isEmpty else {
                return []
            }

            arguments.append(contentsOf: files.map(\.path))
        }

        return arguments
    }

    private nonisolated static func matchOptions(_ query: SearchQuery) -> [String] {
        [query.regex ? "-E" : "-F"]
            + (query.wholeWord ? ["-w"] : [])
            + (query.caseSensitive ? [] : ["-i"])
    }

    private nonisolated static func normalizedSearchTexts(_ texts: [String]) -> [String] {
        texts
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private nonisolated static func shellQuoted(_ value: String) -> String {
        if value.rangeOfCharacter(from: CharacterSet(charactersIn: " \t\n'\"\\$&;()<>|*?[]{}!")) == nil {
            return value
        }

        return "'\(value.replacingOccurrences(of: "'", with: "'\\''"))'"
    }
}

private final class GrepProcessBox: @unchecked Sendable {
    nonisolated private let lock = NSLock()
    nonisolated(unsafe) private var process: Process?

    nonisolated init() {}

    nonisolated func set(_ process: Process) {
        lock.lock()
        self.process = process
        lock.unlock()
    }

    nonisolated func terminate() {
        lock.lock()
        let process = process
        lock.unlock()

        if process?.isRunning == true {
            process?.terminate()
        }
    }

    nonisolated func clear() {
        lock.lock()
        process = nil
        lock.unlock()
    }
}

nonisolated private struct SearchableFiles: Sequence, IteratorProtocol {
    private static let keys: [URLResourceKey] = [.isDirectoryKey, .isRegularFileKey]

    private let enumerator: FileManager.DirectoryEnumerator?
    private let folderPath: String
    private let filePatterns: FilePatternFilter
    private let recursive: Bool

    init(folder: URL, filePatterns: FilePatternFilter, recursive: Bool) {
        enumerator = FileManager.default.enumerator(
            at: folder,
            includingPropertiesForKeys: Self.keys,
            options: [],
            errorHandler: { _, _ in true }
        )
        folderPath = folder.standardizedFileURL.path
        self.filePatterns = filePatterns
        self.recursive = recursive
    }

    mutating func next() -> (url: URL, relativePath: String)? {
        while let fileURL = enumerator?.nextObject() as? URL {
            if Task.isCancelled {
                return nil
            }

            let relativePath = SearchEngine.relativePath(from: fileURL.standardizedFileURL.path, folderPath: folderPath)

            guard let resourceValues = try? fileURL.resourceValues(forKeys: Set(Self.keys)) else {
                continue
            }

            if resourceValues.isDirectory == true {
                if !recursive || filePatterns.excludesDirectory(relativePath: relativePath) {
                    enumerator?.skipDescendants()
                }

                continue
            }

            if resourceValues.isRegularFile == true,
               filePatterns.includes(relativePath: relativePath),
               !filePatterns.excludes(relativePath: relativePath) {
                return (fileURL, relativePath)
            }
        }

        return nil
    }
}
