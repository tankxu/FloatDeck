import SwiftUI
import UniformTypeIdentifiers

struct PDFDropDelegate: DropDelegate {
    let appState: AppState
    let windowController: FloatingWindowController

    func validateDrop(info: DropInfo) -> Bool {
        info.hasItemsConforming(to: [.pdf, .fileURL])
    }

    func performDrop(info: DropInfo) -> Bool {
        guard let itemProvider = info.itemProviders(for: [.fileURL]).first else {
            return false
        }

        itemProvider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { data, _ in
            guard let data = data as? Data,
                  let url = URL(dataRepresentation: data, relativeTo: nil) else { return }

            DispatchQueue.main.async {
                if url.pathExtension.lowercased() == "pdf" {
                    appState.loadPDF(url: url)
                    windowController.updateCardAspectRatio()
                }
            }
        }

        return true
    }
}
