import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct ContentView: View {
    @State private var workspaces = WorkspaceStore()
    @State private var search = SearchController()
    @State private var searchText = ""
    @State private var additionalSearchTexts: [SearchTextField] = []

    private var settings: WorkspaceSettings {
        workspaces.settings
    }

    private var activeSearchTexts: [String] {
        ([searchText] + additionalSearchTexts.map(\.text))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    var body: some View {
        VStack(spacing: 12) {
            SearchBar(
                settings: $workspaces.settings,
                searchText: $searchText,
                additionalSearchTexts: $additionalSearchTexts,
                recentSearches: workspaces.recentSearches,
                isSearching: search.isSearching,
                canStop: search.canStop,
                onMoveUp: moveFolderUp,
                onBrowse: chooseFolder,
                onRun: runSearch,
                onStop: search.stop,
                onSelectRecent: applyRecentSearch,
                onClearRecent: workspaces.clearRecentSearches
            )

            HStack {
                Text(search.summary(fileNamesOnly: settings.searchFileNames))
                    .font(.caption)
                    .foregroundStyle(search.errorMessage == nil ? Color.secondary : Color.red)

                Spacer()

                exportMenu
            }

            ResultsTable(
                results: search.results,
                settings: $workspaces.settings,
                matcher: search.matcher,
                makeQuery: { try? makeQuery() },
                onRun: runSearch
            )
        }
        .padding(16)
        .frame(minWidth: 900, minHeight: 560)
        .toolbar {
            ToolbarItem(placement: .navigation) {
                WorkspaceMenu(store: workspaces, onSwitch: search.clear)
            }
        }
        .onDisappear(perform: search.stop)
    }

    private var exportMenu: some View {
        Menu {
            Button("Copy All Results") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(ResultsExport.text.render(search.results), forType: .string)
            }

            Divider()

            Button("Export as Text…") { export(.text) }
            Button("Export as CSV…") { export(.csv) }
        } label: {
            Label("Export", systemImage: "square.and.arrow.up")
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .disabled(search.results.isEmpty)
    }

    private func makeQuery() throws -> SearchQuery {
        try SearchQuery(
            texts: activeSearchTexts,
            filePatterns: FilePatternFilter.parse(includes: settings.fileFilter, excludes: settings.fileExclusions),
            recursive: settings.searchSubfolders,
            caseSensitive: settings.caseSensitiveSearch,
            regex: settings.regexSearch,
            wholeWord: settings.wholeWordSearch,
            fileNamesOnly: settings.searchFileNames
        )
    }

    private func runSearch() {
        guard !activeSearchTexts.isEmpty else {
            search.clear()
            return
        }

        let query: SearchQuery

        do {
            query = try makeQuery()
        } catch {
            search.fail(error.localizedDescription)
            return
        }

        guard let access = FolderAccess.resolve(folder: settings.folder, bookmark: settings.folderBookmark) else {
            search.clear()
            return
        }

        if access.needsNewBookmark {
            workspaces.settings.folderBookmark = FolderAccess.bookmark(for: access.url)
        }

        workspaces.recordSearch(
            RecentSearch(terms: query.texts, caseSensitive: query.caseSensitive, regex: query.regex, wholeWord: query.wholeWord)
        )
        search.run(query, in: access)
    }

    private func applyRecentSearch(_ recent: RecentSearch) {
        searchText = recent.terms.first ?? ""
        additionalSearchTexts = recent.terms.dropFirst().map { SearchTextField(text: $0) }

        var settings = settings
        settings.caseSensitiveSearch = recent.caseSensitive
        settings.regexSearch = recent.regex
        settings.wholeWordSearch = recent.wholeWord
        workspaces.settings = settings

        runSearch()
    }

    private func export(_ format: ResultsExport) {
        let results = search.results
        let panel = NSSavePanel()
        panel.allowedContentTypes = [format.contentType]
        panel.nameFieldStringValue = "Prescient Results.\(format.fileExtension)"

        guard panel.runModal() == .OK, let url = panel.url else {
            return
        }

        do {
            try format.render(results).write(to: url, atomically: true, encoding: .utf8)
        } catch {
            NSAlert(error: error).runModal()
        }
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false

        if panel.runModal() == .OK, let url = panel.url {
            setFolder(url)
        }
    }

    private func moveFolderUp() {
        guard !settings.folder.isEmpty else {
            return
        }

        let currentURL = URL(fileURLWithPath: settings.folder).standardizedFileURL
        let parentURL = currentURL.deletingLastPathComponent()

        if parentURL.path != currentURL.path {
            setFolder(parentURL)
        }
    }

    private func setFolder(_ url: URL) {
        var settings = settings
        settings.folder = url.path
        settings.folderBookmark = FolderAccess.bookmark(for: url)
        workspaces.settings = settings
    }
}
