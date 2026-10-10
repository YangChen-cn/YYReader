import SwiftUI
@preconcurrency import WebKit

struct SettingsView: View {
    @Environment(AppServices.self) private var services
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
                    Toggle("自动预取 · 小说 3 章 / 漫画 10 张图片", isOn: $prefetchNext)
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

            Tab("缓存", systemImage: "internaldrive") {
                if let store = services.libraryStore { LocalCacheManagementView(store: store) }
                else { ProgressView("正在打开书架…") }
            }

            Tab("同步", systemImage: "arrow.trianglehead.2.clockwise") {
                FolderSyncSettingsView()
            }

            Tab("关于", systemImage: "info.circle") {
                AboutSettingsView()
            }
            Tab("更新", systemImage: "arrow.down.circle") {
                ScrollView {
                    AppUpdateSettingsView().padding(24)
                }
            }
        }
        .frame(width: 540, height: 620)
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
