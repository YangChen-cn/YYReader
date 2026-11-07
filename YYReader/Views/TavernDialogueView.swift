import SwiftUI

struct TavernDialogueView: View {
    let speaker: String
    let text: String
    let inferredPlayer: String
    let fontFamily: ReaderFontFamily
    let fontSize: Double
    let lineSpacing: Double
    let compact: Bool
    @AppStorage(ReaderPreferenceKeys.tavernCharacters) private var charactersData = Data()
    @AppStorage(ReaderPreferenceKeys.tavernPlayerName) private var playerName = ""
    @State private var editingAppearance = false
    @ScaledMetric(relativeTo: .body) private var textScale = 1.0

    private var isPlayer: Bool {
        speaker == (playerName.isEmpty ? inferredPlayer : playerName) || speaker == "{{user}}"
    }

    var body: some View {
        let appearance = TavernCharacterAppearance.characters(from: charactersData)[speaker] ?? .init()
        let gold = Color(red: 0.86, green: 0.73, blue: 0.43)
        let nameColor = isPlayer ? gold : TavernCharacterEditor.color(hex: appearance.colorHex)
        let edge = isPlayer ? gold : Color(red: 0.37, green: 0.90, blue: 1)
        HStack(alignment: .top, spacing: compact ? 10 : 20) {
            if !isPlayer { Button { editingAppearance = true } label: {
                    TavernAvatarView(speaker: speaker, fileName: appearance.avatarFile, accent: nameColor,
                                     size: compact ? 44 : 68, usesRemoteFallback: !isPlayer)
                }
                .buttonStyle(.plain)
                .help("导入头像")
                .accessibilityLabel(Text("导入\(speaker)的头像")) }
            VStack(alignment: .leading, spacing: compact ? 14 : 18) {
                HStack {
                    if isPlayer { appearanceButton(accent: edge) }
                    if isPlayer { Spacer(minLength: 8) }
                    Text(speaker == "{{user}}" ? (playerName.isEmpty ? "主角" : playerName) : speaker)
                        .font(.system(size: max(14, fontSize * 0.85) * textScale, weight: .semibold))
                        .foregroundStyle(nameColor)
                    if !isPlayer { Spacer(minLength: 8) }
                    if !isPlayer { appearanceButton(accent: edge) }
                }
                HStack(spacing: 14) {
                    if !isPlayer { Rectangle().fill(edge.opacity(0.45)).frame(width: 1) }
                    Text(inlineText(text))
                        .font((fontFamily == .serif ? ReaderFontFamily.kaiti : fontFamily).font(size: fontSize * textScale))
                        .lineSpacing(lineSpacing * textScale)
                        .foregroundStyle(Color(white: 0.96))
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    if isPlayer { Rectangle().fill(edge.opacity(0.45)).frame(width: 1) }
                }
                .fixedSize(horizontal: false, vertical: true)
            }
            .padding(compact ? 16 : 22)
            .background {
                RoundedRectangle(cornerRadius: 10)
                    .fill(LinearGradient(colors: [Color(white: 0.25), Color(white: 0.29)], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .background(Color(white: 0.25), in: RoundedRectangle(cornerRadius: 10))
            }
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.white.opacity(0.20), lineWidth: 1))
            .overlay(alignment: isPlayer ? .trailing : .leading) {
                RoundedRectangle(cornerRadius: 2).fill(edge).frame(width: 4).padding(.vertical, 9)
            }
            .shadow(color: .black.opacity(0.10), radius: compact ? 8 : 16, y: 8)
            if isPlayer { Button { editingAppearance = true } label: {
                    TavernAvatarView(speaker: speaker, fileName: appearance.avatarFile, accent: nameColor,
                                     size: compact ? 44 : 68, usesRemoteFallback: !isPlayer)
                }
                .buttonStyle(.plain)
                .help("导入头像")
                .accessibilityLabel(Text("导入\(speaker)的头像")) }
        }
        .padding(.vertical, compact ? 6 : 10)
        .sheet(isPresented: $editingAppearance) {
            TavernCharacterEditor(speaker: speaker, inferredPlayer: inferredPlayer)
        }
    }

    private func appearanceButton(accent: Color) -> some View {
        Button("外观") { editingAppearance = true }
            .font(.caption.weight(.medium))
            .foregroundStyle(accent.opacity(0.85))
            .padding(.horizontal, 9).padding(.vertical, 6)
            .background(accent.opacity(0.06), in: RoundedRectangle(cornerRadius: 5))
            .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(accent.opacity(0.3)))
            .buttonStyle(.plain)
            .accessibilityLabel(Text("编辑\(speaker)的外观"))
    }

    private func inlineText(_ source: String) -> AttributedString {
        (try? AttributedString(markdown: source, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(source)
    }
}
