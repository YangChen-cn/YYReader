import SwiftUI

/// A bounded three-page strip: only the current page and its neighbors are rendered.
struct MobileMangaPager: View {
    let pages: [URL]
    let referer: URL
    let pageIndex: Int
    let size: CGSize
    let imageCache: MangaImageCache
    let hasPrevious: Bool
    let hasNext: Bool
    let turn: (Int) -> Void
    let toggleControls: () -> Void
    let didLoad: (Int, Double) -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var offset = 0.0
    @State private var animationID: UUID?
    @State private var showingZoom = false

    var body: some View {
        HStack(spacing: 0) {
            ForEach(-1...1, id: \.self) { neighbor in
                let index = pageIndex + neighbor
                ZStack {
                    if pages.indices.contains(index) {
                        MangaPageImage(url: pages[index], referer: referer, pageNumber: index + 1,
                            imageCache: imageCache, allowsZoom: false) { didLoad(index, $0) }
                            .padding(.vertical, 4)
                            .id(pages[index])
                    } else if neighbor < 0 && hasPrevious {
                        Label("上一话", systemImage: "chevron.left")
                    } else if neighbor > 0 && hasNext {
                        Label("下一话", systemImage: "chevron.right")
                    }
                }
                .frame(width: size.width, height: size.height)
            }
        }
        .offset(x: offset)
        .frame(width: size.width, height: size.height)
        .clipped()
        .contentShape(Rectangle())
        .gesture(DragGesture(minimumDistance: 12)
            .onChanged { drag in
                guard animationID == nil,
                      abs(drag.translation.width) > abs(drag.translation.height) * 1.3 else { return }
                let direction = drag.translation.width < 0 ? 1 : -1
                offset = max(-size.width, min(size.width, drag.translation.width)) * (canTurn(direction) ? 1 : 0.2)
            }
            .onEnded { drag in
                guard animationID == nil else { return }
                if let direction = MangaPageLayout.swipeDirection(translation: drag.translation,
                    predictedWidth: drag.predictedEndTranslation.width, viewportWidth: size.width) {
                    animateTurn(direction)
                } else { resetOffset() }
            })
        .simultaneousGesture(TapGesture(count: 2).exclusively(before: SpatialTapGesture())
            .onEnded { value in
                guard animationID == nil else { return }
                switch value {
                case .first: showingZoom = true
                case let .second(tap):
                    switch MangaPageLayout.tap(at: tap.location.x, width: size.width) {
                    case .backward: animateTurn(-1)
                    case .forward: animateTurn(1)
                    case .controls: toggleControls()
                    }
                }
            })
        .fullScreenCover(isPresented: $showingZoom) {
            if pages.indices.contains(pageIndex) {
                MobileMangaZoomView(url: pages[pageIndex], referer: referer,
                                    pageNumber: pageIndex + 1, imageCache: imageCache)
            }
        }
        .onChange(of: pageIndex) { _, _ in cancelTransition() }
        .onChange(of: size) { _, _ in cancelTransition() }
        .onDisappear { cancelTransition() }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("manga.canvas")
        .accessibilityAction(named: "上一页") { animateTurn(-1) }
        .accessibilityAction(named: "下一页") { animateTurn(1) }
        .accessibilityAction(named: "放大图片") { showingZoom = true }
    }

    private func canTurn(_ direction: Int) -> Bool {
        pages.indices.contains(pageIndex + direction) || (direction < 0 ? hasPrevious : hasNext)
    }

    private func animateTurn(_ direction: Int) {
        guard animationID == nil, canTurn(direction) else { resetOffset(); return }
        guard !reduceMotion else { cancelTransition(); turn(direction); return }
        let id = UUID()
        animationID = id
        withAnimation(.easeOut(duration: 0.22), completionCriteria: .removed) {
            offset = direction < 0 ? size.width : -size.width
        } completion: {
            guard animationID == id else { return }
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                cancelTransition()
                turn(direction)
            }
        }
    }

    private func resetOffset() {
        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.18)) { offset = 0 }
    }

    private func cancelTransition() {
        animationID = nil
        offset = 0
    }
}
