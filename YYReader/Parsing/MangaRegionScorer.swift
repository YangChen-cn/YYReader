import Foundation
import SwiftSoup

/// Scores local DOM regions, never the document/body image collection.
/// The score measures evidence strength; it is not a statistical probability.
struct MangaRegionScorer {
    struct Evidence: Sendable {
        let sequence: Int
        let structure: Int
        let imageQuality: Int
        let sparseContent: Int
        let context: Int
        let penalty: Int
        var score: Int { max(0, min(100, sequence + structure + imageQuality + sparseContent + context - penalty)) }
    }
    struct Recognition: Sendable {
        let imageURLs: [URL]
        let domIndices: [Int]
        let domNodeIDs: [String]
        let needsBrowser: [Bool]
        let evidence: Evidence
        let isHighConfidence: Bool
    }
    private struct ImageRecord {
        let node: Element
        let url: URL
        let needsBrowser: Bool
        let width: Double?
        let height: Double?
        let interruptions: Int
        let linked: Bool
        var large: Bool { (width ?? 0) >= 400 && (height ?? 0) >= 300 }
        var tall: Bool { large && (height ?? 0) / (width ?? 1) >= 3 }
    }
    private struct Region {
        let node: Element
        var indices: [Int] = []
        var uniqueURLs: Set<URL> = []
    }
    private struct Content {
        var text = 0
        var linkText = 0
        var links = 0
        var images = 0
    }

    static let noiseSelectors = "script, style, noscript, iframe, header, footer, nav, aside, form, .ad, .ads, .advertisement, [class*=advert], .banner, .logo, .cover, .thumbnail, .thumbnails, .recommend, .recommendations, .related, [hidden], [aria-hidden=true]"
    static let manualThreshold = 55
    static let automaticThreshold = 80

    func recognize(in dom: Document, base: URL, chapterTitle: Bool, chapterNavigation: Bool) throws -> Recognition? {
        for (index, image) in try dom.select("img").array().enumerated() {
            try image.attr("data-yyreader-dom-index", String(index))
        }
        // Loading labels are controls, not prose. Never remove a wrapper that
        // actually contains an image.
        for control in try dom.select(".loading-content, .chapter-loading, .image-loading, .progress-container").array()
            where try control.select("img").isEmpty() { try control.remove() }
        try dom.select(Self.noiseSelectors).remove()
        let elements = try dom.getAllElements().array()
        var content: [ObjectIdentifier: Content] = [:]
        var regions: [ObjectIdentifier: Region] = [:]
        var records: [ImageRecord] = []
        var interruptions = 0
        // One DOM traversal plus at most eight ancestors per image. Regions share
        // image indices, rather than repeatedly scanning every subtree with CSS.
        for (offset, element) in elements.enumerated() {
            if offset % 256 == 0 { try Task.checkCancellation() }
            let text = element.ownText().filter { !$0.isWhitespace }.count
            let tag = element.tagNameNormal()
            content[ObjectIdentifier(element)] = Content(text: text, linkText: tag == "a" ? text : 0,
                                                        links: tag == "a" ? 1 : 0, images: tag == "img" ? 1 : 0)
            if text >= 30 || (tag == "a" && text > 0) { interruptions += 1 }
            guard tag == "img", let record = try imageRecord(element, base: base, interruptions: interruptions) else { continue }
            let index = records.count
            records.append(record)
            var ancestor = element.parent()
            for _ in 0..<8 {
                guard let node = ancestor, !["body", "html", "#root"].contains(node.tagNameNormal()) else { break }
                let key = ObjectIdentifier(node)
                if regions[key] == nil { regions[key] = Region(node: node) }
                regions[key]?.indices.append(index)
                regions[key]?.uniqueURLs.insert(record.url)
                ancestor = node.parent()
            }
        }
        // Bottom-up text/link counts include nested captions and nested anchors.
        for element in elements.reversed() {
            guard let parent = element.parent(), let child = content[ObjectIdentifier(element)] else { continue }
            let key = ObjectIdentifier(parent)
            content[key, default: Content()].text += child.text
            content[key, default: Content()].linkText += element.tagNameNormal() == "a" ? child.text : child.linkText
            content[key, default: Content()].links += child.links
            content[key, default: Content()].images += child.images
        }
        var best: Recognition?
        var bestText = Int.max
        var accepted: [Recognition] = []
        for region in regions.values {
            try Task.checkCancellation()
            let stats = content[ObjectIdentifier(region.node)] ?? Content()
            var seen = Set<URL>()
            let rawImages = region.indices.map { records[$0] }
            let containsBlob = rawImages.contains { $0.url.scheme == "blob" }
            let images = rawImages.filter { containsBlob || $0.url.scheme != "yyreader-pending" }
                .filter { seen.insert($0.url).inserted }
            guard !images.isEmpty else { continue }
            if images.count == 1 {
                var ancestor = region.node.parent()
                var belongsToSequence = false
                for _ in 0..<8 {
                    guard let node = ancestor else { break }
                    if (regions[ObjectIdentifier(node)]?.uniqueURLs.count ?? 0) >= 2 {
                        belongsToSequence = true
                        break
                    }
                    ancestor = node.parent()
                }
                if belongsToSequence { continue }
            }
            // Separate multi-image subregions are not one reading sequence.
            // Single-image wrappers remain valid (figure/picture per page).
            var branches: [ObjectIdentifier: Int] = [:]
            for image in images {
                var child = image.node
                for _ in 0..<8 {
                    guard let parent = child.parent() else { break }
                    if parent === region.node { branches[ObjectIdentifier(child), default: 0] += 1; break }
                    child = parent
                }
            }
            if branches.values.filter({ $0 >= 2 }).count > 1 { continue }
            let prose = max(0, stats.text - stats.linkText)
            let hint = try readerHint(region.node)
            // Unknown dimensions do not count as large. A solitary image needs
            // positive size and chapter evidence, not merely a CSS name.
            let single = images.count == 1
            if single && !(images[0].large && (images[0].height ?? 0) >= 600
                           && (chapterTitle || chapterNavigation) && (hint || images[0].tall)) { continue }
            guard prose < 240 else { continue }
            let evidence = score(images, rawImageCount: region.indices.count, content: stats, hint: hint,
                                 chapterTitle: chapterTitle, chapterNavigation: chapterNavigation)
            let contextual = chapterTitle || chapterNavigation || hint
            guard contextual, evidence.score >= Self.manualThreshold else { continue }
            // Without a reader hint/navigation, a chapter-like heading alone
            // cannot turn a photo gallery into automatic manga recognition.
            let high = evidence.score >= Self.automaticThreshold
                && (chapterNavigation || (hint && chapterTitle))
                && (images.count >= 3 || (single && images[0].tall && chapterNavigation))
            let recognition = Recognition(imageURLs: images.map(\.url),
                domIndices: images.map { Int((try? $0.node.attr("data-yyreader-dom-index")) ?? "") ?? -1 },
                domNodeIDs: images.map { (try? $0.node.attr("data-yyreader-node")) ?? "" },
                needsBrowser: images.map(\.needsBrowser), evidence: evidence, isHighConfidence: high)
            accepted.append(recognition)
            if best == nil || evidence.score > best!.evidence.score
                || (evidence.score == best!.evidence.score && prose < bestText) {
                best = recognition
                bestText = prose
            }
        }
        if let best {
            let chosen = Set(best.imageURLs)
            if accepted.contains(where: { abs($0.evidence.score - best.evidence.score) <= 5
                && chosen.isDisjoint(with: $0.imageURLs) }) { return nil }
        }
        return best
    }

    private func score(_ images: [ImageRecord], rawImageCount: Int, content: Content, hint: Bool,
                       chapterTitle: Bool, chapterNavigation: Bool) -> Evidence {
        let count = images.count
        let sequence = count >= 8 ? 20 : count >= 4 ? 16 : count >= 2 ? 10 : (images[0].tall ? 14 : 10)
        var parents: [ObjectIdentifier: Int] = [:]
        for image in images {
            var parent = image.node.parent()
            // A pure figure/picture/div per page is still one shared sequence.
            for _ in 0..<3 {
                guard let wrapper = parent, wrapper.children().count == 1, wrapper.ownText().isEmpty,
                      let outer = wrapper.parent(), !["body", "html"].contains(outer.tagNameNormal()) else { break }
                parent = outer
            }
            if let parent { parents[ObjectIdentifier(parent), default: 0] += 1 }
        }
        let cohesion = Double(parents.values.max() ?? 0) / Double(count)
        let adjacent = zip(images, images.dropFirst()).filter { $0.interruptions == $1.interruptions }.count
        let continuity = count == 1 ? 1 : Double(adjacent) / Double(count - 1)
        let structure = Int((continuity * 12).rounded()) + Int((cohesion * 8).rounded())
        let known = images.filter { $0.width != nil && $0.height != nil }
        let large = known.isEmpty ? 0 : Int((12 * Double(images.filter(\.large).count) / Double(count)).rounded())
        // Landscape spreads and arbitrarily tall webtoon images are both valid.
        let shape = known.isEmpty ? 0 : Int((4 * Double(known.filter { ($0.height ?? 0) / ($0.width ?? 1) >= 0.35 }.count) / Double(known.count)).rounded())
        let widths = images.compactMap(\.width).sorted()
        let median = widths.isEmpty ? 0 : widths[widths.count / 2]
        let consistent = widths.count < 2 ? 0 : Int((4 * Double(widths.filter { abs($0 - median) <= median * 0.25 }.count) / Double(widths.count)).rounded())
        let prose = max(0, content.text - content.linkText)
        let sparse = prose <= 40 ? 15 : prose <= 120 ? 10 : 3
        let linkedRatio = Double(images.filter(\.linked).count) / Double(count)
        let linkPenalty = Int((linkedRatio * 35).rounded()) + (content.linkText > max(30, content.text / 3) ? 20 : 0)
            + (content.links > max(4, count * 2) ? 10 : 0)
        let prosePenalty = prose > 120 ? 15 : 0
        let noiseRatio = Double(max(0, content.images - rawImageCount)) / Double(max(1, content.images))
        return Evidence(sequence: sequence, structure: structure, imageQuality: large + shape + consistent,
                        sparseContent: sparse, context: (hint ? 10 : 0) + (chapterTitle ? 5 : 0) + (chapterNavigation ? 10 : 0),
                        penalty: linkPenalty + prosePenalty + Int((noiseRatio * 3).rounded()))
    }

    private func readerHint(_ node: Element) throws -> Bool {
        let identity = try (node.attr("id") + " " + node.attr("class")).lowercased()
        return node.hasAttr("data-reader-images")
            || HTMLParsingSupport.firstCapture("(?:^|[ _-])(comic|manga|chapter|reading|reader|viewer|showimage|images)(?:$|[ _-])", in: identity) != nil
    }

    private func imageRecord(_ image: Element, base: URL, interruptions: Int) throws -> ImageRecord? {
        let identity = try [image.attr("id"), image.attr("class"), image.attr("alt")].joined(separator: " ")
        guard !isNoise(identity, includesPlaceholders: false) else { return nil }
        let width = try dimension("width", image: image)
        let height = try dimension("height", image: image)
        if let width, width < 160 { return nil }
        if let height, height < 160 { return nil }
        var ancestor = image.parent()
        var linked = false
        for _ in 0..<8 {
            guard let node = ancestor, !["body", "html"].contains(node.tagNameNormal()) else { break }
            let identity = try node.attr("id") + " " + node.attr("class")
            if isNoise(identity, includesPlaceholders: false) { return nil }
            if node.tagNameNormal() == "a", let href = HTMLParsingSupport.absoluteURL(for: node, relativeTo: base),
               href != base, !["jpg", "jpeg", "png", "webp", "avif", "gif"].contains(href.pathExtension.lowercased()) { linked = true }
            ancestor = node.parent()
        }
        let current = try image.attr("src").trimmingCharacters(in: .whitespacesAndNewlines)
        if current.hasPrefix("blob:"), let url = URL(string: current),
           let origin = URL(string: String(current.dropFirst(5))), HTMLParsingSupport.isSameOrigin(origin, as: base) {
            return ImageRecord(node: image, url: url, needsBrowser: true, width: width, height: height,
                               interruptions: interruptions, linked: linked)
        }
        let pending = current.isEmpty || isNoise(current) || !["http", "https"].contains(URL(string: current, relativeTo: base)?.scheme ?? "")
        for attribute in ["data-original", "data-src", "data-lazy-src", "data-lazy", "data-url", "data-echo", "src"] {
            let source = try image.attr(attribute).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !source.isEmpty, !isNoise(source), let url = URL(string: source, relativeTo: base)?.absoluteURL,
                  var components = URLComponents(url: url, resolvingAgainstBaseURL: false),
                  ["http", "https"].contains(components.scheme?.lowercased() ?? ""),
                  !["svg", "ico"].contains(url.pathExtension.lowercased()) else { continue }
            components.fragment = nil
            guard let resolved = components.url, resolved != base else { continue }
            return ImageRecord(node: image, url: resolved, needsBrowser: pending, width: width, height: height,
                               interruptions: interruptions, linked: linked)
        }
        if pending {
            let index = try image.attr("data-yyreader-dom-index")
            if let url = URL(string: "yyreader-pending://image/" + index) {
                return ImageRecord(node: image, url: url, needsBrowser: true, width: width, height: height,
                                   interruptions: interruptions, linked: linked)
            }
        }
        return nil
    }

    private func dimension(_ name: String, image: Element) throws -> Double? {
        for attribute in ["data-yyreader-" + name, "data-" + name, name] {
            let value = try image.attr(attribute).replacingOccurrences(of: "px", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
            if let number = Double(value), number.isFinite, number > 0 { return number }
        }
        return nil
    }

    private func isNoise(_ value: String, includesPlaceholders: Bool = true) -> Bool {
        let common = "ad|ads|advert[^/\\s]*|logo|cover|thumb[^/\\s]*|avatar|banner|icon|tracking|captcha|recommend[^/\\s]*|related"
        let placeholders = includesPlaceholders ? "|(?:new)?loading\\d*|lazyload|placeholder|spacer" : ""
        return HTMLParsingSupport.firstCapture("(?i)(?:^|[/_.\\s?&=-])(\(common)\(placeholders))(?:$|[/_.\\s?&=-])", in: value) != nil
            || value.contains("广告") || value.contains("封面") || value.contains("缩略图")
    }
}
