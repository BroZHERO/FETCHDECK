import SwiftUI
import AppKit

public struct AboutView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var manager = DownloadManager.shared

    public var body: some View {
        VStack(spacing: 16) {
            // App Icon with Sequoia Glass Glow
            ZStack {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [Color.blue.opacity(0.4), Color.purple.opacity(0.15), Color.clear],
                            center: .center,
                            startRadius: 10,
                            endRadius: 70
                        )
                    )
                    .frame(width: 140, height: 140)

                if let img = loadAppIcon() {
                    Image(nsImage: img)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 92, height: 92)
                        .clipShape(RoundedRectangle(cornerRadius: 20))
                        .shadow(color: Color.blue.opacity(0.4), radius: 16, x: 0, y: 8)
                        .overlay(
                            RoundedRectangle(cornerRadius: 20)
                                .stroke(Color.white.opacity(0.25), lineWidth: 1)
                        )
                } else {
                    Image(systemName: "arrow.down.circle.fill")
                        .font(.system(size: 72))
                        .foregroundColor(.blue)
                }
            }
            .padding(.top, 10)

            // App Name & Tagline
            VStack(spacing: 4) {
                Text("FETCHDECK")
                    .font(.system(size: 24, weight: .black, design: .rounded))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [Color.white, Color.blue.opacity(0.85)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )

                Text("[Your downloads, all in one place.]")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundColor(.cyan)

                Text("Version 1.0.0 • Apple Silicon Native")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.secondary)
                    .padding(.top, 2)
            }

            // Creator Credit Badge
            HStack(spacing: 6) {
                Image(systemName: "sparkles")
                    .foregroundColor(.yellow)
                    .font(.system(size: 11))
                Text("Vibecoded by Abishek @brozhero")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.primary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                Capsule()
                    .fill(Color.purple.opacity(0.15))
            )
            .overlay(
                Capsule()
                    .stroke(Color.purple.opacity(0.35), lineWidth: 0.8)
            )

            // 1,000+ Universal Sites Banner
            VStack(spacing: 6) {
                Text("UNIVERSAL 1,000+ SITE SUPPORT")
                    .font(.system(size: 9.5, weight: .heavy))
                    .foregroundColor(.secondary)
                    .tracking(0.5)

                HStack(spacing: 5) {
                    sitePill("YouTube", color: .red)
                    sitePill("TikTok", color: .cyan)
                    sitePill("Instagram", color: .pink)
                    sitePill("X / Twitter", color: .blue)
                    sitePill("Reddit", color: .orange)
                    sitePill("Vimeo", color: .teal)
                    sitePill("SoundCloud", color: .orange)
                }
            }
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.secondary.opacity(0.08))
            )

            // Extraction Engine Status & Updater
            VStack(spacing: 6) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Extraction Engine: yt-dlp \(manager.engineVersion)")
                            .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        Text("Muxer: FFmpeg • Challenge Solver: Node.js")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                    }

                    Spacer()

                    Button {
                        manager.updateExtractionEngine()
                    } label: {
                        if manager.isUpdatingEngine {
                            ProgressView()
                                .scaleEffect(0.6)
                        } else {
                            Text("Update Engine")
                                .font(.system(size: 11, weight: .medium))
                        }
                    }
                    .buttonStyle(.bordered)
                    .disabled(manager.isUpdatingEngine)
                }

                if let msg = manager.engineUpdateMessage {
                    Text(msg)
                        .font(.system(size: 10.5))
                        .foregroundColor(msg.contains("✓") ? .green : .blue)
                        .lineLimit(1)
                }
            }
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color(NSColor.controlBackgroundColor).opacity(0.5))
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
            )

            Spacer()

            // Close Button
            Button("Done") {
                dismiss()
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.defaultAction)
            .padding(.bottom, 6)
        }
        .padding(20)
        .frame(width: 440, height: 490)
    }

    private func sitePill(_ name: String, color: Color) -> some View {
        Text(name)
            .font(.system(size: 9.5, weight: .semibold))
            .padding(.horizontal, 6)
            .padding(.vertical, 2.5)
            .background(color.opacity(0.15))
            .foregroundColor(color)
            .clipShape(Capsule())
            .overlay(
                Capsule()
                    .stroke(color.opacity(0.3), lineWidth: 0.5)
            )
    }

    private func loadAppIcon() -> NSImage? {
        let bundlePath = Bundle.main.bundleURL.appendingPathComponent("Contents/Resources/AppIcon.icns").path
        if let img = NSImage(contentsOfFile: bundlePath) {
            return img
        }
        let devPath = "/Users/abishekwork/.gemini/antigravity/scratch/MacDownloader/Sources/MacDownloader/Resources/AppIcon512.png"
        if let img = NSImage(contentsOfFile: devPath) {
            return img
        }
        return NSApp.applicationIconImage
    }
}
