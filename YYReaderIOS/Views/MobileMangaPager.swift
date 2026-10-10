import SwiftUI

/// A bounded three-group strip: iPhone uses single pages, iPad can use spreads.
struct MobileMangaPager: View {
    let pages: [URL]
    let referer: URL
    let pageIndex: Int
    let layout: MangaPageLayout
    let aspectRatios: [Double?]
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
    @State private var zoomPageIndex = 0

    var body: some View {
        HStack(spacing: 0) {
            // Group bounds retain neighboring images across a page turn.
            ForEach(layout.neighboringGroups(containing: pageIndex), id: \.lowerBound) { group in
                ZStack {
                    if group.count == 2 {
                        spread(group)
                    } else if let index = group.first, pages.indices.contains(index) {
                        MangaPageImage(url: pages[index], referer: referer, pageNumber: index + 1,
                            imageCache: imageCache, allowsZoom: false) { didLoad(index, $0) }
                            .padding(.vertical, 4)
                            .id(pages[index])
                    } else if group.lowerBound < 0 && hasPrevious {
                        Label("上一话", systemImage: "chevron.left")
                    } else if group.lowerBound >= pages.count && hasNext {
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
        .simultaneousGesture(SpatialTapGesture(count: 2).exclusively(before: SpatialTapGesture())
            .onEnded { value in
                guard animationID == nil else { return }
                switch value {
                case let .first(tap):
                    zoomPageIndex = imageIndex(at: tap.location.x)
                    showingZoom = true
                case let .second(tap):
                    switch MangaPageLayout.tap(at: tap.location.x, width: size.width) {
                    case .backward: turnImmediately(-1)
                    case .forward: turnImmediately(1)
                    case .controls: toggleControls()
                    }
                }
            })
        .fullScreenCover(isPresented: $showingZoom) {
            if pages.indices.contains(zoomPageIndex) {
                MobileMangaZoomView(url: pages[zoomPageIndex], referer: referer,
                                    pageNumber: zoomPageIndex + 1, imageCache: imageCache)
            }
        }
        .onChange(of: pageIndex) { _, _ in cancelTransition() }
        .onChange(of: size) { _, _ in cancelTransition() }
        .onChange(of: layout) { _, _ in cancelTransition() }
        .onDisappear { cancelTransition() }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("manga.canvas")
        .accessibilityAction(named: "上一页") { turnImmediately(-1) }
        .accessibilityAction(named: "下一页") { turnImmediately(1) }
        .accessibilityAction(named: "放大图片") { zoomPageIndex = pageIndex; showingZoom = true }
    }

    private func spread(_ group: Range<Int>) -> some View {
        let ratios = group.map { aspectRatios[$0] ?? 0.7 }
        let height = spreadHeight(ratios)
        return HStack(spacing: 0) {
            ForEach(Array(group), id: \.self) { index in
                if index > group.lowerBound {
                    Rectangle().fill(Color.primary.opacity(0.18))
                        .frame(width: 1, height: height).frame(width: 16)
                        .accessibilityHidden(true)
                }
                MangaPageImage(url: pages[index], referer: referer, pageNumber: index + 1,
                    imageCache: imageCache, allowsZoom: false) { didLoad(index, $0) }
                    .frame(width: height * ratios[index - group.lowerBound], height: height)
                    .id(pages[index])
                    .accessibilityAction(named: "放大图片") { zoomPageIndex = index; showingZoom = true }
            }
        }
    }

    private func spreadHeight(_ ratios: [Double]) -> Double {
        MangaPageLayout.fittedHeight(ratios: ratios,
            viewport: CGSize(width: max(1, size.width - 16), height: max(1, size.height - 8)), gap: 16)
    }

    private func imageIndex(at x: Double) -> Int {
        let group = layout.group(containing: pageIndex)
        guard group.count == 2 else { return pageIndex }
        let ratios = group.map { aspectRatios[$0] ?? 0.7 }
        let height = spreadHeight(ratios)
        let left = (size.width - height * ratios.reduce(0, +) - 16) / 2
        return x < left + height * ratios[0] + 8 ? group.lowerBound : group.lowerBound + 1
    }

    private func canTurn(_ direction: Int) -> Bool {
        layout.adjacentIndex(from: pageIndex, direction: direction) != nil || (direction < 0 ? hasPrevious : hasNext)
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

    private func turnImmediately(_ direction: Int) {
        guard animationID == nil, canTurn(direction) else { return }
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            cancelTransition()
            turn(direction)
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
