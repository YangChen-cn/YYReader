import SwiftUI
import UniformTypeIdentifiers

struct TavernCharacterEditor: View {
    let speaker: String
    let inferredPlayer: String
    @Environment(\.dismiss) private var dismiss
    @AppStorage(ReaderPreferenceKeys.tavernCharacters) private var charactersData = Data()
    @AppStorage(ReaderPreferenceKeys.tavernPlayerName) private var playerName = ""
    @State private var color = Color(red: 0.85, green: 0.55, blue: 0.64)
    @State private var isPlayer = false
    @State private var choosingAvatar = false
    @State private var avatarData: Data?
    @State private var avatarFile: String?
    @State private var isWorking = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 16) {
                        TavernAvatarView(speaker: speaker, fileName: avatarFile, accent: color, size: 64, previewData: avatarData, usesRemoteFallback: speaker != (playerName.isEmpty ? inferredPlayer : playerName))
                        VStack(alignment: .leading, spacing: 8) {
                            Text(speaker).font(.headline)
                            Button(avatarData == nil ? "选择头像" : "已选择新头像") { choosingAvatar = true }
                        }
                    }
                    .padding(.vertical, 8)
                    ColorPicker("角色颜色", selection: $color, supportsOpacity: false)
                    Toggle("设为主角（右侧对话）", isOn: $isPlayer)
                }
                if let errorMessage { Text(errorMessage).foregroundStyle(.red) }
            }
            .formStyle(.grouped)
            .navigationTitle("角色外观")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消", action: dismiss.callAsFunction).disabled(isWorking) }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { Task { await save() } }.disabled(isWorking)
                }
            }
        }
        .interactiveDismissDisabled(isWorking)
        .frame(minWidth: 300, idealWidth: 380, minHeight: 310, idealHeight: 360)
        .onAppear {
            let appearance = TavernCharacterAppearance.characters(from: charactersData)[speaker] ?? .init()
            color = Self.color(hex: appearance.colorHex)
            avatarFile = appearance.avatarFile
            isPlayer = speaker == (playerName.isEmpty ? inferredPlayer : playerName)
        }
        .fileImporter(isPresented: $choosingAvatar, allowedContentTypes: [.image]) { result in
            switch result {
            case let .success(url):
                Task {
                    isWorking = true
                    defer { isWorking = false }
                    do {
                        avatarData = try await TavernAvatarStore.shared.prepare(from: url)
                        errorMessage = nil
                    } catch { errorMessage = "读取头像失败：\(error.localizedDescription)" }
                }
            case let .failure(error): errorMessage = "读取头像失败：\(error.localizedDescription)"
            }
        }
    }

    private func save() async {
        isWorking = true
        defer { isWorking = false }
        do {
            if let avatarData { avatarFile = try await TavernAvatarStore.shared.save(avatarData, character: speaker) }
            var characters = TavernCharacterAppearance.characters(from: charactersData)
            let resolved = color.resolve(in: EnvironmentValues())
            let hex = String(format: "%02X%02X%02X", Int(resolved.red * 255), Int(resolved.green * 255), Int(resolved.blue * 255))
            characters[speaker] = TavernCharacterAppearance(colorHex: hex, avatarFile: avatarFile)
            charactersData = try JSONEncoder().encode(characters)
            if isPlayer { playerName = speaker }
            else if speaker == (playerName.isEmpty ? inferredPlayer : playerName) { playerName = "—" }
            dismiss()
        } catch { errorMessage = "保存角色外观失败：\(error.localizedDescription)" }
    }

    static func color(hex: String) -> Color {
        let value = UInt32(hex, radix: 16) ?? 0xD88DA3
        return Color(red: Double((value >> 16) & 255) / 255,
                     green: Double((value >> 8) & 255) / 255, blue: Double(value & 255) / 255)
    }
}
