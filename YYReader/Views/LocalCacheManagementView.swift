import SwiftUI

struct LocalCacheManagementView: View {
    let store: LibraryStore
    @State private var summary = LocalCacheSummary()
    @State private var isWorking = false
    @State private var errorMessage: String?

    var body: some View {
        Form {
            Section {
                LabeledContent("本地缓存", value: size(summary.totalBytes))
                    .accessibilityIdentifier("cache.totalSize")
                Button("清空全部缓存", systemImage: "trash", role: .destructive) { clear(nil) }
                    .disabled(isWorking || summary.totalBytes == 0)
                    .accessibilityIdentifier("cache.clearAll")
                if isWorking { ProgressView("正在处理…") }
            } footer: {
                Text("清理后保留书架、阅读进度和本地 TXT。")
            }
            Section("按书籍清理") {
                if summary.books.isEmpty {
                    Text("暂无网页书籍缓存").foregroundStyle(.secondary)
                }
                ForEach(summary.books) { entry in
                    HStack(spacing: 12) {
                        Image(systemName: entry.isManga ? "photo.stack" : "book.closed")
                            .foregroundStyle(.secondary)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(entry.title).lineLimit(2)
                            Text(size(entry.totalBytes)).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("清空", systemImage: "trash", role: .destructive) { clear(entry.id) }
                            .disabled(isWorking || entry.totalBytes == 0)
                            .accessibilityLabel("清空\(entry.title)的缓存")
                            .accessibilityIdentifier("cache.book.\(entry.id.uuidString)")
                    }
                }
            }
            Button("刷新统计", systemImage: "arrow.clockwise") { Task { await reload() } }
                .disabled(isWorking)
        }
        .formStyle(.grouped)
        .navigationTitle("本地缓存管理")
        .task { await reload() }
        .alert("缓存操作失败", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("好", role: .cancel) { errorMessage = nil }
        } message: { Text(errorMessage ?? "") }
    }

    private func size(_ bytes: Int) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }

    private func reload() async {
        isWorking = true
        defer { isWorking = false }
        do { summary = try await store.localCacheSummary() }
        catch { errorMessage = error.localizedDescription }
    }

    private func clear(_ bookID: UUID?) {
        guard !isWorking else { return }
        isWorking = true
        Task {
            defer { isWorking = false }
            do {
                try await store.clearLocalCache(bookID: bookID)
                summary = try await store.localCacheSummary()
            } catch { errorMessage = error.localizedDescription }
        }
    }
}
