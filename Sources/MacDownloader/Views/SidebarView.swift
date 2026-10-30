import SwiftUI
import AppKit

public struct SidebarView: View {
    @ObservedObject var manager = DownloadManager.shared

    public var body: some View {
        VStack(spacing: 0) {
            // Header: FETCHDECK & Glass Icon
            HStack(spacing: 9) {
                if let img = loadMiniIcon() {
                    Image(nsImage: img)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 28, height: 28)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .shadow(color: Color.blue.opacity(0.3), radius: 4)
                } else {
                    Image(systemName: "tray.and.arrow.down.fill")
                        .font(.system(size: 20))
                        .foregroundColor(.blue)
                }

                VStack(alignment: .leading, spacing: 1) {
                    Text("FETCHDECK")
                        .font(.system(size: 13, weight: .black, design: .rounded))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [.primary, .blue],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                    Text("Your downloads, all in one place.")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(Color(NSColor.controlBackgroundColor).opacity(0.3))

            Divider()

            List(selection: $manager.selectedCategoryID) {
                Section("Status") {
                    categoryRow(.all)
                    categoryRow(.downloading)
                    categoryRow(.paused)
                    categoryRow(.completed)
                }

                Section("Categories") {
                    categoryRow(.video)
                    categoryRow(.audio)
                    categoryRow(.compressed)
                    categoryRow(.documents)
                    categoryRow(.other)
                }
            }
            .listStyle(.sidebar)

            Divider()

            // Footer: About, Network & Engine Version
            HStack(spacing: 8) {
                Button {
                    manager.showingAboutSheet = true
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "info.circle")
                            .font(.system(size: 11))
                        Text("About")
                            .font(.system(size: 11, weight: .medium))
                    }
                }
                .buttonStyle(.plain)
                .foregroundColor(.secondary)

                Spacer()

                HStack(spacing: 4) {
                    Circle()
                        .fill(manager.isNetworkConnected ? Color.green : Color.red)
                        .frame(width: 6, height: 6)
                    Text("v\(manager.engineVersion)")
                        .font(.system(size: 9.5, design: .monospaced))
                        .foregroundColor(.secondary)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(Color(NSColor.controlBackgroundColor).opacity(0.2))
        }
        .frame(minWidth: 195)
    }

    private func categoryRow(_ category: DownloadCategory) -> some View {
        NavigationLink(value: category) {
            Label {
                HStack {
                    Text(category.rawValue)
                    Spacer()
                    let count = count(for: category)
                    if count > 0 {
                        Text("\(count)")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 1)
                            .background(Color.primary.opacity(0.08))
                            .clipShape(Capsule())
                    }
                }
            } icon: {
                Image(systemName: category.systemIcon)
                    .foregroundColor(color(for: category))
            }
        }
    }

    private func count(for category: DownloadCategory) -> Int {
        switch category {
        case .all:
            return manager.items.count
        case .downloading:
            return manager.items.filter { $0.status == .downloading }.count
        case .paused:
            return manager.items.filter { $0.status == .paused }.count
        case .completed:
            return manager.items.filter { $0.status == .completed }.count
        case .video:
            return manager.items.filter { $0.category == .video }.count
        case .audio:
            return manager.items.filter { $0.category == .audio }.count
        case .compressed:
            return manager.items.filter { $0.category == .compressed }.count
        case .documents:
            return manager.items.filter { $0.category == .documents }.count
        case .other:
            return manager.items.filter { $0.category == .other }.count
        }
    }

    private func color(for category: DownloadCategory) -> Color {
        switch category {
        case .all: return .primary
        case .downloading: return .blue
        case .paused: return .orange
        case .completed: return .green
        case .video: return .purple
        case .audio: return .pink
        case .compressed: return .orange
        case .documents: return .blue
        case .other: return .gray
        }
    }

    private func loadMiniIcon() -> NSImage? {
        let path = "/Users/abishekwork/.gemini/antigravity/scratch/MacDownloader/Sources/MacDownloader/Resources/AppIcon512.png"
        return NSImage(contentsOfFile: path)
    }
}
