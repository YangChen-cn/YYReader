import Foundation
import SwiftSoup

/// Conservative fallback used only when the user explicitly chooses manga.
struct GenericMangaAdapter: NovelSourceAdapter {
    func canHandle(_ document: LoadedHTML) -> Bool { true }

    private let readerSelectors = "[data-reader-images], #comic-content, .comic-content, #manga-reader, .manga-reader, #comic-reader, .comic-reader, #manga-content, .manga-content, .reading-content, .reader-images, .reader-pages, .reader-img-con, .chapter-images, #chapter-img, #ChapterContent, #showimage, .comic-pages, .manga-pages, #images, #viewer, #reader"
    private let noiseSelectors = "script, style, noscript, iframe, header, footer, nav, .ad, .ads, .advertisement, [class*=advert], .banner, .logo, .cover, .thumbnail, .thumbnails, .recommend, .recommendations, .related, [hidden]"

    func parseChapterPage(_ loaded: LoadedHTML) throws -> ParsedChapterPage {
        let dom = try HTMLParsingSupport.document(from: loaded)
        let title = try heading(in: dom)
        let previous = try navigation(in: dom, labels: ["上一话", "上一章", "上一章节", "Previous Chapter"], rel: "prev", base: loaded.finalURL)
        let next = try navigation(in: dom, labels: ["下一话", "下一章", "下一章节", "Next Chapter"], rel: "next", base: loaded.finalURL)
        let catalog = try navigation(in: dom, labels: ["目录", "章节列表", "返回目录", "全部章节", "All Chapters"], base: loaded.finalURL)
        let nextPage = try navigation(in: dom, labels: ["下一页", "下页", "Next Page"], base: loaded.finalURL)
        try dom.select(noiseSelectors).remove()
        let chapterEvidence = isChapterTitle(title) || previous != nil || next != nil
        var candidates: [[URL]] = []
        for container in try dom.select(readerSelectors).array() {
            let identity = try (container.attr("id") + " " + container.attr("class")).lowercased()
            let explicit = container.hasAttr("data-reader-images") || identity.contains("comic") || identity.contains("manga") || identity.contains("chapter-images") || identity.contains("reader-pages")
            guard chapterEvidence || explicit else { continue }
            let images = try images(in: container, base: loaded.finalURL)
            if try images.count >= 2 || (images.count == 1 && chapterEvidence && (explicit || hasLargeImage(container))) {
                candidates.append(images)
            }
        }
        // Semantic containers need a sequence plus chapter evidence and little prose.
        // Never fall back to body or all images on the page.
        if candidates.isEmpty && chapterEvidence {
            for container in try dom.select("article, main, #content, .chapter-content").array() {
                guard try container.text().count < 60 else { continue }
                let images = try images(in: container, base: loaded.finalURL)
                if images.count >= 3 { candidates.append(images) }
            }
        }
        guard let images = candidates.max(by: { $0.count < $1.count }), !images.isEmpty else {
            throw NovelParsingError.noMangaImages
        }
        return ParsedChapterPage(title: title,
            bookTitle: try meta("og:novel:book_name", in: dom) ?? meta("og:book_name", in: dom) ?? bookTitle(in: dom),
            author: try meta("author", in: dom), paragraphs: [],
            catalogURL: catalog,
            previousChapterURL: previous, nextChapterURL: next,
            nextPageURL: nextPage, imageURLs: images)
    }

    func parseCatalogPage(_ loaded: LoadedHTML) throws -> ParsedBookCatalog {
        let dom = try HTMLParsingSupport.document(from: loaded)
        try dom.select(noiseSelectors).remove()
        let containers = try dom.select(".chapter-list, #chapter-list, #chapterlist, .chapter_list, .chapter-grid, .manga-chapters, .comic-chapters, .comic-chapter, .catalog, #catalog, .chapters, #chapters, .playlist, #playlist, .detail-list-select, #chapterlistload").array()
        var candidates: [[ChapterSeed]] = []
        for container in containers {
            var seen = Set<String>()
            var chapters: [ChapterSeed] = []
            for link in try container.select("a[href]").array() {
                let title = try link.text().trimmingCharacters(in: .whitespacesAndNewlines)
                guard isChapterTitle(title), let url = HTMLParsingSupport.absoluteURL(for: link, relativeTo: loaded.finalURL),
                      ["http", "https"].contains(url.scheme?.lowercased() ?? ""),
                      HTMLParsingSupport.isSameOrigin(url, as: loaded.finalURL),
                      seen.insert(URLCanonicalizer.canonicalString(url.absoluteString)).inserted else { continue }
                chapters.append(ChapterSeed(title: title, url: url, sortIndex: chapters.count + 1))
            }
            if chapters.count >= 2 { candidates.append(chapters) }
        }
        guard let chapters = candidates.max(by: { $0.count < $1.count }) else { throw NovelParsingError.missingCatalog }
        return ParsedBookCatalog(title: try meta("og:book_name", in: dom) ?? heading(in: dom),
            author: try meta("author", in: dom) ?? "未知作者", chapters: chapters,
            nextPageURL: try navigation(in: dom, labels: ["下一页", "下页", "Next Page"], base: loaded.finalURL))
    }

    private func images(in container: Element, base: URL) throws -> [URL] {
        var seen = Set<String>()
        var result: [URL] = []
        for image in try container.select("img").array() {
            let identity = try [image.attr("id"), image.attr("class"), image.attr("alt")].joined(separator: " ").lowercased()
            guard !isNoise(identity) else { continue }
            if let width = try dimension("width", of: image), width < 160 { continue }
            if let height = try dimension("height", of: image), height < 160 { continue }
            for attribute in ["data-original", "data-src", "data-lazy-src", "data-url", "data-echo", "src"] {
                let source = try image.attr(attribute).trimmingCharacters(in: .whitespacesAndNewlines)
                guard !source.isEmpty, var components = URLComponents(url: URL(string: source, relativeTo: base)?.absoluteURL ?? base, resolvingAgainstBaseURL: false),
                      ["http", "https"].contains(components.scheme?.lowercased() ?? ""),
                      !isNoise(source.lowercased()), !source.lowercased().hasSuffix(".svg"), !source.lowercased().hasSuffix(".ico") else { continue }
                components.fragment = nil
                guard let url = components.url, url != base else { continue }
                if seen.insert(url.absoluteString).inserted { result.append(url) }
                break
            }
        }
        return result
    }

    private func isNoise(_ value: String) -> Bool {
        HTMLParsingSupport.firstCapture("(?i)(?:^|[/_.\\s?&=-])(ad|ads|advert[^/\\s]*|logo|cover|thumb[^/\\s]*|avatar|banner|icon|(?:new)?loading\\d*|lazyload|placeholder|spacer|tracking|captcha)(?:$|[/_.\\s?&=-])", in: value) != nil
            || value.contains("广告") || value.contains("封面") || value.contains("缩略图")
    }

    private func dimension(_ name: String, of image: Element) throws -> Double? {
        let value = try image.attr(name).replacingOccurrences(of: "px", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
        return Double(value)
    }

    private func hasLargeImage(_ container: Element) throws -> Bool {
        for image in try container.select("img").array() {
            if let width = try dimension("width", of: image), let height = try dimension("height", of: image), width >= 400, height >= 600 { return true }
        }
        return false
    }

    private func heading(in dom: Document) throws -> String {
        let heading = try dom.select("h1, .chapter-title, #chapter-title").first()?.text()
        return try heading.flatMap { $0.isEmpty ? nil : $0 } ?? dom.title().components(separatedBy: "|")[0]
    }

    private func meta(_ name: String, in dom: Document) throws -> String? {
        let value = try dom.select("meta[property='\(name)'], meta[name='\(name)']").first()?.attr("content")
        return value.flatMap { $0.isEmpty ? nil : $0 }
    }

    private func bookTitle(in dom: Document) throws -> String? {
        guard let title = HTMLParsingSupport.firstCapture("^(.+?)第\\s*[0-9一二三四五六七八九十百千]+\\s*[话話章]", in: try dom.title()) else { return nil }
        return HTMLParsingSupport.replacingRegex("(?:漫画|漫畫)$", in: title.trimmingCharacters(in: CharacterSet(charactersIn: " _-")), with: "")
    }

    private func isChapterTitle(_ title: String) -> Bool {
        HTMLParsingSupport.firstCapture("(?i)(第\\s*[0-9一二三四五六七八九十百千]+\\s*[话話章回卷]|(?:chapter|episode)\\s*\\d+)", in: title) != nil
            || ["序章", "序话", "番外", "后记"].contains(where: title.hasPrefix)
    }

    private func navigation(in dom: Document, labels: Set<String>, rel: String? = nil, base: URL) throws -> URL? {
        for link in try dom.select("a[href]").array() {
            let visible = try link.text().trimmingCharacters(in: .whitespacesAndNewlines)
            let text = visible.isEmpty ? try link.attr("title") : visible
            let relationship = try link.attr("rel").split(separator: " ")
            guard labels.contains(text) || (labels.contains("目录") && text.hasSuffix("完整章节目录")) || (rel.map { relationship.contains(Substring($0)) } == true && !["下一页", "下页", "Next Page"].contains(text)),
                  let url = HTMLParsingSupport.absoluteURL(for: link, relativeTo: base),
                  HTMLParsingSupport.isSameOrigin(url, as: base), url != base else { continue }
            return url
        }
        return nil
    }
}
