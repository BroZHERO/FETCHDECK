import SwiftUI
import AppKit

public struct NewDownloadSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var vm: NewDownloadViewModel

    public init(viewModel: NewDownloadViewModel = NewDownloadViewModel()) {
        self.vm = viewModel
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Header with Brand and Glass Icon
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [Color.blue.opacity(0.85), Color.cyan.opacity(0.75)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 38, height: 38)
                        .shadow(color: Color.blue.opacity(0.35), radius: 6, x: 0, y: 3)

                    Image(systemName: "arrow.down.to.line.compact")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(.white)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("Add New Download")
                        .font(.system(size: 15, weight: .bold))
                    Text("Enter video URL or direct stream link to accelerate")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }

                Spacer()
            }
            .padding(.horizontal, 24)
            .padding(.top, 20)
            .padding(.bottom, 16)

            Divider()
                .opacity(0.4)

            // Form Body
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // URL Input Field
                    VStack(alignment: .leading, spacing: 6) {
                        Text("MEDIA OR STREAM URL")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.secondary)

                        HStack {
                            Image(systemName: "link")
                                .foregroundColor(.secondary)
                                .font(.system(size: 12))
                            TextField("Paste YouTube, TikTok, Vimeo, or direct video/file URL...", text: $vm.urlString)
                                .textFieldStyle(.plain)
                                .font(.system(size: 12))
                                .onChange(of: vm.urlString) { newValue in
                                    if let url = URL(string: newValue), vm.filename.isEmpty {
                                        vm.filename = url.lastPathComponent
                                    }
                                }
                            if !vm.urlString.isEmpty {
                                Button(action: { vm.urlString = "" }) {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundColor(.secondary)
                                        .font(.system(size: 12))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(10)
                        .background(Color(NSColor.controlBackgroundColor).opacity(0.6))
                        .cornerRadius(8)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.white.opacity(0.12), lineWidth: 1)
                        )
                    }

                    // Format & Audio Extraction Preset Picker
                    VStack(alignment: .leading, spacing: 6) {
                        Text("FORMAT & CONVERSION PRESET")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.secondary)

                        Picker("", selection: $vm.selectedPreset) {
                            ForEach(DownloadPreset.allCases) { preset in
                                Text(preset.rawValue).tag(preset)
                            }
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                    }

                    // Custom File Name
                    VStack(alignment: .leading, spacing: 6) {
                        Text("CUSTOM FILE NAME (OPTIONAL)")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.secondary)

                        TextField("Auto-detect from page title or media headers", text: $vm.filename)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(size: 12))
                    }

                    // Save Location
                    VStack(alignment: .leading, spacing: 6) {
                        Text("SAVE LOCATION")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.secondary)

                        HStack(spacing: 8) {
                            TextField("Destination folder", text: $vm.destinationFolder)
                                .textFieldStyle(.roundedBorder)
                                .font(.system(size: 12))

                            Button("Browse...") {
                                vm.selectFolder()
                            }
                            .controlSize(.regular)
                        }
                    }

                    // Options: Parallel Connections & Auto-Start
                    HStack(spacing: 24) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("ACCELERATION CHUNKS")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(.secondary)

                            Picker("", selection: $vm.connections) {
                                Text("1 Chunk (Single Stream)").tag(1)
                                Text("4 Chunks").tag(4)
                                Text("8 Chunks (IDM Turbo Default)").tag(8)
                                Text("16 Chunks (Hyper Speed)").tag(16)
                                Text("32 Chunks (Max Throughput)").tag(32)
                            }
                            .pickerStyle(.menu)
                            .frame(width: 220)
                        }

                        Spacer()

                        VStack(alignment: .trailing, spacing: 6) {
                            Text("QUEUE BEHAVIOR")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(.secondary)

                            Toggle("Start immediately", isOn: $vm.autoStart)
                                .toggleStyle(.switch)
                                .font(.system(size: 12))
                        }
                    }

                    if let err = vm.errorMessage {
                        HStack(spacing: 6) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(.red)
                                .font(.system(size: 12))
                            Text(err)
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(.red)
                        }
                        .padding(8)
                        .background(Color.red.opacity(0.1))
                        .cornerRadius(6)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 16)
            }

            Divider()
                .opacity(0.4)

            // Action Buttons
            HStack {
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                Button(action: {
                    vm.submit {
                        dismiss()
                    }
                }) {
                    HStack(spacing: 6) {
                        Image(systemName: "bolt.fill")
                        Text("Start Download")
                    }
                    .padding(.horizontal, 10)
                }
                .buttonStyle(.borderedProminent)
                .tint(.blue)
                .keyboardShortcut(.defaultAction)
                .disabled(vm.urlString.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
        }
        .frame(width: 530, height: 480)
        .background(.ultraThinMaterial)
    }
}
