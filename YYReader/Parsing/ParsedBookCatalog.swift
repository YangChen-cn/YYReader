import Foundation

struct ParsedBookCatalog: Sendable {
    let title: String
    let author: String
    let chapters: [ChapterSeed]
    let nextPageURL: URL?

    /// Correct a convincingly descending sequence, never sort individual entries.
    /// Unknown labels, volume resets and mixed lists keep their original order.
    func inReadingOrder() -> ParsedBookCatalog {
        let numbers = chapters.compactMap { Self.sequenceNumber($0.title) }
        guard numbers.count >= 3, numbers.count * 2 >= chapters.count,
              let first = numbers.first, let last = numbers.last, first > last else { return self }
        let span = (numbers.max() ?? first) - (numbers.min() ?? last)
        // A mistyped chapter number can spike then immediately return to the
        // surrounding sequence. Ignore it as evidence, but retain its DOM entry.
        var runs: [Double] = []
        for number in numbers where runs.last != number { runs.append(number) }
        let evidence = runs.enumerated().compactMap { index, number -> Double? in
            guard index > 0, index + 1 < runs.count else { return number }
            let before = runs[index - 1], after = runs[index + 1]
            let outside = number < min(before, after) || number > max(before, after)
            if outside, abs(before - after) <= max(2, span * 0.02),
               min(abs(number - before), abs(number - after)) > max(2, span * 0.1) { return nil }
            return number
        }
        let pairs = zip(evidence, evidence.dropFirst()).filter { $0 != $1 }
        let descending = pairs.filter { $0 > $1 }.count
        guard pairs.count >= 2, descending * 10 >= pairs.count * 9 else { return self }
        // Repeated number ranges commonly indicate separate volumes; a single
        // stray announcement number must not veto a strongly descending list.
        guard Set(runs).count * 2 > runs.count else { return self }
        return ParsedBookCatalog(title: title, author: author,
            chapters: chapters.reversed().enumerated().map {
                ChapterSeed(title: $0.element.title, url: $0.element.url, sortIndex: $0.offset + 1)
            }, nextPageURL: nextPageURL)
    }

    private static func sequenceNumber(_ title: String) -> Double? {
        let number = "([0-9]+(?:[.][0-9]+)?|[零〇一二两三四五六七八九十百千万]+)"
        let patterns = ["第\\s*" + number + "\\s*[章回节話话集]",
                        "^\\s*总\\s*" + number,
                        "^\\s*(?:chapter|episode|ch[.])\\s*" + number,
                        "^\\s*" + number + "(?:\\s|[·、:：.\\-]|$)"]
        guard let value = patterns.lazy.compactMap({
            HTMLParsingSupport.firstCapture("(?i)" + $0, in: title)
        }).first else { return nil }
        if let number = Double(value) { return number }
        let digits: [Character: Int] = ["零": 0, "〇": 0, "一": 1, "二": 2, "两": 2, "三": 3,
                                      "四": 4, "五": 5, "六": 6, "七": 7, "八": 8, "九": 9]
        let units: [Character: Int] = ["十": 10, "百": 100, "千": 1000, "万": 10000]
        if !value.contains(where: { units[$0] != nil }) {
            return Double(value.reduce(0) { $0 * 10 + (digits[$1] ?? 0) })
        }
        var total = 0, section = 0, digit = 0
        for character in value {
            if let next = digits[character] { digit = next }
            else if let unit = units[character] {
                if unit == 10000 {
                    total += (section + digit) * unit
                    section = 0
                } else { section += max(1, digit) * unit }
                digit = 0
            }
        }
        return Double(total + section + digit)
    }
}
