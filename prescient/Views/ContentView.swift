import SwiftUI
import AppKit

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
                isSearching: search.isSearching,
                canStop: search.canStop,
                onMoveUp: moveFolderUp,
                onBrowse: chooseFolder,
                onRun: runSearch,
                onStop: search.stop
            )

            HStack {
                Text(search.summary(fileNamesOnly: settings.searchFileNames))
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer()
            }

            ResultsTable(
                results: search.results,
                settings: $workspaces.settings,
                searchTexts: activeSearchTexts,
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

    private func runSearch() {
        let texts = activeSearchTexts

        guard !texts.isEmpty,
              let access = FolderAccess.resolve(folder: settings.folder, bookmark: settings.folderBookmark) else {
            search.clear()
            return
        }

        if access.needsNewBookmark {
            workspaces.settings.folderBookmark = FolderAccess.bookmark(for: access.url)
        }

        search.run(
            SearchQuery(
                texts: texts,
                filePatterns: FilePatternFilter.parse(includes: settings.fileFilter, excludes: settings.fileExclusions),
                recursive: settings.searchSubfolders,
                caseSensitive: settings.caseSensitiveSearch,
                fileNamesOnly: settings.searchFileNames
            ),
            in: access
        )
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
