import SwiftUI

struct LoadingOverlay: View {
    let message: String
    let onCancel: (() -> Void)?

    var body: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text(message)
                .font(.headline)
            if let onCancel {
                Button("停止操作", role: .cancel, action: onCancel)
                    .keyboardShortcut(.cancelAction)
            }
        }
        .padding(24)
        .background(.regularMaterial, in: .rect(cornerRadius: 14))
        .shadow(radius: 12)
        .accessibilityElement(children: .combine)
    }
}
