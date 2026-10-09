import SwiftUI

/// Zooming has its own surface, so panning cannot accidentally turn a reading page.
struct MobileMangaZoomView: View {
    let url: URL
    let referer: URL
    let pageNumber: Int
    let imageCache: MangaImageCache
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var scale = 2.0
    @State private var offset = CGSize.zero
    @State private var aspectRatio = 0.7
    @GestureState private var magnification = 1.0
    @GestureState private var translation = CGSize.zero

    private var visibleScale: Double { min(4, max(1, scale * magnification)) }

    var body: some View {
        GeometryReader { geometry in
            MangaPageImage(url: url, referer: referer, pageNumber: pageNumber,
                           imageCache: imageCache, allowsZoom: false) { aspectRatio = $0 }
                .frame(width: geometry.size.width, height: geometry.size.height)
                .scaleEffect(visibleScale)
                .offset(clampedOffset(CGSize(width: offset.width + translation.width,
                                             height: offset.height + translation.height), in: geometry.size))
                .frame(width: geometry.size.width, height: geometry.size.height)
                .contentShape(Rectangle())
                .clipped()
                .gesture(MagnifyGesture()
                    .updating($magnification) { value, state, _ in state = value.magnification }
                    .onEnded { value in
                        scale = min(4, max(1, scale * value.magnification))
                        offset = clampedOffset(offset, in: geometry.size, scale: scale)
                    })
                .simultaneousGesture(DragGesture()
                    .updating($translation) { value, state, _ in
                        if visibleScale > 1 { state = value.translation }
                    }
                    .onEnded { value in
                        offset = clampedOffset(CGSize(width: offset.width + value.translation.width,
                                                      height: offset.height + value.translation.height), in: geometry.size)
                    })
                .onTapGesture(count: 2) {
                    withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) {
                        scale = scale > 1 ? 1 : 2
                        offset = .zero
                    }
                }
                .onChange(of: geometry.size) { _, size in offset = clampedOffset(offset, in: size) }
        }
        .background(Color.black)
        .preferredColorScheme(.dark)
        .safeAreaInset(edge: .top) {
            HStack {
                Text("第 \(pageNumber) 页").font(.subheadline)
                Spacer()
                Button("还原", systemImage: "arrow.down.right.and.arrow.up.left") { scale = 1; offset = .zero }
                    .labelStyle(.iconOnly)
                Button("关闭", systemImage: "xmark", action: dismiss.callAsFunction)
                    .labelStyle(.iconOnly)
                    .accessibilityIdentifier("manga.closeZoom")
            }
            .padding(.horizontal)
            .padding(.vertical, 10)
        }
        .accessibilityAction(named: "放大") { scale = min(4, scale + 0.5) }
        .accessibilityAction(named: "缩小") { scale = max(1, scale - 0.5); offset = .zero }
    }

    private func clampedOffset(_ value: CGSize, in size: CGSize, scale: Double? = nil) -> CGSize {
        let height = min(size.height, size.width / aspectRatio)
        let zoom = scale ?? visibleScale
        let maxX = max(0, (height * aspectRatio * zoom - size.width) / 2)
        let maxY = max(0, (height * zoom - size.height) / 2)
        return CGSize(width: max(-maxX, min(maxX, value.width)), height: max(-maxY, min(maxY, value.height)))
    }
}
