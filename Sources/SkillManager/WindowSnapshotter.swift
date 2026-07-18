import AppKit

/// Renders the app's own windows to PNG files by caching the window frame
/// view's display — pure self-rendering, so it needs no screen-recording
/// permission. Used by the SM_SNAPSHOT_DIR documentation-screenshot mode.
@MainActor
enum WindowSnapshotter {
    static func capture(_ window: NSWindow, to url: URL) {
        // contentView.superview is the theme frame: includes the title bar.
        guard let frameView = window.contentView?.superview,
              let rep = frameView.bitmapImageRepForCachingDisplay(in: frameView.bounds) else {
            return
        }
        // Blur materials are composited by the window server and come out
        // blank in a self-render; flatten them to plain backgrounds first.
        flattenVibrancy(in: frameView)
        window.displayIfNeeded()
        frameView.cacheDisplay(in: frameView.bounds, to: rep)
        if let data = rep.representation(using: .png, properties: [:]) {
            try? data.write(to: url)
        }
    }

    private static func flattenVibrancy(in view: NSView) {
        if let effect = view as? NSVisualEffectView {
            effect.state = .inactive
            effect.material = .windowBackground
        }
        view.subviews.forEach { flattenVibrancy(in: $0) }
    }

    static var mainWindow: NSWindow? {
        NSApp.windows.first {
            $0.isVisible && $0.frame.width > 500 && !($0 is NSPanel)
        }
    }

    static func captureMainWindow(to url: URL) {
        guard let window = mainWindow else { return }
        capture(window, to: url)
    }

    static func captureAttachedSheet(to url: URL) {
        guard let sheet = mainWindow?.attachedSheet else { return }
        capture(sheet, to: url)
    }

    static func captureKeyWindow(resizedTo size: NSSize?, to url: URL) {
        guard let window = NSApp.keyWindow ?? NSApp.windows.last(where: { $0.isVisible }) else { return }
        if let size {
            window.setContentSize(size)
            window.center()
        }
        window.layoutIfNeeded()
        capture(window, to: url)
    }
}
