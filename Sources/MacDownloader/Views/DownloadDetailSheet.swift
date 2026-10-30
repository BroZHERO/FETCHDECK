import SwiftUI

public struct DownloadDetailSheet: View {
    @Environment(\.dismiss) private var dismiss
    public let item: DownloadItem

    public var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            HStack {
                Image(systemName: item.category.systemIcon)
                    .font(.system(size: 24))
                    .foregroundColor(.blue)

                VStack(alignment: .leading, spacing: 2) {
                    Text(item.filename)
                        .font(.headline)
                        .lineLimit(1)
                    Text("Connection & Segment Details")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                Button("Done") {
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }

            Divider()

            // Info Grid
            VStack(alignment: .leading, spacing: 8) {
                infoRow(title: "Status:", value: item.status.rawValue)
                if let q = item.quality {
                    infoRow(title: "Resolution:", value: q)
                }
                infoRow(title: "File Size:", value: item.formattedSize)
                infoRow(title: "Downloaded:", value: "\(item.formattedDownloaded) (\(Int(item.progress * 100))%)")
                infoRow(title: "Speed:", value: item.formattedSpeed)
                infoRow(title: "Connections:", value: "\(item.connectionCount) parallel threads")
                infoRow(title: "Target Path:", value: item.destinationFileURL.path)
                infoRow(title: "Source URL:", value: item.url.absoluteString)
            }
            .font(.system(size: 12))

            Divider()

            Text("Parallel Segments Status (\(item.segments.count) active):")
                .font(.system(size: 12, weight: .semibold))

            // Segments Table / List
            if item.segments.isEmpty {
                Text("Segments will be created once server connection starts.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: 100)
            } else {
                ScrollView {
                    VStack(spacing: 6) {
                        ForEach(item.segments) { segment in
                            HStack(spacing: 8) {
                                Text("Part \(segment.id + 1)")
                                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                                    .frame(width: 50, alignment: .leading)

                                GeometryReader { geo in
                                    ZStack(alignment: .leading) {
                                        RoundedRectangle(cornerRadius: 3)
                                            .fill(Color.primary.opacity(0.1))
                                        RoundedRectangle(cornerRadius: 3)
                                            .fill(segmentColor(segment))
                                            .frame(width: max(0, geo.size.width * CGFloat(segment.progress)))
                                    }
                                }
                                .frame(height: 12)

                                Text("\(Int(segment.progress * 100))%")
                                    .font(.system(size: 11, design: .monospaced))
                                    .frame(width: 40, alignment: .trailing)

                                Text(ByteCountFormatter.string(fromByteCount: segment.downloadedBytes, countStyle: .file))
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundColor(.secondary)
                                    .frame(width: 70, alignment: .trailing)
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color(NSColor.controlBackgroundColor))
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                        }
                    }
                }
                .frame(maxHeight: 180)
            }

            Spacer()
        }
        .padding(20)
        .frame(width: 540, height: 460)
    }

    private func infoRow(title: String, value: String) -> some View {
        HStack(alignment: .top) {
            Text(title)
                .foregroundColor(.secondary)
                .frame(width: 100, alignment: .leading)
            Text(value)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer()
        }
    }

    private func segmentColor(_ segment: DownloadSegment) -> Color {
        switch segment.status {
        case .completed: return .green
        case .downloading: return .blue
        case .pending: return .orange
        case .failed: return .red
        }
    }
}
