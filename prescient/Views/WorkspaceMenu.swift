import SwiftUI

struct WorkspaceMenu: View {
    private enum NamingMode {
        case create, rename
    }

    let store: WorkspaceStore
    let onSwitch: () -> Void

    @State private var namingMode: NamingMode?
    @State private var nameDraft = ""
    @State private var isConfirmingDelete = false

    var body: some View {
        Menu {
            ForEach(store.workspaces) { workspace in
                Button {
                    guard workspace.id != store.activeID else { return }
                    store.select(workspace.id)
                    onSwitch()
                } label: {
                    if workspace.id == store.activeID {
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
                nameDraft = store.active.name
                namingMode = .rename
            }

            Button("Delete…", role: .destructive) {
                isConfirmingDelete = true
            }
            .disabled(store.workspaces.count <= 1)
        } label: {
            Label(store.active.name, systemImage: "square.stack.3d.up")
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
        .confirmationDialog("Delete “\(store.active.name)”?", isPresented: $isConfirmingDelete) {
            Button("Delete", role: .destructive) {
                store.deleteActive()
                onSwitch()
            }
        }
    }

    private func commitName() {
        let name = nameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, let mode = namingMode else { return }

        switch mode {
        case .create: store.create(named: name)
        case .rename: store.renameActive(to: name)
        }
    }
}
