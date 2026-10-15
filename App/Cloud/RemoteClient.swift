import Foundation
import ImageIO

/// Refuses redirects: authorization/photo data must stay at the explicitly chosen endpoint.
private final class NoRedirects: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) { completionHandler(nil) }
}

actor RemoteClient {
    static let shared = RemoteClient()
    private var busy = false

    func testVision(_ config: RemoteConfiguration) async throws -> String {
        // No photo is sent. This still calls the user's provider and may incur charges.
        var payload: [String: Any] = ["model": config.model, "stream": false, "max_completion_tokens": 16,
            "messages": [["role": "user", "content": "Reply with OK."]]]
        if config.mimoOptions { payload["thinking"] = ["type": config.disableThinking ? "disabled" : "enabled"] }
        let data = try await sendJSON(payload, config: config, kind: .vision)
        struct Envelope: Decodable { struct Choice: Decodable { struct Message: Decodable { let content: String? }; let message: Message }; let choices: [Choice] }
        guard let e = try? JSONDecoder().decode(Envelope.self, from: data),
              let content = e.choices.first?.message.content, !content.isEmpty else { throw RemoteError.format }
        return "文本接口已响应；图片能力、参数质量和费用仍需实际验证"
    }
    func advice(jpeg: Data, config: RemoteConfiguration) async throws -> VisionAdvice {
        var payload: [String: Any] = ["model": config.model, "stream": false,
            "max_completion_tokens": 600,
            "messages": [
                ["role": "system", "content": CloudContract.instruction],
                ["role": "user", "content": [
                    ["type": "text", "text": "请看图提供建议与保守调色参数。"],
                    ["type": "image_url", "image_url": ["url": "data:image/jpeg;base64,\(jpeg.base64EncodedString())"]]
                ]]
            ]]
        if config.mimoOptions {
            payload["thinking"] = ["type": config.disableThinking ? "disabled" : "enabled"]
            payload["response_format"] = ["type": "json_object"]
        }
        let data = try await sendJSON(payload, config: config, kind: .vision)
        do { return try CloudContract.advice(from: data) }
        catch { throw RemoteError.format }
    }
    /// Optional adapter for providers explicitly documenting multipart image edits + b64_json.
    /// Does not follow returned image URLs, or assume every OpenAI-style provider supports this.
    func edit(jpeg: Data, prompt: String, config: RemoteConfiguration) async throws -> Data {
        guard !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, prompt.count <= 1000 else { throw RemoteError.format }
        var request = try request(config, kind: .editing)
        let boundary = "FrameGuide-\(UUID().uuidString)"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        var body = Data()
        func append(_ value: String) { body.append(Data(value.utf8)) }
        for (key, value) in [("model", config.model), ("prompt", prompt), ("response_format", "b64_json")] {
            append("--\(boundary)\r\nContent-Disposition: form-data; name=\"\(key)\"\r\n\r\n\(value)\r\n")
        }
        append("--\(boundary)\r\nContent-Disposition: form-data; name=\"image\"; filename=\"preview.jpg\"\r\nContent-Type: image/jpeg\r\n\r\n")
        body.append(jpeg); append("\r\n--\(boundary)--\r\n")
        request.httpBody = body
        let data = try await send(request, timeout: config.timeout, limit: 25_000_000)
        struct Envelope: Decodable { struct Item: Decodable { let b64_json: String? }; let data: [Item] }
        guard let envelope = try? JSONDecoder().decode(Envelope.self, from: data),
              let base64 = envelope.data.first?.b64_json, let image = Data(base64Encoded: base64),
              image.count <= 18_000_000, let source = CGImageSourceCreateWithData(image as CFData, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = props[kCGImagePropertyPixelWidth] as? Int,
              let height = props[kCGImagePropertyPixelHeight] as? Int,
              width > 0, height > 0, Int64(width) * Int64(height) <= 24_000_000 else { throw RemoteError.format }
        return image
    }
    private func request(_ config: RemoteConfiguration, kind: RemoteKind) throws -> URLRequest {
        let url = try config.validate(), key = try SecretStore.read(kind, endpoint: url)
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: config.timeout)
        request.httpMethod = "POST"
        request.setValue(config.auth == .bearer ? "Bearer \(key)" : key, forHTTPHeaderField: config.auth.header)
        return request
    }
    private func sendJSON(_ payload: [String: Any], config: RemoteConfiguration, kind: RemoteKind) async throws -> Data {
        var req = try request(config, kind: kind)
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: payload)
        return try await send(req, timeout: config.timeout, limit: 1_000_000)
    }
    private func send(_ request: URLRequest, timeout: Double, limit: Int) async throws -> Data {
        guard !busy else { throw RemoteError.network }
        busy = true
        defer { busy = false }
        let settings = URLSessionConfiguration.ephemeral
        settings.urlCache = nil; settings.httpCookieStorage = nil; settings.urlCredentialStorage = nil
        settings.timeoutIntervalForRequest = timeout; settings.timeoutIntervalForResource = timeout
        let session = URLSession(configuration: settings, delegate: NoRedirects(), delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        do {
            let (bytes, response) = try await session.bytes(for: request)
            guard let response = response as? HTTPURLResponse else { throw RemoteError.format }
            guard !(300...399).contains(response.statusCode) else { throw RemoteError.redirects }
            guard (200...299).contains(response.statusCode) else { throw RemoteError.http(response.statusCode) }
            guard response.expectedContentLength <= Int64(limit) else { throw RemoteError.tooLarge }
            var data = Data(); data.reserveCapacity(min(limit, 64_000))
            for try await byte in bytes {
                try Task.checkCancellation()
                guard data.count < limit else { throw RemoteError.tooLarge }
                data.append(byte)
            }
            return data
        } catch let error as RemoteError { throw error }
        catch { throw RemoteError.network }
    }
}
