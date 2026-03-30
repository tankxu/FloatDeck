import SwiftUI
import UniformTypeIdentifiers

private let imageExtensions: Set<String> = ["png", "jpg", "jpeg", "gif", "bmp", "tiff", "tif", "webp", "heic"]

struct FileDropDelegate: DropDelegate {
    let appState: AppState
    let windowController: FloatingWindowController

    func validateDrop(info: DropInfo) -> Bool {
        info.hasItemsConforming(to: [.fileURL])
    }

    func performDrop(info: DropInfo) -> Bool {
        let providers = info.itemProviders(for: [.fileURL])
        guard !providers.isEmpty else { return false }

        var collectedURLs: [URL] = []
        let group = DispatchGroup()

        for provider in providers {
            group.enter()
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { data, _ in
                defer { group.leave() }
                guard let data = data as? Data,
                      let url = URL(dataRepresentation: data, relativeTo: nil) else { return }
                collectedURLs.append(url)
            }
        }

        group.notify(queue: .main) {
            let ext = collectedURLs.first?.pathExtension.lowercased() ?? ""

            if collectedURLs.count == 1 && ext == "pdf" {
                appState.loadPDF(url: collectedURLs[0])
                windowController.updateCardAspectRatio()
            } else {
                // Filter to image files only
                let imageURLs = collectedURLs.filter { imageExtensions.contains($0.pathExtension.lowercased()) }
                if !imageURLs.isEmpty {
                    appState.loadImages(urls: imageURLs)
                    windowController.updateCardAspectRatio()
                }
            }
        }

        return true
    }
}
