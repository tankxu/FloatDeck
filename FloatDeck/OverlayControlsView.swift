import SwiftUI

struct OverlayControlsView: View {
    @Environment(AppState.self) private var appState
    let windowController: FloatingWindowController

    private var showControls: Bool {
        if appState.mode == .present { return true }
        // Card mode: only show when window is active
        return appState.isWindowActive
    }

    var body: some View {
        VStack {
            if showControls {
                HStack(spacing: 6) {
                    if appState.mode == .present {
                        // Present mode: close + minimize
                        ControlButton(icon: appState.contentType == .empty ? "xmark" : "chevron.left") {
                            if appState.contentType == .empty {
                                NSApp.terminate(nil)
                            } else {
                                appState.closeContent()
                            }
                        }
                        ControlButton(icon: "arrow.down.right.and.arrow.up.left") {
                            windowController.toggleMode()
                        }
                    } else {
                        // Card mode: expand button only (active state)
                        ControlButton(icon: "arrow.up.left.and.arrow.down.right") {
                            windowController.toggleMode()
                        }
                    }

                    Spacer()
                }
                .padding(8)
                .transition(.opacity)
            } else {
                Color.clear.frame(height: 40)
            }

            Spacer()

            // Page indicator (PDF and images)
            if appState.totalPages > 1 {
                PageIndicatorView()
                    .padding(.bottom, 8)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: showControls)
    }
}

// MARK: - Control Button

struct ControlButton: View {
    let icon: String
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(isHovered ? .primary : .tertiary)
                .frame(width: 24, height: 24)
                .glassEffect(in: .rect(cornerRadius: 6))
                .shadow(color: .black.opacity(isHovered ? 0.25 : 0.05), radius: isHovered ? 4 : 1, y: isHovered ? 2 : 0.5)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
    }
}

// MARK: - Page Indicator

struct PageIndicatorView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        Text("\(appState.currentPage + 1) / \(appState.totalPages)")
            .font(.system(size: 11, weight: .medium, design: .rounded))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .glassEffect(in: .capsule)
    }
}
