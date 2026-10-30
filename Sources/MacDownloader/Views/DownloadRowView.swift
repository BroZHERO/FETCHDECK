import SwiftUI
import AppKit

public struct DownloadRowView: View {
    @ObservedObject var manager = DownloadManager.shared
    public let item: DownloadItem

    public var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 12) {
                // Category Icon
                Image(systemName: item.category.systemIcon)
                    .font(.system(size: 20))
                    .foregroundColor(iconColor)
                    .frame(width: 32, height: 32)
                    .background(iconColor.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 6))

                // Name, Resolution and URL
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        if let q = item.quality {
                            Text(q)
                                .font(.system(size: 10, weight: .bold, design: .rounded))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 1.5)
                                .background(qualityColor(for: q).opacity(0.18))
                                .foregroundColor(qualityColor(for: q))
                                .clipShape(RoundedRectangle(cornerRadius: 4))
                        }

                        if let res = item.resolutionDetails ?? defaultResolutionDetails(for: item.quality) {
                            Text(res)
                                .font(.system(size: 9.5, weight: .medium, design: .monospaced))
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1)
                                .background(Color.secondary.opacity(0.12))
                                .foregroundColor(.secondary)
                                .clipShape(RoundedRectangle(cornerRadius: 3))
                        }

                        Text(cleanDisplayName(for: item.filename))
                            .font(.system(size: 13, weight: .semibold))
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }

                    Text(item.url.absoluteString)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }

                Spacer()

                // Status Badge
                statusBadge

                // Action Buttons
                HStack(spacing: 8) {
                    if item.status == .downloading {
                        Button {
                            manager.pauseDownload(id: item.id)
                        } label: {
                            Image(systemName: "pause.fill")
                                .font(.system(size: 11))
                        }
                        .buttonStyle(.bordered)
                        .help("Pause")
                    } else if item.status == .paused || item.status == .queued || item.status == .failed {
                        Button {
                            manager.startDownload(id: item.id)
                        } label: {
                            Image(systemName: "play.fill")
                                .font(.system(size: 11))
                        }
                        .buttonStyle(.borderedProminent)
                        .help("Resume")
                    } else if item.status == .completed {
                        Button {
                            revealInFinder()
                        } label: {
                            Image(systemName: "magnifyingglass")
                                .font(.system(size: 11))
                        }
                        .buttonStyle(.bordered)
                        .help("Show in Finder")
                    }

                    Button {
                        manager.selectedDetailItem = item
                    } label: {
                        Image(systemName: "info.circle")
                            .font(.system(size: 11))
                    }
                    .buttonStyle(.borderless)
                    .help("Download Details")

                    Button(role: .destructive) {
                        manager.removeDownload(id: item.id)
                    } label: {
                        Image(systemName: "trash")
                            .font(.system(size: 11))
                    }
                    .buttonStyle(.borderless)
                    .help("Remove Task")
                }
            }

            // IDM-Style Multi-Connection Segment Visualizer
            SegmentVisualizerView(segments: item.segments)

            // Bottom Metrics Bar
            HStack(spacing: 12) {
                Text("\(item.formattedDownloaded) of \(item.formattedSize) (\(Int(item.progress * 100))%)")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.secondary)

                if item.status == .downloading {
                    Text("•")
                        .foregroundColor(.secondary)
                    Text(item.formattedSpeed)
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundColor(.blue)

                    Text("•")
                        .foregroundColor(.secondary)
                    Text("ETA: \(item.formattedETA)")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.secondary)

                    Text("•")
                        .foregroundColor(.secondary)
                    Text("\(item.connectionCount) conns")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.secondary)
                }

                if let err = item.errorMessage {
                    Text("• Error: \(err)")
                        .font(.system(size: 11))
                        .foregroundColor(.red)
                }

                Spacer()
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 10)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .contextMenu {
            if item.status == .downloading {
                Button("Pause") { manager.pauseDownload(id: item.id) }
            } else if item.status == .paused || item.status == .failed {
                Button("Resume") { manager.startDownload(id: item.id) }
            }
            if item.status == .completed {
                Button("Show in Finder") { revealInFinder() }
                Button("Open File") { openFile() }
            }
            Divider()
            Button("Copy URL") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(item.url.absoluteString, forType: .string)
            }
            Button("Download Details") { manager.selectedDetailItem = item }
            Divider()
            Button("Remove from List", role: .destructive) {
                manager.removeDownload(id: item.id, deleteFile: false)
            }
            Button("Delete File and Remove", role: .destructive) {
                manager.removeDownload(id: item.id, deleteFile: true)
            }
        }
    }

    private var statusBadge: some View {
        Text(item.status.rawValue)
            .font(.system(size: 10, weight: .semibold))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(statusColor.opacity(0.15))
            .foregroundColor(statusColor)
            .clipShape(Capsule())
    }

    private var statusColor: Color {
        switch item.status {
        case .downloading: return .blue
        case .completed: return .green
        case .paused: return .orange
        case .queued: return .purple
        case .failed: return .red
        }
    }

    private var iconColor: Color {
        switch item.category {
        case .video: return .purple
        case .audio: return .pink
        case .compressed: return .orange
        case .documents: return .blue
        default: return .gray
        }
    }

    private func qualityColor(for q: String) -> Color {
        let lower = q.lowercased()
        if lower.contains("2160") || lower.contains("4k") || lower.contains("1440") || lower.contains("1080") {
            return .blue
        } else if lower.contains("720") {
            return .teal
        } else if lower.contains("480") {
            return .purple
        } else if lower.contains("360") || lower.contains("240") {
            return .orange
        } else if lower.contains("audio") {
            return .pink
        }
        return .indigo
    }

    private func defaultResolutionDetails(for quality: String?) -> String? {
        guard let q = quality?.lowercased() else { return nil }
        if q.contains("2160") || q.contains("4k") { return "3840×2160 4K" }
        if q.contains("1440") || q.contains("2k") { return "2560×1440 2K" }
        if q.contains("1080") { return "1920×1080 Full HD" }
        if q.contains("720") { return "1280×720 HD" }
        if q.contains("480") { return "854×480 SD" }
        if q.contains("360") { return "640×360" }
        if q.contains("240") { return "426×240" }
        if q.contains("audio") { return "128 kbps Stereo" }
        return nil
    }

    private func cleanDisplayName(for name: String) -> String {
        var clean = name
        let prefixes = ["[1080p Full HD] ", "[1080p] ", "[720p HD] ", "[720p] ", "[480p] ", "[360p] ", "[Audio] ", "[3p] "]
        for p in prefixes {
            if clean.hasPrefix(p) {
                clean = String(clean.dropFirst(p.count))
                break
            }
        }
        return clean
    }

    private func revealInFinder() {
        NSWorkspace.shared.activateFileViewerSelecting([item.destinationFileURL])
    }

    private func openFile() {
        NSWorkspace.shared.open(item.destinationFileURL)
    }
}
