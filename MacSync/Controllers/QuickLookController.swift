import Foundation
import AppKit
import Quartz

// MARK: - Quick Look Panel Controller
@MainActor
public final class QuickLookController: NSObject, QLPreviewPanelDataSource, QLPreviewPanelDelegate {
    public static let shared = QuickLookController()

    private var previewURL: URL?

    public var isPreviewing: Bool {
        QLPreviewPanel.shared()?.isVisible ?? false
    }

    public func showPreview(for fileURL: URL) {
        self.previewURL = fileURL

        guard let panel = QLPreviewPanel.shared() else { return }
        panel.dataSource = self
        panel.delegate = self
        panel.reloadData()
        panel.makeKeyAndOrderFront(nil)
    }

    public func togglePreview(for fileURL: URL) {
        guard let panel = QLPreviewPanel.shared() else { return }
        if panel.isVisible && previewURL == fileURL {
            panel.orderOut(nil)
            previewURL = nil
        } else {
            showPreview(for: fileURL)
        }
    }

    public func closePreview() {
        QLPreviewPanel.shared()?.orderOut(nil)
        previewURL = nil
    }

    // MARK: - QLPreviewPanelDataSource
    public nonisolated func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int {
        MainActor.assumeIsolated {
            return previewURL != nil ? 1 : 0
        }
    }

    public nonisolated func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> QLPreviewItem! {
        MainActor.assumeIsolated {
            guard let previewURL = previewURL else { return nil }
            return previewURL as NSURL
        }
    }
}
