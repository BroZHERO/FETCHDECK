import Foundation
import AppKit
import Combine

@MainActor
public final class NewDownloadViewModel: ObservableObject {
    @Published public var urlString: String = ""
    @Published public var filename: String = ""
    @Published public var destinationFolder: String = ""
    @Published public var connections: Int = 8
    @Published public var autoStart: Bool = true
    @Published public var errorMessage: String? = nil

    public init() {
        let manager = DownloadManager.shared
        self.destinationFolder = manager.defaultDownloadFolder
        self.connections = manager.defaultConnections
        self.checkClipboard()
    }

    public func checkClipboard() {
        if let clip = NSPasteboard.general.string(forType: .string)?.trimmingCharacters(in: .whitespacesAndNewlines) {
            if clip.hasPrefix("http://") || clip.hasPrefix("https://") {
                urlString = clip
                if let url = URL(string: clip) {
                    filename = url.lastPathComponent
                }
            }
        }
    }

    public func selectFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        if panel.runModal() == .OK, let url = panel.url {
            destinationFolder = url.path
        }
    }

    public func submit(onSuccess: () -> Void) {
        guard let url = URL(string: urlString.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            errorMessage = "Invalid URL format"
            return
        }

        DownloadManager.shared.addDownload(
            url: url,
            filename: filename.isEmpty ? nil : filename,
            destinationFolder: destinationFolder.isEmpty ? nil : destinationFolder,
            connections: connections,
            autoStart: autoStart
        )

        onSuccess()
    }
}
