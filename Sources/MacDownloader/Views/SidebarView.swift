import SwiftUI

public struct SidebarView: View {
    @ObservedObject var manager = DownloadManager.shared

    public var body: some View {
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
        .frame(minWidth: 180)
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
}
