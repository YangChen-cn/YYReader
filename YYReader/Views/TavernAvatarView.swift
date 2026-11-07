import SwiftUI
import ImageIO

struct TavernAvatarView: View {
    let speaker: String
    let fileName: String?
    let accent: Color
    let size: Double
    var previewData: Data? = nil
    var usesRemoteFallback = false
    @AppStorage(ReaderPreferenceKeys.tavernRemoteAvatars) private var remoteEnabled = true
    @State private var image: CGImage?

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 9)
                .fill(LinearGradient(colors: [accent.opacity(0.45), Color(white: 0.16)], startPoint: .topLeading, endPoint: .bottomTrailing))
            if let image {
                Image(decorative: image, scale: 1).resizable().scaledToFill()
                    .frame(width: size, height: size, alignment: .top)
            } else {
                Text(String(speaker.prefix(2))).font(.system(size: size * 0.30, weight: .medium, design: .serif))
                    .foregroundStyle(.white)
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: 9))
        .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(accent.opacity(0.7), lineWidth: 1))
        .shadow(color: .black.opacity(0.18), radius: 10, y: 6)
        .accessibilityLabel(Text("\(speaker)的头像"))
        .onChange(of: previewData, initial: true) { _, data in
            guard let data, let source = CGImageSourceCreateWithData(data as CFData, nil) else { return }
            image = CGImageSourceCreateImageAtIndex(source, 0, nil)
        }
        .task(id: speaker + "|" + (fileName ?? "") + "|" + String(usesRemoteFallback && remoteEnabled)) {
            guard previewData == nil else { return }
            image = nil
            do {
                let data: Data
                if let fileName { data = try await TavernAvatarStore.shared.read(fileName) }
                else if usesRemoteFallback && remoteEnabled { data = try await TavernAvatarStore.shared.remote(for: speaker) }
                else { return }
                guard !Task.isCancelled, previewData == nil else { return }
                if let source = CGImageSourceCreateWithData(data as CFData, nil) {
                    image = CGImageSourceCreateImageAtIndex(source, 0, nil)
                }
            } catch {
                // An optional missing avatar falls back to initials, preserving the text.
                image = nil
            }
        }
    }
}
