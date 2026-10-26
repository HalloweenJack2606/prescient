import Foundation
import Observation

@Observable
final class WorkspaceStore {
    private enum Key {
        static let workspaces = "workspaces"
        static let activeID = "activeWorkspaceID"
    }

    private(set) var workspaces: [Workspace]
    private(set) var activeID: Workspace.ID

    @ObservationIgnored private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        let saved = defaults.data(forKey: Key.workspaces)
            .flatMap { try? JSONDecoder().decode([Workspace].self, from: $0) } ?? []
        let workspaces = saved.isEmpty
            ? [Workspace(name: "Default", settings: Self.legacySettings(from: defaults))]
            : saved
        let savedID = defaults.string(forKey: Key.activeID).flatMap(UUID.init(uuidString:))

        self.workspaces = workspaces
        activeID = workspaces.contains { $0.id == savedID } ? savedID! : workspaces[0].id
        save()
    }

    var active: Workspace {
        workspaces[activeIndex]
    }

    var settings: WorkspaceSettings {
        get { active.settings }
        set {
            guard newValue != active.settings else { return }
            workspaces[activeIndex].settings = newValue
            save()
        }
    }

    func select(_ id: Workspace.ID) {
        guard workspaces.contains(where: { $0.id == id }) else { return }
        activeID = id
        save()
    }

    func create(named name: String) {
        let workspace = Workspace(name: name, settings: settings)
        workspaces.append(workspace)
        activeID = workspace.id
        save()
    }

    func renameActive(to name: String) {
        workspaces[activeIndex].name = name
        save()
    }

    func deleteActive() {
        guard workspaces.count > 1 else { return }
        workspaces.remove(at: activeIndex)
        activeID = workspaces[0].id
        save()
    }

    private var activeIndex: Int {
        workspaces.firstIndex { $0.id == activeID } ?? 0
    }

    private func save() {
        defaults.set(try? JSONEncoder().encode(workspaces), forKey: Key.workspaces)
        defaults.set(activeID.uuidString, forKey: Key.activeID)
    }

    // NOTE: Settings from before workspaces existed seed the first "Default" workspace.
    private static func legacySettings(from defaults: UserDefaults) -> WorkspaceSettings {
        var settings = WorkspaceSettings()
        settings.folder = defaults.string(forKey: "searchFolder") ?? settings.folder
        settings.folderBookmark = defaults.data(forKey: "searchFolderBookmark") ?? settings.folderBookmark
        settings.fileFilter = defaults.string(forKey: "fileFilter") ?? settings.fileFilter
        settings.fileExclusions = defaults.string(forKey: "fileExclusions") ?? settings.fileExclusions
        settings.searchSubfolders = defaults.object(forKey: "searchSubfolders") as? Bool ?? settings.searchSubfolders
        settings.caseSensitiveSearch = defaults.object(forKey: "caseSensitiveSearch") as? Bool ?? settings.caseSensitiveSearch
        settings.searchFileNames = defaults.object(forKey: "searchFileNames") as? Bool ?? settings.searchFileNames
        return settings
    }
}
