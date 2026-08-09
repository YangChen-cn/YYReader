import SwiftUI

struct AddURLSheet: View {
    let onSubmit: @MainActor (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var url = ""
    @State private var submitting = false

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Label("添加小说网页", systemImage: "link")
                .font(.title2)
                .bold()

            Text("粘贴任意章节 URL。YYReader 会识别小说、目录和章节分页。")
                .foregroundStyle(.secondary)

            TextField("https://example.com/book/chapter.html", text: $url)
                .textFieldStyle(.roundedBorder)
                .onSubmit(submit)
                .accessibilityLabel("小说章节网址")

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
        .frame(width: 520)
    }

    private func submit() {
        guard !submitting else { return }
        submitting = true
        let submittedURL = url
        dismiss()
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(350))
            onSubmit(submittedURL)
        }
    }
}
