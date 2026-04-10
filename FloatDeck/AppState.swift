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
    static let imageExtensions: Set<String> = ["png", "jpg", "jpeg", "gif", "bmp", "tiff", "tif", "webp", "heic", "svg"]

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

        if let ratio = Self.assetAspectRatio(for: sorted[0]) {
            aspectRatio = ratio
        }

        let title = sorted.count == 1 ? sorted[0].lastPathComponent : "\(sorted[0].lastPathComponent) +\(sorted.count - 1)"
        addRecentItem(url: sorted[0], title: title, isPDF: false, type: .images)
    }

    /// Smart URL loader:
    /// - Direct resource URL (.pdf/.png/.jpg/.svg...) => download then open as file
    /// - Normal webpage URL => open in web view
    func loadURLSmart(url: URL, onLoaded: (() -> Void)? = nil) {
        let ext = Self.extensionFromURL(url)
        if ext == "pdf" || Self.imageExtensions.contains(ext) {
            downloadToTemp(url: url, preferredExtension: ext) { [weak self] localURL in
                guard let self, let localURL else { return }
                DispatchQueue.main.async {
                    let localExt = localURL.pathExtension.lowercased()
                    if localExt == "pdf" {
                        self.loadPDF(url: localURL)
                    } else {
                        self.loadImages(urls: [localURL])
                    }
                    onLoaded?()
                }
            }
            return
        }

        loadWeb(url: url)
        onLoaded?()
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

    // MARK: - Helpers

    static func extensionFromURL(_ url: URL) -> String {
        if let components = URLComponents(url: url, resolvingAgainstBaseURL: false) {
            let ext = (components.path as NSString).pathExtension.lowercased()
            if !ext.isEmpty { return ext }
        }
        return url.pathExtension.lowercased()
    }

    static func assetAspectRatio(for url: URL) -> CGFloat? {
        let ext = url.pathExtension.lowercased()

        if ext == "svg", let ratio = svgAspectRatio(url: url) {
            return ratio
        }

        if let image = NSImage(contentsOf: url), image.size.height > 0 {
            return image.size.width / image.size.height
        }

        return nil
    }

    private static func svgAspectRatio(url: URL) -> CGFloat? {
        guard let data = try? Data(contentsOf: url),
              let text = String(data: data, encoding: .utf8) else { return nil }

        if let viewBoxMatch = text.range(of: #"viewBox\s*=\s*"([^"]+)""#, options: .regularExpression) {
            let raw = String(text[viewBoxMatch]).replacingOccurrences(of: "viewBox=\"", with: "").dropLast()
            let values = raw.split(whereSeparator: { $0 == " " || $0 == "," }).compactMap { Double($0) }
            if values.count == 4, values[3] > 0 {
                return CGFloat(values[2] / values[3])
            }
        }

        if let width = extractSVGLength(named: "width", in: text),
           let height = extractSVGLength(named: "height", in: text),
           height > 0 {
            return CGFloat(width / height)
        }

        return nil
    }

    private static func extractSVGLength(named name: String, in text: String) -> Double? {
        let pattern = #"\#(name)\s*=\s*"([0-9]+(?:\.[0-9]+)?)""#
        guard let range = text.range(of: pattern, options: .regularExpression) else { return nil }
        let raw = String(text[range])
        let value = raw
            .replacingOccurrences(of: "\(name)=\"", with: "")
            .replacingOccurrences(of: "\"", with: "")
        return Double(value)
    }

    private func downloadToTemp(url: URL, preferredExtension: String, completion: @escaping (URL?) -> Void) {
        let task = URLSession.shared.downloadTask(with: url) { tempURL, _, _ in
            guard let tempURL else {
                completion(nil)
                return
            }

            let ext = preferredExtension.isEmpty ? "bin" : preferredExtension
            let destination = FileManager.default.temporaryDirectory
                .appendingPathComponent("floatdeck-\(UUID().uuidString)")
                .appendingPathExtension(ext)

            do {
                if FileManager.default.fileExists(atPath: destination.path) {
                    try FileManager.default.removeItem(at: destination)
                }
                try FileManager.default.moveItem(at: tempURL, to: destination)
                completion(destination)
            } catch {
                completion(nil)
            }
        }
        task.resume()
    }
}
