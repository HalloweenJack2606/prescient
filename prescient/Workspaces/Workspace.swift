import Foundation

struct WorkspaceSettings: Codable, Equatable {
    var folder = ""
    var folderBookmark = Data()
    var fileFilter = ""
    var fileExclusions = ""
    var searchSubfolders = true
    var caseSensitiveSearch = true
    var searchFileNames = false
}

struct Workspace: Identifiable, Codable, Equatable {
    var id = UUID()
    var name: String
    var settings: WorkspaceSettings
}
