import SwiftUI

struct WebVerificationSheet: View {
    let request: VerificationRequest
    let store: WebVerificationStore
    @State private var status = "正在载入网站验证页面…"
    @State private var failureMessage: String?
    @State private var reloadToken = 0

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Label("完成网站验证后将自动继续", systemImage: "checkmark.shield")
                Spacer()
                Button("取消", action: store.cancel)
                    .keyboardShortcut(.cancelAction)
            }
            .padding()
            .background(.bar)

            WebVerificationWebView(
                request: request,
                reloadToken: reloadToken,
                onStatus: updateStatus,
                onFailure: showFailure,
                onHTMLReady: finish
            )
            .overlay(alignment: .bottom) {
                HStack(spacing: 10) {
                    if failureMessage == nil { ProgressView().controlSize(.small) }
                    Text(failureMessage ?? status)
                        .foregroundStyle(failureMessage == nil ? Color.secondary : Color.red)
                    Spacer()
                    if failureMessage != nil {
                        Button("重试") {
                            failureMessage = nil
                            reloadToken += 1
                        }
                    }
                }
                .padding(12)
                .background(.bar)
            }
        }
        .frame(minWidth: 760, minHeight: 560)
        .interactiveDismissDisabled()
        .task(id: request.id) {
            do {
                try await Task.sleep(for: .seconds(90))
                store.fail(.verificationTimedOut)
            } catch {
                // The sheet disappeared because verification completed or was cancelled.
            }
        }
    }

    private func finish(html: String, url: URL, userAgent: String) {
        store.complete(html: html, finalURL: url, userAgent: userAgent)
    }

    private func updateStatus(_ message: String) {
        failureMessage = nil
        status = message
    }

    private func showFailure(_ message: String) {
        failureMessage = message
    }
}
