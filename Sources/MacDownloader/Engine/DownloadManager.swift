import Foundation
import Combine
import AppKit
import Network

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
    @Published public var showingAboutSheet: Bool = false
    @Published public var selectedDetailItem: DownloadItem? = nil

    // Extraction Engine State
    @Published public var engineVersion: String = "2026.10.26"
    @Published public var isUpdatingEngine: Bool = false
    @Published public var engineUpdateMessage: String? = nil

    // Smart Sleep & Network State
    @Published public var isNetworkConnected: Bool = true
    private var preSleepActiveIDs: Set<UUID> = []
    private let pathMonitor = NWPathMonitor()
    private let monitorQueue = DispatchQueue(label: "com.fetchdeck.networkmonitor")

    private var downloaders: [UUID: SegmentedDownloader] = [:]
    private let storageURL: URL

    public init() {
        let fileManager = FileManager.default
        let downloads = fileManager.urls(for: .downloadsDirectory, in: .userDomainMask).first?.path ?? "/tmp"
        self.defaultDownloadFolder = downloads

        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("FetchDeck")
        try? fileManager.createDirectory(at: appSupport, withIntermediateDirectories: true)
        self.storageURL = appSupport.appendingPathComponent("downloads.json")

        loadPersistedItems()
        self.engineVersion = YouTubeEngine.getEngineVersion()

        setupSleepWakeHandlers()
        setupNetworkMonitor()
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

    // MARK: - Smart Sleep & Network Reconnection

    private func setupSleepWakeHandlers() {
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.willSleepNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.handleSystemSleep()
            }
        }

        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.handleSystemWake()
            }
        }
    }

    private func handleSystemSleep() {
        preSleepActiveIDs = Set(items.filter { $0.status == .downloading }.map { $0.id })
        for id in preSleepActiveIDs {
            pauseDownload(id: id)
        }
    }

    private func handleSystemWake() {
        // Wait 3 seconds for network adapters and WiFi to re-negotiate
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) { [weak self] in
            guard let self = self else { return }
            for id in self.preSleepActiveIDs {
                if let item = self.items.first(where: { $0.id == id }), item.status == .paused {
                    self.startDownload(id: id)
                }
            }
            self.preSleepActiveIDs.removeAll()
        }
    }

    private func setupNetworkMonitor() {
        pathMonitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                let wasConnected = self.isNetworkConnected
                self.isNetworkConnected = (path.status == .satisfied)
                if !wasConnected && self.isNetworkConnected {
                    self.resumeInterruptedDownloads()
                }
            }
        }
        pathMonitor.start(queue: monitorQueue)
    }

    private func resumeInterruptedDownloads() {
        for item in items where item.status == .failed {
            startDownload(id: item.id)
        }
    }

    // MARK: - Extraction Engine Self-Updater

    public func updateExtractionEngine() {
        guard !isUpdatingEngine else { return }
        isUpdatingEngine = true
        engineUpdateMessage = "Checking and downloading latest engine..."

        Task.detached {
            let (success, message) = await YouTubeEngine.updateEngine()
            let newVersion = YouTubeEngine.getEngineVersion()
            await MainActor.run {
                self.isUpdatingEngine = false
                self.engineVersion = newVersion
                self.engineUpdateMessage = success ? "✓ Up-to-date (\(newVersion))" : "Update notice: \(message)"
            }
        }
    }

    // MARK: - Audio Extraction Preset

    public func extractAudioAsMP3(for itemID: UUID) {
        guard let item = items.first(where: { $0.id == itemID }), item.status == .completed else { return }
        guard let ffmpeg = YouTubeEngine.findBinary(named: "ffmpeg") else { return }

        let sourceFile = item.destinationFileURL
        let mp3File = sourceFile.deletingPathExtension().appendingPathExtension("mp3")

        let process = Process()
        process.executableURL = URL(fileURLWithPath: ffmpeg)
        process.arguments = [
            "-y",
            "-i", sourceFile.path,
            "-vn",
            "-acodec", "libmp3lame",
            "-q:a", "0",
            mp3File.path
        ]

        Task.detached {
            try? process.run()
            process.waitUntilExit()
            if process.terminationStatus == 0 {
                let size = (try? FileManager.default.attributesOfItem(atPath: mp3File.path)[.size] as? Int64) ?? -1
                await MainActor.run {
                    let newItem = self.addDownload(
                        url: mp3File,
                        filename: mp3File.lastPathComponent,
                        quality: "MP3 320k",
                        resolutionDetails: "High Quality MP3",
                        category: .audio,
                        autoStart: false
                    )
                    if let idx = self.items.firstIndex(where: { $0.id == newItem.id }) {
                        self.items[idx].status = .completed
                        self.items[idx].fileSize = size
                        self.items[idx].downloadedBytes = size
                        self.persistItems()
                    }
                }
            }
        }
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
        thumbnailURL: URL? = nil,
        duration: String? = nil,
        category: DownloadCategory = .other,
        autoStart: Bool = true
    ) -> DownloadItem {
        let name = filename?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            ? filename!
            : (url.lastPathComponent.isEmpty ? "download_\(Int(Date().timeIntervalSince1970))" : url.lastPathComponent)
        let folder = destinationFolder ?? defaultDownloadFolder
        let conn = connections ?? defaultConnections

        // Smart thumbnail auto-detection for YouTube if missing
        var finalThumb = thumbnailURL
        if finalThumb == nil {
            if let videoId = YouTubeResolver.shared.extractVideoId(from: url.absoluteString) ?? (referer != nil ? YouTubeResolver.shared.extractVideoId(from: referer!) : nil) {
                finalThumb = URL(string: "https://img.youtube.com/vi/\(videoId)/hqdefault.jpg")
            }
        }

        let item = DownloadItem(
            url: url,
            filename: name,
            destinationFolder: folder,
            connectionCount: conn,
            category: category,
            referer: referer,
            userAgent: userAgent,
            cookie: cookie,
            quality: quality,
            audioUrl: audioUrl,
            resolutionDetails: resolutionDetails,
            thumbnailURL: finalThumb,
            duration: duration
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
            // Trigger native notification
            triggerNotification(for: items[index])
        case .failure(let error):
            items[index].status = .failed
            items[index].speed = 0
            items[index].eta = nil
            items[index].errorMessage = error.localizedDescription
        }

        persistItems()
        processNextInQueue()
    }

    private func triggerNotification(for item: DownloadItem) {
        let notification = NSUserNotification()
        notification.title = "Download Complete"
        notification.subtitle = item.filename
        notification.informativeText = "Ready in your Downloads folder."
        notification.soundName = NSUserNotificationDefaultSoundName
        NSUserNotificationCenter.default.deliver(notification)
    }

    private func processNextInQueue() {
        guard activeDownloadsCount < maxConcurrentDownloads else { return }
        if let nextQueued = items.first(where: { $0.status == .queued }) {
            startDownload(id: nextQueued.id)
        }
    }

    // MARK: - State Persistence

    private func loadPersistedItems() {
        guard FileManager.default.fileExists(atPath: storageURL.path),
              let data = try? Data(contentsOf: storageURL),
              let loaded = try? JSONDecoder().decode([DownloadItem].self, from: data) else {
            return
        }
        self.items = loaded.map { var it = $0; if it.status == .downloading { it.status = .paused }; return it }
    }

    private func persistItems() {
        if let data = try? JSONEncoder().encode(items) {
            try? data.write(to: storageURL, options: .atomic)
        }
    }
}
