import SwiftUI

struct ReaderContinuationBoundary: View {
    let status: ReaderContinuationStatus
    let accent: Color
    let secondaryForeground: Color
    let tertiaryForeground: Color
    let prepareAttachment: () -> Void
    let retry: () -> Void

    var body: some View {
        ZStack {
            Text("· · ·")
                .font(.caption)
                .foregroundStyle(tertiaryForeground)
                .accessibilityHidden(true)

            switch status {
            case .idle, .loading:
                ProgressView()
                    .controlSize(.small)
                    .tint(accent)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .accessibilityLabel("正在准备下一章")
            case .failed:
                Button("加载下一章失败，重试", systemImage: "arrow.clockwise", action: retry)
                    .buttonStyle(.borderless)
                    .foregroundStyle(accent)
            case .ready, .attached, .unavailable:
                EmptyView()
            }
        }
        .font(.callout)
        .frame(height: 72)
        .frame(maxWidth: .infinity)
        .onAppear(perform: prepareIfNeeded)
        .onChange(of: status) { _, _ in prepareIfNeeded() }
    }

    private func prepareIfNeeded() {
        if status == .idle || status == .ready {
            prepareAttachment()
        }
    }
}
