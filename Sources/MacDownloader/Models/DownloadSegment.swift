import Foundation

public enum SegmentStatus: String, Codable, Sendable {
    case pending
    case downloading
    case completed
    case failed
}

public struct DownloadSegment: Identifiable, Codable, Sendable {
    public let id: Int
    public let startByte: Int64
    public var endByte: Int64
    public var downloadedBytes: Int64
    public var status: SegmentStatus

    public init(id: Int, startByte: Int64, endByte: Int64, downloadedBytes: Int64 = 0, status: SegmentStatus = .pending) {
        self.id = id
        self.startByte = startByte
        self.endByte = endByte
        self.downloadedBytes = downloadedBytes
        self.status = status
    }

    public var totalBytes: Int64 {
        if endByte >= startByte {
            return (endByte - startByte) + 1
        }
        return 0
    }

    public var progress: Double {
        guard totalBytes > 0 else { return 0 }
        return min(1.0, max(0.0, Double(downloadedBytes) / Double(totalBytes)))
    }
}
