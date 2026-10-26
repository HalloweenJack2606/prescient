import SwiftUI

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

    static func decodeList(_ data: Data) -> [Workspace] {
        (try? JSONDecoder().decode([Workspace].self, from: data)) ?? []
    }

    static func encodeList(_ workspaces: [Workspace]) -> Data {
        (try? JSONEncoder().encode(workspaces)) ?? Data()
    }
}

struct WorkspaceMenu: View {
    private enum NamingMode {
        case create, rename
    }

    let workspaces: [Workspace]
    let activeID: Workspace.ID?
    let onSelect: (Workspace.ID) -> Void
    let onCreate: (String) -> Void
    let onRename: (String) -> Void
    let onDelete: () -> Void

    @State private var namingMode: NamingMode?
    @State private var nameDraft = ""
    @State private var isConfirmingDelete = false

    private var activeName: String {
        workspaces.first { $0.id == activeID }?.name ?? "Workspace"
    }

    var body: some View {
        Menu {
            ForEach(workspaces) { workspace in
                Button {
                    onSelect(workspace.id)
                } label: {
                    if workspace.id == activeID {
                        Label(workspace.name, systemImage: "checkmark")
                    } else {
                        Text(workspace.name)
                    }
                }
            }

            Divider()

            Button("New Workspace…") {
                nameDraft = ""
                namingMode = .create
            }

            Button("Rename…") {
                nameDraft = activeName
                namingMode = .rename
            }

            Button("Delete…", role: .destructive) {
                isConfirmingDelete = true
            }
            .disabled(workspaces.count <= 1)
        } label: {
            Label(activeName, systemImage: "square.stack.3d.up")
                .labelStyle(.titleAndIcon)
        }
        .help("Switch workspace")
        .alert(
            namingMode == .rename ? "Rename Workspace" : "New Workspace",
            isPresented: Binding(get: { namingMode != nil }, set: { if !$0 { namingMode = nil } })
        ) {
            TextField("Name", text: $nameDraft)
            Button("Cancel", role: .cancel) {}
            Button(namingMode == .rename ? "Rename" : "Create", action: commitName)
        } message: {
            if namingMode == .create {
                Text("Starts with the current settings.")
            }
        }
        .confirmationDialog("Delete “\(activeName)”?", isPresented: $isConfirmingDelete) {
            Button("Delete", role: .destructive, action: onDelete)
        }
    }

    private func commitName() {
        let name = nameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, let mode = namingMode else { return }

        switch mode {
        case .create: onCreate(name)
        case .rename: onRename(name)
        }
    }
}
