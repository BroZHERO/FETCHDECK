import SwiftUI
import AppKit

public struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var manager = DownloadManager.shared

    public var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 24))
                    .foregroundColor(.blue)

                VStack(alignment: .leading, spacing: 2) {
                    Text("FETCHDECK Preferences")
                        .font(.headline)
                    Text("Configure acceleration, engine auto-updates, and browser bridge")
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

            Form {
                Section("Download Acceleration") {
                    Picker("Default Parallel Streams:", selection: $manager.defaultConnections) {
                        Text("1 (Single stream)").tag(1)
                        Text("4 Chunks").tag(4)
                        Text("8 Chunks (IDM Recommended)").tag(8)
                        Text("16 Chunks (High Speed)").tag(16)
                        Text("32 Chunks (Aggressive)").tag(32)
                    }

                    Picker("Maximum Concurrent Downloads:", selection: $manager.maxConcurrentDownloads) {
                        Text("1 at a time").tag(1)
                        Text("2 at a time").tag(2)
                        Text("3 at a time").tag(3)
                        Text("5 at a time").tag(5)
                        Text("10 at a time").tag(10)
                    }
                }

                Section("Save Locations") {
                    HStack {
                        TextField("Default Download Folder:", text: $manager.defaultDownloadFolder)
                            .textFieldStyle(.roundedBorder)
                        Button("Browse...") {
                            selectFolder()
                        }
                    }
                }

                Section("Extraction Engine (1,000+ Sites)") {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 6) {
                                Circle()
                                    .fill(Color.green)
                                    .frame(width: 7, height: 7)
                                Text("yt-dlp Engine Version: \(manager.engineVersion)")
                                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                            }
                            Text("Challenge Solver: Node.js • Multiplexer: FFmpeg")
                                .font(.caption2)
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
                                Text("Check for Updates")
                            }
                        }
                        .disabled(manager.isUpdatingEngine)
                    }

                    if let msg = manager.engineUpdateMessage {
                        Text(msg)
                            .font(.system(size: 10.5))
                            .foregroundColor(msg.contains("✓") ? .green : .blue)
                    }
                }

                Section("Smart Sleep & Network") {
                    HStack(spacing: 8) {
                        Image(systemName: "bolt.shield")
                            .foregroundColor(.blue)
                        Text("Auto-pauses active downloads when Mac sleeps; resumes automatically on wake.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                Section("Browser Extension Bridge") {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(Color.green)
                            .frame(width: 7, height: 7)
                        Text("Bridge active on port 45678 (127.0.0.1:45678)")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                    Text("Compatible with Chrome, Brave, Edge, and Chromium browsers.")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }

            Spacer()
        }
        .padding(22)
        .frame(width: 520, height: 490)
    }

    private func selectFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        if panel.runModal() == .OK, let url = panel.url {
            manager.defaultDownloadFolder = url.path
        }
    }
}
