import SwiftUI

public struct SegmentVisualizerView: View {
    public let segments: [DownloadSegment]

    public init(segments: [DownloadSegment]) {
        self.segments = segments
    }

    public var body: some View {
        if segments.isEmpty {
            ProgressView()
                .progressViewStyle(.linear)
                .frame(height: 6)
        } else {
            HStack(spacing: 2) {
                ForEach(segments) { segment in
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            // Track
                            RoundedRectangle(cornerRadius: 2)
                                .fill(Color.primary.opacity(0.12))

                            // Filled progress for this chunk
                            RoundedRectangle(cornerRadius: 2)
                                .fill(color(for: segment))
                                .frame(width: max(0, geo.size.width * CGFloat(segment.progress)))
                        }
                    }
                    .frame(height: 8)
                    .help("Segment \(segment.id + 1): \(Int(segment.progress * 100))% (\(ByteCountFormatter.string(fromByteCount: segment.downloadedBytes, countStyle: .file)))")
                }
            }
            .frame(height: 8)
        }
    }

    private func color(for segment: DownloadSegment) -> Color {
        switch segment.status {
        case .completed:
            return Color.green
        case .downloading:
            return Color.blue
        case .pending:
            return Color.orange.opacity(0.7)
        case .failed:
            return Color.red
        }
    }
}
