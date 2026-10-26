import Foundation

enum EmacsConfiguration {
    static let appPathKey = "emacsAppPath"
    private static let legacyClientPathKey = "emacsClientPath"

    private static let fallbackAppPath = "/Applications/Emacs.app"

    static func resolvedAppURL() -> URL? {
        let configuredPath = UserDefaults.standard.string(forKey: appPathKey) ?? ""

        if let appURL = resolvedAppURL(from: configuredPath) {
            return appURL
        }

        let legacyPath = UserDefaults.standard.string(forKey: legacyClientPathKey) ?? ""
        if let appURL = resolvedAppURL(from: legacyPath) {
            return appURL
        }

        return resolvedAppURL(from: fallbackAppPath)
    }

    static func resolvedAppURL(from path: String) -> URL? {
        let trimmedPath = path.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedPath.isEmpty else {
            return nil
        }

        let url = URL(fileURLWithPath: trimmedPath).standardizedFileURL

        if url.pathExtension == "app", FileManager.default.fileExists(atPath: url.path) {
            return url
        }

        return containingAppURL(for: url)
    }

    static func emacsClientPath(in appURL: URL) -> String? {
        let candidates = [
            appURL.appendingPathComponent("Contents/MacOS/bin/emacsclient").path,
            appURL.appendingPathComponent("Contents/MacOS/emacsclient").path
        ]

        return candidates.first(where: FileManager.default.isExecutableFile)
    }

    static func emacsExecutablePath(in appURL: URL) -> String? {
        let candidates = [
            appURL.appendingPathComponent("Contents/MacOS/Emacs").path,
            appURL.appendingPathComponent("Contents/MacOS/Emacs-x86_64-10_14").path
        ]

        return candidates.first(where: FileManager.default.isExecutableFile)
    }

    private static func containingAppURL(for url: URL) -> URL? {
        var currentURL = url

        while currentURL.path != "/" {
            if currentURL.pathExtension == "app", FileManager.default.fileExists(atPath: currentURL.path) {
                return currentURL
            }

            currentURL.deleteLastPathComponent()
        }

        return nil
    }
}
