import SwiftUI
import AppKit

struct ResultsTable: View {
    let results: [GrepResult]
    @Binding var settings: WorkspaceSettings
    let matcher: SearchMatcher?
    let makeQuery: () -> SearchQuery?
    let onRun: () -> Void
    @State private var selection = Set<GrepResult.ID>()

    var body: some View {
        Table(results, selection: $selection) {
            TableColumn("File") { result in
                resultCell(Text(result.filePath), result: result)
            }
            TableColumn("Line") { result in
                resultCell(Text(result.line.map(String.init) ?? ""), result: result)
            }
            .width(min: 56, ideal: 56, max: 56)
            TableColumn("Text") { result in
                resultCell(Text(highlighted(result.text)), result: result)
            }
        }
        .onCopyCommand {
            let selected = results.filter { selection.contains($0.id) }
            return selected.isEmpty ? [] : [NSItemProvider(object: ResultsExport.text.render(selected) as NSString)]
        }
    }

    private func highlighted(_ text: String) -> AttributedString {
        guard let matcher else {
            return AttributedString(text)
        }

        var attributed = AttributedString()
        var cursor = text.startIndex

        for range in matcher.ranges(in: text) {
            var match = AttributedString(String(text[range]))
            match.swiftUI.backgroundColor = .yellow.opacity(0.4)
            match.swiftUI.font = .body.bold()

            attributed += AttributedString(String(text[cursor..<range.lowerBound]))
            attributed += match
            cursor = range.upperBound
        }

        attributed += AttributedString(String(text[cursor...]))
        return attributed
    }

    private func resultCell(_ text: Text, result: GrepResult) -> some View {
        text
            .contentShape(Rectangle())
            .contextMenu {
                Button {
                    selection = [result.id]
                    EmacsOpener.open(result, folder: settings.folder, folderBookmark: settings.folderBookmark)
                } label: {
                    Label("Open in Emacs", systemImage: "arrow.up.forward.app")
                }

                Button {
                    selection = [result.id]
                    openEnclosingFolder(for: result)
                } label: {
                    Label("Open in Enclosing Folder", systemImage: "folder")
                }

                Divider()

                Button {
                    selection = [result.id]
                    copy(result.absoluteFilePath)
                } label: {
                    Label("Copy File Path", systemImage: "doc.on.doc")
                }

                Button {
                    selection = [result.id]
                    copy(result.text)
                } label: {
                    Label("Copy Match", systemImage: "text.quote")
                }

                Divider()

                Button {
                    selection = [result.id]
                    openTerminalHere(for: result)
                } label: {
                    Label("Open in Terminal Here", systemImage: "terminal")
                }

                Button {
                    selection = [result.id]
                    searchThisFileOnly(result)
                } label: {
                    Label("Search This File Only", systemImage: "doc.text.magnifyingglass")
                }

                Button {
                    selection = [result.id]
                    copyGrepCommand()
                } label: {
                    Label("Copy Grep Command", systemImage: "curlybraces")
                }

                Divider()

                Button {
                    selection = [result.id]
                    excludeThisFile(result)
                } label: {
                    Label("Exclude This File", systemImage: "doc.badge.minus")
                }

                Button {
                    selection = [result.id]
                    excludeThisFolder(result)
                } label: {
                    Label("Exclude This Folder", systemImage: "folder.badge.minus")
                }
            }
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
                        EmacsOpener.open(result, folder: settings.folder, folderBookmark: settings.folderBookmark)
                    }
            )
    }

    private func openEnclosingFolder(for result: GrepResult) {
        let fileURL = URL(fileURLWithPath: result.absoluteFilePath)
        NSWorkspace.shared.activateFileViewerSelecting([fileURL])
    }

    private func copy(_ value: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(value, forType: .string)
    }

    private func openTerminalHere(for result: GrepResult) {
        let folderURL = URL(fileURLWithPath: result.absoluteFilePath).deletingLastPathComponent()
        let process = Process()

        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = ["-a", "Terminal", folderURL.path]

        try? process.run()
    }

    private func searchThisFileOnly(_ result: GrepResult) {
        settings.fileFilter = result.filePath
        onRun()
    }

    private func copyGrepCommand() {
        guard let query = makeQuery() else {
            return
        }

        copy(
            query.fileNamesOnly
                ? SearchEngine.fileNameSearchCommand(query, folder: settings.folder)
                : SearchEngine.grepCommand(query, folder: settings.folder)
        )
    }

    private func excludeThisFile(_ result: GrepResult) {
        appendExclusion(result.filePath)
    }

    private func excludeThisFolder(_ result: GrepResult) {
        let components = result.filePath.split(separator: "/").map(String.init)

        guard components.count > 1 else {
            return
        }

        appendExclusion("\(components.dropLast().joined(separator: "/"))/")
    }

    private func appendExclusion(_ value: String) {
        guard !FilePatternFilter.tokens(from: settings.fileExclusions).contains(value) else {
            return
        }

        if settings.fileExclusions.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            settings.fileExclusions = value
        } else {
            settings.fileExclusions += ", \(value)"
        }
    }
}
