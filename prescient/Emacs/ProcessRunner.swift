import Foundation

enum ProcessRunner {
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

struct ProcessResult {
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
