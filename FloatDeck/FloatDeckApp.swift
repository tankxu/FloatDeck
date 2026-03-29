import AppKit
import UniformTypeIdentifiers

// Pure AppKit entry point — no SwiftUI App/Scene, so no competing menu
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuItemValidation {
    var appState: AppState!
    var windowController: FloatingWindowController!
    var keyboardHandler: KeyboardHandler!

    func applicationDidFinishLaunching(_ notification: Notification) {
        appState = AppState()
        appState.loadRecentItems()

        NSApp.setActivationPolicy(.regular)
        buildMainMenu()

        windowController = FloatingWindowController(appState: appState)

        let contentView = ContentView(windowController: windowController)
        windowController.setContentView(contentView, appState: appState)
        windowController.restoreCardFrame()
        windowController.show()

        NSApp.activate(ignoringOtherApps: true)

        keyboardHandler = KeyboardHandler(appState: appState, windowController: windowController)
        keyboardHandler.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        windowController.saveWindowState()
    }

    // MARK: - Menu

    private func buildMainMenu() {
        let mainMenu = NSMenu()

        // App menu
        let appMenuItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "About FloatDeck", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Quit FloatDeck", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appMenuItem.submenu = appMenu
        mainMenu.addItem(appMenuItem)

        // File menu
        let fileMenuItem = NSMenuItem()
        let fileMenu = NSMenu(title: "File")
        let openItem = NSMenuItem(title: "Open PDF...", action: #selector(handleOpenPDF), keyEquivalent: "o")
        openItem.target = self
        fileMenu.addItem(openItem)
        let urlItem = NSMenuItem(title: "Load URL...", action: #selector(handleLoadURL), keyEquivalent: "l")
        urlItem.target = self
        fileMenu.addItem(urlItem)
        fileMenu.addItem(.separator())
        let closeItem = NSMenuItem(title: "Close", action: #selector(handleClose), keyEquivalent: "w")
        closeItem.target = self
        fileMenu.addItem(closeItem)
        fileMenuItem.submenu = fileMenu
        mainMenu.addItem(fileMenuItem)

        // View menu
        let viewMenuItem = NSMenuItem()
        let viewMenu = NSMenu(title: "View")
        let fullScreenItem = NSMenuItem(title: "Full Screen", action: #selector(toggleFullScreenMode), keyEquivalent: "f")
        fullScreenItem.keyEquivalentModifierMask = [.command, .control]
        fullScreenItem.target = self
        viewMenu.addItem(fullScreenItem)
        viewMenuItem.submenu = viewMenu
        mainMenu.addItem(viewMenuItem)

        NSApp.mainMenu = mainMenu
    }

    @objc private func toggleFullScreenMode() {
        appState.isFullScreenMode.toggle()
        windowController.applyFullScreenPreference()
    }

    @objc private func handleOpenPDF() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.pdf]
        panel.allowsMultipleSelection = false
        panel.begin { [weak self] response in
            guard let self, response == .OK, let url = panel.url else { return }
            self.appState.loadPDF(url: url)
            self.windowController.updateCardAspectRatio()
        }
    }

    @objc private func handleLoadURL() {
        appState.showURLInput = true
    }

    @objc private func handleClose() {
        if appState.contentType == .empty {
            NSApp.terminate(nil)
        } else {
            appState.closeContent()
        }
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        if menuItem.action == #selector(toggleFullScreenMode) {
            menuItem.state = appState.isFullScreenMode ? .on : .off
        }
        return true
    }
}
