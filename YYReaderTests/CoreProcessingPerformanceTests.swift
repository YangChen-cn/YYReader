import Foundation
import Testing
@testable import YYReader

struct CoreProcessingPerformanceTests {
    @Test(arguments: [1_000, 5_000])
    func catalogDedupPreservesOrderAtScale(chapterCount: Int) async throws {
        let seeds = try (1...chapterCount).flatMap { index -> [ChapterSeed] in
            let first = try #require(URL(string: "https://example.com/12/\(index)/1.html"))
            let duplicatePage = try #require(URL(string: "https://example.com/12/\(index)/2.html"))
            return [
                ChapterSeed(title: "第\(index)章", url: first, sortIndex: index * 2 - 1),
                ChapterSeed(title: "重复分页", url: duplicatePage, sortIndex: index * 2)
            ]
        }
        let page = ParsedBookCatalog(
            title: "规模测试",
            author: "测试作者",
            chapters: seeds,
            nextPageURL: nil
        )
        let worker = NovelProcessingWorker()
        let clock = ContinuousClock()
        let startedAt = clock.now

        let result = try await worker.aggregateCatalogPages([page])
        let elapsed = startedAt.duration(to: clock.now)

        #expect(result.chapters.count == chapterCount)
        #expect(result.chapters.first?.title == "第1章")
        #expect(result.chapters.last?.title == "第\(chapterCount)章")
        #expect(result.chapters.map(\.sortIndex) == Array(1...chapterCount))
        print("catalog dedup \(chapterCount): \(elapsed)")
    }

    @Test
    func canonicalizesOneThousandChapterURLsWithoutChangingOrder() throws {
        let input = try (1...1_000).map { index in
            try #require(URL(string: "https://EXAMPLE.com:443/12/\(index)/3.html#page"))
        }
        let clock = ContinuousClock()
        let startedAt = clock.now

        let canonical = input.map {
            URLCanonicalizer.canonicalChapterString($0.absoluteString)
        }
        let elapsed = startedAt.duration(to: clock.now)

        #expect(canonical.count == 1_000)
        #expect(canonical.first == "https://example.com/12/1.html")
        #expect(canonical.last == "https://example.com/12/1000.html")
        print("chapter canonicalization 1000: \(elapsed)")
    }

    @Test
    func aggregatesLargePaginatedChapterOnce() async throws {
        let sourceURL = try #require(URL(string: "https://example.com/12/88/1.html"))
        let allParagraphs = (0..<5_000).map { "用于聚合测试的正文段落 \($0)。" }
        let pages = allParagraphs.chunks(ofCount: 250).enumerated().map { pageIndex, paragraphs in
            ParsedChapterPage(
                title: "第88章",
                bookTitle: "规模测试",
                author: "测试作者",
                paragraphs: paragraphs,
                catalogURL: nil,
                previousChapterURL: nil,
                nextChapterURL: pageIndex == 19
                    ? URL(string: "https://example.com/12/89.html")
                    : nil,
                nextPageURL: nil
            )
        }
        let worker = NovelProcessingWorker()
        let clock = ContinuousClock()
        let startedAt = clock.now

        let result = try await worker.aggregateChapterPages(pages, sourceURL: sourceURL)
        let elapsed = startedAt.duration(to: clock.now)

        #expect(result.bodyText == allParagraphs.joined(separator: "\n\n"))
        #expect(result.chapterURL.absoluteString == "https://example.com/12/88.html")
        #expect(result.nextChapterURL?.absoluteString == "https://example.com/12/89.html")
        print("paragraph aggregation 5000: \(elapsed)")
    }

    @Test(arguments: [50, 200, 1_000])
    func academicPlannerMeasurement(paragraphCount: Int) {
        let paragraphs = (0..<paragraphCount).map { "学术规划测量段落 \($0)" }
        let clock = ContinuousClock()
        let startedAt = clock.now

        let plan = AcademicPaperPlanner.makePlan(
            bookIdentity: "https://example.com/book/",
            chapterIdentity: "https://example.com/book/1.html",
            chapterPosition: 0,
            paragraphs: paragraphs
        )
        let elapsed = startedAt.duration(to: clock.now)

        #expect(plan.paragraphs.map(\.text) == paragraphs)
        #expect(plan.supplements.count <= paragraphCount / 10)
        print("academic planner \(paragraphCount): \(elapsed)")
    }

    @Test
    func continuousReadingTransitionsUseIndexedChapterLookup() {
        let chapterIDs = (0..<5_000).map { _ in UUID() }
        let indexes = Dictionary(uniqueKeysWithValues: chapterIDs.enumerated().map { ($0.element, $0.offset) })
        var gate = ContinuousReaderVisibilityGate()
        var accepted = 0
        let clock = ContinuousClock()
        let startedAt = clock.now

        for index in 1..<chapterIDs.count {
            gate.beginTransaction()
            if gate.accepts(
                candidateID: chapterIDs[index],
                currentID: chapterIDs[index - 1],
                chapterIndexByID: indexes
            ) {
                gate.recordCommit()
                accepted += 1
            }
        }
        let elapsed = startedAt.duration(to: clock.now)

        #expect(accepted == 4_999)
        print("continuous transitions 5000: \(elapsed)")
    }
}

private extension Array {
    func chunks(ofCount size: Int) -> [[Element]] {
        stride(from: 0, to: count, by: size).map { start in
            Array(self[start..<Swift.min(start + size, count)])
        }
    }
}
