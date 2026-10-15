import SwiftUI
import UIKit

@MainActor
final class CameraModel: ObservableObject {
    let engine = CameraEngine()
    let motion = MotionMonitor()
    let live = LiveAdviceModel()
    @Published var status = "准备相机"
    @Published var ready = false
    @Published var lenses: [Lens] = []
    @Published var selectedLens = ""
    @Published var analysis: AnalysisResult?
    @Published var records: [PhotoRecord] = []
    @Published var saving = false
    @Published var message: String?
    @Published var hasUnsavedOriginal = false
    private var pendingData: Data?
    private var backgroundTask = UIBackgroundTaskIdentifier.invalid
    private var screenActive = false
    private var rotation = 90
    var front: Bool { lenses.first(where: { $0.id == selectedLens })?.front ?? false }
    var canCapture: Bool { screenActive && ready && !saving && !hasUnsavedOriginal }

    init() {
        motion.onStability = { [weak self] value in
            guard let self else { return }
            self.engine.analyzer.setStable(value)
            if !value { self.analysis = nil }
            self.syncLiveReadiness()
        }
        live.onSample = { [weak self] id in self?.engine.samplePreview(id: id) }
        live.onCancelSample = { [weak self] id in self?.engine.analyzer.cancelPreview(id: id) }
        engine.onEvent = { [weak self] event in self?.handle(event) }
    }
    func active(_ value: Bool) {
        screenActive = value
        UIApplication.shared.isIdleTimerDisabled = value
        if value { engine.start(); motion.start() }
        else { engine.stop(); motion.stop(); analysis = nil; ready = false }
        syncLiveReadiness()
    }
    func setRotation(_ angle: CGFloat, quarter: Int) {
        rotation = Int(angle)
        live.setScene(lens: selectedLens, rotation: rotation)
        engine.setRotation(angle); motion.setQuarterTurns(quarter)
        syncLiveReadiness()
    }
    func switchLens(_ id: String) {
        guard screenActive, canCapture, id != selectedLens, lenses.contains(where: { $0.id == id }) else { return }
        live.invalidate("正在切换镜头，旧建议已清除", lens: id, rotation: rotation)
        ready = false; syncLiveReadiness(); engine.switchLens(id)
    }
    func capture() {
        guard canCapture else { return }
        saving = true
        live.invalidate("正在拍摄，云端请求已取消"); syncLiveReadiness()
        backgroundTask = UIApplication.shared.beginBackgroundTask(withName: "PersistCameraOriginal") { [weak self] in
            Task { @MainActor in
                self?.message = "后台保存时间将结束，请回到 App 检查原图"
                self?.endBackgroundTask()
            }
        }
        engine.capture()
    }
    func retrySave() { guard !saving, pendingData != nil else { return }; persistPending() }
    func loadRecords() async {
        do { records = try await PhotoStore.shared.records() }
        catch { message = "本机照片列表读取失败：\(error.localizedDescription)" }
    }
    private func handle(_ event: CameraEvent) {
        switch event {
        case .state(let text, let enabled):
            status = text; ready = enabled
            if !enabled { analysis = nil }
            else { live.setScene(lens: selectedLens, rotation: rotation) }
            syncLiveReadiness()
        case .lenses(let options, let selected):
            lenses = options; selectedLens = selected; analysis = nil
            live.setScene(lens: selected, rotation: rotation); syncLiveReadiness()
        case .analysis(let result):
            guard screenActive, motion.stable, engine.analyzer.isCurrent(result.revision) else { return }
            analysis = result; PerformanceMonitor.shared.record(result)
        case .failure(let text):
            message = text
            if pendingData == nil { saving = false; endBackgroundTask() }
            syncLiveReadiness()
        case .captured(let bytes): pendingData = bytes; persistPending()
        case .sceneChanged: live.sceneChanged()
        case .preview(let id, let result): live.receive(id: id, result: result)
        }
    }
    private func persistPending() {
        guard let data = pendingData else { return }
        saving = true
        Task {
            do {
                let record = try await PhotoStore.shared.saveOriginal(data)
                records.insert(record, at: 0)
                pendingData = nil; hasUnsavedOriginal = false
                status = "原图已保存在本机 · \(records.count) 张"
            } catch {
                hasUnsavedOriginal = true
                message = "原图尚未写入磁盘：\(error.localizedDescription)。请释放空间后重试，暂勿关闭 App"
            }
            saving = false; endBackgroundTask(); syncLiveReadiness()
        }
    }
    private func endBackgroundTask() {
        if backgroundTask != .invalid { UIApplication.shared.endBackgroundTask(backgroundTask); backgroundTask = .invalid }
    }
    private func syncLiveReadiness() {
        live.setAvailability(cameraReady: screenActive && ready && !saving && !hasUnsavedOriginal,
                             stable: motion.available && motion.stable)
    }
}
