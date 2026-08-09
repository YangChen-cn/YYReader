import SwiftUI

struct WebVerificationSheet: View {
    let request: VerificationRequest
    let store: WebVerificationStore

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

            WebVerificationWebView(session: request.session)
                .overlay(alignment: .bottom) {
                    HStack(spacing: 10) {
                        if request.session.failureMessage == nil {
                            ProgressView()
                                .controlSize(.small)
                        }
                        Text(request.session.failureMessage ?? request.session.status)
                            .foregroundStyle(
                                request.session.failureMessage == nil ? Color.secondary : Color.red
                            )
                        Spacer()
                        if request.session.failureMessage != nil {
                            Button("重试", action: store.retry)
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
                // Closing the sheet cancels its timeout task.
            }
        }
    }
}
