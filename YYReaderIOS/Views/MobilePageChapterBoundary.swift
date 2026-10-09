import SwiftUI

struct MobilePageChapterBoundary: View {
    let title: String
    let action: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            ProgressView()
            Button(title, action: action)
                .frame(minHeight: 44)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
