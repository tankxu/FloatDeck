import SwiftUI

struct ImageContentView: View {
    let urls: [URL]
    @Binding var currentPage: Int
    let isInteractive: Bool

    var body: some View {
        GeometryReader { geo in
            if currentPage < urls.count, let nsImage = NSImage(contentsOf: urls[currentPage]) {
                let image = Image(nsImage: nsImage)

                if isInteractive {
                    ScrollView([.vertical, .horizontal]) {
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(minWidth: geo.size.width, minHeight: geo.size.height)
                    }
                } else {
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: geo.size.width, height: geo.size.height)
                        .clipped()
                }
            } else {
                Color.clear
            }
        }
    }
}
