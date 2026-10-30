import Foundation

public enum DownloadStatus: String, Codable, Sendable {
    case queued = "Queued"
    case downloading = "Downloading"
    case paused = "Paused"
    case completed = "Completed"
    case failed = "Failed"
}

public enum DownloadCategory: String, CaseIterable, Codable, Sendable {
    case all = "All Downloads"
    case downloading = "Downloading"
    case paused = "Paused"
    case completed = "Finished"
    case video = "Video"
    case audio = "Audio"
    case compressed = "Compressed"
    case documents = "Documents"
    case other = "Other"

    public var systemIcon: String {
        switch self {
        case .all: return "tray.full"
        case .downloading: return "arrow.down.circle"
        case .paused: return "pause.circle"
        case .completed: return "checkmark.circle"
        case .video: return "film"
        case .audio: return "music.note"
        case .compressed: return "archivebox"
        case .documents: return "doc.text"
        case .other: return "questionmark.folder"
        }
    }
}

public struct DownloadItem: Identifiable, Codable, Sendable {
    public let id: UUID
    public var url: URL
    public var filename: String
    public var destinationFolder: String
    public var fileSize: Int64
    public var downloadedBytes: Int64
    public var status: DownloadStatus
    public var speed: Double // bytes per second
    public var eta: TimeInterval?
    public var connectionCount: Int
    public var segments: [DownloadSegment]
    public var category: DownloadCategory
    public var dateAdded: Date
    public var errorMessage: String?
    public var referer: String?
    public var userAgent: String?
    public var cookie: String?
    public var quality: String?
    public var audioUrl: URL?
    public var resolutionDetails: String?
    public var thumbnailURL: URL?
    public var duration: String?

    public init(
        id: UUID = UUID(),
        url: URL,
        filename: String? = nil,
        destinationFolder: String? = nil,
        fileSize: Int64 = -1,
        downloadedBytes: Int64 = 0,
        status: DownloadStatus = .queued,
        speed: Double = 0,
        eta: TimeInterval? = nil,
        connectionCount: Int = 8,
        segments: [DownloadSegment] = [],
        category: DownloadCategory = .other,
        dateAdded: Date = Date(),
        errorMessage: String? = nil,
        referer: String? = nil,
        userAgent: String? = nil,
        cookie: String? = nil,
        quality: String? = nil,
        audioUrl: URL? = nil,
        resolutionDetails: String? = nil,
        thumbnailURL: URL? = nil,
        duration: String? = nil
    ) {
        self.id = id
        self.url = url
        self.audioUrl = audioUrl
        self.resolutionDetails = resolutionDetails
        self.thumbnailURL = thumbnailURL
        self.duration = duration
        var defaultName = url.lastPathComponent.isEmpty ? "download" : url.lastPathComponent
        if defaultName.contains("?") {
            defaultName = defaultName.components(separatedBy: "?").first ?? defaultName
        }
        var finalName = filename ?? defaultName
        if url.pathExtension.lowercased() == "m3u8" || url.absoluteString.contains(".m3u8") {
            if finalName.hasSuffix(".m3u8") {
                finalName = (finalName as NSString).deletingPathExtension + ".mp4"
            } else if !finalName.hasSuffix(".mp4") {
                finalName += ".mp4"
            }
        }
        self.filename = finalName
        let defaultFolder = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first?.path ?? "/tmp"
        self.destinationFolder = destinationFolder ?? defaultFolder
        self.fileSize = fileSize
        self.downloadedBytes = downloadedBytes
        self.status = status
        self.speed = speed
        self.eta = eta
        self.connectionCount = connectionCount
        self.segments = segments
        self.dateAdded = dateAdded
        self.errorMessage = errorMessage
        self.referer = referer
        self.userAgent = userAgent
        self.cookie = cookie
        self.quality = quality ?? Self.extractQuality(from: self.filename)
        self.category = category == .other ? Self.detectCategory(for: self.filename) : category
    }

    public var destinationFileURL: URL {
        URL(fileURLWithPath: destinationFolder).appendingPathComponent(filename)
    }

    public var progress: Double {
        if fileSize > 0 {
            return min(1.0, max(0.0, Double(downloadedBytes) / Double(fileSize)))
        }
        return 0
    }

    public var formattedSpeed: String {
        guard status == .downloading, speed > 0 else { return "0 B/s" }
        return ByteCountFormatter.string(fromByteCount: Int64(speed), countStyle: .binary) + "/s"
    }

    public var formattedSize: String {
        if fileSize > 0 {
            return ByteCountFormatter.string(fromByteCount: fileSize, countStyle: .file)
        }
        return "Unknown size"
    }

    public var formattedDownloaded: String {
        ByteCountFormatter.string(fromByteCount: downloadedBytes, countStyle: .file)
    }

    public var formattedETA: String {
        guard status == .downloading, let eta = eta, eta > 0 else { return "--:--" }
        let minutes = Int(eta) / 60
        let seconds = Int(eta) % 60
        if minutes > 60 {
            let hours = minutes / 60
            return String(format: "%02d:%02d:%02d", hours, minutes % 60, seconds)
        }
        return String(format: "%02d:%02d", minutes, seconds)
    }

    public static func detectCategory(for filename: String) -> DownloadCategory {
        let ext = (filename as NSString).pathExtension.lowercased()
        switch ext {
        case "mp4", "mkv", "mov", "avi", "webm", "flv", "m4v", "wmv", "3gp", "ts", "m3u8":
            return .video
        case "mp3", "wav", "aac", "flac", "ogg", "m4a", "wma", "aiff":
            return .audio
        case "zip", "rar", "7z", "tar", "gz", "bz2", "dmg", "pkg", "iso":
            return .compressed
        case "pdf", "doc", "docx", "xls", "xlsx", "ppt", "pptx", "txt", "epub", "pages", "key", "numbers":
            return .documents
        default:
            return .other
        }
    }

    public static func extractQuality(from filename: String) -> String? {
        let qualities = ["2160p", "4K", "1440p", "2K", "1080p", "720p", "480p", "360p", "240p", "144p", "Audio"]
        for q in qualities {
            if filename.localizedCaseInsensitiveContains(q) {
                return q
            }
        }
        return nil
    }
}
