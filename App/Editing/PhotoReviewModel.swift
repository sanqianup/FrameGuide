import SwiftUI
import ImageIO

@MainActor
final class PhotoReviewModel: ObservableObject {
    let record: PhotoRecord
    @Published var original: UIImage?
    @Published var preview: UIImage?
    @Published var generatedPreview: UIImage?
    @Published var recipe = ToneRecipe()
    @Published var advice = "云端未请求 · 本地自然调色可直接使用"
    @Published var busy = false
    @Published var rendering = false
    @Published var message: String?
    @Published var editPrompt = "保留人物身份和场景细节，轻微改善光线与色彩，不改变构图。"
    @Published private(set) var canUndo = false
    private var history: [ToneRecipe] = []
    private var generatedData: Data?
    private var gate = RequestGate()
    private var remoteTask: Task<Void, Never>?
    private var renderTask: Task<Void, Never>?
    private var alive = true
    init(record: PhotoRecord) { self.record = record }

    func load() async {
        do {
            _ = try await PhotoStore.shared.verifiedOriginal(record)
            let data = try await PhotoRenderer.shared.render(url: record.originalURL, recipe: ToneRecipe(), maxDimension: 1600)
            guard alive else { return }
            original = Self.thumbnail(data); preview = original
        } catch { message = error.localizedDescription }
    }
    func apply(_ value: ToneRecipe) {
        guard value.isSafe, !rendering, !busy, alive else { return }
        let old = recipe
        history.append(old)
        if history.count > 20 { history.removeFirst() }
        recipe = value; canUndo = true
        render()
    }
    func undo() {
        guard !rendering, !busy, let old = history.popLast() else { return }
        recipe = old; canUndo = !history.isEmpty; render()
    }
    private func render() {
        rendering = true
        let value = recipe
        renderTask = Task {
            defer { if alive { rendering = false } }
            do {
                let data = try await PhotoRenderer.shared.render(url: record.originalURL, recipe: value, maxDimension: 1600)
                guard alive, !Task.isCancelled else { return }
                preview = Self.thumbnail(data)
            } catch { if alive { message = error.localizedDescription } }
        }
    }
    func saveOriginal() {
        guard !busy, !rendering else { return }; rendering = true
        Task {
            defer { rendering = false }
            do { try await PhotoStore.shared.exportOriginal(record); message = "原图已添加到系统相册" }
            catch { message = error.localizedDescription }
        }
    }
    func saveColorCopy() {
        guard !busy, !rendering else { return }; rendering = true
        let value = recipe
        Task {
            defer { rendering = false }
            do {
                let data = try await PhotoRenderer.shared.render(url: record.originalURL, recipe: value)
                try await PhotoStore.shared.exportEdited(data)
                message = "调色副本已添加到相册；原始文件保持完整"
            } catch { message = error.localizedDescription }
        }
    }
    func saveGeneratedCopy() {
        guard let data = generatedData, !busy, !rendering else { return }; rendering = true
        Task {
            defer { rendering = false }
            do { try await PhotoStore.shared.exportEdited(data); message = "生成式编辑副本已保存；可能包含模型改变的细节" }
            catch { message = error.localizedDescription }
        }
    }
    /// Invoked only after a per-photo confirmation dialog and an enabled upload switch.
    func request(_ kind: RemoteKind, uploadAllowed: Bool) {
        guard uploadAllowed, alive, !rendering, !busy else { return }
        let config = RemoteConfiguration.load(kind)
        do { _ = try config.validate() } catch { message = error.localizedDescription; return }
        guard let ticket = gate.begin(photo: record.id) else { return }
        busy = true
        let prompt = editPrompt
        remoteTask = Task {
            let started = ProcessInfo.processInfo.systemUptime
            defer {
                if gate.accepts(ticket, photo: record.id) { gate.finish(ticket); busy = false }
            }
            do {
                let data = try await PhotoRenderer.shared.uploadPreview(url: record.originalURL)
                try Task.checkCancellation()
                if kind == .vision {
                    let result = try await RemoteClient.shared.advice(jpeg: data, config: config)
                    guard alive, gate.accepts(ticket, photo: record.id), !Task.isCancelled else {
                        PerformanceMonitor.shared.discardedResponses += 1; return
                    }
                    advice = "模型建议（请自行判断）：\(result.advice)"
                    busy = false // local renderer may now apply the validated recipe
                    apply(result.tone)
                } else {
                    let result = try await RemoteClient.shared.edit(jpeg: data, prompt: prompt, config: config)
                    guard alive, gate.accepts(ticket, photo: record.id), !Task.isCancelled else {
                        PerformanceMonitor.shared.discardedResponses += 1; return
                    }
                    generatedData = result; generatedPreview = Self.thumbnail(result)
                    advice = "生成式结果可能改变细节，请与原图逐项比较后决定是否保存"
                }
                PerformanceMonitor.shared.cloudMS = (ProcessInfo.processInfo.systemUptime - started) * 1000
            } catch {
                guard alive, gate.accepts(ticket, photo: record.id), !Task.isCancelled else {
                    PerformanceMonitor.shared.discardedResponses += 1; return
                }
                PerformanceMonitor.shared.cloudMS = (ProcessInfo.processInfo.systemUptime - started) * 1000
                message = error.localizedDescription
            }
        }
    }
    func cancelRemote() {
        gate.cancel(); remoteTask?.cancel(); remoteTask = nil; busy = false
    }
    func close() {
        alive = false; cancelRemote(); renderTask?.cancel()
        original = nil; preview = nil; generatedPreview = nil; generatedData = nil
    }
    static func thumbnail(_ data: Data) -> UIImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: 1600,
                kCGImageSourceShouldCacheImmediately: true
              ] as CFDictionary) else { return nil }
        return UIImage(cgImage: image)
    }
}
