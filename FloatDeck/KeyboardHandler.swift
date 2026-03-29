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
                openPDFPanel()
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

    private func openPDFPanel() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.pdf]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.message = "Select a PDF to display"

        panel.begin { [weak self] response in
            guard let self, response == .OK, let url = panel.url else { return }
            self.appState.loadPDF(url: url)
            self.windowController.updateCardAspectRatio()
        }
    }
}
