import Foundation

struct WorkspaceSettings: Codable, Equatable {
    var folder = ""
    var folderBookmark = Data()
    var fileFilter = ""
    var fileExclusions = ""
    var searchSubfolders = true
    var caseSensitiveSearch = true
    var searchFileNames = false
    var regexSearch = false
    var wholeWordSearch = false
}

struct RecentSearch: Codable, Equatable {
    var terms: [String]
    var caseSensitive: Bool
    var regex: Bool
    var wholeWord: Bool
}

struct Workspace: Identifiable, Codable, Equatable {
    var id = UUID()
    var name: String
    var settings: WorkspaceSettings
    var recentSearches: [RecentSearch] = []
}

// NOTE: Missing keys decode as defaults so workspaces saved by older versions still load.
extension WorkspaceSettings {
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = WorkspaceSettings()

        folder = try container.decodeIfPresent(String.self, forKey: .folder) ?? defaults.folder
        folderBookmark = try container.decodeIfPresent(Data.self, forKey: .folderBookmark) ?? defaults.folderBookmark
        fileFilter = try container.decodeIfPresent(String.self, forKey: .fileFilter) ?? defaults.fileFilter
        fileExclusions = try container.decodeIfPresent(String.self, forKey: .fileExclusions) ?? defaults.fileExclusions
        searchSubfolders = try container.decodeIfPresent(Bool.self, forKey: .searchSubfolders) ?? defaults.searchSubfolders
        caseSensitiveSearch = try container.decodeIfPresent(Bool.self, forKey: .caseSensitiveSearch) ?? defaults.caseSensitiveSearch
        searchFileNames = try container.decodeIfPresent(Bool.self, forKey: .searchFileNames) ?? defaults.searchFileNames
        regexSearch = try container.decodeIfPresent(Bool.self, forKey: .regexSearch) ?? defaults.regexSearch
        wholeWordSearch = try container.decodeIfPresent(Bool.self, forKey: .wholeWordSearch) ?? defaults.wholeWordSearch
    }
}

extension Workspace {
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        settings = try container.decode(WorkspaceSettings.self, forKey: .settings)
        recentSearches = try container.decodeIfPresent([RecentSearch].self, forKey: .recentSearches) ?? []
    }
}
