import SwiftUI

struct LabeledField<Content: View>: View {
    let title: String
    var showsMarker = false
    @ViewBuilder let content: Content

    var body: some View {
        HStack(spacing: 8) {
            HStack(spacing: 1) {
                Text(title)
                    .foregroundStyle(.secondary)

                if showsMarker {
                    Text("*")
                        .foregroundStyle(.red)
                }
            }
            .font(.caption)
            .frame(width: 44, alignment: .trailing)

            content
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(.regularMaterial, in: .rect(cornerRadius: 6))
                .contentShape(.rect(cornerRadius: 6))
        }
    }
}
