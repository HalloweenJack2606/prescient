import AppKit
import Foundation

enum EmacsOpener {
    private static let startServerExpression = "(progn (require 'server) (unless (server-running-p) (server-start)))"

    static func open(_ result: GrepResult, folder: String, folderBookmark: Data) {
        let folderAccess = FolderAccess.resolve(folder: folder, bookmark: folderBookmark)
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

    private static func showFailure(_ message: String) {
        NSSound.beep()

        let alert = NSAlert()
        alert.messageText = "Could not open in Emacs"
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.runModal()
    }
}
