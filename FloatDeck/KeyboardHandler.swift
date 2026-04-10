import AppKit
import UniformTypeIdentifiers

final class KeyboardHandler {
    private let appState: AppState
    private let windowController: FloatingWindowController
    private var monitor: Any?

    init(appState: AppState, windowController: FloatingWindowController) {
        self.appState = appState
        self.windowController = windowController
    }

    func start() {
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
            guard let self else { return event }
            return self.handleKeyDown(event) ? nil : event
        }
    }

    func stop() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
    }

    private func handleKeyDown(_ event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let hasCmd = flags.contains(.command)

        // Cmd+key shortcuts
        if hasCmd {
            switch event.charactersIgnoringModifiers {
            case "o":
                openFilePanel()
                return true
            case "l":
                appState.showURLInput = true
                return true
            case "w":
                appState.closeContent()
                return true
            case "q":
                windowController.saveWindowState()
                NSApp.terminate(nil)
                return true
            default:
                return false
            }
        }

        // Non-modifier shortcuts
        switch event.keyCode {
        case 49: // Space
            windowController.toggleMode()
            return true
        case 53: // Escape
            if appState.mode == .present {
                windowController.toggleMode()
                return true
            }
            return false
        case 123: // Left arrow
            appState.previousPage()
            return true
        case 124: // Right arrow
            appState.nextPage()
            return true
        case 126: // Up arrow
            appState.previousPage()
            return true
        case 125: // Down arrow
            appState.nextPage()
            return true
        default:
            return false
        }
    }

    private func openFilePanel() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.pdf, .png, .jpeg, .gif, .bmp, .tiff, .webP, .heic, .svg]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.message = "Select a PDF or images to display"

        panel.begin { [weak self] response in
            guard let self, response == .OK, !panel.urls.isEmpty else { return }
            let urls = panel.urls
            let ext = urls.first?.pathExtension.lowercased() ?? ""
            if urls.count == 1 && ext == "pdf" {
                self.appState.loadPDF(url: urls[0])
            } else {
                let imageURLs = urls.filter { AppState.imageExtensions.contains($0.pathExtension.lowercased()) }
                self.appState.loadImages(urls: imageURLs)
            }
            self.windowController.updateCardAspectRatio()
        }
    }
}
