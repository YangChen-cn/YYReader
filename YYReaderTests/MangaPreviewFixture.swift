#if DEBUG
import CryptoKit
import Foundation
import SwiftData
@testable import YYReader

/// Tiny invented images for interaction tests, with no live website requests.
@MainActor
enum MangaPreviewFixture {
    static func seed(in context: ModelContext, directory: URL? = nil) throws -> Book {
        let directory = directory ?? URL.applicationSupportDirectory.appending(path: "YYReader/MangaImages")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let image = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAIAAAADCAIAAAA2iEnWAAAAEElEQVR4nGMomLAAiBhQKABlVQnBJBo8DwAAAABJRU5ErkJggg==")!
        let book = Book(title: "漫画布局预览", author: "预览作者", sourceHost: "www.guazimanhua.com",
                        catalogURL: "https://www.guazimanhua.com/comic.php?id=900001")
        for (chapterNumber, count) in [(1, 7), (2, 5)] {
            let chapter = Chapter(sourceURL: "https://www.guazimanhua.com/chapter.php?id=90000\(chapterNumber)",
                                  title: "第\(chapterNumber)话 测试画面", sortIndex: chapterNumber, cachedAt: .now)
            let urls = (1...count).map { URL(string: "https://example.invalid/manga-layout-test/ch\(chapterNumber)/page\($0).png")! }
            chapter.replaceImages(urls)
            chapter.imagesCachedAt = .now
            chapter.book = book
            book.chapters.append(chapter)
            for url in urls {
                let digest = SHA256.hash(data: Data(url.absoluteString.utf8)).map { String(format: "%02x", $0) }.joined()
                try image.write(to: directory.appending(path: digest))
            }
        }
        book.currentChapterID = book.chapters.first?.id
        context.insert(book)
        try context.save()
        return book
    }
}
#endif
