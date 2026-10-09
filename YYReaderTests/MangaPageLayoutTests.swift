import Foundation
import Testing
@testable import YYReader

struct MangaPageLayoutTests {
    private let wide = CGSize(width: 1100, height: 700)
    private let narrow = CGSize(width: 650, height: 850)

    @Test func singleDoubleAndAutomaticPreserveOriginalImageIndices() {
        let ratios: [Double?] = Array(repeating: 0.7, count: 7)
        let single = MangaPageLayout(aspectRatios: ratios, mode: .single, firstPageAlone: true, viewport: wide)
        let double = MangaPageLayout(aspectRatios: ratios, mode: .double, firstPageAlone: true, viewport: wide)
        #expect(single.groups == (0..<7).map { $0..<$0 + 1 })
        #expect(double.groups == [0..<1, 1..<3, 3..<5, 5..<7])
        #expect(MangaPageLayout(aspectRatios: ratios, mode: .automatic, firstPageAlone: true, viewport: wide) == double)
        #expect(MangaPageLayout(aspectRatios: ratios, mode: .automatic, firstPageAlone: true, viewport: narrow) == single)
        // Index 2 is the second image in a spread, never rewritten as spread index 1.
        #expect(double.group(containing: 2) == 1..<3)
        #expect(single.group(containing: 2) == 2..<3)
        #expect(double.adjacentIndex(from: 2, direction: 1) == 3)
        #expect(double.adjacentIndex(from: 2, direction: -1) == 0)
    }

    @Test func landscapeCoverAndOddTailNeverJoinAnotherChapter() {
        let layout = MangaPageLayout(aspectRatios: [0.7, 0.7, 1.6, 0.7, 0.7, 0.7], mode: .double,
                                     firstPageAlone: true, viewport: wide)
        #expect(layout.groups == [0..<1, 1..<2, 2..<3, 3..<5, 5..<6])
        #expect(layout.adjacentIndex(from: 5, direction: 1) == nil)
        #expect(layout.adjacentIndex(from: 0, direction: -1) == nil)
        let noCover = MangaPageLayout(aspectRatios: [0.7, 0.7, 0.7], mode: .double, firstPageAlone: false, viewport: wide)
        #expect(noCover.groups == [0..<2, 2..<3])
        #expect(MangaPageLayout(aspectRatios: [], mode: .double, firstPageAlone: true, viewport: wide).groups.isEmpty)
    }

    @Test func reflowAndNewlyKnownLandscapeKeepTheRequestedOriginalPage() {
        let before = MangaPageLayout(aspectRatios: Array(repeating: nil, count: 8), mode: .double,
                                     firstPageAlone: true, viewport: wide)
        let after = MangaPageLayout(aspectRatios: [0.7, 1.8, 0.7, 0.7, 0.7, 0.7, 0.7, 0.7], mode: .double,
                                    firstPageAlone: true, viewport: wide)
        for index in 0..<8 {
            #expect(before.group(containing: index).contains(index))
            #expect(after.group(containing: index).contains(index))
        }
        #expect(after.group(containing: 5) == 4..<6)
    }

    @Test func fitKeepsBothDimensionsInsideCanvasWithoutStretching() {
        for ratios in [[0.7, 0.8], [1.8], [0.7]] {
            let height = MangaPageLayout.fittedHeight(ratios: ratios, viewport: wide)
            #expect(height <= wide.height)
            #expect(height * ratios.reduce(0, +) + Double(ratios.count - 1) * 4 <= wide.width + 0.001)
        }
        #expect(MangaPageLayout.scrollWidth(viewportWidth: 400, desktop: false) == 400)
        #expect(MangaPageLayout.scrollWidth(viewportWidth: 1100, desktop: true) > MangaPageLayout.scrollWidth(viewportWidth: 800, desktop: true))
        #expect(MangaPageLayout.gap(after: 0, ratios: [0.3, 0.3, 0.3]) == 0)
        #expect(MangaPageLayout.gap(after: 0, ratios: [0.7, 0.7]) == 4)
    }

    @Test func tapZonesLeaveMiddleForChrome() {
        #expect(MangaPageLayout.tap(at: 20, width: 400) == .backward)
        #expect(MangaPageLayout.tap(at: 200, width: 400) == .controls)
        #expect(MangaPageLayout.tap(at: 380, width: 400) == .forward)
    }
}
