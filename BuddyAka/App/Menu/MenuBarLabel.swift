import AppKit
import SwiftUI

struct MenuBarLabel: View {
    let allGranted: Bool
    let hasError: Bool
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Group {
            if allGranted && !hasError {
                Image(systemName: "sparkles")
            } else {
                Image(systemName: "sparkles")
                    .symbolRenderingMode(.hierarchical)
                    .overlay(alignment: .topTrailing) {
                        Image(systemName: "circle.fill")
                            .font(.system(size: 6))
                            .foregroundStyle(hasError ? .red : .orange)
                            .offset(x: 2, y: -2)
                    }
            }
        }
        // Session errors set `lastError` even when the main window is closed.
        // MainWindow's `.alert` only displays if its host window is visible, so
        // bring the window forward whenever an error appears.
        .onChange(of: hasError) { _, isErrored in
            if isErrored {
                WindowPresenter.showMainWindow(using: openWindow)
            }
        }
    }
}
