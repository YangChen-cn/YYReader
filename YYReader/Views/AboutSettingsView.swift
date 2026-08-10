import AppKit
import SwiftUI

struct AboutSettingsView: View {
    private let projectURL = URL(string: "https://github.com/YangChen-cn/YYReader")!

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(spacing: 8) {
                    Image(nsImage: NSApplication.shared.applicationIconImage)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 96, height: 96)
                        .accessibilityHidden(true)

                    Text("YYReader")
                        .font(.title)
                        .bold()

                    Text(versionDescription)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)

                GroupBox {
                    VStack(alignment: .leading, spacing: 12) {
                        LabeledContent("作者", value: "Yangchen")
                        Link(destination: projectURL) {
                            Label("在 GitHub 查看项目", systemImage: "link")
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                VStack(alignment: .leading, spacing: 12) {
                    Text("1.1.0 更新日志")
                        .font(.headline)

                    Label("新增可选连续阅读，提前预取下一章并稳定衔接章节。", systemImage: "text.page")
                    Label("新增章节批量下载、后台下载进度和离线缓存管理。", systemImage: "arrow.down.circle")
                    Label("增强通用网站、目录页和无目录小说兼容性。", systemImage: "network")
                    Label("改进阅读进度、键盘滚动、目录跟随和上次阅读恢复。", systemImage: "bookmark")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding()
        }
    }

    private var versionDescription: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—"
        return "版本 \(version)（\(build)）"
    }
}
