import Foundation
import AppKit
import Combine

public enum DownloadPreset: String, CaseIterable, Identifiable {
    case video = "🎬 High-Res Video (MP4)"
    case mp3 = "🎵 High Quality MP3 (320 kbps)"
    case m4a = "🎧 Original Audio (M4A)"

    public var id: String { rawValue }
}

@MainActor
public final class NewDownloadViewModel: ObservableObject {
    @Published public var urlString: String = ""
    @Published public var filename: String = ""
    @Published public var destinationFolder: String = ""
    @Published public var connections: Int = 8
    @Published public var selectedPreset: DownloadPreset = .video
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
        let trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed) else {
            errorMessage = "Invalid URL format"
            return
        }

        var category: DownloadCategory = .other
        var quality: String = "Original"
        var resolutionDetails: String = "Best Quality"

        switch selectedPreset {
        case .video:
            category = .video
            quality = "HD Video"
            resolutionDetails = "Best Resolution"
        case .mp3:
            category = .audio
            quality = "MP3 320k"
            resolutionDetails = "High Quality MP3"
        case .m4a:
            category = .audio
            quality = "M4A Audio"
            resolutionDetails = "Original Audio Track"
        }

        var finalName = filename.trimmingCharacters(in: .whitespacesAndNewlines)
        if !finalName.isEmpty {
            if selectedPreset == .mp3 && !finalName.lowercased().hasSuffix(".mp3") {
                let base = (finalName as NSString).deletingPathExtension
                finalName = "\(base).mp3"
            } else if selectedPreset == .m4a && !finalName.lowercased().hasSuffix(".m4a") {
                let base = (finalName as NSString).deletingPathExtension
                finalName = "\(base).m4a"
            }
        }

        DownloadManager.shared.addDownload(
            url: url,
            filename: finalName.isEmpty ? nil : finalName,
            destinationFolder: destinationFolder.isEmpty ? nil : destinationFolder,
            connections: connections,
            quality: quality,
            resolutionDetails: resolutionDetails,
            category: category,
            autoStart: autoStart
        )

        onSuccess()
    }
}
