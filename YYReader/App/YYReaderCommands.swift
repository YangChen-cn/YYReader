import SwiftUI

struct YYReaderCommands: Commands {
    @FocusedValue(\.readerCommandActions) private var actions
    @AppStorage(ReaderPreferenceKeys.academicModeShortcut)
    private var academicModeShortcut = ReaderKeyboardShortcut.defaultValue.storageValue

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

            academicModeButton
        }
    }

    @ViewBuilder
    private var academicModeButton: some View {
        let shortcut = ReaderKeyboardShortcut(storageValue: academicModeShortcut) ?? .defaultValue
        Button("切换论文伪装模式", action: toggleAcademicMode)
            .keyboardShortcut(shortcut.keyEquivalent, modifiers: shortcut.eventModifiers)
            .disabled(actions?.canToggleAcademicMode != true)
    }

    private func addURL() { actions?.addURL() }
    private func refreshCatalog() { actions?.refreshCatalog() }
    private func previousChapter() { actions?.previousChapter() }
    private func nextChapter() { actions?.nextChapter() }
    private func toggleCatalog() { actions?.toggleCatalog() }
    private func toggleAppearance() { actions?.toggleAppearance() }
    private func toggleAcademicMode() { actions?.toggleAcademicMode() }
}
