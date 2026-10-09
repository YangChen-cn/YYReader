import SwiftUI
#if os(iOS)
import UIKit
#else
import AppKit
#endif

struct MangaPageImage: View {
    let url: URL
    let referer: URL
    let pageNumber: Int
    var imageCache: MangaImageCache = .shared
    let didLoad: (Double) -> Void
    @State private var image: Image?
    @State private var errorMessage: String?
    @State private var retry = 0
    @State private var requestID: UUID?

    var body: some View {
        ZStack {
            if let image {
                image.resizable().aspectRatio(contentMode: .fit)
                    .accessibilityLabel("漫画第 \(pageNumber) 页")
            } else {
                VStack(spacing: 10) {
                    if let errorMessage {
                        Image(systemName: "photo.badge.exclamationmark")
                        Text(errorMessage).font(.caption).multilineTextAlignment(.center)
                        Button("重试加载") { retry += 1 }
                    } else { ProgressView("加载第 \(pageNumber) 页…") }
                }.padding()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityIdentifier("manga.image.\(pageNumber)")
        .onDisappear { requestID = nil; image = nil }
        .task(id: "\(url.absoluteString)#\(retry)") {
            let token = UUID()
            requestID = token
            image = nil
            errorMessage = nil
            do {
                let payload = try await imageCache.image(at: url, referer: referer)
                try Task.checkCancellation()
                guard requestID == token else { return }
                #if os(iOS)
                guard let native = UIImage(data: payload.data) else { throw HTMLLoadError.invalidResponse }
                image = Image(uiImage: native)
                #else
                guard let native = NSImage(data: payload.data) else { throw HTMLLoadError.invalidResponse }
                image = Image(nsImage: native)
                #endif
                didLoad(payload.aspectRatio)
            } catch is CancellationError {
                // Leaving this page normally cancels the view's waiter, not shared decodes.
            } catch let error as URLError where error.code == .cancelled {
            } catch {
                guard !Task.isCancelled, requestID == token else { return }
                errorMessage = error.localizedDescription
            }
        }
    }
}
