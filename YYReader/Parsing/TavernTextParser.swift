import Foundation

/// Recognizes the exported text grammar; never executes regex replacement HTML/JS.
enum TavernTextParser {
    private static let tokens = try! NSRegularExpression(pattern: #"<!--|-->|</?([a-zA-Z_][a-zA-Z_0-9~\-]*)\s*>"#)
    private static let dialogue = try! NSRegularExpression(
        pattern: #"^(\{\{user\}\}|\{[^{}\r\n]{1,40}\}|\[[^\[\]\r\n]{1,40}\]|【[^【】\r\n]{1,40}】)\s*(?:[:：]\s*(.+)|([「『“"].+[」』”"]))$"#)
    private static let hidden = Set(["think", "thinking", "konatan_planning~", "disclaimer", "guifan", "htmlcontent", "danmu", "script", "style"])
    private static let auxiliary = ["options": "剧情选项", "tucao": "旁注", "konatan_chat": "旁注", "current_event": "当前事件", "progress": "事件进度"]
    private static let wrappers = Set(["content", "maintext", "gametext", "narrative", "story"])
    private static let reservedSpeakers = Set(["系统", "状态", "状态栏", "旁白", "选项", "作者", "规则", "日志", "meta", "debug", "content"])

    static func parse(_ paragraphs: [String]) -> TavernReadingPlan {
        var blocks: [TavernReadingPlan.Block] = []
        var hiddenStack: [String] = []
        var isComment = false
        var card: (tag: String, title: String, index: Int, text: String)?

        func append(_ segment: TavernReadingPlan.Segment, at index: Int) {
            guard !segment.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
            if blocks.last?.id == index { blocks[blocks.count - 1].segments.append(segment) }
            else { blocks.append(.init(id: index, segments: [segment])) }
        }
        for (index, paragraph) in paragraphs.enumerated() {
            if paragraph.range(of: #"^[（(]第\s*[0-9]+\s*楼[）)]$|^\[#[0-9]+\]$|^-{20}$"#, options: .regularExpression) != nil { continue }
            var line = ""
            func consume(_ text: String) {
                guard !isComment, hiddenStack.isEmpty else { return }
                if card != nil { card?.text += text }
                else { line += text }
            }
            func flushLine() {
                let value = line.trimmingCharacters(in: .whitespacesAndNewlines)
                if !value.isEmpty { append(segment(for: value), at: index) }
                line = ""
            }
            var cursor = paragraph.startIndex
            for match in tokens.matches(in: paragraph, range: NSRange(paragraph.startIndex..., in: paragraph)) {
                guard let range = Range(match.range, in: paragraph) else { continue }
                consume(String(paragraph[cursor..<range.lowerBound]))
                let token = String(paragraph[range])
                cursor = range.upperBound
                if token == "<!--" { isComment = true; continue }
                if token == "-->" { isComment = false; continue }
                guard !isComment, let tagRange = Range(match.range(at: 1), in: paragraph) else { continue }
                let tag = paragraph[tagRange].lowercased()
                let closing = token.hasPrefix("</")
                if hidden.contains(tag) {
                    if closing {
                        if let start = hiddenStack.lastIndex(of: tag) { hiddenStack.removeSubrange(start...) }
                    } else { hiddenStack.append(tag) }
                    continue
                }
                guard hiddenStack.isEmpty else { continue }
                if let title = auxiliary[tag] {
                    if closing, let current = card, current.tag == tag {
                        append(.init(kind: .auxiliary(title: current.title), text: current.text.trimmingCharacters(in: .whitespacesAndNewlines)), at: current.index)
                        card = nil
                    } else if !closing, card == nil {
                        flushLine()
                        card = (tag, title, index, "")
                    }
                } else if !wrappers.contains(tag) { consume(token) }
            }
            consume(String(paragraph[cursor...]))
            flushLine()
            if card != nil { card?.text += "\n" }
        }
        // A truncated export can still contain useful choices; reasoning stays hidden.
        if let card { append(.init(kind: .auxiliary(title: card.title), text: card.text), at: card.index) }
        return TavernReadingPlan(blocks: blocks)
    }

    private static func segment(for text: String) -> TavernReadingPlan.Segment {
        guard let match = dialogue.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let speakerRange = Range(match.range(at: 1), in: text) else {
            return .init(kind: .narration, text: text)
        }
        let raw = String(text[speakerRange])
        let speaker = raw == "{{user}}" ? raw : raw.trimmingCharacters(in: CharacterSet(charactersIn: "{}[]【】"))
        guard !reservedSpeakers.contains(speaker.lowercased()) else { return .init(kind: .narration, text: text) }
        let body = match.range(at: 2).location != NSNotFound ? match.range(at: 2) : match.range(at: 3)
        guard let bodyRange = Range(body, in: text) else { return .init(kind: .narration, text: text) }
        return .init(kind: .dialogue(speaker: speaker), text: String(text[bodyRange]))
    }
}
