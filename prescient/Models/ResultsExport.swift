import Foundation
import UniformTypeIdentifiers

nonisolated enum ResultsExport: CaseIterable {
    case text
    case csv

    var contentType: UTType {
        switch self {
        case .text: .plainText
        case .csv: .commaSeparatedText
        }
    }

    var fileExtension: String {
        switch self {
        case .text: "txt"
        case .csv: "csv"
        }
    }

    func render(_ results: [GrepResult]) -> String {
        switch self {
        case .text:
            return results.map(Self.grepLine).joined(separator: "\n") + "\n"
        case .csv:
            let rows = results.map { result in
                [result.absoluteFilePath, result.line.map(String.init) ?? "", result.text]
                    .map(Self.csvField)
                    .joined(separator: ",")
            }
            return (["file,line,text"] + rows).joined(separator: "\n") + "\n"
        }
    }

    private static func grepLine(_ result: GrepResult) -> String {
        guard let line = result.line else {
            return result.absoluteFilePath
        }

        return "\(result.absoluteFilePath):\(line):\(result.text)"
    }

    private static func csvField(_ value: String) -> String {
        guard value.contains(where: { ",\"\n\r".contains($0) }) else {
            return value
        }

        return "\"\(value.replacingOccurrences(of: "\"", with: "\"\""))\""
    }
}
