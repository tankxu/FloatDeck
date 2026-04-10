import SwiftUI
import WebKit

struct SVGContentView: NSViewRepresentable {
    let url: URL
    let isInteractive: Bool

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.setValue(false, forKey: "drawsBackground")
        webView.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        if webView.url != url {
            webView.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
        }

        if let scrollView = webView.enclosingScrollView ?? webView.subviews.first(where: { $0 is NSScrollView }) as? NSScrollView {
            scrollView.hasVerticalScroller = isInteractive
            scrollView.hasHorizontalScroller = isInteractive
        }
    }
}
