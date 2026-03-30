import SwiftUI
import PDFKit

enum WindowMode {
    case card
    case present
}

enum ContentType: Equatable {
    case empty
    case pdf(URL)
    case web(URL)
    case images([URL])
}

enum RecentItemType: String, Codable {
    case pdf
    case web
    case images
}

// MARK: - Recent Item

struct RecentItem: Codable, Identifiable, Equatable {
    var id: String { url.absoluteString }
    let url: URL
    let title: String
    let isPDF: Bool
    let itemType: RecentItemType?
    let date: Date
    let bookmarkData: Data?

    var resolvedType: RecentItemType {
        itemType ?? (isPDF ? .pdf : .web)
    }

    /// Resolve bookmark to get a security-scoped URL for sandbox access
    func resolveURL() -> URL? {
        guard let bookmarkData else { return url }
        var isStale = false
        guard let resolved = try? URL(
            resolvingBookmarkData: bookmarkData,
            options: .withSecurityScope,
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        ) else { return nil }
        return resolved
    }
}

@Observable
final class AppState {
    var mode: WindowMode = .card
    var contentType: ContentType = .empty
    var currentPage: Int = 0
    var totalPages: Int = 0
    var aspectRatio: CGFloat = 1.0 / 1.414 // default A4 width/height ratio

    // Card frame (remembered for animation back)
    var cardFrame: NSRect = .zero

    // UI flags
    var showURLInput: Bool = false
    var isAnimating: Bool = false
    var isWindowActive: Bool = true
    /// User preference: present mode uses native full screen when true
    /// Resets to false on every launch — not persisted
    var isFullScreenMode: Bool = false
    /// Tracks actual native full screen state
    var isInNativeFullScreen: Bool = false

    // Recent history
    var recentItems: [RecentItem] = []
    private static let maxRecent = 20
    private static let recentKey = "FloatDeck.recentItems"

    // Card size constraints
    let cardMinWidth: CGFloat = 160
    let cardMaxWidth: CGFloat = 480
    let defaultCardWidth: CGFloat = 280

    var defaultCardSize: NSSize {
        let width = defaultCardWidth
        let height = width / aspectRatio
        return NSSize(width: width, height: height)
    }

    func toggleMode() {
        if !isAnimating {
            mode = (mode == .card) ? .present : .card
        }
    }

    func goToPage(_ page: Int) {
        switch contentType {
        case .pdf, .images:
            let clamped = max(0, min(page, totalPages - 1))
            currentPage = clamped
        default:
            break
        }
    }

    func nextPage() {
        goToPage(currentPage + 1)
    }

    func previousPage() {
        goToPage(currentPage - 1)
    }

    func loadPDF(url: URL) {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }

        guard let document = PDFDocument(url: url) else { return }
        contentType = .pdf(url)
        currentPage = 0
        totalPages = document.pageCount

        if let firstPage = document.page(at: 0) {
            let bounds = firstPage.bounds(for: .mediaBox)
            if bounds.height > 0 {
                aspectRatio = bounds.width / bounds.height
            }
        }

        addRecentItem(url: url, title: url.lastPathComponent, isPDF: true, type: .pdf)
    }

    func loadWeb(url: URL) {
        contentType = .web(url)
        currentPage = 0
        totalPages = 0
        addRecentItem(url: url, title: url.host ?? url.absoluteString, isPDF: false, type: .web)
    }

    func loadImages(urls: [URL]) {
        guard !urls.isEmpty else { return }
        let sorted = urls.sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
        contentType = .images(sorted)
        currentPage = 0
        totalPages = sorted.count

        // Aspect ratio from first image
        if let image = NSImage(contentsOf: sorted[0]) {
            let size = image.size
            if size.height > 0 {
                aspectRatio = size.width / size.height
            }
        }

        let title = sorted.count == 1 ? sorted[0].lastPathComponent : "\(sorted[0].lastPathComponent) +\(sorted.count - 1)"
        addRecentItem(url: sorted[0], title: title, isPDF: false, type: .images)
    }

    func closeContent() {
        contentType = .empty
        currentPage = 0
        totalPages = 0
        aspectRatio = 1.0 / 1.414
    }

    // MARK: - Recent History

    func loadRecentItems() {
        guard let data = UserDefaults.standard.data(forKey: Self.recentKey),
              let items = try? JSONDecoder().decode([RecentItem].self, from: data) else { return }
        recentItems = items
    }

    private func saveRecentItems() {
        guard let data = try? JSONEncoder().encode(recentItems) else { return }
        UserDefaults.standard.set(data, forKey: Self.recentKey)
    }

    private func addRecentItem(url: URL, title: String, isPDF: Bool, type: RecentItemType) {
        // Create bookmark for sandbox re-access (local files)
        let needsBookmark = (type == .pdf || type == .images)
        let bookmark: Data? = needsBookmark ? (try? url.bookmarkData(
            options: .withSecurityScope,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )) : nil

        // Remove existing entry for same URL
        recentItems.removeAll { $0.url == url }
        // Insert at front
        let item = RecentItem(url: url, title: title, isPDF: isPDF, itemType: type, date: Date(), bookmarkData: bookmark)
        recentItems.insert(item, at: 0)
        // Trim to max
        if recentItems.count > Self.maxRecent {
            recentItems = Array(recentItems.prefix(Self.maxRecent))
        }
        saveRecentItems()
    }

    func removeRecentItem(_ item: RecentItem) {
        recentItems.removeAll { $0.id == item.id }
        saveRecentItems()
    }
}
