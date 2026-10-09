import AppKit
import SwiftUI

struct AboutSettingsView: View {
    private let projectURL = URL(string: "https://github.com/YangChen-cn/YYReader")!

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header
                authorCard
                changelog
            }
            .padding(28)
            .frame(maxWidth: 480)
            .frame(maxWidth: .infinity)
        }
    }

    private var header: some View {
        VStack(spacing: 12) {
            Image(nsImage: NSApplication.shared.applicationIconImage)
                .resizable()
                .scaledToFit()
                .frame(width: 88, height: 88)
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                .shadow(color: .black.opacity(0.15), radius: 8, y: 3)
                .accessibilityHidden(true)

            VStack(spacing: 6) {
                Text("YYReader")
                    .font(.title2.weight(.bold))

                Text(versionDescription)
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(.quaternary.opacity(0.6), in: .capsule)

                Text("原生小说与漫画阅读器")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var authorCard: some View {
        GroupBox("关于") {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 12) {
                    Image(systemName: "person.circle.fill")
                        .font(.title2)
                        .foregroundStyle(.secondary)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("作者")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("YangChen")
                            .font(.body.weight(.medium))
                    }

                    Spacer()
                }

                Divider()

                Link(destination: projectURL) {
                    Label("GitHub：YangChen-cn/YYReader", systemImage: "link")
                        .font(.callout)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 2)
        }
    }

    private var changelog: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("最新改进")
                .font(.headline)

            GroupBox("版本 1.4.0") {
                VStack(alignment: .leading, spacing: 10) {
                    Label("添加网址时选择自动、小说或漫画。", systemImage: "link")
                    Label("漫画自动双页、快速跳页与深灰背景。", systemImage: "rectangle.split.2x1")
                    Label("默认预取，按书籍查看与清理缓存。", systemImage: "internaldrive")
                    Label("恢复阅读位置，共享书架与进度。", systemImage: "arrow.triangle.2.circlepath")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .font(.callout)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var versionDescription: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—"
        return "版本 \(version)（\(build)）"
    }
}
