import Foundation
import Observation

@Observable
final class SearchController {
    private(set) var results: [GrepResult] = []
    private(set) var searchedFileCount: Int?
    private(set) var isSearching = false
    private(set) var isCountingSearchedFiles = false

    @ObservationIgnored private var searchTask: Task<Void, Never>?
    @ObservationIgnored private var currentSearchID: UUID?

    var canStop: Bool {
        isSearching || isCountingSearchedFiles
    }

    func summary(fileNamesOnly: Bool) -> String {
        let matchingFileCount = Set(results.map(\.filePath)).count
        let countStatus: String

        if isCountingSearchedFiles {
            countStatus = "searched files calculating..."
        } else if let searchedFileCount {
            countStatus = "of \(searchedFileCount) searched"
        } else {
            countStatus = "searched files not calculated"
        }

        if fileNamesOnly {
            return "Found \(matchingFileCount) matching files (\(countStatus))"
        }

        return "Found \(results.count) matching lines in \(matchingFileCount) files (\(countStatus))"
    }

    func run(_ query: SearchQuery, in access: FolderAccess) {
        clear()

        let searchID = UUID()
        currentSearchID = searchID
        isSearching = true

        searchTask = Task {
            defer {
                access.stopAccessing()
            }

            let worker = Task.detached(priority: .userInitiated) {
                await SearchEngine.run(query, folder: access.url) { result in
                    await self.append(result, for: searchID)
                }
            }

            await withTaskCancellationHandler {
                await worker.value
            } onCancel: {
                worker.cancel()
            }

            guard !Task.isCancelled, currentSearchID == searchID else { return }

            isSearching = false
            isCountingSearchedFiles = true

            let countWorker = Task.detached(priority: .utility) {
                SearchEngine.countSearchableFiles(folder: access.url, filePatterns: query.filePatterns, recursive: query.recursive)
            }

            let count = await withTaskCancellationHandler {
                await countWorker.value
            } onCancel: {
                countWorker.cancel()
            }

            guard currentSearchID == searchID else { return }

            searchedFileCount = count
            isCountingSearchedFiles = false
            currentSearchID = nil
            searchTask = nil
        }
    }

    func stop() {
        searchTask?.cancel()
        searchTask = nil
        currentSearchID = nil
        isSearching = false
        isCountingSearchedFiles = false
    }

    func clear() {
        stop()
        results = []
        searchedFileCount = nil
    }

    private func append(_ result: GrepResult, for searchID: UUID) {
        guard currentSearchID == searchID else { return }
        results.append(result)
    }
}
