import SwiftUI

struct ReaderContinuationBoundary: View {
    let status: ReaderContinuationStatus
    let prefetch: () -> Void
    let retry: () -> Void

    var body: some View {
        Group {
            switch status {
            case .idle:
                ProgressView("正在准备下一章…")
                    .onAppear(perform: prefetch)
            case .loading:
                ProgressView("正在准备下一章…")
            case .failed:
                Button("加载下一章失败，重试", systemImage: "arrow.clockwise", action: retry)
                    .buttonStyle(.borderless)
                    .foregroundStyle(.secondary)
            case .ready:
                Color.clear
                    .frame(height: 1)
                    .onAppear(perform: prefetch)
            case .unavailable:
                EmptyView()
            }
        }
        .font(.callout)
        .padding(.vertical, 32)
        .frame(maxWidth: .infinity)
    }
}
