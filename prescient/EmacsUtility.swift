import AppKit
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

enum EmacsOpener {
    private static let startServerExpression = "(progn (require 'server) (unless (server-running-p) (server-start)))"

    static func open(_ result: GrepResult, folder: String, folderBookmark: Data) {
        let folderAccess = resolveFolderAccess(folder: folder, folderBookmark: folderBookmark)
        defer {
            folderAccess?.stopAccessing()
        }

        guard let appURL = EmacsConfiguration.resolvedAppURL() else {
            showFailure("Set Emacs.app in Settings first.")
            return
        }

        if isRunning(appURL: appURL) {
            openInRunningEmacs(appURL: appURL, result: result)
            return
        }

        launchEmacs(appURL: appURL, result: result)
    }

    private static func openInRunningEmacs(appURL: URL, result: GrepResult) {
        guard let emacsClientPath = EmacsConfiguration.emacsClientPath(in: appURL) else {
            showFailure("Could not find emacsclient inside Emacs.app.")
            return
        }

        let processResult = ProcessRunner.run(
            emacsClientPath,
            arguments: [
                "-n",
                "--eval",
                openInCurrentWindowExpression(filePath: result.absoluteFilePath, line: result.line ?? 1)
            ]
        )

        guard !processResult.succeeded else {
            return
        }

        if processResult.standardError.contains("can't find socket") {
            showFailure("""
            Emacs is open, but its server is not running.

            Add this to your Emacs init file and restart Emacs:
            (require 'server)
            (unless (server-running-p)
              (server-start))
            """)
            return
        }

        showFailure("emacsclient could not open the selected file.\n\n\(processResult.description)")
    }

    private static func launchEmacs(appURL: URL, result: GrepResult) {
        guard let executablePath = EmacsConfiguration.emacsExecutablePath(in: appURL) else {
            showFailure("Could not find the Emacs executable inside Emacs.app.")
            return
        }

        let didLaunch = ProcessRunner.launch(
            executablePath,
            arguments: [
                "--eval",
                startServerExpression,
                "+\(result.line ?? 1)",
                result.absoluteFilePath
            ]
        )

        if !didLaunch {
            showFailure("Could not launch Emacs.")
        }
    }

    private static func isRunning(appURL: URL) -> Bool {
        let targetPath = appURL.standardizedFileURL.path

        return NSWorkspace.shared.runningApplications.contains { app in
            app.bundleURL?.standardizedFileURL.path == targetPath
        }
    }

    private static func openInCurrentWindowExpression(filePath: String, line: Int) -> String {
        """
        (progn
          (select-frame-set-input-focus (selected-frame))
          (find-file \(elispString(filePath)))
          (goto-char (point-min))
          (forward-line \(max(line - 1, 0)))
          (recenter))
        """
    }

    private static func elispString(_ text: String) -> String {
        let escapedText = text
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")

        return "\"\(escapedText)\""
    }

    private static func resolveFolderAccess(folder: String, folderBookmark: Data) -> SearchFolderAccess? {
        if !folderBookmark.isEmpty {
            var isStale = false

            do {
                let url = try URL(
                    resolvingBookmarkData: folderBookmark,
                    options: .withSecurityScope,
                    relativeTo: nil,
                    bookmarkDataIsStale: &isStale
                )
                let didStartAccessing = url.startAccessingSecurityScopedResource()

                return SearchFolderAccess(url: url) {
                    if didStartAccessing {
                        url.stopAccessingSecurityScopedResource()
                    }
                }
            } catch {
                return nil
            }
        }

        if folder.isEmpty {
            return nil
        }

        return SearchFolderAccess(url: URL(fileURLWithPath: folder)) {}
    }

    private static func showFailure(_ message: String) {
        NSSound.beep()

        let alert = NSAlert()
        alert.messageText = "Could not open in Emacs"
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.runModal()
    }
}

private enum ProcessRunner {
    static func run(_ executablePath: String, arguments: [String]) -> ProcessResult {
        let process = Process()
        let outputPipe = Pipe()
        let errorPipe = Pipe()

        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = arguments
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        do {
            try process.run()
            process.waitUntilExit()
            return ProcessResult(
                executablePath: executablePath,
                terminationStatus: process.terminationStatus,
                standardOutput: String(data: outputPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? "",
                standardError: String(data: errorPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            )
        } catch {
            return ProcessResult(
                executablePath: executablePath,
                terminationStatus: -1,
                standardOutput: "",
                standardError: error.localizedDescription
            )
        }
    }

    static func launch(_ executablePath: String, arguments: [String]) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = arguments
        process.standardOutput = Pipe()
        process.standardError = Pipe()

        do {
            try process.run()
            return true
        } catch {
            return false
        }
    }
}

private struct ProcessResult {
    let executablePath: String
    let terminationStatus: Int32
    let standardOutput: String
    let standardError: String

    var succeeded: Bool {
        terminationStatus == 0
    }

    var description: String {
        let output = standardOutput.trimmingCharacters(in: .whitespacesAndNewlines)
        let error = standardError.trimmingCharacters(in: .whitespacesAndNewlines)

        if output.isEmpty && error.isEmpty {
            return "\(executablePath) exited with status \(terminationStatus)."
        }

        return "\(executablePath) exited with status \(terminationStatus).\nstdout: \(output)\nstderr: \(error)"
    }
}
