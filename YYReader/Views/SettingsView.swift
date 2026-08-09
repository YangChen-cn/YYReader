import SwiftUI
@preconcurrency import WebKit

struct SettingsView: View {
    @AppStorage(ReaderPreferenceKeys.prefetchNext) private var prefetchNext = true
    @State private var clearingWebsiteData = false

    var body: some View {
        TabView {
            Tab("阅读", systemImage: "textformat") {
                AppearanceInspectorView()
                    .padding()
            }

            Tab("网络", systemImage: "network") {
                Form {
                    Toggle("空闲时预取下一章", isOn: $prefetchNext)
                    LabeledContent("网页验证数据") {
                        Button("清除 Cookie 与缓存", action: clearWebsiteData)
                            .disabled(clearingWebsiteData)
                    }
                    Text("清除后，受保护的网站可能再次要求浏览器验证。")
                        .foregroundStyle(.secondary)
                }
                .formStyle(.grouped)
                .padding()
            }
        }
        .frame(width: 520, height: 440)
    }

    private func clearWebsiteData() {
        clearingWebsiteData = true
        let types = WKWebsiteDataStore.allWebsiteDataTypes()
        WKWebsiteDataStore.default().removeData(ofTypes: types, modifiedSince: .distantPast) {
            Task { @MainActor in
                clearingWebsiteData = false
            }
        }
    }
}
