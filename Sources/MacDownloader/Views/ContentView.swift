import SwiftUI

public struct ContentView: View {
    @ObservedObject var manager = DownloadManager.shared

    public var body: some View {
        NavigationSplitView {
            SidebarView()
        } detail: {
            VStack(spacing: 0) {
                // Main List Area
                if manager.filteredItems.isEmpty {
                    emptyStateView
                } else {
                    ScrollView {
                        LazyVStack(spacing: 8) {
                            ForEach(manager.filteredItems) { item in
                                DownloadRowView(item: item)
                            }
                        }
                        .padding(12)
                    }
                }

                Divider()

                // Bottom Status Bar
                bottomStatusBar
            }
        }
        .frame(minWidth: 800, minHeight: 500)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    manager.showingAddSheet = true
                } label: {
                    Label("Add URL", systemImage: "plus")
                }
                .help("Add new download URL")

                Button {
                    manager.resumeAll()
                } label: {
                    Label("Resume All", systemImage: "play.fill")
                }
                .help("Resume all downloads")

                Button {
                    manager.pauseAll()
                } label: {
                    Label("Pause All", systemImage: "pause.fill")
                }
                .help("Pause all downloads")

                Button {
                    manager.showingSettingsSheet = true
                } label: {
                    Label("Settings", systemImage: "gearshape")
                }
                .help("Preferences")
            }
        }
        .searchable(text: $manager.searchText, prompt: "Search downloads...")
        .sheet(isPresented: $manager.showingAddSheet) {
            NewDownloadSheet()
        }
        .sheet(isPresented: $manager.showingSettingsSheet) {
            SettingsView()
        }
        .sheet(isPresented: $manager.showingAboutSheet) {
            AboutView()
        }
        .sheet(item: $manager.selectedDetailItem) { item in
            DownloadDetailSheet(item: item)
        }
    }

    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "arrow.down.circle")
                .font(.system(size: 54))
                .foregroundColor(.secondary.opacity(0.4))

            Text("No Downloads in \"\(manager.selectedCategoryID.rawValue)\"")
                .font(.headline)
                .foregroundColor(.secondary)

            Text("Click \"Add URL\" or use the Chrome Extension to capture video and audio streams.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 380)

            Button {
                manager.showingAddSheet = true
            } label: {
                Label("Add Download", systemImage: "plus")
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var bottomStatusBar: some View {
        HStack(spacing: 16) {
            HStack(spacing: 6) {
                Circle()
                    .fill(Color.green)
                    .frame(width: 7, height: 7)
                Text("Chrome Bridge: 127.0.0.1:45678")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }

            Spacer()

            Text("\(manager.items.count) tasks")
                .font(.system(size: 11))
                .foregroundColor(.secondary)

            if manager.activeDownloadsCount > 0 {
                Text("•")
                    .foregroundColor(.secondary)

                Text("\(manager.activeDownloadsCount) active")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.blue)

                Text("•")
                    .foregroundColor(.secondary)

                HStack(spacing: 4) {
                    Image(systemName: "bolt.fill")
                        .font(.system(size: 10))
                        .foregroundColor(.yellow)
                    Text(manager.formattedTotalSpeed)
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color(NSColor.windowBackgroundColor))
    }
}
