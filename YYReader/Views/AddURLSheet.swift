import SwiftUI

struct AddURLSheet: View {
    let onSubmit: @MainActor (String, BookContentType) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var url = ""
    @State private var submitting = false
    @State private var contentType = BookContentType.auto

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Label("添加阅读网页", systemImage: "link")
                .font(.title2)
                .bold()

            Text("粘贴小说章节、漫画章节或目录网址。")
                .foregroundStyle(.secondary)

            Picker("内容类型", selection: $contentType) {
                ForEach(BookContentType.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("import.contentType")

            TextField("https://example.com/book/chapter.html", text: $url)
                #if os(iOS)
                .keyboardType(.URL)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                #endif
                .textFieldStyle(.roundedBorder)
                .onSubmit(submit)
                .accessibilityLabel("章节或目录网址")
                .accessibilityIdentifier("chapterURL")

            HStack {
                Spacer()
                Button("取消", action: dismiss.callAsFunction)
                    .keyboardShortcut(.cancelAction)
                Button("添加", action: submit)
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(url.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || submitting)
            }
        }
        .padding(24)
        #if os(macOS)
        .frame(width: 520)
        #endif
    }

    private func submit() {
        // Return also submits, so the empty-input guard cannot live on the button
        // alone: an empty field would otherwise be forwarded and dismissed.
        let submittedURL = url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !submittedURL.isEmpty, !submitting else { return }
        submitting = true
        onSubmit(submittedURL, contentType)
        dismiss()
    }
}
