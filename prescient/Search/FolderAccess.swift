import Foundation

struct FolderAccess: Sendable {
    let url: URL
    let needsNewBookmark: Bool
    let stopAccessing: @Sendable () -> Void

    // NOTE: The bookmark is only trusted if it still points at `folder`, so typed paths win.
    static func resolve(folder: String, bookmark: Data) -> FolderAccess? {
        guard !folder.isEmpty else {
            return nil
        }

        let folderURL = URL(fileURLWithPath: folder).standardizedFileURL
        var isStale = false

        if !bookmark.isEmpty,
           let url = try? URL(
               resolvingBookmarkData: bookmark,
               options: .withSecurityScope,
               relativeTo: nil,
               bookmarkDataIsStale: &isStale
           ),
           url.standardizedFileURL.path == folderURL.path {
            let didStartAccessing = url.startAccessingSecurityScopedResource()

            return FolderAccess(url: url, needsNewBookmark: isStale) {
                if didStartAccessing {
                    url.stopAccessingSecurityScopedResource()
                }
            }
        }

        return FolderAccess(url: folderURL, needsNewBookmark: true) {}
    }

    static func bookmark(for url: URL) -> Data {
        (try? url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)) ?? Data()
    }
}
