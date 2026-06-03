import SwiftUI
import AppKit
import Darwin

struct GrepResult: Identifiable, Sendable {
    let filePath: String
    let absoluteFilePath: String
    let line: Int
    let text: String

    let id = UUID()
}

struct SearchFolderAccess: Sendable {
    let url: URL
    let stopAccessing: @Sendable () -> Void
}

struct ContentView: View {
    @AppStorage("searchFolder") private var folder = ""
    @AppStorage("fileFilter") private var fileFilter = ""
    @AppStorage("fileExclusions") private var fileExclusions = ""
    @AppStorage("searchFolderBookmark") private var folderBookmark = Data()
    @State private var searchText = ""
    @State private var results: [GrepResult] = []
    @State private var isSearching = false
    @State private var searchTask: Task<Void, Never>?

    var body: some View {
        VStack(spacing: 12) {
            SearchBar(
                folder: $folder,
                fileFilter: $fileFilter,
                fileExclusions: $fileExclusions,
                searchText: $searchText,
                isSearching: isSearching,
                onBrowse: chooseFolder,
                onRun: runSearch
            )

            ResultsTable(
                results: results,
                folder: folder,
                folderBookmark: folderBookmark
            )
        }
        .padding(16)
        .frame(minWidth: 900, minHeight: 560)
        .onDisappear {
            searchTask?.cancel()
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
        results = []

        guard !folder.isEmpty, !searchText.isEmpty else {
            return
        }

        guard let folderAccess = resolvedFolderAccess() else {
            return
        }

        let filePatterns = FilePatternFilter.parse(includes: fileFilter, excludes: fileExclusions)
        let needle = searchText

        isSearching = true
        searchTask = Task {
            let matches = await Task.detached(priority: .userInitiated) {
                SearchEngine.search(folder: folderAccess.url, filePatterns: filePatterns, text: needle)
            }.value
            folderAccess.stopAccessing()

            guard !Task.isCancelled else { return }
            results = matches
            isSearching = false
        }
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
    @Binding var searchText: String

    @State private var isFileOptionsExpanded = false

    let isSearching: Bool
    let onBrowse: () -> Void
    let onRun: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                LabeledField(title: "Folder") {
                    HStack(spacing: 6) {
                        TextField("/path/to/folder", text: $folder)
                            .textFieldStyle(.plain)

                        Button(action: onBrowse) {
                            Image(systemName: "folder")
                        }
                        .buttonStyle(.borderless)
                            .help("Choose folder")
                    }
                }
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

            HStack(spacing: 10) {
                LabeledField(title: "Text") {
                    TextField("Text to find", text: $searchText)
                        .textFieldStyle(.plain)
                        .onSubmit(onRun)
                }

                Button(action: onRun) {
                    Label(isSearching ? "Searching" : "Run", systemImage: "magnifyingglass")
                        .frame(width: 100)
                }
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(isSearching)
            }
        }
        .padding(12)
        .glassEffect(.regular, in: .rect(cornerRadius: 12))
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
    let allowsAllFiles: Bool

    nonisolated var grepExcludePatterns: [String] {
        excludePatterns.filter { !$0.contains("/") }
    }

    nonisolated func excludes(relativePath: String) -> Bool {
        let basename = URL(fileURLWithPath: relativePath).lastPathComponent

        return excludePatterns.contains { pattern in
            if pattern.contains("/") {
                return pathMatches(pattern: pattern, value: relativePath)
            }

            return pathMatches(pattern: pattern, value: basename)
        }
    }

    nonisolated static func parse(includes: String, excludes: String) -> FilePatternFilter {
        let includePatterns = tokens(from: includes).map(normalizeInclude)
        let excludePatterns = tokens(from: excludes).flatMap(normalizeExclude)

        return FilePatternFilter(
            includePatterns: includePatterns,
            excludePatterns: excludePatterns,
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

        if pattern.contains("*") || pattern.contains("?") {
            return pattern
        }

        return "*.\(pattern.trimmingCharacters(in: CharacterSet(charactersIn: ".")))"
    }

    private nonisolated static func normalizeExclude(_ pattern: String) -> [String] {
        if pattern == "*" || pattern == "*.*" {
            return [pattern]
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

    private nonisolated func pathMatches(pattern: String, value: String) -> Bool {
        fnmatch(pattern, value, FNM_PATHNAME) == 0
    }
}

enum SearchEngine {
    nonisolated static func search(folder: URL, filePatterns: FilePatternFilter, text: String) -> [GrepResult] {
        let output = runGrep(folder: folder, filePatterns: filePatterns, text: text)
        return parse(output: output, relativeTo: folder)
            .filter { !filePatterns.excludes(relativePath: $0.filePath) }
    }

    private nonisolated static func runGrep(folder: URL, filePatterns: FilePatternFilter, text: String) -> String {
        let process = Process()
        let outputPipe = Pipe()

        var arguments = [
            "-R",
            "-n",
            "-H",
            "-I",
            "-F",
            "-s",
            "--exclude-dir=.git",
            "--exclude-dir=.build",
            "--exclude-dir=DerivedData"
        ]

        if !filePatterns.allowsAllFiles {
            arguments.append(contentsOf: filePatterns.includePatterns.map { "--include=\($0)" })
        }

        arguments.append(contentsOf: filePatterns.grepExcludePatterns.map { "--exclude=\($0)" })

        arguments.append(text)
        arguments.append(folder.path)

        process.executableURL = URL(fileURLWithPath: "/usr/bin/grep")
        process.arguments = arguments
        process.standardOutput = outputPipe
        process.standardError = Pipe()

        do {
            try process.run()
        } catch {
            return ""
        }

        let data = outputPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        return String(data: data, encoding: .utf8) ?? ""
    }

    private nonisolated static func parse(output: String, relativeTo folder: URL) -> [GrepResult] {
        if output.isEmpty {
            return []
        }

        var results: [GrepResult] = []
        let lines = output.split(separator: "\n", omittingEmptySubsequences: false)
        let folderPath = folder.standardizedFileURL.path

        for line in lines {
            let parts = line.split(separator: ":", maxSplits: 2, omittingEmptySubsequences: false)

            guard parts.count == 3,
                  let lineNumber = Int(parts[1]) else {
                continue
            }

            let filePath = relativePath(from: String(parts[0]), folderPath: folderPath)
            let absoluteFilePath = String(parts[0])

            results.append(
                GrepResult(
                    filePath: filePath,
                    absoluteFilePath: absoluteFilePath,
                    line: lineNumber,
                    text: String(parts[2])
                )
            )
        }

        return results
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
}

struct ResultsTable: View {
    let results: [GrepResult]
    let folder: String
    let folderBookmark: Data
    @State private var selection = Set<GrepResult.ID>()

    var body: some View {
        Table(results, selection: $selection) {
            TableColumn("File") { result in
                resultCell(result.filePath, result: result)
            }
                .width(min: 180, ideal: 240, max: 320)
            TableColumn("Line") { result in
                resultCell("\(result.line)", result: result)
            }
            .width(48)
            TableColumn("Text") { result in
                resultCell(result.text, result: result)
            }
        }
    }

    private func resultCell(_ text: String, result: GrepResult) -> some View {
        Text(text)
            .contentShape(Rectangle())
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
}
