import Foundation

struct GrepResult: Identifiable, Sendable {
    let filePath: String
    let absoluteFilePath: String
    let line: Int?
    let text: String

    let id = UUID()
}

struct SearchTextField: Identifiable, Sendable {
    let id = UUID()
    var text = ""
}
