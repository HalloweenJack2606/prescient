import SwiftUI
import AppKit

struct SettingsView: View {
    @AppStorage(EmacsConfiguration.appPathKey) private var emacsPath = ""

    private var resolvedEmacsURL: URL? {
        EmacsConfiguration.resolvedAppURL(from: emacsPath)
    }

    var body: some View {
        Form {
            Section {
                LabeledField(title: "Emacs") {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 6) {
                            TextField("/Applications/Emacs.app", text: $emacsPath)
                                .textFieldStyle(.plain)

                            Button(action: chooseEmacs) {
                                Image(systemName: "folder")
                            }
                            .buttonStyle(.borderless)
                            .help("Choose Emacs")
                        }

                        Text(statusText)
                            .font(.caption)
                            .foregroundStyle(resolvedEmacsURL == nil && !emacsPath.isEmpty ? .red : .secondary)
                    }
                }
            }
        }
        .padding(16)
        .frame(width: 560)
    }

    private var statusText: String {
        if emacsPath.isEmpty {
            return "Choose Emacs.app."
        }

        if let resolvedEmacsURL {
            return "Using \(resolvedEmacsURL.path)"
        }

        return "Could not find Emacs.app at that path."
    }

    private func chooseEmacs() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.treatsFilePackagesAsDirectories = false
        panel.title = "Choose Emacs"
        panel.message = "Choose Emacs.app."

        if !emacsPath.isEmpty {
            panel.directoryURL = URL(fileURLWithPath: emacsPath).deletingLastPathComponent()
        }

        if panel.runModal() == .OK, let url = panel.url {
            emacsPath = url.path
        }
    }
}
