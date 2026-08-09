import SwiftUI

struct YYReaderCommands: Commands {
    @FocusedValue(\.readerCommandActions) private var actions

    var body: some Commands {
        CommandMenu("阅读") {
            Button("添加网页…", action: addURL)
                .keyboardShortcut("l", modifiers: .command)
                .disabled(actions?.canAddURL != true)

            Button("刷新目录", action: refreshCatalog)
                .keyboardShortcut("r", modifiers: [.command, .shift])
                .disabled(actions?.canRefreshCatalog != true)

            Divider()

            Button("上一章", action: previousChapter)
                .keyboardShortcut("[", modifiers: .command)
                .disabled(actions?.canNavigatePreviousChapter != true)

            Button("下一章", action: nextChapter)
                .keyboardShortcut("]", modifiers: .command)
                .disabled(actions?.canNavigateNextChapter != true)

            Divider()

            Button("显示或隐藏目录", action: toggleCatalog)
                .keyboardShortcut("d", modifiers: [.command, .shift])
                .disabled(actions?.canToggleCatalog != true)

            Button("阅读外观", action: toggleAppearance)
                .keyboardShortcut("a", modifiers: [.command, .option])
                .disabled(actions?.canChangeAppearance != true)
        }
    }

    private func addURL() { actions?.addURL() }
    private func refreshCatalog() { actions?.refreshCatalog() }
    private func previousChapter() { actions?.previousChapter() }
    private func nextChapter() { actions?.nextChapter() }
    private func toggleCatalog() { actions?.toggleCatalog() }
    private func toggleAppearance() { actions?.toggleAppearance() }
}
