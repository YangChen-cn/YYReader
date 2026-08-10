import SwiftUI

struct ReaderParagraphViewportFrame: Equatable {
    let focus: ReaderParagraphFocus
    let frame: CGRect
}

struct ReaderParagraphViewportFramePreferenceKey: PreferenceKey {
    static let defaultValue: [ReaderParagraphViewportFrame] = []

    static func reduce(
        value: inout [ReaderParagraphViewportFrame],
        nextValue: () -> [ReaderParagraphViewportFrame]
    ) {
        value.append(contentsOf: nextValue())
    }
}

struct ReaderParagraphFocusReporter: View {
    let focus: ReaderParagraphFocus

    var body: some View {
        GeometryReader { proxy in
            Color.clear.preference(
                key: ReaderParagraphViewportFramePreferenceKey.self,
                value: [ReaderParagraphViewportFrame(focus: focus, frame: proxy.frame(in: .global))]
            )
        }
    }
}
