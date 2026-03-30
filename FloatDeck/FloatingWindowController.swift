import AppKit
import SwiftUI

// MARK: - FloatingPanel (NSPanel subclass)

final class FloatingPanel: NSPanel {
    var lockedAspectRatio: CGFloat?

    init(contentRect: NSRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [.borderless, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        level = .floating
        hidesOnDeactivate = false
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        isMovableByWindowBackground = true
        titlebarAppearsTransparent = true
        titleVisibility = .hidden

        standardWindowButton(.closeButton)?.isHidden = true
        standardWindowButton(.miniaturizeButton)?.isHidden = true
        standardWindowButton(.zoomButton)?.isHidden = true

        collectionBehavior = [.canJoinAllSpaces, .fullScreenPrimary]
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    override func sendEvent(_ event: NSEvent) {
        if event.type == .leftMouseDown {
            makeKey()
            NSApp.activate(ignoringOtherApps: true)
        }
        super.sendEvent(event)
    }
}

// MARK: - FloatingWindowController

final class FloatingWindowController: NSObject, NSWindowDelegate {
    let panel: FloatingPanel
    let appState: AppState
    private var hostingView: NSHostingView<AnyView>?

    /// When true, exiting native full screen should go to card mode
    private var goToCardAfterFullScreenExit = false

    init(appState: AppState) {
        self.appState = appState

        let screenFrame = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)

        // Start in present mode: centered, 90% of screen
        let ratio = appState.aspectRatio
        let maxWidth = screenFrame.width * 0.9
        let maxHeight = screenFrame.height * 0.9
        var width = maxWidth
        var height = width / ratio
        if height > maxHeight {
            height = maxHeight
            width = height * ratio
        }
        let presentOrigin = NSPoint(
            x: screenFrame.midX - width / 2,
            y: screenFrame.midY - height / 2
        )
        let presentRect = NSRect(origin: presentOrigin, size: NSSize(width: width, height: height))

        // Pre-calculate a card frame
        let cardSize = appState.defaultCardSize
        let cardOrigin = NSPoint(
            x: screenFrame.maxX - cardSize.width - 32,
            y: screenFrame.minY + 32
        )
        appState.cardFrame = NSRect(origin: cardOrigin, size: cardSize)

        appState.mode = .present
        panel = FloatingPanel(contentRect: presentRect)
        panel.level = .normal

        super.init()
        panel.delegate = self
    }

    func setContentView<V: View>(_ view: V, appState: AppState) {
        let hosting = NSHostingView(rootView:
            AnyView(view.environment(appState))
        )
        hosting.frame = panel.contentView?.bounds ?? .zero
        hosting.autoresizingMask = [.width, .height]

        panel.contentView?.wantsLayer = true
        panel.contentView?.layer?.cornerRadius = 12
        panel.contentView?.layer?.masksToBounds = true

        panel.contentView?.addSubview(hosting)
        self.hostingView = hosting
    }

    func show() {
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        observeWindowActive()
    }

    private func observeWindowActive() {
        NotificationCenter.default.addObserver(
            forName: NSWindow.didBecomeKeyNotification, object: panel, queue: .main
        ) { [weak self] _ in
            self?.appState.isWindowActive = true
            NSApp.activate(ignoringOtherApps: true)
        }
        NotificationCenter.default.addObserver(
            forName: NSWindow.didResignKeyNotification, object: panel, queue: .main
        ) { [weak self] _ in
            self?.appState.isWindowActive = false
        }
    }

    // MARK: - NSWindowDelegate

    func windowWillResize(_ sender: NSWindow, to frameSize: NSSize) -> NSSize {
        // Lock aspect ratio for PDF and images
        switch appState.contentType {
        case .pdf, .images:
            let ratio = appState.aspectRatio
            if ratio > 0 {
                return NSSize(width: frameSize.width, height: frameSize.width / ratio)
            }
        default:
            break
        }
        if let ratio = panel.lockedAspectRatio, ratio > 0 {
            return NSSize(width: frameSize.width, height: frameSize.width / ratio)
        }
        return frameSize
    }

    func windowDidResize(_ notification: Notification) {
        if appState.mode == .card && !appState.isInNativeFullScreen {
            appState.cardFrame = panel.frame
        }
    }

    func windowDidEnterFullScreen(_ notification: Notification) {
        appState.isInNativeFullScreen = true
    }

    func windowWillExitFullScreen(_ notification: Notification) {
        if goToCardAfterFullScreenExit {
            // Pre-set frame so the exit animation targets the card position
            panel.setFrame(appState.cardFrame, display: false)
        } else {
            // Staying in present mode — target the windowed present frame
            panel.setFrame(presentFrame(), display: false)
        }
    }

    func windowDidExitFullScreen(_ notification: Notification) {
        appState.isInNativeFullScreen = false

        if goToCardAfterFullScreenExit {
            goToCardAfterFullScreenExit = false
            applyCardState()
        } else {
            // Stay in present mode (user toggled fullscreen preference off)
            appState.mode = .present
            panel.level = .normal
            panel.setFrame(presentFrame(), display: true)
        }
    }

    // MARK: - Mode Switching

    /// Main entry point: toggle between card and present
    func toggleMode() {
        if appState.mode == .card {
            enterPresent()
        } else {
            enterCard()
        }
    }

    private func enterPresent() {
        guard !appState.isAnimating else { return }

        appState.cardFrame = panel.frame
        appState.mode = .present
        panel.lockedAspectRatio = nil
        panel.level = .normal

        if appState.isFullScreenMode {
            // Enter native full screen
            panel.toggleFullScreen(nil)
        } else {
            // Animate to windowed present
            appState.isAnimating = true
            let target = presentFrame()
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = 0.4
                context.timingFunction = CAMediaTimingFunction(controlPoints: 0.2, 1.0, 0.3, 1.0)
                panel.animator().setFrame(target, display: true)
            }, completionHandler: { [weak self] in
                self?.appState.isAnimating = false
            })
        }
    }

    private func enterCard() {
        guard !appState.isAnimating else { return }

        if appState.isInNativeFullScreen {
            // Exit native full screen first, then go to card
            goToCardAfterFullScreenExit = true
            panel.toggleFullScreen(nil)
        } else {
            // Animate directly to card
            appState.isAnimating = true
            appState.mode = .card
            let target = appState.cardFrame
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = 0.35
                context.timingFunction = CAMediaTimingFunction(controlPoints: 0.2, 1.0, 0.3, 1.0)
                panel.animator().setFrame(target, display: true)
            }, completionHandler: { [weak self] in
                guard let self else { return }
                self.appState.isAnimating = false
                self.applyCardState()
            })
        }
    }

    private func applyCardState() {
        appState.mode = .card
        panel.lockedAspectRatio = appState.aspectRatio
        panel.setFrame(appState.cardFrame, display: true)
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenPrimary, .stationary]
        panel.orderFrontRegardless()
    }

    /// Called when user toggles the Full Screen preference from the menu.
    /// If currently in present mode, switch between native full screen and windowed present.
    func applyFullScreenPreference() {
        guard appState.mode == .present else { return }

        if appState.isFullScreenMode && !appState.isInNativeFullScreen {
            // Preference turned ON while in windowed present → enter full screen
            panel.toggleFullScreen(nil)
        } else if !appState.isFullScreenMode && appState.isInNativeFullScreen {
            // Preference turned OFF while in native full screen → exit to windowed present
            goToCardAfterFullScreenExit = false
            panel.toggleFullScreen(nil)
        }
    }

    // MARK: - Frame Calculation

    private func presentFrame() -> NSRect {
        let screen = panel.screen ?? NSScreen.main ?? NSScreen.screens.first!
        let visibleFrame = screen.visibleFrame

        let maxWidth = visibleFrame.width * 0.9
        let maxHeight = visibleFrame.height * 0.9

        let ratio = appState.aspectRatio
        var width = maxWidth
        var height = width / ratio

        if height > maxHeight {
            height = maxHeight
            width = height * ratio
        }

        return NSRect(
            x: visibleFrame.midX - width / 2,
            y: visibleFrame.midY - height / 2,
            width: width, height: height
        )
    }

    // MARK: - Card Size Update

    func updateCardAspectRatio() {
        let ratio = appState.aspectRatio

        let cardBase = appState.cardFrame
        let cardWidth = cardBase.width
        let cardHeight = cardWidth / ratio
        let cardOrigin = NSPoint(
            x: cardBase.origin.x,
            y: cardBase.origin.y + cardBase.height - cardHeight
        )
        appState.cardFrame = NSRect(origin: cardOrigin, size: NSSize(width: cardWidth, height: cardHeight))

        if appState.mode == .card {
            panel.setFrame(appState.cardFrame, display: true, animate: true)
            panel.lockedAspectRatio = ratio
        } else if !appState.isInNativeFullScreen {
            let target = presentFrame()
            panel.setFrame(target, display: true, animate: true)
        }
    }

    // MARK: - Persistence

    func saveWindowState() {
        let frame = appState.mode == .card ? panel.frame : appState.cardFrame
        UserDefaults.standard.set(NSStringFromRect(frame), forKey: "FloatDeck.cardFrame")
    }

    func restoreCardFrame() {
        if let frameString = UserDefaults.standard.string(forKey: "FloatDeck.cardFrame") {
            let frame = NSRectFromString(frameString)
            // Sanity check: card should be small (under 600pt wide)
            if frame.width > 0 && frame.width <= 600 && frame.height > 0 {
                appState.cardFrame = frame
            }
        }
    }
}
