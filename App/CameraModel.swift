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
    @Published var selectionArmed = false
    @Published var guidedMode = false
    @Published var guideStatus = "点选主体后，显示本地构图目标"
    @Published var zoomRatio = 1.0
    private var freshness = TrackingFreshness()
    private var trackingWatchdog: Task<Void, Never>?
    private var wasAligned = false
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
            if !value { self.analysis = nil; self.clearGuideUI("移动中 · 稳定后请重新点选主体") }
            self.syncLiveReadiness()
        }
        live.onSample = { [weak self] id in self?.engine.samplePreview(id: id) }
        live.onCancelSample = { [weak self] id in self?.engine.analyzer.cancelPreview(id: id) }
        engine.onEvent = { [weak self] event in self?.handle(event) }
    }
    func active(_ value: Bool) {
        screenActive = value
        UIApplication.shared.isIdleTimerDisabled = value
        if value {
            engine.start(); motion.start()
            if trackingWatchdog == nil {
                trackingWatchdog = Task { [weak self] in
                    while !Task.isCancelled {
                        try? await Task.sleep(nanoseconds: 300_000_000)
                        guard !Task.isCancelled else { return }
                        self?.expireTracking()
                    }
                }
            }
        } else {
            trackingWatchdog?.cancel(); trackingWatchdog = nil
            engine.stop(); motion.stop(); analysis = nil; ready = false; clearGuideUI("取景暂停")
        }
        syncLiveReadiness()
    }
    func setRotation(_ angle: CGFloat, quarter: Int) {
        guard rotation != Int(angle) else { return }
        exitGuidance(reason: "方向变化 · 请重新点选主体")
        rotation = Int(angle)
        live.setScene(lens: selectedLens, rotation: rotation)
        engine.setRotation(angle); motion.setQuarterTurns(quarter)
        syncLiveReadiness()
    }
    func switchLens(_ id: String) {
        guard screenActive, canCapture, id != selectedLens, lenses.contains(where: { $0.id == id }) else { return }
        live.invalidate("正在切换镜头，旧建议已清除", lens: id, rotation: rotation)
        analysis = nil; clearGuideUI("镜头切换 · 请重新点选主体"); engine.analyzer.clearSelection()
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
    func armSelection() {
        guard canCapture, motion.stable else { guideStatus = "先稳住手机，再点选主体"; return }
        exitGuidance(reason: "轻点画面中的主体 · 同时对焦")
        selectionArmed = true
    }
    func selectSubject(at point: CGPoint) {
        guard selectionArmed, canCapture, motion.stable else { return }
        live.invalidate("已选择新主体，旧云端建议已清除")
        analysis = nil; selectionArmed = false; guidedMode = true; wasAligned = false
        freshness = TrackingFreshness()
        let now = ProcessInfo.processInfo.systemUptime
        freshness.accept(captured: now, now: now)
        guideStatus = "本机区域追踪准备中 · 请稳住"
        engine.analyzer.selectSubject(x: Double(point.x), y: Double(point.y))
    }
    func exitGuidance(reason: String = "已退出构图引导 · 可自由拍摄") {
        engine.analyzer.clearSelection(); analysis = nil; clearGuideUI(reason)
        live.invalidate("构图状态已变化，旧云端建议已清除")
    }
    func applySuggestedZoom() {
        guard canCapture, motion.stable, guidedMode, let factor = analysis?.guided?.relativeZoom else { return }
        exitGuidance(reason: "已请求数字放大 · 稳定后请重新选主体")
        engine.zoom(by: factor)
    }
    func resetZoom() {
        guard canCapture, zoomRatio > 1.01 else { return }
        exitGuidance(reason: "已请求还原画幅 · 请重新选主体")
        engine.zoom(by: 1 / zoomRatio)
    }
    private func clearGuideUI(_ text: String) {
        selectionArmed = false; guidedMode = false; wasAligned = false; guideStatus = text
    }
    private func expireTracking() {
        guard guidedMode, freshness.expired(now: ProcessInfo.processInfo.systemUptime) else { return }
        exitGuidance(reason: "追踪已过期 · 请重新点选主体")
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
            if !enabled { analysis = nil; clearGuideUI("相机暂停 · 请重新点选主体") }
            else { live.setScene(lens: selectedLens, rotation: rotation) }
            syncLiveReadiness()
        case .lenses(let options, let selected):
            lenses = options; selectedLens = selected; analysis = nil
            live.setScene(lens: selected, rotation: rotation); syncLiveReadiness()
        case .analysis(let result):
            guard screenActive, motion.stable, engine.analyzer.isCurrent(result.revision) else { return }
            if guidedMode {
                guard result.guided != nil else {
                    exitGuidance(reason: "分析配置变化 · 请重新点选主体"); return
                }
                guard freshness.accept(captured: result.capturedAt, now: ProcessInfo.processInfo.systemUptime) else {
                    exitGuidance(reason: "追踪返回过期 · 请重新点选主体"); return
                }
                if let guide = result.guided {
                    guideStatus = guide.aligned ? "构图到位 · 可以拍摄（水平独立校正）" : guide.direction.text
                    if guide.aligned && !wasAligned { UINotificationFeedbackGenerator().notificationOccurred(.success) }
                    wasAligned = guide.aligned
                }
            }
            analysis = result; PerformanceMonitor.shared.record(result)
        case .failure(let text):
            message = text
            if pendingData == nil { saving = false; endBackgroundTask() }
            syncLiveReadiness()
        case .captured(let bytes): pendingData = bytes; persistPending()
        case .sceneChanged: live.sceneChanged()
        case .preview(let id, let result): live.receive(id: id, result: result)
        case .trackingLost(let revision):
            guard engine.analyzer.isCurrent(revision) else { return }
            analysis = nil; clearGuideUI("主体追踪丢失 · 请重新点选")
            live.invalidate("主体追踪丢失，旧云端建议已清除")
        case .zoom(let value): zoomRatio = value
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
