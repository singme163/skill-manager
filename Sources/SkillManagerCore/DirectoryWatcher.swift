import Foundation

/// Watches a directory for writes/renames via a dispatch file-system source
/// and fires a debounced callback on the main queue.
public final class DirectoryWatcher {
    private let source: DispatchSourceFileSystemObject
    private var debounceWorkItem: DispatchWorkItem?

    public init?(url: URL, debounce: TimeInterval = 0.4, onChange: @escaping @Sendable () -> Void) {
        let descriptor = open(url.path, O_EVTONLY)
        guard descriptor >= 0 else { return nil }

        source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor,
            eventMask: [.write, .delete, .rename, .link],
            queue: .main
        )
        source.setCancelHandler { close(descriptor) }
        source.setEventHandler { [weak self] in
            self?.debounceWorkItem?.cancel()
            let item = DispatchWorkItem(block: onChange)
            self?.debounceWorkItem = item
            DispatchQueue.main.asyncAfter(deadline: .now() + debounce, execute: item)
        }
        source.resume()
    }

    deinit {
        source.cancel()
    }
}
