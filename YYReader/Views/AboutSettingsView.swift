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

                Text("以正文为中心的原生 macOS 小说阅读器")
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
                        Text("Yang Chen")
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

            GroupBox("版本 1.2.3") {
                VStack(alignment: .leading, spacing: 10) {
                    Label("空闲预取扩展为最多 3 章，保持低优先级、串行、可取消并跳过缓存。", systemImage: "arrow.down.circle")
                    Label("切换可见章节时会接管重叠窗口的在途加载，不再中断后续预取。", systemImage: "arrow.trianglehead.2.clockwise.rotate.90")
                    Label("Windows 的更后阅读位置同步到当前书籍时会立即恢复，无需切换书籍。", systemImage: "rectangle.2.swap")
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
