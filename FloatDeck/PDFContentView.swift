import SwiftUI
import PDFKit

struct PDFContentView: NSViewRepresentable {
    let url: URL
    @Binding var currentPage: Int
    let isInteractive: Bool

    func makeNSView(context: Context) -> PDFView {
        let pdfView = PDFView()
        pdfView.autoScales = true
        pdfView.displayMode = .singlePage
        pdfView.displayDirection = .vertical
        pdfView.backgroundColor = .clear
        pdfView.pageShadowsEnabled = false
        pdfView.pageBreakMargins = NSEdgeInsetsZero

        // Remove internal document view background
        if let documentView = pdfView.documentView {
            documentView.wantsLayer = true
            documentView.layer?.backgroundColor = .clear
        }

        // Load document
        if url.startAccessingSecurityScopedResource() {
            context.coordinator.isAccessingSecurityScope = true
        }
        if let document = PDFDocument(url: url) {
            pdfView.document = document
        }

        // Clear backgrounds after document load
        pdfView.documentView?.wantsLayer = true
        pdfView.documentView?.layer?.backgroundColor = .clear
        clearScrollViewBackgrounds(pdfView)

        context.coordinator.pdfView = pdfView

        // Observe page changes from PDFView
        NotificationCenter.default.addObserver(
            context.coordinator,
            selector: #selector(Coordinator.pageChanged(_:)),
            name: .PDFViewPageChanged,
            object: pdfView
        )

        return pdfView
    }

    private func clearScrollViewBackgrounds(_ view: NSView) {
        for subview in view.subviews {
            if let scrollView = subview as? NSScrollView {
                scrollView.drawsBackground = false
                scrollView.contentView.drawsBackground = false
            }
            subview.wantsLayer = true
            subview.layer?.backgroundColor = .clear
            clearScrollViewBackgrounds(subview)
        }
    }

    func updateNSView(_ pdfView: PDFView, context: Context) {
        // Sync page from state -> PDFView
        if let document = pdfView.document,
           let targetPage = document.page(at: currentPage),
           pdfView.currentPage != targetPage {
            pdfView.go(to: targetPage)
        }

        // Toggle scroll: in card mode, disable scroll/selection
        if let scrollView = pdfView.enclosingScrollView ?? pdfView.subviews.compactMap({ $0 as? NSScrollView }).first {
            scrollView.hasVerticalScroller = isInteractive
            scrollView.hasHorizontalScroller = false
            scrollView.scrollerStyle = .overlay
        }
    }

    static func dismantleNSView(_ pdfView: PDFView, coordinator: Coordinator) {
        NotificationCenter.default.removeObserver(coordinator)
        if coordinator.isAccessingSecurityScope {
            // URL security scope cleanup
            coordinator.isAccessingSecurityScope = false
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    final class Coordinator: NSObject {
        let parent: PDFContentView
        weak var pdfView: PDFView?
        var isAccessingSecurityScope = false

        init(parent: PDFContentView) {
            self.parent = parent
        }

        @objc func pageChanged(_ notification: Notification) {
            guard let pdfView = pdfView,
                  let currentPage = pdfView.currentPage,
                  let document = pdfView.document else { return }
            let index = document.index(for: currentPage)
            if index != parent.currentPage {
                DispatchQueue.main.async {
                    self.parent.currentPage = index
                }
            }
        }
    }
}
