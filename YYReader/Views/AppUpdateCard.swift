import SwiftUI

/// Shared card for bookshelf and Settings. Release Markdown is rendered as text,
/// never executed as HTML or JavaScript.
struct AppUpdateCard: View {
    @Bindable var updates: AppUpdateController
    var canDismiss = false
    @Environment(AppServices.self) private var services
    @State private var expanded = false
    @State private var confirmingRestart = false
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        if let release = updates.release {
            VStack(alignment: .leading, spacing: 14) {
                #if DEBUG
                if updates.isPreview {
                    HStack {
                        Text("UI 预览 · 不会安装").font(.callout).foregroundStyle(.secondary)
                        Spacer()
                        Menu("预览状态", systemImage: "eye") {
                            Button("发现更新", action: updates.showPreviewAvailable)
                            #if os(macOS)
                            Button("下载进度", action: updates.download)
                            Button("下载完成", action: updates.showPreviewReady)
                            Button("下载失败", action: updates.showPreviewFailure)
                            #endif
                            Divider()
                            Button("退出预览", systemImage: "xmark.circle", action: updates.exitPreview)
                        }
                    }
                    Divider()
                }
                #endif
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "app.badge")
                        .font(.title2)
                        .foregroundStyle(.tint)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("发现新版本").font(.headline)
                        Text(verbatim: "YYReader \(release.version)").foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                    #if os(macOS)
                    if canDismiss, updates.canDismissBanner {
                        Button("稍后提醒", systemImage: "xmark", action: updates.dismissBanner)
                            .labelStyle(.iconOnly)
                            .buttonStyle(.borderless)
                            .frame(minWidth: 44, minHeight: 44)
                    }
                    #endif
                }
                #if os(macOS)
                if updates.isDownloading {
                    VStack(spacing: 6) {
                        ProgressView(value: updates.downloadProgress)
                        HStack {
                            Text("正在下载更新…").foregroundStyle(.secondary)
                            Spacer()
                            Text(updates.downloadProgress, format: .percent.precision(.fractionLength(0))).monospacedDigit()
                            Button("取消", action: updates.cancelDownload).buttonStyle(.borderless)
                        }
                        Text(verbatim: "\(Int64(updates.downloadProgress * Double(release.asset.size)).formatted(.byteCount(style: .file))) / \(release.asset.size.formatted(.byteCount(style: .file)))")
                            .font(.callout).foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                } else if updates.isInstalling {
                    ProgressView("正在准备安装…")
                } else if updates.downloadedArchive != nil {
                    HStack {
                        Button("安装并重启", systemImage: "arrow.clockwise") { confirmingRestart = true }
                            .buttonStyle(.borderedProminent)
                        if updates.errorMessage != nil {
                            Button("重新下载") { Task { await updates.retryDownload() } }
                        }
                    }
                } else {
                    Button("下载更新", systemImage: "arrow.down.to.line", action: updates.download)
                        .buttonStyle(.borderedProminent)
                }
                #else
                mobileActions(release)
                Text("下载后使用 SideStore 等侧载工具重新签名安装。")
                    .font(.subheadline).foregroundStyle(.secondary)
                #endif
                DisclosureGroup("更新内容", isExpanded: $expanded) {
                    ReleaseNotesView(notes: release.notes)
                        .padding(.top, 8)
                }
                Link("在 GitHub 查看", destination: release.pageURL).font(.callout)
                if let error = updates.errorMessage {
                    Label(error, systemImage: "exclamationmark.circle").foregroundStyle(.red)
                }
                #if DEBUG
                if updates.isPreview, let message = updates.statusMessage {
                    Text(message).font(.callout).foregroundStyle(.secondary)
                }
                #endif
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.background, in: .rect(cornerRadius: 18))
            .overlay { RoundedRectangle(cornerRadius: 18).strokeBorder(.tint.opacity(0.2)) }
            .alert("安装更新并重启？", isPresented: $confirmingRestart) {
                #if os(macOS)
                Button("安装并重启") { Task { await updates.install(store: services.libraryStore) } }
                #endif
                Button("取消", role: .cancel) {}
            } message: {
                Text("阅读进度会先保存，更新完成后自动重新打开 YYReader。")
            }
        }
    }

    private func mobileActions(_ release: AppRelease) -> some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(spacing: 10)) : AnyLayout(HStackLayout(spacing: 10))
        return layout {
            Group {
                #if DEBUG
                if updates.isPreview {
                    Button(action: updates.previewIPALink) { ipaButtonLabel }
                } else {
                    Link(destination: release.asset.browserDownloadURL) { ipaButtonLabel }
                }
                #else
                Link(destination: release.asset.browserDownloadURL) { ipaButtonLabel }
                #endif
            }
            .buttonStyle(.borderedProminent)
            .frame(minHeight: 44)
            if canDismiss, updates.canDismissBanner {
                Button(action: updates.dismissBanner) {
                    Text("暂时忽略").frame(minHeight: 20)
                }
                .buttonStyle(.bordered)
                .frame(minHeight: 44)
            }
        }
        .font(.callout)
        .controlSize(.regular)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var ipaButtonLabel: some View {
        Label("下载 IPA", systemImage: "arrow.down.to.line")
            .labelStyle(.titleAndIcon)
            .frame(minHeight: 20, alignment: .center)
    }
}
