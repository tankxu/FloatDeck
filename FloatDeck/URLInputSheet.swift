import SwiftUI

struct URLInputSheet: View {
    let appState: AppState
    let windowController: FloatingWindowController
    @State private var urlText = "https://"
    @FocusState private var isInputFocused: Bool
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 12) {
            Text("Load Web Page")
                .font(.headline)

            TextField("Enter URL", text: $urlText)
                .textFieldStyle(.roundedBorder)
                .focused($isInputFocused)
                .onSubmit { loadURL() }

            HStack {
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)

                Button("Go") { loadURL() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!isValidURL)
            }
        }
        .padding(20)
        .frame(width: 360)
        .onAppear {
            DispatchQueue.main.async {
                isInputFocused = true
            }
        }
    }

    private var isValidURL: Bool {
        guard let url = URL(string: urlText) else { return false }
        return url.scheme == "http" || url.scheme == "https"
    }

    private func loadURL() {
        guard let url = URL(string: urlText), isValidURL else { return }
        appState.loadURLSmart(url: url) {
            windowController.updateCardAspectRatio()
        }
        dismiss()
    }
}
