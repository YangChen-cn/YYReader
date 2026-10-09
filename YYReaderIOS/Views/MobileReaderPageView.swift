import SwiftUI

struct MobileReaderPageView: View {
    let page: MobileReadingPage
    let layout: MobilePaginationLayout
    let viewportSize: CGSize

    var body: some View {
        ScrollView {
            MobileReaderPageContent(page: page, layout: layout)
        }
        .scrollIndicators(.hidden)
        .frame(width: viewportSize.width, height: viewportSize.height)
        .accessibilityIdentifier("ios.readerPage.\(page.id)")
    }
}
