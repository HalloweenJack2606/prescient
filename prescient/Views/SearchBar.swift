import SwiftUI

struct SearchBar: View {
    @Binding var settings: WorkspaceSettings
    @Binding var searchText: String
    @Binding var additionalSearchTexts: [SearchTextField]

    @State private var isFileOptionsExpanded = false
    @FocusState private var isSearchTextFocused: Bool

    let recentSearches: [RecentSearch]
    let isSearching: Bool
    let canStop: Bool
    let onMoveUp: () -> Void
    let onBrowse: () -> Void
    let onRun: () -> Void
    let onStop: () -> Void
    let onSelectRecent: (RecentSearch) -> Void
    let onClearRecent: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                LabeledField(title: "Folder") {
                    HStack(spacing: 6) {
                        TextField("/path/to/folder", text: $settings.folder)
                            .textFieldStyle(.plain)

                        Button(action: onMoveUp) {
                            ZStack(alignment: .topTrailing) {
                                Image(systemName: "folder")
                                Image(systemName: "arrow.up.circle.fill")
                                    .font(.system(size: 9))
                                    .offset(x: 3, y: -3)
                            }
                            .frame(width: 24, height: 24)
                        }
                        .buttonStyle(.borderless)
                        .help("Move up one folder")

                        Button(action: onBrowse) {
                            Image(systemName: "folder")
                        }
                        .buttonStyle(.borderless)
                        .help("Choose folder")
                    }
                }

                Toggle("Search Subfolders", isOn: $settings.searchSubfolders)
                    .toggleStyle(.checkbox)
            }

            VStack(spacing: 8) {
                HStack(spacing: 10) {
                    LabeledField(title: "Files", showsMarker: !settings.fileExclusions.isEmpty) {
                        TextField("*.cpp, *.h", text: $settings.fileFilter)
                            .textFieldStyle(.plain)
                            .onSubmit(onRun)
                    }

                    Button(action: {
                        withAnimation(.easeInOut(duration: 0.16)) {
                            isFileOptionsExpanded.toggle()
                        }
                    }) {
                        Image(systemName: isFileOptionsExpanded ? "chevron.down" : "chevron.right")
                            .frame(width: 24, height: 24)
                    }
                    .buttonStyle(.borderless)
                    .help(isFileOptionsExpanded ? "Hide exclusions" : "Show exclusions")
                }

                if isFileOptionsExpanded {
                    LabeledField(title: "Exclude") {
                        TextField("generated, file.cpp~, .txt", text: $settings.fileExclusions)
                            .textFieldStyle(.plain)
                            .onSubmit(onRun)
                    }
                }
            }

            VStack(spacing: 8) {
                HStack(spacing: 10) {
                    LabeledField(title: "Text") {
                        HStack(spacing: 4) {
                            TextField("Text to find", text: $searchText)
                                .textFieldStyle(.plain)
                                .focused($isSearchTextFocused)
                                .onSubmit(onRun)

                            OptionToggle(title: "Aa", help: "Match Case", isOn: $settings.caseSensitiveSearch)
                            OptionToggle(title: "ab", help: "Match Whole Word", underlined: true, isOn: $settings.wholeWordSearch)
                            OptionToggle(title: ".*", help: "Use Regular Expression", isOn: $settings.regexSearch)

                            recentSearchesMenu
                        }
                    }

                    Button(action: addSearchTextField) {
                        Label("Add", systemImage: "plus")
                            .frame(width: 72)
                    }

                    Button(action: onRun) {
                        Label(isSearching ? "Searching" : "Search", systemImage: "magnifyingglass")
                            .frame(width: 100)
                    }
                    .keyboardShortcut(.return, modifiers: .command)
                    .disabled(isSearching)

                    Button(action: onStop) {
                        Label("Stop", systemImage: "stop.fill")
                            .frame(width: 76)
                    }
                    .disabled(!canStop)

                    Toggle("Search File Names", isOn: $settings.searchFileNames)
                        .toggleStyle(.checkbox)
                }

                ForEach($additionalSearchTexts) { $searchTerm in
                    LabeledField(title: "") {
                        HStack(spacing: 6) {
                            TextField("Text to find", text: $searchTerm.text)
                                .textFieldStyle(.plain)
                                .onSubmit(onRun)

                            Button {
                                removeSearchTextField(searchTerm.id)
                            } label: {
                                Image(systemName: "xmark")
                                    .frame(width: 24, height: 24)
                            }
                            .buttonStyle(.borderless)
                            .help("Remove search text")
                        }
                    }
                }
            }
        }
        .padding(12)
        .glassEffect(.regular, in: .rect(cornerRadius: 12))
        .onAppear {
            // HACK: Defer focus until the window is key, otherwise no caret is drawn.
            DispatchQueue.main.async {
                NSApp.activate(ignoringOtherApps: true)
                isSearchTextFocused = true
            }
        }
    }

    private var recentSearchesMenu: some View {
        Menu {
            if recentSearches.isEmpty {
                Button("No Recent Searches") {}
                    .disabled(true)
            } else {
                ForEach(Array(recentSearches.enumerated()), id: \.offset) { _, recent in
                    Button(title(for: recent)) {
                        onSelectRecent(recent)
                    }
                }

                Divider()

                Button("Clear Recent Searches", action: onClearRecent)
            }
        } label: {
            Image(systemName: "clock.arrow.circlepath")
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Recent searches")
    }

    private func title(for recent: RecentSearch) -> String {
        let options = [
            recent.caseSensitive ? "Aa" : nil,
            recent.wholeWord ? "Word" : nil,
            recent.regex ? "Regex" : nil
        ].compactMap { $0 }
        let terms = recent.terms.joined(separator: "  ·  ")

        return options.isEmpty ? terms : "\(terms)   [\(options.joined(separator: ", "))]"
    }

    private func addSearchTextField() {
        additionalSearchTexts.append(SearchTextField())
    }

    private func removeSearchTextField(_ id: SearchTextField.ID) {
        additionalSearchTexts.removeAll { $0.id == id }
    }
}

private struct OptionToggle: View {
    let title: String
    let help: String
    var underlined = false
    @Binding var isOn: Bool

    var body: some View {
        Button {
            isOn.toggle()
        } label: {
            Text(title)
                .underline(underlined)
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(isOn ? Color.white : Color.secondary)
                .frame(width: 22, height: 18)
                .background(isOn ? Color.accentColor : Color.clear, in: .rect(cornerRadius: 4))
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .help(help)
        .accessibilityLabel(help)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}
