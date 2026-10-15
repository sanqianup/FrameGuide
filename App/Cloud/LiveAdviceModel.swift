import SwiftUI

struct LiveUploadConfirmation: Identifiable {
    let ticket: LiveRequestGate.Ticket
    let sample: PreviewSample
    let config: RemoteConfiguration
    var id: UUID { ticket.id }
}

/// Manual live-frame advice only. No automatic upload and no dependence from shutter to network.
@MainActor
final class LiveAdviceModel: ObservableObject {
    @Published private(set) var phase = LiveRequestGate.Phase.idle
    @Published private(set) var cloudText: String?
    @Published private(set) var cloudModel = ""
    @Published private(set) var status = "尚无云端建议 · 本地 Vision 独立运行"
    @Published private(set) var cooldownSeconds = 0
    @Published var confirmation: LiveUploadConfirmation?
    @Published var message: String?
    var onSample: ((UUID) -> Void)?
    var onCancelSample: ((UUID) -> Void)?
    private var gate = LiveRequestGate()
    private var available = false
    private var stable = false
    private var uploadsAllowed = false
    private var requestTask: Task<Void, Never>?
    private var sampleTimeout: Task<Void, Never>?
    private var frozenConfiguration: RemoteConfiguration?
    var configured: Bool {
        let config = RemoteConfiguration.load(.vision)
        guard let url = try? config.validate() else { return false }
        return SecretStore.hasKey(.vision, endpoint: url)
    }
    var canPrepare: Bool {
        available && stable && uploadsAllowed && configured && phase == .idle && cooldownSeconds == 0
    }
    var availabilityText: String {
        if !uploadsAllowed { return "云端关闭：请在设置中允许手动请求" }
        if !configured { return "MiMo / 看图服务未启用或未保存此主机的密钥" }
        if !available { return "等待相机就绪" }
        if !stable { return "请先稳住手机，暂不取样" }
        if cooldownSeconds > 0 { return "请求间隔还剩 \(cooldownSeconds) 秒" }
        return status
    }
    func setScene(lens: String, rotation: Int) {
        guard gate.scene.lens != lens || gate.scene.rotation != rotation else { return }
        invalidate("镜头或方向变化，云端旧建议已清除", lens: lens, rotation: rotation)
    }
    func setAvailability(cameraReady: Bool, stable: Bool) {
        let lost = (available && !cameraReady) || (self.stable && !stable)
        available = cameraReady; self.stable = stable
        if lost { invalidate("画面移动或相机暂停，请稳定后重新分析") }
        objectWillChange.send()
    }
    func setUploadsAllowed(_ value: Bool) {
        uploadsAllowed = value
        if !value { invalidate("照片上传已关闭") }
        objectWillChange.send()
    }
    func sceneChanged() { invalidate("画面亮度/布局已变化，旧云端建议已清除") }
    func prepare() {
        tick()
        guard canPrepare else { message = availabilityText; return }
        guard let ticket = gate.begin(now: now, eligible: available && stable && uploadsAllowed) else { return }
        frozenConfiguration = RemoteConfiguration.load(.vision)
        cloudText = nil; phase = gate.phase; status = "正在本机采样，尚未上传"
        sampleTimeout?.cancel()
        sampleTimeout = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 2_800_000_000)
            guard !Task.isCancelled, let self, self.gate.ticket == ticket, self.phase == .sampling else { return }
            self.invalidate("取样超时，未上传；请重新尝试")
        }
        onSample?(ticket.id)
    }
    func receive(id: UUID, result: Result<PreviewSample, PreviewSampleError>) {
        guard let ticket = gate.ticket, ticket.id == id, phase == .sampling else { return }
        sampleTimeout?.cancel(); sampleTimeout = nil
        switch result {
        case .failure:
            invalidate("相机状态或画面已变化，未上传；请重新取样")
        case .success(let sample):
            guard available, stable, uploadsAllowed, let config = frozenConfiguration,
                  sample.capturedAt >= ticket.created, gate.sampled(ticket, now: now) else {
                invalidate("样本已过期，未上传"); return
            }
            confirmation = LiveUploadConfirmation(ticket: ticket, sample: sample, config: config)
            phase = gate.phase; status = "请确认这张冻结预览；尚未上传"
        }
    }
    /// Only the confirmation sheet's explicit button may call this method.
    func confirm(_ item: LiveUploadConfirmation) {
        guard uploadsAllowed, available, stable,
              let url = try? item.config.validate(), SecretStore.hasKey(.vision, endpoint: url),
              gate.confirm(item.ticket, now: now, eligible: available && stable && uploadsAllowed) else {
            invalidate("确认期间画面或配置已失效，未上传"); return
        }
        confirmation = nil; frozenConfiguration = nil
        phase = gate.phase; tick(); status = "云端请求中 · 可正常取景和拍摄"
        requestTask = Task { [weak self] in
            guard let self else { return }
            let started = self.now
            defer {
                self.gate.finish(item.ticket)
                self.phase = self.gate.phase
            }
            do {
                let result = try await RemoteClient.shared.advice(jpeg: item.sample.jpeg, config: item.config)
                guard !Task.isCancelled, self.uploadsAllowed, self.available, self.stable,
                      self.gate.accepts(item.ticket, now: self.now) else {
                    PerformanceMonitor.shared.discardedResponses += 1
                    if self.gate.ticket == item.ticket { self.status = "云端返回已过期，未显示；请重新分析" }
                    return
                }
                self.cloudText = result.advice; self.cloudModel = item.config.model
                self.responseCreatedAt = item.ticket.created
                self.status = "云端建议仅对应刚才确认的画面 · 参数未应用到相机"
                PerformanceMonitor.shared.cloudMS = (self.now - started) * 1000
            } catch {
                guard !Task.isCancelled, self.gate.accepts(item.ticket, now: self.now) else {
                    PerformanceMonitor.shared.discardedResponses += 1
                    if self.gate.ticket == item.ticket { self.status = "云端请求已取消或超过画面有效期；本地功能继续" }
                    return
                }
                self.status = "云端失败，本地 Vision 与拍摄继续可用"
                self.message = error.localizedDescription
                PerformanceMonitor.shared.cloudMS = (self.now - started) * 1000
            }
        }
    }
    func dismissedConfirmation() {
        if phase == .confirming { invalidate("已取消，未上传") }
    }
    func cancel() { invalidate("已停止云端分析；本地取景继续") }
    func tick() {
        let seconds = Int(ceil(gate.remainingCooldown(now: now)))
        if seconds != cooldownSeconds { cooldownSeconds = seconds }
        if phase == .confirming, let ticket = gate.ticket, now - ticket.created > 15 {
            invalidate("冻结预览已过期，未上传；请重新取样")
        }
        if cloudText != nil, let timestamp = responseCreatedAt, now - timestamp > 30 {
            cloudText = nil; status = "云端建议已过期，请重新分析"
        }
    }
    private var responseCreatedAt: Double?
    private var now: Double { ProcessInfo.processInfo.systemUptime }
    func invalidate(_ reason: String, lens: String? = nil, rotation: Int? = nil) {
        if let ticket = gate.ticket { onCancelSample?(ticket.id) }
        sampleTimeout?.cancel(); sampleTimeout = nil
        requestTask?.cancel(); requestTask = nil
        gate.invalidate(lens: lens ?? gate.scene.lens, rotation: rotation ?? gate.scene.rotation)
        confirmation = nil; frozenConfiguration = nil; cloudText = nil; responseCreatedAt = nil
        phase = gate.phase; status = reason
    }
}
