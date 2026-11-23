import Foundation

public actor SegmentedDownloader {
    public let itemID: UUID
    private let url: URL
    private let destinationFileURL: URL
    private let connectionCount: Int
    private let referer: String?
    private let userAgent: String?
    private let cookie: String?
    private let quality: String?
    private let audioUrl: URL?

    private var isCancelled = false
    private var isPaused = false
    private var activeTasks: [URLSessionDataTask] = []
    private var ffmpegProcess: Process?
    private var ytProcess: Process?
    private var session: URLSession!

    public typealias ProgressCallback = @Sendable (Int64, [DownloadSegment], Double) -> Void
    public typealias CompletionCallback = @Sendable (Result<URL, Error>) -> Void

    private var onProgress: ProgressCallback?
    private var onCompletion: CompletionCallback?

    private var totalBytes: Int64 = -1
    private var segments: [DownloadSegment] = []
    private var lastSpeedCalcTime: Date = Date()
    private var lastBytesCount: Int64 = 0
    private var currentSpeed: Double = 0

    public init(
        item: DownloadItem,
        onProgress: ProgressCallback? = nil,
        onCompletion: CompletionCallback? = nil
    ) {
        self.itemID = item.id
        self.url = item.url
        self.destinationFileURL = item.destinationFileURL
        self.connectionCount = max(1, item.connectionCount)
        self.referer = item.referer
        self.userAgent = item.userAgent
        self.cookie = item.cookie
        self.quality = item.quality
        self.audioUrl = item.audioUrl
        self.segments = item.segments
        self.totalBytes = item.fileSize
        self.onProgress = onProgress
        self.onCompletion = onCompletion

        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 3600
        self.session = URLSession(configuration: config)
    }

    public func start() async {
        isCancelled = false
        isPaused = false
        lastSpeedCalcTime = Date()
        lastBytesCount = segments.reduce(0) { $0 + $1.downloadedBytes }

        // Special handling 1: YouTube video stream (use yt-dlp backend with Node challenge solver & FFmpeg)
        if isYouTubeDownload() {
            await downloadYouTubeStream()
            return
        }

        // Special handling 2: Separate audio/video tracks
        if let audioUrl = audioUrl, let ffmpeg = findFFmpeg() {
            await downloadWithAudioMux(videoURL: url, audioURL: audioUrl, ffmpegPath: ffmpeg)
            return
        }

        // Special handling 3: HLS (.m3u8) video playlists
        if isHLSStream(), let ffmpeg = findFFmpeg() {
            await downloadHLSWithFFmpeg(ffmpegPath: ffmpeg)
            return
        }

        await executeNativeDownload()
    }

    private func executeNativeDownload() async {
        do {
            let (contentLength, supportsRanges, finalURL) = try await probeServer()
            self.totalBytes = contentLength

            if isCancelled || isPaused { return }

            let isGoogleVideo = finalURL.host?.contains("googlevideo.com") == true

            if segments.isEmpty {
                if !isGoogleVideo && supportsRanges && contentLength > 0 && connectionCount > 1 {
                    self.segments = createSegments(totalBytes: contentLength, count: connectionCount)
                } else {
                    self.segments = [DownloadSegment(id: 0, startByte: 0, endByte: contentLength > 0 ? (contentLength - 1) : -1)]
                }
            }

            try await withThrowingTaskGroup(of: (Int, Int64).self) { group in
                for index in 0..<self.segments.count {
                    let segment = self.segments[index]
                    if segment.status == .completed {
                        continue
                    }

                    group.addTask { [self] in
                        try await self.downloadSegment(index: index, targetURL: finalURL)
                    }
                }

                while let _ = try await group.next() {
                    if self.isCancelled || self.isPaused {
                        group.cancelAll()
                        return
                    }
                }
            }

            if isCancelled || isPaused { return }

            try mergeSegments()

            if let attrs = try? FileManager.default.attributesOfItem(atPath: destinationFileURL.path),
               let fileSize = attrs[.size] as? Int64 {
                if fileSize <= 128 && (self.totalBytes > 1024 || self.totalBytes == -1) {
                    throw NSError(
                        domain: "MacDownloader",
                        code: 400,
                        userInfo: [NSLocalizedDescriptionKey: "Stream truncated to \(fileSize) bytes by YouTube. Stream URL was restricted."]
                    )
                }
            }

            onCompletion?(.success(destinationFileURL))
        } catch {
            if !isCancelled && !isPaused {
                onCompletion?(.failure(error))
            }
        }
    }

    public func pause() {
        isPaused = true
        for task in activeTasks {
            task.cancel()
        }
        activeTasks.removeAll()
        ffmpegProcess?.terminate()
        ffmpegProcess = nil
        ytProcess?.terminate()
        ytProcess = nil
    }

    public func cancel() {
        isCancelled = true
        for task in activeTasks {
            task.cancel()
        }
        activeTasks.removeAll()
        ffmpegProcess?.terminate()
        ffmpegProcess = nil
        ytProcess?.terminate()
        ytProcess = nil
        cleanUpTemporaryFiles()
    }

    // MARK: - YouTube Dedicated Download Engine

    private func isYouTubeDownload() -> Bool {
        if let host = url.host?.lowercased() {
            if host.contains("youtube.com") || host.contains("youtu.be") || host.contains("googlevideo.com") {
                return true
            }
        }
        if let ref = referer?.lowercased() {
            if ref.contains("youtube.com") || ref.contains("youtu.be") {
                return true
            }
        }
        return false
    }

    private func downloadYouTubeStream() async {
        guard let python = YouTubeEngine.findBinary(named: "python3"),
              let ytdlp = YouTubeEngine.findBinary(named: "yt-dlp"),
              let ffmpeg = YouTubeEngine.findBinary(named: "ffmpeg") else {
            await executeNativeDownload()
            return
        }

        var targetUrl = url.absoluteString
        if url.host?.contains("googlevideo.com") == true {
            if let ref = referer, (ref.contains("youtube.com") || ref.contains("youtu.be")) {
                targetUrl = ref
            }
        }

        let q = (quality ?? "").lowercased()
        let isAudioOnly = q.contains("audio") || q.contains("mp3") || q.contains("m4a")

        let formatSpec: String
        if isAudioOnly {
            formatSpec = "bestaudio/best"
        } else if q.contains("2160") || q.contains("4k") {
            formatSpec = "bestvideo[height<=2160]+bestaudio/best[height<=2160]/best"
        } else if q.contains("1440") || q.contains("2k") {
            formatSpec = "bestvideo[height<=1440]+bestaudio/best[height<=1440]/best"
        } else if q.contains("1080") {
            formatSpec = "bestvideo[height<=1080]+bestaudio/best[height<=1080]/best"
        } else if q.contains("720") {
            formatSpec = "bestvideo[height<=720]+bestaudio/best[height<=720]/best"
        } else if q.contains("480") {
            formatSpec = "bestvideo[height<=480]+bestaudio/best[height<=480]/best"
        } else if q.contains("360") {
            formatSpec = "18/bestvideo[height<=360]+bestaudio/best[height<=360]/best"
        } else {
            let digits = q.replacingOccurrences(of: "[^0-9]", with: "", options: .regularExpression)
            if let h = Int(digits), h > 0 {
                formatSpec = "bestvideo[height<=\(h)]+bestaudio/best[height<=\(h)]/best"
            } else {
                formatSpec = "bestvideo+bestaudio/best"
            }
        }

        let parentDir = destinationFileURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: parentDir, withIntermediateDirectories: true)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: python)

        var args = [
            ytdlp,
            "-f", formatSpec,
            "--ffmpeg-location", ffmpeg,
            "--no-playlist",
            "--no-warnings",
            "--newline",
            "-o", destinationFileURL.path
        ]

        if let node = YouTubeEngine.findBinary(named: "node") {
            args.append(contentsOf: ["--js-runtimes", "node:\(node)"])
        }

        if isAudioOnly && destinationFileURL.pathExtension.lowercased() == "mp3" {
            args.append(contentsOf: ["-x", "--audio-format", "mp3"])
        } else {
            args.append(contentsOf: ["--merge-output-format", "mp4"])
        }

        if let ck = cookie, !ck.isEmpty {
            args.append(contentsOf: ["--add-header", "Cookie: \(ck)"])
        }

        args.append(targetUrl)
        process.arguments = args

        var env = ProcessInfo.processInfo.environment
        env["PATH"] = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/Users/abishekwork/.nvm/versions/node/v24.21.0/bin"
        process.environment = env

        let stdoutPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stdoutPipe

        self.ytProcess = process
        self.segments = [DownloadSegment(id: 0, startByte: 0, endByte: totalBytes > 0 ? totalBytes : -1, downloadedBytes: 0, status: .downloading)]
        notifyProgress()

        stdoutPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
            Task { [weak self] in
                await self?.parseYtDlpOutput(text)
            }
        }

        do {
            try process.run()
            process.waitUntilExit()
            stdoutPipe.fileHandleForReading.readabilityHandler = nil

            if isCancelled || isPaused { return }

            if process.terminationStatus == 0 {
                let finalPath = destinationFileURL.path
                if FileManager.default.fileExists(atPath: finalPath) {
                    if let attrs = try? FileManager.default.attributesOfItem(atPath: finalPath),
                       let size = attrs[.size] as? Int64, size > 1024 {
                        self.totalBytes = size
                        self.segments = [DownloadSegment(id: 0, startByte: 0, endByte: size, downloadedBytes: size, status: .completed)]
                        notifyProgress()
                        onCompletion?(.success(destinationFileURL))
                        return
                    }
                }
            }

            throw NSError(
                domain: "MacDownloader",
                code: Int(process.terminationStatus),
                userInfo: [NSLocalizedDescriptionKey: "YouTube download failed (exit code \(process.terminationStatus))."]
            )
        } catch {
            stdoutPipe.fileHandleForReading.readabilityHandler = nil
            if !isCancelled && !isPaused {
                onCompletion?(.failure(error))
            }
        }
    }

    private func parseYtDlpOutput(_ text: String) {
        let lines = text.components(separatedBy: "\n")
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed.hasPrefix("[download]") else { continue }

            if let pctRange = trimmed.range(of: "([0-9.]+)%", options: .regularExpression) {
                let pctStr = String(trimmed[pctRange]).replacingOccurrences(of: "%", with: "")
                if let pct = Double(pctStr) {
                    let fraction = pct / 100.0
                    if totalBytes > 0 {
                        let downloaded = Int64(Double(totalBytes) * fraction)
                        if !segments.isEmpty {
                            segments[0].downloadedBytes = downloaded
                        }
                    }
                }
            }

            if let ofRange = trimmed.range(of: "of ~?([0-9.]+)([KMG]iB)", options: .regularExpression) {
                let match = String(trimmed[ofRange])
                let sizeStr = match.replacingOccurrences(of: "of ", with: "").replacingOccurrences(of: "~", with: "")
                if let bytes = parseSizeStringToBytes(sizeStr) {
                    self.totalBytes = bytes
                    if !segments.isEmpty {
                        segments[0].endByte = bytes
                    }
                }
            }

            if let speedRange = trimmed.range(of: "at\\s+([0-9.]+)([KMG]iB/s)", options: .regularExpression) {
                let match = String(trimmed[speedRange])
                let speedPart = match.replacingOccurrences(of: "at ", with: "").replacingOccurrences(of: "/s", with: "")
                if let bytesPerSec = parseSizeStringToBytes(speedPart) {
                    self.currentSpeed = Double(bytesPerSec)
                }
            }

            notifyProgress()
        }
    }

    private func parseSizeStringToBytes(_ str: String) -> Int64? {
        let clean = str.trimmingCharacters(in: .whitespaces)
        if clean.hasSuffix("GiB") {
            let num = Double(clean.replacingOccurrences(of: "GiB", with: "")) ?? 0
            return Int64(num * 1024 * 1024 * 1024)
        } else if clean.hasSuffix("MiB") {
            let num = Double(clean.replacingOccurrences(of: "MiB", with: "")) ?? 0
            return Int64(num * 1024 * 1024)
        } else if clean.hasSuffix("KiB") {
            let num = Double(clean.replacingOccurrences(of: "KiB", with: "")) ?? 0
            return Int64(num * 1024)
        }
        return nil
    }

    // MARK: - Server Probing

    private func probeServer() async throws -> (Int64, Bool, URL) {
        guard let scheme = url.scheme?.lowercased(), (scheme == "http" || scheme == "https") else {
            throw URLError(.unsupportedURL)
        }

        if let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
           let clenStr = components.queryItems?.first(where: { $0.name == "clen" })?.value,
           let clen = Int64(clenStr), clen > 0 {
            return (clen, true, url)
        }

        let isGoogleVideo = url.host?.contains("googlevideo.com") == true
        if isGoogleVideo {
            return (-1, true, url)
        }

        var headRequest = URLRequest(url: url)
        headRequest.httpMethod = "HEAD"
        let isSuno = url.host?.contains("suno.ai") == true || url.host?.contains("suno.com") == true
        if let referer = referer { headRequest.setValue(referer, forHTTPHeaderField: "Referer") }
        if let userAgent = userAgent { headRequest.setValue(userAgent, forHTTPHeaderField: "User-Agent") }
        if let cookie = cookie { headRequest.setValue(cookie, forHTTPHeaderField: "Cookie") }
        if isSuno {
            headRequest.setValue("https://suno.com", forHTTPHeaderField: "Origin")
            if headRequest.value(forHTTPHeaderField: "Referer") == nil {
                headRequest.setValue("https://suno.com/", forHTTPHeaderField: "Referer")
            }
            headRequest.setValue("*/*", forHTTPHeaderField: "Accept")
            headRequest.setValue("identity;q=1, *;q=0", forHTTPHeaderField: "Accept-Encoding")
        }

        if let (_, response) = try? await session.data(for: headRequest),
           let httpResponse = response as? HTTPURLResponse,
           (httpResponse.statusCode == 200 || httpResponse.statusCode == 206) {
            let length = httpResponse.expectedContentLength
            let acceptRanges = httpResponse.allHeaderFields["Accept-Ranges"] as? String ?? httpResponse.allHeaderFields["accept-ranges"] as? String
            let supportsRanges = (acceptRanges?.lowercased() == "bytes")
            let resolvedURL = httpResponse.url ?? url
            return (length, supportsRanges, resolvedURL)
        }

        var rangeRequest = URLRequest(url: url)
        rangeRequest.httpMethod = "GET"
        rangeRequest.setValue("bytes=0-0", forHTTPHeaderField: "Range")
        if let referer = referer { rangeRequest.setValue(referer, forHTTPHeaderField: "Referer") }
        if let userAgent = userAgent { rangeRequest.setValue(userAgent, forHTTPHeaderField: "User-Agent") }
        if let cookie = cookie { rangeRequest.setValue(cookie, forHTTPHeaderField: "Cookie") }
        if isSuno {
            rangeRequest.setValue("https://suno.com", forHTTPHeaderField: "Origin")
            if rangeRequest.value(forHTTPHeaderField: "Referer") == nil {
                rangeRequest.setValue("https://suno.com/", forHTTPHeaderField: "Referer")
            }
            rangeRequest.setValue("*/*", forHTTPHeaderField: "Accept")
            rangeRequest.setValue("identity;q=1, *;q=0", forHTTPHeaderField: "Accept-Encoding")
        }

        if let (_, response) = try? await session.data(for: rangeRequest),
           let httpResponse = response as? HTTPURLResponse {
            if httpResponse.statusCode == 206 {
                var totalLength: Int64 = -1
                if let contentRange = (httpResponse.allHeaderFields["Content-Range"] as? String ?? httpResponse.allHeaderFields["content-range"] as? String) {
                    let parts = contentRange.components(separatedBy: "/")
                    if parts.count == 2, let parsed = Int64(parts[1].trimmingCharacters(in: .whitespaces)) {
                        totalLength = parsed
                    }
                }
                if totalLength <= 0 {
                    totalLength = httpResponse.expectedContentLength
                }
                let resolvedURL = httpResponse.url ?? url
                return (totalLength, true, resolvedURL)
            } else if httpResponse.statusCode == 200 {
                return (httpResponse.expectedContentLength, false, httpResponse.url ?? url)
            }
        }

        return (-1, false, url)
    }

    private func createSegments(totalBytes: Int64, count: Int) -> [DownloadSegment] {
        var result: [DownloadSegment] = []
        let chunkSize = totalBytes / Int64(count)

        for i in 0..<count {
            let start = Int64(i) * chunkSize
            let end = (i == count - 1) ? (totalBytes - 1) : (start + chunkSize - 1)
            result.append(DownloadSegment(id: i, startByte: start, endByte: end))
        }
        return result
    }

    // MARK: - Segment Worker

    private func downloadSegment(index: Int, targetURL: URL) async throws -> (Int, Int64) {
        guard index < segments.count else { return (index, 0) }
        var segment = segments[index]
        let partFileURL = partFileURL(for: segment.id)

        let startOffset = segment.startByte + segment.downloadedBytes
        guard segment.endByte < 0 || startOffset <= segment.endByte else {
            segments[index].status = .completed
            return (index, segment.downloadedBytes)
        }

        var request = URLRequest(url: targetURL)
        let isGoogleVideo = targetURL.host?.contains("googlevideo.com") == true

        if isGoogleVideo || segment.endByte <= 0 {
            request.setValue("bytes=\(startOffset)-", forHTTPHeaderField: "Range")
        } else {
            request.setValue("bytes=\(startOffset)-\(segment.endByte)", forHTTPHeaderField: "Range")
        }

        if let referer = referer { request.setValue(referer, forHTTPHeaderField: "Referer") }
        if let userAgent = userAgent { request.setValue(userAgent, forHTTPHeaderField: "User-Agent") }
        if let cookie = cookie { request.setValue(cookie, forHTTPHeaderField: "Cookie") }

        let isSuno = targetURL.host?.contains("suno.ai") == true || targetURL.host?.contains("suno.com") == true
        if isSuno {
            request.setValue("https://suno.com", forHTTPHeaderField: "Origin")
            if request.value(forHTTPHeaderField: "Referer") == nil {
                request.setValue("https://suno.com/", forHTTPHeaderField: "Referer")
            }
            request.setValue("cors", forHTTPHeaderField: "Sec-Fetch-Mode")
            request.setValue("cross-site", forHTTPHeaderField: "Sec-Fetch-Site")
            request.setValue("audio", forHTTPHeaderField: "Sec-Fetch-Dest")
            request.setValue("*/*", forHTTPHeaderField: "Accept")
            request.setValue("identity;q=1, *;q=0", forHTTPHeaderField: "Accept-Encoding")
            if request.value(forHTTPHeaderField: "User-Agent") == nil {
                request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0.0.0 Safari/537.36", forHTTPHeaderField: "User-Agent")
            }
        }

        if isGoogleVideo {
            request.setValue("https://www.youtube.com", forHTTPHeaderField: "Origin")
            request.setValue("https://www.youtube.com/", forHTTPHeaderField: "Referer")
            request.setValue("cors", forHTTPHeaderField: "Sec-Fetch-Mode")
            request.setValue("cross-site", forHTTPHeaderField: "Sec-Fetch-Site")
            request.setValue("video", forHTTPHeaderField: "Sec-Fetch-Dest")
            request.setValue("*/*", forHTTPHeaderField: "Accept")
            request.setValue("identity;q=1, *;q=0", forHTTPHeaderField: "Accept-Encoding")
            if request.value(forHTTPHeaderField: "User-Agent") == nil {
                request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0.0.0 Safari/537.36", forHTTPHeaderField: "User-Agent")
            }
        }

        segments[index].status = .downloading

        if !FileManager.default.fileExists(atPath: partFileURL.path) {
            FileManager.default.createFile(atPath: partFileURL.path, contents: nil)
        }
        let fileHandle = try FileHandle(forWritingTo: partFileURL)
        try fileHandle.seekToEnd()

        let (bytes, response) = try await session.bytes(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (httpResponse.statusCode == 200 || httpResponse.statusCode == 206) else {
            try fileHandle.close()
            if let http = response as? HTTPURLResponse {
                let statusMsg = HTTPURLResponse.localizedString(forStatusCode: http.statusCode)
                let detailMsg: String
                if http.statusCode == 403 {
                    if isSuno {
                        detailMsg = "Suno CDN access restricted (HTTP 403 Forbidden). Session cookies or CloudFront signature missing. Use the 'Browser' download button in the extension to save directly."
                    } else {
                        detailMsg = "Access restricted (HTTP 403 Forbidden). The stream URL may have expired, or requires session authentication. Try the 'Browser' download button to save directly."
                    }
                } else if http.statusCode == 404 {
                    detailMsg = "File not found (HTTP 404). The media stream may have expired or moved."
                } else {
                    detailMsg = "Server returned HTTP \(http.statusCode) (\(statusMsg))."
                }
                throw NSError(
                    domain: "FETCHDECK",
                    code: http.statusCode,
                    userInfo: [NSLocalizedDescriptionKey: detailMsg]
                )
            }
            throw URLError(.badServerResponse)
        }

        var buffer = Data()
        buffer.reserveCapacity(64 * 1024)

        for try await byte in bytes {
            if isCancelled || isPaused {
                try fileHandle.close()
                return (index, segment.downloadedBytes)
            }

            buffer.append(byte)
            segment.downloadedBytes += 1

            if buffer.count >= 64 * 1024 {
                try fileHandle.write(contentsOf: buffer)
                buffer.removeAll(keepingCapacity: true)
                segments[index].downloadedBytes = segment.downloadedBytes
                notifyProgress()
            }
        }

        if !buffer.isEmpty {
            try fileHandle.write(contentsOf: buffer)
            buffer.removeAll()
        }
        try fileHandle.close()

        segments[index].downloadedBytes = segment.downloadedBytes
        segments[index].status = .completed
        notifyProgress()

        return (index, segment.downloadedBytes)
    }

    private func notifyProgress() {
        let now = Date()
        let elapsed = now.timeIntervalSince(lastSpeedCalcTime)
        let currentTotalDownloaded = segments.reduce(0) { $0 + $1.downloadedBytes }

        if elapsed >= 0.5 {
            let bytesDelta = currentTotalDownloaded - lastBytesCount
            if currentSpeed == 0 || !isYouTubeDownload() {
                currentSpeed = max(0, Double(bytesDelta) / elapsed)
            }
            lastSpeedCalcTime = now
            lastBytesCount = currentTotalDownloaded
        }

        onProgress?(currentTotalDownloaded, segments, currentSpeed)
    }

    private func mergeSegments() throws {
        if segments.count == 1 {
            let singlePart = partFileURL(for: segments[0].id)
            if FileManager.default.fileExists(atPath: singlePart.path) {
                if FileManager.default.fileExists(atPath: destinationFileURL.path) {
                    try FileManager.default.removeItem(at: destinationFileURL)
                }
                try FileManager.default.moveItem(at: singlePart, to: destinationFileURL)
            }
            return
        }

        if FileManager.default.fileExists(atPath: destinationFileURL.path) {
            try FileManager.default.removeItem(at: destinationFileURL)
        }
        FileManager.default.createFile(atPath: destinationFileURL.path, contents: nil)
        let destinationHandle = try FileHandle(forWritingTo: destinationFileURL)

        for segment in segments.sorted(by: { $0.id < $1.id }) {
            let partFile = partFileURL(for: segment.id)
            if FileManager.default.fileExists(atPath: partFile.path) {
                let partHandle = try FileHandle(forReadingFrom: partFile)
                while true {
                    let chunk = partHandle.readData(ofLength: 1024 * 1024)
                    if chunk.isEmpty { break }
                    try destinationHandle.write(contentsOf: chunk)
                }
                try partHandle.close()
                try? FileManager.default.removeItem(at: partFile)
            }
        }

        try destinationHandle.close()
    }

    private func partFileURL(for segmentID: Int) -> URL {
        destinationFileURL.deletingLastPathComponent()
            .appendingPathComponent(".\(destinationFileURL.lastPathComponent).part\(segmentID)")
    }

    private func cleanUpTemporaryFiles() {
        for segment in segments {
            try? FileManager.default.removeItem(at: partFileURL(for: segment.id))
        }
    }

    private func isHLSStream() -> Bool {
        url.pathExtension.lowercased() == "m3u8" || url.absoluteString.contains(".m3u8")
    }

    private func findFFmpeg() -> String? {
        YouTubeEngine.findBinary(named: "ffmpeg")
    }

    private func downloadWithAudioMux(videoURL: URL, audioURL: URL, ffmpegPath: String) async {
        let parentDir = destinationFileURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: parentDir, withIntermediateDirectories: true)

        let tempVideoFile = parentDir.appendingPathComponent("temp_v_\(itemID.uuidString).mp4")
        let tempAudioFile = parentDir.appendingPathComponent("temp_a_\(itemID.uuidString).m4a")

        self.segments = [
            DownloadSegment(id: 0, startByte: 0, endByte: -1, status: .downloading),
            DownloadSegment(id: 1, startByte: 0, endByte: -1, status: .downloading)
        ]
        notifyProgress()

        do {
            func fetchStream(from streamURL: URL, to localURL: URL, segmentIndex: Int) async throws {
                var req = URLRequest(url: streamURL)
                req.setValue("bytes=0-", forHTTPHeaderField: "Range")
                req.setValue("https://www.youtube.com", forHTTPHeaderField: "Origin")
                req.setValue("https://www.youtube.com/", forHTTPHeaderField: "Referer")
                req.setValue("cors", forHTTPHeaderField: "Sec-Fetch-Mode")
                req.setValue("cross-site", forHTTPHeaderField: "Sec-Fetch-Site")
                req.setValue("video", forHTTPHeaderField: "Sec-Fetch-Dest")
                req.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0.0.0 Safari/537.36", forHTTPHeaderField: "User-Agent")

                let (bytes, response) = try await session.bytes(for: req)
                guard let http = response as? HTTPURLResponse, (http.statusCode == 200 || http.statusCode == 206) else {
                    if let http = response as? HTTPURLResponse {
                        let statusMsg = HTTPURLResponse.localizedString(forStatusCode: http.statusCode)
                        throw NSError(
                            domain: "FETCHDECK",
                            code: http.statusCode,
                            userInfo: [NSLocalizedDescriptionKey: "Server returned HTTP \(http.statusCode) (\(statusMsg)). Stream URL may be expired or forbidden."]
                        )
                    }
                    throw URLError(.badServerResponse)
                }

                if !FileManager.default.fileExists(atPath: localURL.path) {
                    FileManager.default.createFile(atPath: localURL.path, contents: nil)
                }
                let handle = try FileHandle(forWritingTo: localURL)
                var buffer = Data()
                buffer.reserveCapacity(64 * 1024)

                for try await byte in bytes {
                    if isCancelled || isPaused {
                        try? handle.close()
                        return
                    }
                    buffer.append(byte)
                    segments[segmentIndex].downloadedBytes += 1
                    if buffer.count >= 64 * 1024 {
                        try handle.write(contentsOf: buffer)
                        buffer.removeAll(keepingCapacity: true)
                        notifyProgress()
                    }
                }
                if !buffer.isEmpty {
                    try handle.write(contentsOf: buffer)
                }
                try handle.close()
                segments[segmentIndex].status = .completed
                notifyProgress()
            }

            try await withThrowingTaskGroup(of: Void.self) { group in
                group.addTask {
                    try await fetchStream(from: videoURL, to: tempVideoFile, segmentIndex: 0)
                }
                group.addTask {
                    try await fetchStream(from: audioURL, to: tempAudioFile, segmentIndex: 1)
                }
                try await group.waitForAll()
            }

            if isCancelled || isPaused {
                try? FileManager.default.removeItem(at: tempVideoFile)
                try? FileManager.default.removeItem(at: tempAudioFile)
                return
            }

            let muxProcess = Process()
            muxProcess.executableURL = URL(fileURLWithPath: ffmpegPath)
            muxProcess.arguments = [
                "-y",
                "-i", tempVideoFile.path,
                "-i", tempAudioFile.path,
                "-c", "copy",
                destinationFileURL.path
            ]

            self.ffmpegProcess = muxProcess
            try muxProcess.run()
            muxProcess.waitUntilExit()

            try? FileManager.default.removeItem(at: tempVideoFile)
            try? FileManager.default.removeItem(at: tempAudioFile)

            if muxProcess.terminationStatus == 0 {
                onCompletion?(.success(destinationFileURL))
            } else if !isCancelled && !isPaused {
                throw NSError(domain: "FFmpegError", code: Int(muxProcess.terminationStatus), userInfo: [NSLocalizedDescriptionKey: "FFmpeg audio/video mux failed with code \(muxProcess.terminationStatus)"])
            }
        } catch {
            try? FileManager.default.removeItem(at: tempVideoFile)
            try? FileManager.default.removeItem(at: tempAudioFile)
            if !isCancelled && !isPaused {
                onCompletion?(.failure(error))
            }
        }
    }

    private func downloadHLSWithFFmpeg(ffmpegPath: String) async {
        let parentDir = destinationFileURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: parentDir, withIntermediateDirectories: true)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: ffmpegPath)

        var headerString = ""
        if let ua = userAgent { headerString += "User-Agent: \(ua)\r\n" }
        if let ref = referer { headerString += "Referer: \(ref)\r\n" }
        if let ck = cookie { headerString += "Cookie: \(ck)\r\n" }

        var args = ["-y"]
        if !headerString.isEmpty {
            args.append(contentsOf: ["-headers", headerString])
        }
        args.append(contentsOf: [
            "-i", url.absoluteString,
            "-c", "copy",
            "-bsf:a", "aac_adtstoasc",
            destinationFileURL.path
        ])
        process.arguments = args

        self.ffmpegProcess = process
        self.segments = [DownloadSegment(id: 0, startByte: 0, endByte: -1, status: .downloading)]
        notifyProgress()

        do {
            try process.run()
            process.waitUntilExit()

            if process.terminationStatus == 0 {
                segments[0].status = .completed
                notifyProgress()
                onCompletion?(.success(destinationFileURL))
            } else if !isCancelled && !isPaused {
                throw NSError(domain: "FFmpegError", code: Int(process.terminationStatus), userInfo: [NSLocalizedDescriptionKey: "FFmpeg stream mux failed with code \(process.terminationStatus)"])
            }
        } catch {
            if !isCancelled && !isPaused {
                onCompletion?(.failure(error))
            }
        }
    }
}
