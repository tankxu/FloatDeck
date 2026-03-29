import SwiftUI
import WebKit

struct WebContentView: NSViewRepresentable {
    let url: URL
    let isInteractive: Bool

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.preferences.isElementFullscreenEnabled = false

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.setValue(false, forKey: "drawsBackground") // transparent background
        webView.load(URLRequest(url: url))

        context.coordinator.webView = webView
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        // Reload if URL changed
        if webView.url != url {
            webView.load(URLRequest(url: url))
        }

        // Toggle interaction for card vs present mode
        if let scrollView = webView.enclosingScrollView ?? webView.subviews.first(where: { $0 is NSScrollView }) as? NSScrollView {
            scrollView.hasVerticalScroller = isInteractive
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    final class Coordinator: NSObject {
        weak var webView: WKWebView?
    }
}
