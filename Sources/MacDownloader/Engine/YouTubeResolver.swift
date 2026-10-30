import Foundation

public struct YouTubeStreamOption: Codable, Sendable {
    public let itag: Int
    public let quality: String           // "1080p", "720p", "480p", "360p", "Audio", "MP3"
    public let label: String             // "1080p Full HD", "720p HD", etc.
    public let dimensions: String        // "1920×1080", "1280×720", etc.
    public let format: String            // "MP4 Video", "M4A Audio", "MP3 Audio"
    public let type: String              // "video" or "audio"
    public let combined: Bool            // true if progressive (both video and audio)
    public let url: String
    public let audioUrl: String?
    public let size: Int64
    public let formattedSize: String
    public let formatId: String?
    public let thumbnail: String?
    public let duration: String?
}

public struct YouTubeResolutionResult: Codable, Sendable {
    public let videoId: String
    public let title: String
    public let channel: String?
    public let durationSeconds: Int?
    public let durationText: String?
    public let thumbnail: String?
    public let streams: [YouTubeStreamOption]
}

public final class YouTubeEngine: @unchecked Sendable {
    public static func findBinary(named name: String) -> String? {
        // 1. App Bundle Resources
        if let res = Bundle.main.resourceURL?.appendingPathComponent("bin/\(name)").path,
           FileManager.default.isExecutableFile(atPath: res) {
            return res
        }
        // 2. Project bin
        let projectBin = "/Users/abishekwork/.gemini/antigravity/scratch/MacDownloader/bin/\(name)"
        if FileManager.default.isExecutableFile(atPath: projectBin) {
            return projectBin
        }
        // 3. Homebrew
        let brew = "/opt/homebrew/bin/\(name)"
        if FileManager.default.isExecutableFile(atPath: brew) {
            return brew
        }
        // 4. Local /usr/local/bin
        let local = "/usr/local/bin/\(name)"
        if FileManager.default.isExecutableFile(atPath: local) {
            return local
        }
        // 5. /usr/bin
        let usr = "/usr/bin/\(name)"
        if FileManager.default.isExecutableFile(atPath: usr) {
            return usr
        }
        // 6. Node in nvm
        if name == "node" {
            let nvmNode = "/Users/abishekwork/.nvm/versions/node/v24.21.0/bin/node"
            if FileManager.default.isExecutableFile(atPath: nvmNode) {
                return nvmNode
            }
        }
        return nil
    }

    public static func formatSeconds(_ sec: Int) -> String {
        guard sec > 0 else { return "" }
        let h = sec / 3600
        let m = (sec % 3600) / 60
        let s = sec % 60
        if h > 0 {
            return String(format: "%02d:%02d:%02d", h, m, s)
        }
        return String(format: "%02d:%02d", m, s)
    }

    public static func getEngineVersion() -> String {
        guard let python = findBinary(named: "python3"),
              let ytdlp = findBinary(named: "yt-dlp") else {
            return "2026.10.26"
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: python)
        process.arguments = [ytdlp, "--version"]
        let pipe = Pipe()
        process.standardOutput = pipe
        do {
            try process.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            let v = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return v.isEmpty ? "2026.10.26" : v
        } catch {
            return "2026.10.26"
        }
    }

    public static func updateEngine() async -> (success: Bool, message: String) {
        guard let python = findBinary(named: "python3"),
              let ytdlp = findBinary(named: "yt-dlp") else {
            return (false, "Engine binaries not found")
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: python)
        process.arguments = [ytdlp, "-U"]

        var env = ProcessInfo.processInfo.environment
        env["PATH"] = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/Users/abishekwork/.nvm/versions/node/v24.21.0/bin"
        process.environment = env

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        do {
            try process.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if process.terminationStatus == 0 {
                return (true, output.isEmpty ? "yt-dlp is already up-to-date." : output)
            } else {
                return (false, "Update status \(process.terminationStatus): \(output)")
            }
        } catch {
            return (false, error.localizedDescription)
        }
    }
}

public final class YouTubeResolver: @unchecked Sendable {
    public static let shared = YouTubeResolver()
    private let session: URLSession

    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 15
        self.session = URLSession(configuration: config)
    }

    public func extractVideoId(from string: String) -> String? {
        if string.count == 11 && !string.contains("/") && !string.contains("?") && !string.contains("=") {
            return string
        }
        guard let url = URL(string: string) else { return nil }
        if let host = url.host?.lowercased() {
            if host.contains("youtu.be") {
                return url.pathComponents.dropFirst().first
            }
            if host.contains("youtube.com") {
                if let comps = URLComponents(url: url, resolvingAgainstBaseURL: false) {
                    if let v = comps.queryItems?.first(where: { $0.name == "v" })?.value {
                        return v
                    }
                }
                if url.path.contains("/shorts/") {
                    return url.lastPathComponent
                }
                if url.path.contains("/embed/") {
                    return url.lastPathComponent
                }
            }
        }
        return nil
    }

    public func resolve(urlOrId: String) async -> YouTubeResolutionResult? {
        let canonicalUrl: String
        let videoId: String
        if let vid = extractVideoId(from: urlOrId) {
            videoId = vid
            canonicalUrl = "https://www.youtube.com/watch?v=\(vid)"
        } else if urlOrId.hasPrefix("http") {
            canonicalUrl = urlOrId
            videoId = extractVideoId(from: urlOrId) ?? "universal_media"
        } else {
            return nil
        }

        // Strategy 1: Universal media resolution via yt-dlp + Node JS challenge solver (1,000+ sites)
        if let result = await resolveWithYtDlp(url: canonicalUrl, videoId: videoId) {
            return result
        }

        // Strategy 2: Fallback to InnerTube client query for YouTube
        if canonicalUrl.contains("youtube.com") || canonicalUrl.contains("youtu.be") {
            if let res = await queryInnerTube(videoId: videoId, clientName: "IOS", clientVersion: "19.29.1") {
                return res
            }
            if let res = await queryInnerTube(videoId: videoId, clientName: "TVHTML5", clientVersion: "7.20240901.12.00") {
                return res
            }
        }
        return nil
    }

    // MARK: - Universal yt-dlp Backend Resolution

    private func resolveWithYtDlp(url: String, videoId: String) async -> YouTubeResolutionResult? {
        guard let python = YouTubeEngine.findBinary(named: "python3"),
              let ytdlp = YouTubeEngine.findBinary(named: "yt-dlp") else {
            return nil
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: python)

        var args = [
            ytdlp,
            "-J",
            "--no-warnings",
            "--no-playlist",
            "--flat-playlist"
        ]

        if let node = YouTubeEngine.findBinary(named: "node") {
            args.append(contentsOf: ["--js-runtimes", "node:\(node)"])
        }

        args.append(url)
        process.arguments = args

        var env = ProcessInfo.processInfo.environment
        env["PATH"] = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/Users/abishekwork/.nvm/versions/node/v24.21.0/bin"
        process.environment = env

        let stdoutPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = Pipe()

        do {
            try process.run()
            let data = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()

            guard process.terminationStatus == 0, !data.isEmpty else {
                return nil
            }

            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return nil
            }

            let title = json["title"] as? String ?? "Media Stream"
            let channel = json["uploader"] as? String ?? json["channel"] as? String ?? json["creator"] as? String
            let duration = json["duration"] as? Int
            let thumbnail = json["thumbnail"] as? String
            let formats = json["formats"] as? [[String: Any]] ?? []

            return parseYtDlpFormats(
                videoId: videoId,
                title: title,
                channel: channel,
                duration: duration,
                thumbnail: thumbnail,
                pageUrl: url,
                rawFormats: formats
            )
        } catch {
            return nil
        }
    }

    private func parseYtDlpFormats(
        videoId: String,
        title: String,
        channel: String?,
        duration: Int?,
        thumbnail: String?,
        pageUrl: String,
        rawFormats: [[String: Any]]
    ) -> YouTubeResolutionResult {
        var bestAudioSize: Int64 = 0
        for f in rawFormats {
            let vcodec = f["vcodec"] as? String ?? ""
            let acodec = f["acodec"] as? String ?? ""
            if (vcodec == "none" || vcodec.isEmpty) && acodec != "none" && !acodec.isEmpty {
                let size = (f["filesize"] as? Int64) ?? (f["filesize_approx"] as? Int64) ?? 0
                if size > bestAudioSize {
                    bestAudioSize = size
                }
            }
        }
        if bestAudioSize == 0 {
            bestAudioSize = 3_500_000
        }

        let durationText = YouTubeEngine.formatSeconds(duration ?? 0)
        var streamOptions: [YouTubeStreamOption] = []
        let targetHeights = [2160, 1440, 1080, 720, 480, 360]

        for targetH in targetHeights {
            let matches = rawFormats.filter { f in
                let h = f["height"] as? Int ?? 0
                let vcodec = f["vcodec"] as? String ?? ""
                return h == targetH && vcodec != "none" && !vcodec.isEmpty
            }
            guard !matches.isEmpty else { continue }

            let chosen = matches.first { ($0["ext"] as? String) == "mp4" } ?? matches[0]

            let q = "\(targetH)p"
            let w = chosen["width"] as? Int ?? (targetH == 1080 ? 1920 : (targetH == 720 ? 1280 : (targetH == 480 ? 854 : 640)))
            let fps = chosen["fps"] as? Int ?? 30
            let vSize = (chosen["filesize"] as? Int64) ?? (chosen["filesize_approx"] as? Int64) ?? 0
            let acodec = chosen["acodec"] as? String ?? ""
            let isMuxed = acodec != "none" && !acodec.isEmpty
            let totalSize = isMuxed ? vSize : (vSize + bestAudioSize)

            let label: String
            if targetH >= 2160 {
                label = "4K Ultra HD"
            } else if targetH >= 1440 {
                label = "1440p 2K QHD"
            } else if targetH >= 1080 {
                label = "1080p Full HD"
            } else if targetH >= 720 {
                label = "720p HD"
            } else {
                label = "\(targetH)p"
            }

            let fpsSuffix = fps > 30 ? " (\(fps)fps)" : ""
            let dimStr = "\(w)×\(targetH)\(fpsSuffix)"
            let formattedSize = totalSize > 0 ? ByteCountFormatter.string(fromByteCount: totalSize, countStyle: .file) : "Direct Stream"

            let formatId: String
            if isMuxed {
                formatId = chosen["format_id"] as? String ?? "\(targetH)"
            } else {
                formatId = "bestvideo[height<=\(targetH)]+bestaudio/best[height<=\(targetH)]/best"
            }

            let directUrl = (chosen["url"] as? String) ?? pageUrl

            streamOptions.append(YouTubeStreamOption(
                itag: chosen["format_id"] as? Int ?? targetH,
                quality: q,
                label: label,
                dimensions: dimStr,
                format: "MP4 Video",
                type: "video",
                combined: isMuxed,
                url: directUrl,
                audioUrl: isMuxed ? nil : directUrl,
                size: totalSize,
                formattedSize: formattedSize,
                formatId: formatId,
                thumbnail: thumbnail,
                duration: durationText
            ))
        }

        // Add Audio options (M4A and MP3)
        let formattedAudioSize = ByteCountFormatter.string(fromByteCount: bestAudioSize, countStyle: .file)
        streamOptions.append(YouTubeStreamOption(
            itag: 140,
            quality: "Audio",
            label: "Audio Track (M4A)",
            dimensions: "128 kbps (Stereo)",
            format: "M4A Audio",
            type: "audio",
            combined: false,
            url: pageUrl,
            audioUrl: nil,
            size: bestAudioSize,
            formattedSize: formattedAudioSize,
            formatId: "bestaudio[ext=m4a]/bestaudio/best",
            thumbnail: thumbnail,
            duration: durationText
        ))

        streamOptions.append(YouTubeStreamOption(
            itag: 251,
            quality: "MP3",
            label: "Audio Track (MP3)",
            dimensions: "High Quality Stereo",
            format: "MP3 Audio",
            type: "audio",
            combined: false,
            url: pageUrl,
            audioUrl: nil,
            size: bestAudioSize,
            formattedSize: formattedAudioSize,
            formatId: "bestaudio/best",
            thumbnail: thumbnail,
            duration: durationText
        ))

        return YouTubeResolutionResult(
            videoId: videoId,
            title: title,
            channel: channel,
            durationSeconds: duration,
            durationText: durationText,
            thumbnail: thumbnail,
            streams: streamOptions
        )
    }

    // MARK: - InnerTube Fallback

    private func queryInnerTube(videoId: String, clientName: String, clientVersion: String) async -> YouTubeResolutionResult? {
        let endpoint = URL(string: "https://www.youtube.com/youtubei/v1/player")!
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("https://www.youtube.com", forHTTPHeaderField: "Origin")
        request.setValue("https://www.youtube.com/", forHTTPHeaderField: "Referer")

        var clientDict: [String: Any] = [
            "clientName": clientName,
            "clientVersion": clientVersion,
            "hl": "en",
            "gl": "US"
        ]

        if clientName == "IOS" {
            clientDict["deviceModel"] = "iPhone16,2"
            clientDict["osName"] = "iOS"
            clientDict["osVersion"] = "17.5.1.21F90"
        }

        let body: [String: Any] = [
            "context": [
                "client": clientDict
            ],
            "videoId": videoId
        ]

        guard let httpBody = try? JSONSerialization.data(withJSONObject: body) else { return nil }
        request.httpBody = httpBody

        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return nil }
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }

            let videoDetails = json["videoDetails"] as? [String: Any] ?? [:]
            let title = videoDetails["title"] as? String ?? "YouTube Video"
            let channel = videoDetails["author"] as? String
            let durationSeconds = Int(videoDetails["lengthSeconds"] as? String ?? "0")
            let thumbnail = (videoDetails["thumbnail"] as? [String: Any])?["thumbnails"] as? [[String: Any]]
            let thumbUrl = thumbnail?.last?["url"] as? String

            guard let streamingData = json["streamingData"] as? [String: Any] else { return nil }

            return parseStreamingData(
                videoId: videoId,
                title: title,
                channel: channel,
                durationSeconds: durationSeconds,
                thumbnail: thumbUrl,
                streamingData: streamingData
            )
        } catch {
            return nil
        }
    }

    private func parseStreamingData(
        videoId: String,
        title: String,
        channel: String?,
        durationSeconds: Int?,
        thumbnail: String?,
        streamingData: [String: Any]
    ) -> YouTubeResolutionResult {
        let formats = streamingData["formats"] as? [[String: Any]] ?? []
        let adaptive = streamingData["adaptiveFormats"] as? [[String: Any]] ?? []

        var bestAudioUrl: String? = nil
        var bestAudioSize: Int64 = 0
        for f in adaptive {
            let mime = f["mimeType"] as? String ?? ""
            if mime.contains("audio/mp4") || mime.contains("audio/") {
                if let u = f["url"] as? String, !u.isEmpty {
                    bestAudioUrl = u
                    if let clen = f["contentLength"] as? String, let s = Int64(clen) {
                        bestAudioSize = s
                    }
                    if mime.contains("audio/mp4") { break }
                }
            }
        }

        let durationText = YouTubeEngine.formatSeconds(durationSeconds ?? 0)
        var streamOptions: [YouTubeStreamOption] = []
        var seenQualities = Set<String>()

        // 1. Progressive formats (720p, 360p)
        for f in formats {
            guard let url = f["url"] as? String, !url.isEmpty else { continue }
            let itag = f["itag"] as? Int ?? 0
            let qLabel = f["qualityLabel"] as? String ?? (itag == 22 ? "720p" : "360p")
            let shortQ = qLabel
                .replacingOccurrences(of: "60fps", with: "", options: .caseInsensitive)
                .replacingOccurrences(of: "50fps", with: "", options: .caseInsensitive)
                .trimmingCharacters(in: .whitespaces)

            if seenQualities.contains(shortQ) { continue }
            seenQualities.insert(shortQ)

            let width = f["width"] as? Int ?? (shortQ == "720p" ? 1280 : 640)
            let height = f["height"] as? Int ?? (shortQ == "720p" ? 720 : 360)
            let dimensions = "\(width)×\(height)"
            let size = Int64(f["contentLength"] as? String ?? "0") ?? 0
            let formattedSize = size > 0 ? ByteCountFormatter.string(fromByteCount: size, countStyle: .file) : "Direct Stream"

            streamOptions.append(YouTubeStreamOption(
                itag: itag,
                quality: shortQ,
                label: "\(shortQ) HD",
                dimensions: dimensions,
                format: "MP4 Video",
                type: "video",
                combined: true,
                url: url,
                audioUrl: nil,
                size: size,
                formattedSize: formattedSize,
                formatId: String(itag),
                thumbnail: thumbnail,
                duration: durationText
            ))
        }

        // 2. Adaptive formats
        for f in adaptive {
            let mime = f["mimeType"] as? String ?? ""
            guard mime.contains("video/mp4") || mime.contains("video/webm") else { continue }
            guard let url = f["url"] as? String, !url.isEmpty else { continue }

            let itag = f["itag"] as? Int ?? 0
            let height = f["height"] as? Int ?? 0
            let width = f["width"] as? Int ?? 0
            let fps = f["fps"] as? Int ?? 30
            guard height >= 360 else { continue }

            let qualityKey = "\(height)p"
            if seenQualities.contains(qualityKey) { continue }
            seenQualities.insert(qualityKey)

            let label = height >= 1080 ? "\(height)p Full HD" : (height >= 720 ? "\(height)p HD" : "\(height)p SD")
            let dimensions = width > 0 && height > 0 ? "\(width)×\(height) (\(fps)fps)" : "\(height)p"
            let videoSize = Int64(f["contentLength"] as? String ?? "0") ?? 0
            let totalEstSize = videoSize + bestAudioSize
            let formattedSize = totalEstSize > 0 ? ByteCountFormatter.string(fromByteCount: totalEstSize, countStyle: .file) : "Direct Stream"

            streamOptions.append(YouTubeStreamOption(
                itag: itag,
                quality: qualityKey,
                label: label,
                dimensions: dimensions,
                format: mime.contains("mp4") ? "MP4 Video" : "WebM Video",
                type: "video",
                combined: false,
                url: url,
                audioUrl: bestAudioUrl,
                size: totalEstSize,
                formattedSize: formattedSize,
                formatId: "bestvideo[height<=\(height)]+bestaudio/best[height<=\(height)]/best",
                thumbnail: thumbnail,
                duration: durationText
            ))
        }

        // 3. Audio format
        if let audioUrl = bestAudioUrl {
            let formattedAudioSize = bestAudioSize > 0 ? ByteCountFormatter.string(fromByteCount: bestAudioSize, countStyle: .file) : "Audio Stream"
            streamOptions.append(YouTubeStreamOption(
                itag: 140,
                quality: "Audio",
                label: "Audio Track (M4A)",
                dimensions: "128 kbps (Stereo)",
                format: "M4A Audio",
                type: "audio",
                combined: false,
                url: audioUrl,
                audioUrl: nil,
                size: bestAudioSize,
                formattedSize: formattedAudioSize,
                formatId: "bestaudio[ext=m4a]/bestaudio/best",
                thumbnail: thumbnail,
                duration: durationText
            ))
        }

        streamOptions.sort { a, b in
            if a.type == "video" && b.type == "audio" { return true }
            if a.type == "audio" && b.type == "video" { return false }
            let pA = Int(a.quality.replacingOccurrences(of: "p", with: "")) ?? 0
            let pB = Int(b.quality.replacingOccurrences(of: "p", with: "")) ?? 0
            return pA > pB
        }

        return YouTubeResolutionResult(
            videoId: videoId,
            title: title,
            channel: channel,
            durationSeconds: durationSeconds,
            durationText: durationText,
            thumbnail: thumbnail,
            streams: streamOptions
        )
    }
}
