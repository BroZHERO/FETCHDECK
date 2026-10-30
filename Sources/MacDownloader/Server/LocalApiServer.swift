import Foundation
import Network

public final class LocalApiServer: @unchecked Sendable {
    public static let shared = LocalApiServer()
    private var listener: NWListener?
    private let port: NWEndpoint.Port = 45678
    private let queue = DispatchQueue(label: "com.macdownloader.apiserver", qos: .userInitiated)

    public private(set) var isRunning: Bool = false

    public func start() {
        guard !isRunning else { return }
        do {
            let parameters = NWParameters.tcp
            parameters.allowLocalEndpointReuse = true
            listener = try NWListener(using: parameters, on: port)

            listener?.newConnectionHandler = { [weak self] connection in
                self?.handleConnection(connection)
            }

            listener?.stateUpdateHandler = { [weak self] state in
                switch state {
                case .ready:
                    print("Local API Server listening on 127.0.0.1:45678")
                    self?.isRunning = true
                case .failed(let error):
                    print("API Server failed: \(error)")
                    self?.isRunning = false
                case .cancelled:
                    self?.isRunning = false
                default:
                    break
                }
            }

            listener?.start(queue: queue)
        } catch {
            print("Failed to initialize NWListener: \(error)")
        }
    }

    public func stop() {
        listener?.cancel()
        listener = nil
        isRunning = false
    }

    private func handleConnection(_ connection: NWConnection) {
        connection.start(queue: queue)
        receiveData(from: connection)
    }

    private func receiveData(from connection: NWConnection) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] content, _, isComplete, error in
            guard let self = self else { return }

            if let data = content, !data.isEmpty, let requestString = String(data: data, encoding: .utf8) {
                Task {
                    let response = await self.processHttpRequest(requestString: requestString)
                    connection.send(content: response.data(using: .utf8), completion: .contentProcessed({ _ in
                        connection.cancel()
                    }))
                }
            } else if isComplete || error != nil {
                connection.cancel()
            }
        }
    }

    private func processHttpRequest(requestString: String) async -> String {
        let lines = requestString.components(separatedBy: "\r\n")
        guard let requestLine = lines.first else {
            return makeHttpResponse(status: 400, body: "{\"error\":\"Empty request\"}")
        }

        let parts = requestLine.components(separatedBy: " ")
        guard parts.count >= 2 else {
            return makeHttpResponse(status: 400, body: "{\"error\":\"Malformed request\"}")
        }

        let method = parts[0].uppercased()
        let path = parts[1]

        // Handle CORS Preflight
        if method == "OPTIONS" {
            return """
            HTTP/1.1 204 No Content\r
            Access-Control-Allow-Origin: *\r
            Access-Control-Allow-Methods: GET, POST, OPTIONS\r
            Access-Control-Allow-Headers: Content-Type, Authorization, Range\r
            Access-Control-Max-Age: 86400\r
            Content-Length: 0\r
            \r\n
            """
        }

        // Endpoint: Status check
        if method == "GET" && path == "/api/status" {
            let body = "{\"status\":\"running\",\"app\":\"MacDownloader\",\"version\":\"1.0.0\"}"
            return makeHttpResponse(status: 200, body: body)
        }

        // Endpoint: Resolve YouTube video streams
        if method == "POST" && (path == "/api/resolve" || path == "/api/resolve-youtube") {
            if let bodyRange = requestString.range(of: "\r\n\r\n") {
                let bodyString = String(requestString[bodyRange.upperBound...])
                if let bodyData = bodyString.data(using: .utf8),
                   let json = try? JSONSerialization.jsonObject(with: bodyData) as? [String: Any] {
                    let target = (json["url"] as? String) ?? (json["videoId"] as? String) ?? ""
                    if !target.isEmpty {
                        if let result = await YouTubeResolver.shared.resolve(urlOrId: target) {
                            if let resData = try? JSONEncoder().encode(result),
                               let resStr = String(data: resData, encoding: .utf8) {
                                return makeHttpResponse(status: 200, body: resStr)
                            }
                        }
                    }
                }
            }
            return makeHttpResponse(status: 404, body: "{\"error\":\"Could not resolve stream options for this video\"}")
        }

        // Endpoint: Receive new download task
        if method == "POST" && path == "/api/download" {
            if let bodyRange = requestString.range(of: "\r\n\r\n") {
                let bodyString = String(requestString[bodyRange.upperBound...])
                if let bodyData = bodyString.data(using: .utf8) {
                    if let json = try? JSONSerialization.jsonObject(with: bodyData) as? [String: Any],
                       let urlString = json["url"] as? String {

                        // Validate against in-browser memory blob / data pseudo-URLs
                        if urlString.hasPrefix("blob:") || urlString.hasPrefix("data:") {
                            return makeHttpResponse(status: 400, body: "{\"error\":\"Browser blob/data URLs cannot be downloaded directly. Please select an HTTP media stream from the extension quality dropdown.\"}")
                        }

                        guard let url = URL(string: urlString),
                              let scheme = url.scheme?.lowercased(),
                              (scheme == "http" || scheme == "https") else {
                            return makeHttpResponse(status: 400, body: "{\"error\":\"Invalid or unsupported URL protocol. Only HTTP and HTTPS streams are supported.\"}")
                        }

                        let filename = json["filename"] as? String
                        let referer = (json["referer"] as? String) ?? (json["pageUrl"] as? String)
                        let userAgent = json["userAgent"] as? String
                        let cookie = json["cookie"] as? String
                        let quality = json["quality"] as? String
                        let resolutionDetails = json["dimensions"] as? String ?? json["resolutionDetails"] as? String
                        let audioUrlString = json["audioUrl"] as? String
                        let audioUrl = audioUrlString != nil ? URL(string: audioUrlString!) : nil

                        Task { @MainActor in
                            DownloadManager.shared.addDownload(
                                url: url,
                                filename: filename,
                                referer: referer,
                                userAgent: userAgent,
                                cookie: cookie,
                                quality: quality,
                                audioUrl: audioUrl,
                                resolutionDetails: resolutionDetails,
                                autoStart: true
                            )
                        }

                        let responseBody = "{\"status\":\"success\",\"message\":\"Download task added\",\"url\":\"\(urlString)\"}"
                        return makeHttpResponse(status: 200, body: responseBody)
                    }
                }
            }
            return makeHttpResponse(status: 400, body: "{\"error\":\"Invalid JSON payload or missing URL\"}")
        }

        return makeHttpResponse(status: 404, body: "{\"error\":\"Not Found\"}")
    }

    private func makeHttpResponse(status: Int, body: String) -> String {
        let statusText = status == 200 ? "OK" : (status == 400 ? "Bad Request" : (status == 404 ? "Not Found" : "Internal Server Error"))
        let bodyLength = body.utf8.count
        return """
        HTTP/1.1 \(status) \(statusText)\r
        Content-Type: application/json\r
        Access-Control-Allow-Origin: *\r
        Access-Control-Allow-Methods: GET, POST, OPTIONS\r
        Access-Control-Allow-Headers: Content-Type, Range\r
        Content-Length: \(bodyLength)\r
        Connection: close\r
        \r
        \(body)
        """
    }
}
