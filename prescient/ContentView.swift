import SwiftUI
import AppKit
import Darwin

struct GrepResult: Identifiable, Sendable {
    let filePath: String
    let absoluteFilePath: String
    let line: Int?
    let text: String

    let id = UUID()
}

struct SearchFolderAccess: Sendable {
    let url: URL
    let stopAccessing: @Sendable () -> Void
}

struct SearchTextField: Identifiable, Sendable {
    let id = UUID()
    var text = ""
}

struct ContentView: View {
    @AppStorage("searchFolder") private var folder = ""
    @AppStorage("fileFilter") private var fileFilter = ""
    @AppStorage("fileExclusions") private var fileExclusions = ""
    @AppStorage("searchSubfolders") private var searchSubfolders = true
    @AppStorage("caseSensitiveSearch") private var caseSensitiveSearch = true
    @AppStorage("searchFileNames") private var searchFileNames = false
    @AppStorage("searchFolderBookmark") private var folderBookmark = Data()
    @State private var searchText = ""
    @State private var additionalSearchTexts: [SearchTextField] = []
    @State private var results: [GrepResult] = []
    @State private var searchedFileCount: Int?
    @State private var isCountingSearchedFiles = false
    @State private var isSearching = false
    @State private var searchTask: Task<Void, Never>?
    @State private var currentSearchID: UUID?

    private var matchingFileCount: Int {
        Set(results.map(\.filePath)).count
    }

    private var searchSummary: String {
        let countStatus: String

        if isCountingSearchedFiles {
            countStatus = "searched files calculating..."
        } else if let searchedFileCount {
            countStatus = "of \(searchedFileCount) searched"
        } else {
            countStatus = "searched files not calculated"
        }

        if searchFileNames {
            return "Found \(matchingFileCount) matching files (\(countStatus))"
        }

        return "Found \(results.count) matching lines in \(matchingFileCount) files (\(countStatus))"
    }

    private var activeSearchTexts: [String] {
        ([searchText] + additionalSearchTexts.map(\.text))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    var body: some View {
        VStack(spacing: 12) {
            SearchBar(
                folder: $folder,
                fileFilter: $fileFilter,
                fileExclusions: $fileExclusions,
                searchSubfolders: $searchSubfolders,
                searchText: $searchText,
                additionalSearchTexts: $additionalSearchTexts,
                caseSensitiveSearch: $caseSensitiveSearch,
                searchFileNames: $searchFileNames,
                isSearching: isSearching,
                canStop: isSearching || isCountingSearchedFiles,
                onMoveUp: moveFolderUp,
                onBrowse: chooseFolder,
                onRun: runSearch,
                onStop: stopSearch
            )

            HStack {
                Text(searchSummary)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer()
            }

            ResultsTable(
                results: results,
                folder: folder,
                folderBookmark: folderBookmark,
                fileFilter: $fileFilter,
                fileExclusions: $fileExclusions,
                searchTexts: activeSearchTexts,
                searchSubfolders: searchSubfolders,
                caseSensitiveSearch: caseSensitiveSearch,
                searchFileNames: searchFileNames,
                onRun: runSearch
            )
        }
        .padding(16)
        .frame(minWidth: 900, minHeight: 560)
        .onDisappear {
            stopSearch()
        }
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false

        if panel.runModal() == .OK, let url = panel.url {
            folder = url.path
            saveBookmark(for: url)
        }
    }

    private func runSearch() {
        searchTask?.cancel()
        let searchID = UUID()
        currentSearchID = searchID
        results = []
        searchedFileCount = nil
        isCountingSearchedFiles = false

        let needles = activeSearchTexts

        guard !folder.isEmpty, !needles.isEmpty else {
            isSearching = false
            currentSearchID = nil
            return
        }

        guard let folderAccess = resolvedFolderAccess() else {
            isSearching = false
            currentSearchID = nil
            return
        }

        let filePatterns = FilePatternFilter.parse(includes: fileFilter, excludes: fileExclusions)
        let recursive = searchSubfolders
        let caseSensitive = caseSensitiveSearch
        let fileNameOnly = searchFileNames

        isSearching = true
        searchTask = Task {
            defer {
                folderAccess.stopAccessing()
            }

            let worker = Task.detached(priority: .userInitiated) {
                if fileNameOnly {
                    await SearchEngine.searchFileNames(
                        folder: folderAccess.url,
                        filePatterns: filePatterns,
                        texts: needles,
                        recursive: recursive,
                        caseSensitive: caseSensitive
                    ) { result in
                        await MainActor.run {
                            guard currentSearchID == searchID else { return }
                            results.append(result)
                        }
                    }
                } else {
                    await SearchEngine.search(
                        folder: folderAccess.url,
                        filePatterns: filePatterns,
                        texts: needles,
                        recursive: recursive,
                        caseSensitive: caseSensitive
                    ) { result in
                        await MainActor.run {
                            guard currentSearchID == searchID else { return }
                            results.append(result)
                        }
                    }
                }
            }

            await withTaskCancellationHandler {
                await worker.value

                await MainActor.run {
                    guard currentSearchID == searchID else { return }
                    isSearching = false
                    isCountingSearchedFiles = true
                }
            } onCancel: {
                worker.cancel()
            }

            guard !Task.isCancelled, currentSearchID == searchID else { return }

            let countWorker = Task.detached(priority: .utility) {
                SearchEngine.countSearchableFiles(
                    folder: folderAccess.url,
                    filePatterns: filePatterns,
                    recursive: recursive
                )
            }

            await withTaskCancellationHandler {
                let count = await countWorker.value

                await MainActor.run {
                    guard currentSearchID == searchID else { return }
                    searchedFileCount = count
                    isCountingSearchedFiles = false
                    currentSearchID = nil
                    searchTask = nil
                }
            } onCancel: {
                countWorker.cancel()
            }
        }
    }

    private func moveFolderUp() {
        guard !folder.isEmpty else {
            return
        }

        let currentURL = URL(fileURLWithPath: folder).standardizedFileURL
        let parentURL = currentURL.deletingLastPathComponent()

        guard parentURL.path != currentURL.path else {
            return
        }

        folder = parentURL.path
        saveBookmark(for: parentURL)
    }

    private func stopSearch() {
        searchTask?.cancel()
        searchTask = nil
        isSearching = false
        isCountingSearchedFiles = false
        currentSearchID = nil
    }

    private func saveBookmark(for url: URL) {
        do {
            folderBookmark = try url.bookmarkData(
                options: .withSecurityScope,
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
        } catch {
            folderBookmark = Data()
        }
    }

    private func resolvedFolderAccess() -> SearchFolderAccess? {
        if !folderBookmark.isEmpty {
            var isStale = false

            do {
                let url = try URL(
                    resolvingBookmarkData: folderBookmark,
                    options: .withSecurityScope,
                    relativeTo: nil,
                    bookmarkDataIsStale: &isStale
                )

                if isStale {
                    saveBookmark(for: url)
                }

                let didStartAccessing = url.startAccessingSecurityScopedResource()
                folder = url.path

                return SearchFolderAccess(url: url) {
                    if didStartAccessing {
                        url.stopAccessingSecurityScopedResource()
                    }
                }
            } catch {
                folderBookmark = Data()
            }
        }

        return SearchFolderAccess(url: URL(fileURLWithPath: folder)) {}
    }
}

struct SearchBar: View {
    @Binding var folder: String
    @Binding var fileFilter: String
    @Binding var fileExclusions: String
    @Binding var searchSubfolders: Bool
    @Binding var searchText: String
    @Binding var additionalSearchTexts: [SearchTextField]
    @Binding var caseSensitiveSearch: Bool
    @Binding var searchFileNames: Bool

    @State private var isFileOptionsExpanded = false

    let isSearching: Bool
    let canStop: Bool
    let onMoveUp: () -> Void
    let onBrowse: () -> Void
    let onRun: () -> Void
    let onStop: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                LabeledField(title: "Folder") {
                    HStack(spacing: 6) {
                        TextField("/path/to/folder", text: $folder)
                            .textFieldStyle(.plain)

                        Button(action: onMoveUp) {
                            ZStack(alignment: .topTrailing) {
                                Image(systemName: "folder")
                                Image(systemName: "arrow.up.circle.fill")
                                    .font(.system(size: 9))
                                    .offset(x: 3, y: -3)
                            }
                            .frame(width: 24, height: 24)
                        }
                        .buttonStyle(.borderless)
                        .help("Move up one folder")

                        Button(action: onBrowse) {
                            Image(systemName: "folder")
                        }
                        .buttonStyle(.borderless)
                        .help("Choose folder")
                    }
                }

                Toggle("Search Subfolders", isOn: $searchSubfolders)
                    .toggleStyle(.checkbox)
            }

            VStack(spacing: 8) {
                HStack(spacing: 10) {
                    LabeledField(title: "Files", showsMarker: !fileExclusions.isEmpty) {
                        TextField("*.cpp, *.h", text: $fileFilter)
                            .textFieldStyle(.plain)
                            .onSubmit(onRun)
                    }

                    Button(action: {
                        withAnimation(.easeInOut(duration: 0.16)) {
                            isFileOptionsExpanded.toggle()
                        }
                    }) {
                        Image(systemName: isFileOptionsExpanded ? "chevron.down" : "chevron.right")
                            .frame(width: 24, height: 24)
                    }
                    .buttonStyle(.borderless)
                    .help(isFileOptionsExpanded ? "Hide exclusions" : "Show exclusions")
                }

                if isFileOptionsExpanded {
                    LabeledField(title: "Exclude") {
                        TextField("generated, file.cpp~, .txt", text: $fileExclusions)
                            .textFieldStyle(.plain)
                            .onSubmit(onRun)
                    }
                }
            }

            VStack(spacing: 8) {
                HStack(spacing: 10) {
                    LabeledField(title: "Text") {
                        TextField("Text to find", text: $searchText)
                            .textFieldStyle(.plain)
                            .onSubmit(onRun)
                    }

                    Button(action: addSearchTextField) {
                        Label("Add", systemImage: "plus")
                            .frame(width: 72)
                    }

                    Button(action: onRun) {
                        Label(isSearching ? "Searching" : "Search", systemImage: "magnifyingglass")
                            .frame(width: 100)
                    }
                    .keyboardShortcut(.return, modifiers: .command)
                    .disabled(isSearching)

                    Button(action: onStop) {
                        Label("Stop", systemImage: "stop.fill")
                            .frame(width: 76)
                    }
                    .disabled(!canStop)

                    Toggle("Case Sensitive", isOn: $caseSensitiveSearch)
                        .toggleStyle(.checkbox)

                    Toggle("Search File Names", isOn: $searchFileNames)
                        .toggleStyle(.checkbox)
                }

                ForEach($additionalSearchTexts) { $searchTerm in
                    LabeledField(title: "") {
                        HStack(spacing: 6) {
                            TextField("Text to find", text: $searchTerm.text)
                                .textFieldStyle(.plain)
                                .onSubmit(onRun)

                            Button {
                                removeSearchTextField(searchTerm.id)
                            } label: {
                                Image(systemName: "xmark")
                                    .frame(width: 24, height: 24)
                            }
                            .buttonStyle(.borderless)
                            .help("Remove search text")
                        }
                    }
                }
            }
        }
        .padding(12)
        .glassEffect(.regular, in: .rect(cornerRadius: 12))
    }

    private func addSearchTextField() {
        additionalSearchTexts.append(SearchTextField())
    }

    private func removeSearchTextField(_ id: SearchTextField.ID) {
        additionalSearchTexts.removeAll { $0.id == id }
    }
}

struct LabeledField<Content: View>: View {
    let title: String
    var showsMarker = false
    @ViewBuilder let content: Content

    var body: some View {
        HStack(spacing: 8) {
            HStack(spacing: 1) {
                Text(title)
                    .foregroundStyle(.secondary)

                if showsMarker {
                    Text("*")
                        .foregroundStyle(.red)
                }
            }
            .font(.caption)
            .frame(width: 44, alignment: .trailing)

            content
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(.regularMaterial, in: .rect(cornerRadius: 6))
        }
    }
}

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

    private nonisolated static func tokens(from text: String) -> [String] {
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

enum SearchEngine {
    nonisolated static func grepCommand(folder: String, filePatterns: FilePatternFilter, texts: [String], recursive: Bool, caseSensitive: Bool) -> String {
        let folderURL = URL(fileURLWithPath: folder)
        let arguments = grepArguments(
            folder: folderURL,
            filePatterns: filePatterns,
            texts: texts,
            recursive: recursive,
            caseSensitive: caseSensitive
        )

        guard !arguments.isEmpty else {
            return ""
        }

        return ([URL(fileURLWithPath: "/usr/bin/grep").path] + arguments)
            .map(shellQuoted)
            .joined(separator: " ")
    }

    nonisolated static func fileNameSearchCommand(folder: String, texts: [String], caseSensitive: Bool) -> String {
        let activeTexts = normalizedSearchTexts(texts, caseSensitive: true)

        guard !folder.isEmpty, !activeTexts.isEmpty else {
            return ""
        }

        let grepArguments = (caseSensitive ? ["-F"] : ["-F", "-i"])
            + activeTexts.flatMap { ["-e", $0] }

        return "\(URL(fileURLWithPath: "/usr/bin/find").path) \(shellQuoted(folder)) -type f | \(URL(fileURLWithPath: "/usr/bin/grep").path) \(grepArguments.map(shellQuoted).joined(separator: " "))"
    }

    nonisolated static func countSearchableFiles(folder: URL, filePatterns: FilePatternFilter, recursive: Bool) -> Int {
        searchableFiles(folder: folder, filePatterns: filePatterns, recursive: recursive).count
    }

    nonisolated static func searchFileNames(
        folder: URL,
        filePatterns: FilePatternFilter,
        texts: [String],
        recursive: Bool,
        caseSensitive: Bool,
        onResult: @escaping @Sendable (GrepResult) async -> Void
    ) async {
        let activeTexts = normalizedSearchTexts(texts, caseSensitive: caseSensitive)

        guard !activeTexts.isEmpty else {
            return
        }

        let folderPath = folder.standardizedFileURL.path
        let keys: [URLResourceKey] = [.isDirectoryKey, .isRegularFileKey]

        guard let enumerator = FileManager.default.enumerator(
            at: folder,
            includingPropertiesForKeys: keys,
            options: [],
            errorHandler: { _, _ in true }
        ) else {
            return
        }

        for case let fileURL as URL in enumerator {
            if Task.isCancelled {
                break
            }

            let relativePath = relativePath(from: fileURL.standardizedFileURL.path, folderPath: folderPath)

            guard let resourceValues = try? fileURL.resourceValues(forKeys: Set(keys)) else {
                continue
            }

            if resourceValues.isDirectory == true {
                if !recursive {
                    enumerator.skipDescendants()
                    continue
                }

                if filePatterns.excludesDirectory(relativePath: relativePath) {
                    enumerator.skipDescendants()
                }

                continue
            }

            guard resourceValues.isRegularFile == true,
                  filePatterns.includes(relativePath: relativePath),
                  !filePatterns.excludes(relativePath: relativePath) else {
                continue
            }

            let fileName = fileURL.lastPathComponent
            let comparableName = caseSensitive ? fileName : fileName.lowercased()

            guard activeTexts.contains(where: { comparableName.contains($0) }) else {
                continue
            }

            await onResult(
                GrepResult(
                    filePath: relativePath,
                    absoluteFilePath: fileURL.standardizedFileURL.path,
                    line: nil,
                    text: fileName
                )
            )
        }
    }

    private nonisolated static func searchableFiles(folder: URL, filePatterns: FilePatternFilter, recursive: Bool) -> [URL] {
        let folderPath = folder.standardizedFileURL.path
        let keys: [URLResourceKey] = [.isDirectoryKey, .isRegularFileKey]

        guard let enumerator = FileManager.default.enumerator(
            at: folder,
            includingPropertiesForKeys: keys,
            options: [],
            errorHandler: { _, _ in true }
        ) else {
            return []
        }

        var files: [URL] = []

        for case let fileURL as URL in enumerator {
            if Task.isCancelled {
                break
            }

            let relativePath = relativePath(from: fileURL.standardizedFileURL.path, folderPath: folderPath)

            guard let resourceValues = try? fileURL.resourceValues(forKeys: Set(keys)) else {
                continue
            }

            if resourceValues.isDirectory == true {
                if !recursive {
                    enumerator.skipDescendants()
                    continue
                }

                if filePatterns.excludesDirectory(relativePath: relativePath) {
                    enumerator.skipDescendants()
                }

                continue
            }

            guard resourceValues.isRegularFile == true,
                  filePatterns.includes(relativePath: relativePath),
                  !filePatterns.excludes(relativePath: relativePath) else {
                continue
            }

            files.append(fileURL)
        }

        return files
    }

    nonisolated static func search(
        folder: URL,
        filePatterns: FilePatternFilter,
        texts: [String],
        recursive: Bool,
        caseSensitive: Bool,
        onResult: @escaping @Sendable (GrepResult) async -> Void
    ) async {
        let processBox = GrepProcessBox()

        await withTaskCancellationHandler {
            await runGrep(
                folder: folder,
                filePatterns: filePatterns,
                texts: texts,
                recursive: recursive,
                caseSensitive: caseSensitive,
                processBox: processBox,
                onResult: onResult
            )
        } onCancel: {
            processBox.terminate()
        }
    }

    private nonisolated static func runGrep(
        folder: URL,
        filePatterns: FilePatternFilter,
        texts: [String],
        recursive: Bool,
        caseSensitive: Bool,
        processBox: GrepProcessBox,
        onResult: @escaping @Sendable (GrepResult) async -> Void
    ) async {
        let process = Process()
        let outputPipe = Pipe()
        let arguments = grepArguments(folder: folder, filePatterns: filePatterns, texts: texts, recursive: recursive, caseSensitive: caseSensitive)

        guard !arguments.isEmpty else {
            return
        }

        process.executableURL = URL(fileURLWithPath: "/usr/bin/grep")
        process.arguments = arguments
        process.standardOutput = outputPipe
        process.standardError = Pipe()

        do {
            try process.run()
        } catch {
            return
        }

        processBox.set(process)
        defer {
            processBox.clear()
            try? outputPipe.fileHandleForReading.close()
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

    private nonisolated static func relativePath(from path: String, folderPath: String) -> String {
        let normalizedFolder = folderPath.hasSuffix("/") ? folderPath : "\(folderPath)/"

        if path.hasPrefix(normalizedFolder) {
            return String(path.dropFirst(normalizedFolder.count))
        }

        if path == folderPath {
            return URL(fileURLWithPath: path).lastPathComponent
        }

        return path
    }

    private nonisolated static func grepArguments(folder: URL, filePatterns: FilePatternFilter, texts: [String], recursive: Bool, caseSensitive: Bool) -> [String] {
        let activeTexts = normalizedSearchTexts(texts, caseSensitive: true)

        guard !activeTexts.isEmpty else {
            return []
        }

        var arguments = [
            "-n",
            "-H",
            "-I",
            "-F",
            "-s",
            "--line-buffered",
            "--exclude-dir=.git",
            "--exclude-dir=.build",
            "--exclude-dir=DerivedData"
        ]

        if !caseSensitive {
            arguments.append("-i")
        }

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

    private nonisolated static func normalizedSearchTexts(_ texts: [String], caseSensitive: Bool) -> [String] {
        texts
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .map { caseSensitive ? $0 : $0.lowercased() }
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

struct ResultsTable: View {
    let results: [GrepResult]
    let folder: String
    let folderBookmark: Data
    @Binding var fileFilter: String
    @Binding var fileExclusions: String
    let searchTexts: [String]
    let searchSubfolders: Bool
    let caseSensitiveSearch: Bool
    let searchFileNames: Bool
    let onRun: () -> Void
    @State private var selection = Set<GrepResult.ID>()

    var body: some View {
        Table(results, selection: $selection) {
            TableColumn("File") { result in
                resultCell(result.filePath, result: result)
            }
            TableColumn("Line") { result in
                resultCell(result.line.map(String.init) ?? "", result: result)
            }
            .width(min: 56, ideal: 56, max: 56)
            TableColumn("Text") { result in
                resultCell(result.text, result: result)
            }
        }
    }

    private func resultCell(_ text: String, result: GrepResult) -> some View {
        Text(text)
            .contentShape(Rectangle())
            .contextMenu {
                Button {
                    selection = [result.id]
                    EmacsOpener.open(result, folder: folder, folderBookmark: folderBookmark)
                } label: {
                    Label("Open in Emacs", systemImage: "arrow.up.forward.app")
                }

                Button {
                    selection = [result.id]
                    openEnclosingFolder(for: result)
                } label: {
                    Label("Open in Enclosing Folder", systemImage: "folder")
                }

                Divider()

                Button {
                    selection = [result.id]
                    copy(result.absoluteFilePath)
                } label: {
                    Label("Copy File Path", systemImage: "doc.on.doc")
                }

                Button {
                    selection = [result.id]
                    copy(result.text)
                } label: {
                    Label("Copy Match", systemImage: "text.quote")
                }

                Divider()

                Button {
                    selection = [result.id]
                    openTerminalHere(for: result)
                } label: {
                    Label("Open in Terminal Here", systemImage: "terminal")
                }

                Button {
                    selection = [result.id]
                    searchThisFileOnly(result)
                } label: {
                    Label("Search This File Only", systemImage: "doc.text.magnifyingglass")
                }

                Button {
                    selection = [result.id]
                    copyGrepCommand()
                } label: {
                    Label("Copy Grep Command", systemImage: "curlybraces")
                }

                Divider()

                Button {
                    selection = [result.id]
                    excludeThisFile(result)
                } label: {
                    Label("Exclude This File", systemImage: "doc.badge.minus")
                }

                Button {
                    selection = [result.id]
                    excludeThisFolder(result)
                } label: {
                    Label("Exclude This Folder", systemImage: "folder.badge.minus")
                }
            }
            .simultaneousGesture(
                TapGesture()
                    .onEnded {
                        selection = [result.id]
                    }
            )
            .simultaneousGesture(
                TapGesture(count: 2)
                    .onEnded {
                        selection = [result.id]
                        EmacsOpener.open(result, folder: folder, folderBookmark: folderBookmark)
                    }
            )
    }

    private func openEnclosingFolder(for result: GrepResult) {
        let fileURL = URL(fileURLWithPath: result.absoluteFilePath)
        NSWorkspace.shared.activateFileViewerSelecting([fileURL])
    }

    private func copy(_ value: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(value, forType: .string)
    }

    private func openTerminalHere(for result: GrepResult) {
        let folderURL = URL(fileURLWithPath: result.absoluteFilePath).deletingLastPathComponent()
        let process = Process()

        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = ["-a", "Terminal", folderURL.path]

        try? process.run()
    }

    private func searchThisFileOnly(_ result: GrepResult) {
        fileFilter = result.filePath
        onRun()
    }

    private func copyGrepCommand() {
        if searchFileNames {
            copy(
                SearchEngine.fileNameSearchCommand(
                    folder: folder,
                    texts: searchTexts,
                    caseSensitive: caseSensitiveSearch
                )
            )
            return
        }

        let filePatterns = FilePatternFilter.parse(includes: fileFilter, excludes: fileExclusions)

        copy(
            SearchEngine.grepCommand(
                folder: folder,
                filePatterns: filePatterns,
                texts: searchTexts,
                recursive: searchSubfolders,
                caseSensitive: caseSensitiveSearch
            )
        )
    }

    private func excludeThisFile(_ result: GrepResult) {
        appendExclusion(result.filePath)
    }

    private func excludeThisFolder(_ result: GrepResult) {
        let components = result.filePath.split(separator: "/").map(String.init)

        guard components.count > 1 else {
            return
        }

        appendExclusion("\(components.dropLast().joined(separator: "/"))/")
    }

    private func appendExclusion(_ value: String) {
        let existingValues = Set(
            fileExclusions
                .split { character in
                    character == "," || character == ";" || character.isWhitespace
                }
                .map(String.init)
        )

        guard !existingValues.contains(value) else {
            return
        }

        if fileExclusions.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            fileExclusions = value
        } else {
            fileExclusions += ", \(value)"
        }
    }
}
