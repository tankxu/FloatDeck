import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @Environment(AppState.self) private var appState
    let windowController: FloatingWindowController

    var body: some View {
        ZStack {
            // Liquid Glass background — edge to edge
            Color.clear
                .background(.ultraThinMaterial)
                .ignoresSafeArea()

            // Content area — edge to edge, no padding
            contentLayer

            // Card mode: transparent click catcher for tap-to-expand
            if appState.mode == .card && !appState.isAnimating {
                cardClickCatcher
            }

            // Overlay controls (buttons + page indicator)
            OverlayControlsView(windowController: windowController)
        }
        .onDrop(of: [.fileURL], delegate: FileDropDelegate(appState: appState, windowController: windowController))
        .sheet(isPresented: Binding(
            get: { appState.showURLInput },
            set: { appState.showURLInput = $0 }
        )) {
            URLInputSheet(appState: appState)
        }
    }

    @ViewBuilder
    private var contentLayer: some View {
        switch appState.contentType {
        case .empty:
            emptyState
        case .pdf(let url):
            PDFContentView(
                url: url,
                currentPage: Binding(
                    get: { appState.currentPage },
                    set: { appState.currentPage = $0 }
                ),
                isInteractive: appState.mode == .present
            )
        case .web(let url):
            WebContentView(
                url: url,
                isInteractive: appState.mode == .present
            )
        case .images(let urls):
            ImageContentView(
                urls: urls,
                currentPage: Binding(
                    get: { appState.currentPage },
                    set: { appState.currentPage = $0 }
                ),
                isInteractive: appState.mode == .present
            )
        }
    }

    @State private var showAllRecent = false

    private var emptyState: some View {
        VStack(spacing: 16) {
            Spacer()

            Image(systemName: "doc.on.doc")
                .font(.system(size: appState.mode == .card ? 28 : 48))
                .foregroundStyle(.secondary)

            if appState.mode == .present {
                Text("Drop PDF or images here")
                    .font(.system(size: 14))
                    .foregroundStyle(.tertiary)

                HStack(spacing: 12) {
                    Button {
                        openFile()
                    } label: {
                        Label("Open File", systemImage: "folder")
                            .font(.system(size: 13, weight: .medium))
                    }
                    .buttonStyle(.glass)
                    .controlSize(.large)

                    Button {
                        appState.showURLInput = true
                    } label: {
                        Label("Load URL", systemImage: "globe")
                            .font(.system(size: 13, weight: .medium))
                    }
                    .buttonStyle(.glass)
                    .controlSize(.large)
                }
                .padding(.top, 4)

                Text("⌘O open file  ·  ⌘L enter URL")
                    .font(.system(size: 11))
                    .foregroundStyle(.quaternary)

                // Recent history
                if !appState.recentItems.isEmpty {
                    recentHistorySection
                        .padding(.top, 12)
                }
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var recentHistorySection: some View {
        let visibleItems = showAllRecent ? appState.recentItems : Array(appState.recentItems.prefix(3))
        let hasMore = appState.recentItems.count > 3

        return VStack(spacing: 0) {
            HStack {
                Text("Recent")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                Spacer()
                if hasMore {
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            showAllRecent.toggle()
                        }
                    } label: {
                        Text(showAllRecent ? "Show Less" : "Show All (\(appState.recentItems.count))")
                            .font(.system(size: 11))
                            .foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 8)
            .padding(.bottom, 6)

            VStack(spacing: 2) {
                ForEach(visibleItems) { item in
                    RecentItemRow(item: item) {
                        openRecentItem(item)
                    } onDelete: {
                        withAnimation { appState.removeRecentItem(item) }
                    }
                }
            }
        }
        .frame(maxWidth: 320)
    }

    private func openRecentItem(_ item: RecentItem) {
        switch item.resolvedType {
        case .pdf:
            if let url = item.resolveURL() {
                _ = url.startAccessingSecurityScopedResource()
                appState.loadPDF(url: url)
                windowController.updateCardAspectRatio()
            } else {
                let panel = NSOpenPanel()
                panel.allowedContentTypes = [.pdf]
                panel.message = "Re-open \"\(item.title)\" to grant access"
                panel.directoryURL = item.url.deletingLastPathComponent()
                panel.begin { response in
                    guard response == .OK, let url = panel.url else { return }
                    appState.loadPDF(url: url)
                    windowController.updateCardAspectRatio()
                }
            }
        case .images:
            if let url = item.resolveURL() {
                _ = url.startAccessingSecurityScopedResource()
                appState.loadImages(urls: [url])
                windowController.updateCardAspectRatio()
            }
        case .web:
            appState.loadWeb(url: item.url)
        }
    }

    private func openFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.pdf, .png, .jpeg, .gif, .bmp, .tiff, .webP, .heic]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.begin { response in
            guard response == .OK, !panel.urls.isEmpty else { return }
            let urls = panel.urls
            if urls.count == 1 && urls[0].pathExtension.lowercased() == "pdf" {
                appState.loadPDF(url: urls[0])
            } else {
                appState.loadImages(urls: urls)
            }
            windowController.updateCardAspectRatio()
        }
    }

    private var cardClickCatcher: some View {
        Color.clear
            .contentShape(Rectangle())
            .onTapGesture {
                windowController.toggleMode()
            }
    }
}

// MARK: - Recent Item Row

struct RecentItemRow: View {
    let item: RecentItem
    let onTap: () -> Void
    let onDelete: () -> Void

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: item.resolvedType == .pdf ? "doc.fill" : item.resolvedType == .images ? "photo.fill" : "globe")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
                .frame(width: 16)

            Text(item.title)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)

            Spacer()

            if isHovered {
                Button {
                    onDelete()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.quaternary)
                        .frame(width: 16, height: 16)
                }
                .buttonStyle(.plain)
                .transition(.opacity)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isHovered ? Color.primary.opacity(0.06) : .clear)
        )
        .contentShape(Rectangle())
        .onTapGesture { onTap() }
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
    }
}
