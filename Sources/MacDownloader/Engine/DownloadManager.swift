import Foundation
import Combine

@MainActor
public class DownloadManager: ObservableObject {
    public static let shared = DownloadManager()

    @Published public var items: [DownloadItem] = []
    @Published public var selectedCategoryID: DownloadCategory = .all
    @Published public var searchText: String = ""
    @Published public var maxConcurrentDownloads: Int = 3
    @Published public var defaultConnections: Int = 8
    @Published public var defaultDownloadFolder: String

    // UI Presentation State
    @Published public var showingAddSheet: Bool = false
    @Published public var showingSettingsSheet: Bool = false
    @Published public var selectedDetailItem: DownloadItem? = nil

    private var downloaders: [UUID: SegmentedDownloader] = [:]
    private let storageURL: URL

    public init() {
        let fileManager = FileManager.default
        let downloads = fileManager.urls(for: .downloadsDirectory, in: .userDomainMask).first?.path ?? "/tmp"
        self.defaultDownloadFolder = downloads

        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("MacDownloader")
        try? fileManager.createDirectory(at: appSupport, withIntermediateDirectories: true)
        self.storageURL = appSupport.appendingPathComponent("downloads.json")

        loadPersistedItems()
    }

    public var filteredItems: [DownloadItem] {
        items.filter { item in
            let matchesCategory: Bool
            switch selectedCategoryID {
            case .all:
                matchesCategory = true
            case .downloading:
                matchesCategory = (item.status == .downloading)
            case .paused:
                matchesCategory = (item.status == .paused)
            case .completed:
                matchesCategory = (item.status == .completed)
            case .video:
                matchesCategory = (item.category == .video)
            case .audio:
                matchesCategory = (item.category == .audio)
            case .compressed:
                matchesCategory = (item.category == .compressed)
            case .documents:
                matchesCategory = (item.category == .documents)
            case .other:
                matchesCategory = (item.category == .other)
            }

            if !matchesCategory { return false }
            if searchText.isEmpty { return true }
            return item.filename.localizedCaseInsensitiveContains(searchText) ||
                   item.url.absoluteString.localizedCaseInsensitiveContains(searchText)
        }
    }

    public var totalSpeed: Double {
        items.filter { $0.status == .downloading }.reduce(0) { $0 + $1.speed }
    }

    public var formattedTotalSpeed: String {
        guard totalSpeed > 0 else { return "0 B/s" }
        return ByteCountFormatter.string(fromByteCount: Int64(totalSpeed), countStyle: .binary) + "/s"
    }

    public var activeDownloadsCount: Int {
        items.filter { $0.status == .downloading }.count
    }

    // MARK: - Download Operations

    @discardableResult
    public func addDownload(
        url: URL,
        filename: String? = nil,
        destinationFolder: String? = nil,
        connections: Int? = nil,
        referer: String? = nil,
        userAgent: String? = nil,
        cookie: String? = nil,
        quality: String? = nil,
        audioUrl: URL? = nil,
        resolutionDetails: String? = nil,
        autoStart: Bool = true
    ) -> DownloadItem {
        let name = filename?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false ? filename! : (url.lastPathComponent.isEmpty ? "download_\(Int(Date().timeIntervalSince1970))" : url.lastPathComponent)
        let folder = destinationFolder ?? defaultDownloadFolder
        let conn = connections ?? defaultConnections

        let item = DownloadItem(
            url: url,
            filename: name,
            destinationFolder: folder,
            connectionCount: conn,
            referer: referer,
            userAgent: userAgent,
            cookie: cookie,
            quality: quality,
            audioUrl: audioUrl,
            resolutionDetails: resolutionDetails
        )

        items.insert(item, at: 0)
        persistItems()

        if autoStart {
            startDownload(id: item.id)
        }

        return item
    }

    public func startDownload(id: UUID) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        var item = items[index]

        // Check concurrency cap
        if activeDownloadsCount >= maxConcurrentDownloads && item.status != .downloading {
            items[index].status = .queued
            persistItems()
            return
        }

        items[index].status = .downloading
        items[index].errorMessage = nil
        item = items[index]

        let downloader = SegmentedDownloader(
            item: item,
            onProgress: { [weak self] downloaded, segments, speed in
                Task { @MainActor [weak self] in
                    self?.updateProgress(id: id, downloaded: downloaded, segments: segments, speed: speed)
                }
            },
            onCompletion: { [weak self] result in
                Task { @MainActor [weak self] in
                    self?.handleCompletion(id: id, result: result)
                }
            }
        )

        downloaders[id] = downloader

        Task {
            await downloader.start()
        }
    }

    public func pauseDownload(id: UUID) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        items[index].status = .paused
        items[index].speed = 0
        items[index].eta = nil

        if let downloader = downloaders[id] {
            Task {
                await downloader.pause()
            }
            downloaders.removeValue(forKey: id)
        }

        persistItems()
        processNextInQueue()
    }

    public func pauseAll() {
        for item in items where item.status == .downloading {
            pauseDownload(id: item.id)
        }
    }

    public func resumeAll() {
        for item in items where item.status == .paused || item.status == .queued {
            startDownload(id: item.id)
        }
    }

    public func removeDownload(id: UUID, deleteFile: Bool = false) {
        pauseDownload(id: id)
        if let index = items.firstIndex(where: { $0.id == id }) {
            let item = items[index]
            if deleteFile {
                try? FileManager.default.removeItem(at: item.destinationFileURL)
            }
            items.remove(at: index)
            persistItems()
        }
    }

    // MARK: - Internal Progress and Completion Handlers

    private func updateProgress(id: UUID, downloaded: Int64, segments: [DownloadSegment], speed: Double) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        items[index].downloadedBytes = downloaded
        items[index].segments = segments
        items[index].speed = speed

        if items[index].fileSize <= 0, let first = segments.first, first.endByte > 0 {
            items[index].fileSize = first.endByte
        }

        let total = items[index].fileSize
        if total > 0 && speed > 0 {
            let remaining = total - downloaded
            items[index].eta = remaining > 0 ? Double(remaining) / speed : 0
        } else {
            items[index].eta = nil
        }
    }

    private func handleCompletion(id: UUID, result: Result<URL, Error>) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        downloaders.removeValue(forKey: id)

        switch result {
        case .success(let finalUrl):
            items[index].status = .completed
            items[index].speed = 0
            items[index].eta = 0
            if let attrs = try? FileManager.default.attributesOfItem(atPath: finalUrl.path),
               let size = attrs[.size] as? Int64, size > 0 {
                items[index].fileSize = size
                items[index].downloadedBytes = size
            } else if items[index].fileSize > 0 {
                items[index].downloadedBytes = items[index].fileSize
            }
        case .failure(let error):
            items[index].status = .failed
            items[index].speed = 0
            items[index].eta = nil
            items[index].errorMessage = error.localizedDescription
        }

        persistItems()
        processNextInQueue()
    }

    private func processNextInQueue() {
        guard activeDownloadsCount < maxConcurrentDownloads else { return }
        if let nextQueued = items.first(where: { $0.status == .queued }) {
            startDownload(id: nextQueued.id)
        }
    }

    // MARK: - Persistence

    private func persistItems() {
        do {
            let data = try JSONEncoder().encode(items)
            try data.write(to: storageURL)
        } catch {
            print("Failed to save downloads: \(error)")
        }
    }

    private func loadPersistedItems() {
        guard FileManager.default.fileExists(atPath: storageURL.path) else { return }
        do {
            let data = try Data(contentsOf: storageURL)
            var loaded = try JSONDecoder().decode([DownloadItem].self, from: data)
            // Reset downloading items to paused on app launch
            for i in 0..<loaded.count {
                if loaded[i].status == .downloading {
                    loaded[i].status = .paused
                    loaded[i].speed = 0
                }
            }
            self.items = loaded
        } catch {
            print("Failed to load downloads: \(error)")
        }
    }
}
