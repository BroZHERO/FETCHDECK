import SwiftUI
import AppKit

public struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var manager = DownloadManager.shared

    public var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 24))
                    .foregroundColor(.blue)

                VStack(alignment: .leading) {
                    Text("Preferences")
                        .font(.headline)
                    Text("Configure download acceleration and Chrome extension bridge")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
                Button("Done") {
                    dismiss()
                }
            }

            Divider()

            Form {
                Section("Download Acceleration") {
                    Picker("Default Connections per Download:", selection: $manager.defaultConnections) {
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

                Section("Chrome Extension Integration") {
                    HStack {
                        Circle()
                            .fill(Color.green)
                            .frame(width: 8, height: 8)
                        Text("Local Extension Bridge is active on port 45678 (127.0.0.1:45678)")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                    Text("The Chrome extension automatically sends clicked video and audio streams directly to this listener.")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }

            Spacer()
        }
        .padding(24)
        .frame(width: 500, height: 380)
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
