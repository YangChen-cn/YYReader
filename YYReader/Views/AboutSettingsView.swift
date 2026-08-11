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
            Text("更新日志")
                .font(.headline)

            GroupBox("性能与稳定性") {
                VStack(alignment: .leading, spacing: 10) {
                    Label("正文段落采用 8 章 LRU 缓存，减少主题和窗口变化时的重复拆分，并自动释放远离章节。", systemImage: "memorychip")
                    Label("大目录建立章节与位置索引，章节切换、进度更新和邻章查询由线性扫描降为常数时间。", systemImage: "list.number")
                    Label("连续阅读窗口、预取与章节挂接更加稳定，避免长时间阅读时正文跳动或缓存持续增长。", systemImage: "speedometer")
                    Label("目录切换优先读取本地缓存，不再因缓存时间自动刷新大目录。", systemImage: "externaldrive")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            GroupBox("Bug 修复") {
                VStack(alignment: .leading, spacing: 10) {
                    Label("修复“继续阅读”回到章首的问题，现在会恢复到已保存的顶部段落。", systemImage: "bookmark")
                    Label("修复方向键滚动只能前进一次的问题，支持按住连续滚动及稳定的进度保存。", systemImage: "arrow.up.arrow.down")
                    Label("修复连续章节切换、预取挂接和可见章节判断导致的跳章、闪动与进度错位。", systemImage: "arrow.trianglehead.2.clockwise.rotate.90")
                    Label("修复选择目录或书籍时意外重置当前阅读章节的问题。", systemImage: "books.vertical")
                    Label("改进通用网页导入与渲染 DOM 回退，提升无目录正文页及复杂站点的兼容性。", systemImage: "safari")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            GroupBox("阅读体验") {
                VStack(alignment: .leading, spacing: 10) {
                    Label("新增连续阅读、离线缓存和下一章机会性预取。", systemImage: "arrow.down.to.line.compact")
                    Label("新增可选文件夹同步，可通过任意共享目录与 Windows 交换书架和阅读位置。", systemImage: "folder.badge.gearshape")
                    Label("书架支持手动导入、导出跨平台 `.yyreader` 数据，并在导入前预览变更。", systemImage: "square.and.arrow.up.on.square")
                    Label("新增 ←/→ 整页滚动与 ↑/↓ 小幅滚动，翻页保留重叠便于衔接。", systemImage: "arrow.left.and.right")
                    Label("正文宽度、行距与段距改为随字号缩放，并支持更宽范围的自定义滑块。", systemImage: "textformat.size")
                    Label("扩充阅读主题，并为连续章节提供更紧凑、与主题一致的视觉边界。", systemImage: "paintpalette")
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
