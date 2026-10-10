import SwiftUI

struct ReleaseNotesView: View {
    let notes: String

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 9) {
                if notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text("此版本未提供更新说明。")
                } else {
                    ForEach(Array(notes.components(separatedBy: "\n").enumerated()), id: \.offset) { _, line in
                        if line.hasPrefix("#") {
                            Text(verbatim: line.drop(while: { $0 == "#" || $0 == " " }).description)
                                .font(.headline).padding(.top, 4)
                        } else if !line.trimmingCharacters(in: .whitespaces).isEmpty {
                            Text(markdown(line)).font(.callout)
                        }
                    }
                }
            }
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxHeight: 300)
    }

    private func markdown(_ line: String) -> AttributedString {
        (try? AttributedString(markdown: line,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(line)
    }
}
