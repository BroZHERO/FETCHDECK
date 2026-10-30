import SwiftUI
import AppKit

public struct DownloadRowView: View {
    @ObservedObject var manager = DownloadManager.shared
    public let item: DownloadItem

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                // Downie-Effect: Rich Video Thumbnail with duration badge or fallback category icon
                thumbnailView

                // Name, Resolution, Dimensions and URL
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        if let q = item.quality {
                            Text(q)
                                .font(.system(size: 10, weight: .bold, design: .rounded))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(qualityColor(for: q).opacity(0.18))
                                .foregroundColor(qualityColor(for: q))
                                .clipShape(RoundedRectangle(cornerRadius: 4))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 4)
                                        .stroke(qualityColor(for: q).opacity(0.35), lineWidth: 0.5)
                                )
                        }

                        if let res = item.resolutionDetails ?? defaultResolutionDetails(for: item.quality) {
                            Text(res)
                                .font(.system(size: 9.5, weight: .medium, design: .monospaced))
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1.5)
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
                        .font(.system(size: 10.5))
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

                        Button {
                            openFile()
                        } label: {
                            Image(systemName: "play.circle")
                                .font(.system(size: 12))
                        }
                        .buttonStyle(.bordered)
                        .help("Play Media")
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
                        .foregroundColor(.secondary.opacity(0.6))
                    Text(item.formattedSpeed)
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundColor(.blue)

                    Text("•")
                        .foregroundColor(.secondary.opacity(0.6))
                    Text("ETA: \(item.formattedETA)")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.secondary)

                    if item.connectionCount > 1 && !item.segments.isEmpty {
                        Text("•")
                            .foregroundColor(.secondary.opacity(0.6))
                        Text("\(item.connectionCount) streams")
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                            .foregroundColor(.indigo)
                    }
                }

                if let err = item.errorMessage, item.status == .failed {
                    Text("• \(err)")
                        .font(.system(size: 10.5))
                        .foregroundColor(.red)
                        .lineLimit(1)
                }

                Spacer()

                Text(item.dateAdded, style: .time)
                    .font(.system(size: 10))
                    .foregroundColor(.secondary.opacity(0.6))
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(NSColor.controlBackgroundColor).opacity(0.45))
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
        .contextMenu {
            if item.status == .downloading {
                Button("Pause") { manager.pauseDownload(id: item.id) }
            } else if item.status == .paused || item.status == .failed {
                Button("Resume") { manager.startDownload(id: item.id) }
            }
            if item.status == .completed {
                Button("Show in Finder") { revealInFinder() }
                Button("Play Media") { openFile() }
                if item.category == .video {
                    Divider()
                    Button("Extract Audio as MP3 (320 kbps)") {
                        manager.extractAudioAsMP3(for: item.id)
                    }
                }
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

    // MARK: - Downie-Style Rich Thumbnail View

    private var thumbnailView: some View {
        ZStack(alignment: .bottomTrailing) {
            if let thumbUrl = item.thumbnailURL {
                AsyncImage(url: thumbUrl) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: 68, height: 44)
                            .clipped()
                    case .failure:
                        fallbackCategoryIcon
                    case .empty:
                        ZStack {
                            Color.black.opacity(0.2)
                            ProgressView()
                                .scaleEffect(0.6)
                        }
                        .frame(width: 68, height: 44)
                    @unknown default:
                        fallbackCategoryIcon
                    }
                }
            } else {
                fallbackCategoryIcon
            }

            // Duration Pill Overlay
            if let dur = item.duration, !dur.isEmpty {
                Text(dur)
                    .font(.system(size: 8.5, weight: .bold, design: .monospaced))
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(Color.black.opacity(0.75))
                    .foregroundColor(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 3))
                    .padding(3)
            }
        }
        .frame(width: 68, height: 44)
        .background(Color.black.opacity(0.15))
        .clipShape(RoundedRectangle(cornerRadius: 7))
        .overlay(
            RoundedRectangle(cornerRadius: 7)
                .stroke(Color.white.opacity(0.12), lineWidth: 0.8)
        )
    }

    private var fallbackCategoryIcon: some View {
        ZStack {
            LinearGradient(
                colors: [iconColor.opacity(0.22), iconColor.opacity(0.08)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            Image(systemName: item.category.systemIcon)
                .font(.system(size: 18))
                .foregroundColor(iconColor)
        }
        .frame(width: 68, height: 44)
    }

    private var statusBadge: some View {
        Text(item.status.rawValue)
            .font(.system(size: 10, weight: .semibold))
            .padding(.horizontal, 7)
            .padding(.vertical, 2.5)
            .background(statusColor.opacity(0.15))
            .foregroundColor(statusColor)
            .clipShape(Capsule())
            .overlay(
                Capsule()
                    .stroke(statusColor.opacity(0.3), lineWidth: 0.5)
            )
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
        } else if lower.contains("audio") || lower.contains("mp3") {
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
        if q.contains("mp3") { return "320 kbps MP3" }
        return nil
    }

    private func cleanDisplayName(for name: String) -> String {
        var clean = name
        let prefixes = [
            "[4K Ultra HD] ", "[4K] ", "[2160p] ", "[1440p 2K QHD] ", "[1440p] ",
            "[1080p Full HD] ", "[1080p] ", "[720p HD] ", "[720p] ",
            "[480p SD] ", "[480p] ", "[360p] ", "[Audio] ", "[MP3] ", "[3p] "
        ]
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
