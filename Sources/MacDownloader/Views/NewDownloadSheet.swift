import SwiftUI
import AppKit

public struct NewDownloadSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var vm: NewDownloadViewModel

    public init(viewModel: NewDownloadViewModel = NewDownloadViewModel()) {
        self.vm = viewModel
    }

    public var body: some View {
        VStack(spacing: 20) {
            // Header
            HStack {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 24))
                    .foregroundColor(.blue)
                VStack(alignment: .leading) {
                    Text("Add New Download")
                        .font(.headline)
                    Text("Enter the direct URL or stream link to accelerate")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                Spacer()
            }

            Divider()

            // Fields
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Download URL:")
                        .font(.system(size: 12, weight: .semibold))
                    TextField("https://example.com/file.zip", text: $vm.urlString)
                        .textFieldStyle(.roundedBorder)
                        .onChange(of: vm.urlString) { newValue in
                            if let url = URL(string: newValue), vm.filename.isEmpty {
                                vm.filename = url.lastPathComponent
                            }
                        }
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("File Name (Optional):")
                        .font(.system(size: 12, weight: .semibold))
                    TextField("Auto-detect from server or URL", text: $vm.filename)
                        .textFieldStyle(.roundedBorder)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Save Directory:")
                        .font(.system(size: 12, weight: .semibold))
                    HStack {
                        TextField("Folder", text: $vm.destinationFolder)
                            .textFieldStyle(.roundedBorder)
                        Button("Browse...") {
                            vm.selectFolder()
                        }
                    }
                }

                HStack(spacing: 20) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Parallel Connections:")
                            .font(.system(size: 12, weight: .semibold))
                        Picker("", selection: $vm.connections) {
                            Text("1 (Single)").tag(1)
                            Text("2 Chunks").tag(2)
                            Text("4 Chunks").tag(4)
                            Text("8 Chunks (IDM Default)").tag(8)
                            Text("16 Chunks (Fast)").tag(16)
                            Text("32 Chunks (Max)").tag(32)
                        }
                        .pickerStyle(.menu)
                        .frame(width: 180)
                    }

                    Spacer()

                    Toggle("Start immediately", isOn: $vm.autoStart)
                        .padding(.top, 16)
                }
            }

            if let err = vm.errorMessage {
                Text(err)
                    .font(.caption)
                    .foregroundColor(.red)
            }

            Spacer()

            Divider()

            // Action Buttons
            HStack {
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                Button("Start Download") {
                    vm.submit {
                        dismiss()
                    }
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(vm.urlString.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(24)
        .frame(width: 520, height: 420)
    }
}
