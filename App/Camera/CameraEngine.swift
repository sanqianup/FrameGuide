import AVFoundation
import UIKit

struct Lens: Identifiable, Equatable {
    let id: String
    let title: String
    let front: Bool
}

enum CameraEvent {
    case state(String, ready: Bool)
    case lenses([Lens], selected: String)
    case captured(Data)
    case analysis(AnalysisResult)
    case failure(String)
    case sceneChanged(Int)
    case preview(UUID, Result<PreviewSample, PreviewSampleError>)
}

/// All session/device/photo mutation is confined to sessionQueue.
/// Events are delivered on main. Never call startRunning on main.
final class CameraEngine: NSObject {
    let session = AVCaptureSession()
    let analyzer = FrameAnalyzer()
    var onEvent: ((CameraEvent) -> Void)?
    private let sessionQueue = DispatchQueue(label: "camera.session", qos: .userInitiated)
    private let photoOutput = AVCapturePhotoOutput()
    private let videoOutput = AVCaptureVideoDataOutput()
    private var input: AVCaptureDeviceInput?
    private var devices: [AVCaptureDevice] = []
    private var observers: [NSObjectProtocol] = []
    private var configured = false
    private var startIntent = CameraStartIntent()
    private var desiredRunning: Bool { startIntent.wantsRunning }
    private var interrupted = false
    private var capturing = false
    private var captureID: Int64?
    private var angle: CGFloat = 90
    private var memoryPressure = false
    private var recoveryCount = 0
    private var policy = AnalysisPolicy.make(heat: .nominal, lowPower: false, memoryPressure: false)

    override init() {
        super.init()
        analyzer.onResult = { [weak self] result in self?.emit(.analysis(result)) }
        analyzer.onSceneChange = { [weak self] revision in self?.emit(.sceneChanged(revision)) }
        analyzer.onPreview = { [weak self] id, result in self?.emit(.preview(id, result)) }
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: AVCaptureSession.wasInterruptedNotification, object: session, queue: nil) { [weak self] _ in
            guard let self else { return }
            self.sessionQueue.async {
                self.interrupted = true; self.refreshAnalysis()
                self.emit(.state("相机被系统中断 · 等待恢复", ready: false))
            }
        })
        observers.append(center.addObserver(forName: AVCaptureSession.interruptionEndedNotification, object: session, queue: nil) { [weak self] _ in
            guard let self else { return }
            self.sessionQueue.async { self.interrupted = false; self.resumeIfNeeded() }
        })
        observers.append(center.addObserver(forName: AVCaptureSession.runtimeErrorNotification, object: session, queue: nil) { [weak self] note in
            guard let self else { return }
            let error = note.userInfo?[AVCaptureSessionErrorKey] as? AVError
            self.sessionQueue.async {
                self.refreshAnalysis(forceOff: true)
                if self.capturing {
                    self.capturing = false; self.captureID = nil
                    self.emit(.failure("相机服务中断，此次拍摄未确认完成"))
                }
                if error?.code == .mediaServicesWereReset && self.recoveryCount < 2 {
                    self.recoveryCount += 1
                    self.resumeIfNeeded()
                } else {
                    self.emit(.state("相机服务异常，请点重试或重新打开 App", ready: false))
                }
            }
        })
        for name in [ProcessInfo.thermalStateDidChangeNotification, .NSProcessInfoPowerStateDidChange] {
            observers.append(center.addObserver(forName: name, object: nil, queue: nil) { [weak self] _ in self?.refreshPolicy() })
        }
        observers.append(center.addObserver(forName: UIApplication.didReceiveMemoryWarningNotification, object: nil, queue: nil) { [weak self] _ in
            guard let self else { return }
            self.sessionQueue.async {
                self.memoryPressure = true
                self.updatePolicy()
            }
        })
    }
    deinit { observers.forEach { NotificationCenter.default.removeObserver($0) } }

    func start() {
        sessionQueue.async {
            switch AVCaptureDevice.authorizationStatus(for: .video) {
            case .authorized:
                _ = self.startIntent.start(needsPermission: false)
                self.startAuthorizedOnQueue()
            case .notDetermined:
                guard self.startIntent.start(needsPermission: true) else { return }
                AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                    guard let self else { return }
                    self.sessionQueue.async {
                        if self.startIntent.resolved(granted: granted) { self.startAuthorizedOnQueue() }
                        else if !granted { self.permissionDeniedOnQueue() }
                    }
                }
            default:
                self.permissionDeniedOnQueue()
            }
        }
    }
    private func startAuthorizedOnQueue() {
        guard desiredRunning else { return }
        do {
            if !configured { try configure() }
            updatePolicy(); resumeIfNeeded()
        } catch { emit(.state("相机初始化失败：\(error.localizedDescription)", ready: false)) }
    }
    private func permissionDeniedOnQueue() {
        startIntent.stop(); refreshAnalysis(forceOff: true)
        if session.isRunning { session.stopRunning() }
        emit(.state("相机权限未开启，请在设置中允许", ready: false))
    }
    func stop() {
        sessionQueue.async {
            self.startIntent.stop()
            self.refreshAnalysis(forceOff: true)
            if self.session.isRunning { self.session.stopRunning() }
            self.emit(.state("相机已暂停", ready: false))
        }
    }
    func setRotation(_ degrees: CGFloat) {
        sessionQueue.async {
            guard self.angle != degrees else { return }
            self.angle = degrees
            // Keep photo orientation fixed for the entire capture; apply the latest later.
            if !self.capturing { self.applyRotation() }
            self.refreshAnalysis()
        }
    }
    func switchLens(_ id: String) {
        sessionQueue.async {
            guard self.configured, !self.capturing, self.desiredRunning, !self.interrupted,
                  let device = self.devices.first(where: { $0.uniqueID == id }),
                  device.uniqueID != self.input?.device.uniqueID else { return }
            self.emit(.state("切换镜头…", ready: false))
            self.refreshAnalysis(forceOff: true)
            do {
                let next = try AVCaptureDeviceInput(device: device)
                let previous = self.input
                self.session.beginConfiguration()
                if let previous { self.session.removeInput(previous) }
                if self.session.canAddInput(next) {
                    self.session.addInput(next); self.input = next
                } else if let previous, self.session.canAddInput(previous) {
                    self.session.addInput(previous)
                }
                self.session.commitConfiguration()
                self.configurePhotoDimensions()
                self.applyRotation()
                self.emitLenses()
                self.resumeIfNeeded()
            } catch {
                self.emit(.failure("镜头切换失败：\(error.localizedDescription)"))
                self.resumeIfNeeded()
            }
        }
    }
    func focus(at point: CGPoint) {
        sessionQueue.async {
            guard let device = self.input?.device, !self.capturing else { return }
            do {
                try device.lockForConfiguration()
                defer { device.unlockForConfiguration() }
                if device.isFocusPointOfInterestSupported {
                    device.focusPointOfInterest = point
                    if device.isFocusModeSupported(.autoFocus) { device.focusMode = .autoFocus }
                }
                if device.isExposurePointOfInterestSupported {
                    device.exposurePointOfInterest = point
                    if device.isExposureModeSupported(.continuousAutoExposure) { device.exposureMode = .continuousAutoExposure }
                }
            } catch { self.emit(.failure("暂时无法对焦")) }
        }
    }
    func capture() {
        sessionQueue.async {
            guard self.session.isRunning, self.desiredRunning, !self.interrupted,
                  !self.capturing, self.policy.mayCapture else {
                self.emit(.failure("相机状态已变化，此次未拍摄，请等待就绪后重试")); return
            }
            self.capturing = true
            self.refreshAnalysis(forceOff: true)
            self.emit(.state("拍摄中…", ready: false))
            let settings: AVCapturePhotoSettings
            if self.photoOutput.availablePhotoCodecTypes.contains(.hevc) {
                settings = AVCapturePhotoSettings(format: [AVVideoCodecKey: AVVideoCodecType.hevc])
            } else { settings = AVCapturePhotoSettings() }
            settings.maxPhotoDimensions = self.photoOutput.maxPhotoDimensions
            settings.photoQualityPrioritization = .balanced
            self.captureID = settings.uniqueID
            self.photoOutput.capturePhoto(with: settings, delegate: self)
        }
    }
    func samplePreview(id: UUID) {
        sessionQueue.async {
            guard self.desiredRunning, self.session.isRunning, !self.capturing, !self.interrupted, self.policy.mayCapture else {
                self.emit(.preview(id, .failure(.unavailable))); return
            }
            self.analyzer.requestPreview(id: id)
        }
    }
    private func configure() throws {
        devices = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInUltraWideCamera, .builtInWideAngleCamera, .builtInTelephotoCamera, .builtInTrueDepthCamera],
            mediaType: .video, position: .unspecified).devices
        guard let device = devices.first(where: { $0.position == .back && $0.deviceType == .builtInWideAngleCamera })
            ?? devices.first else { throw CameraError.unavailable }
        let first = try AVCaptureDeviceInput(device: device)
        session.beginConfiguration()
        defer { session.commitConfiguration() }
        session.sessionPreset = .photo
        guard session.canAddInput(first), session.canAddOutput(photoOutput), session.canAddOutput(videoOutput) else {
            throw CameraError.unavailable
        }
        session.addInput(first); input = first
        session.addOutput(photoOutput)
        session.addOutput(videoOutput)
        videoOutput.alwaysDiscardsLateVideoFrames = true
        videoOutput.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarFullRange]
        videoOutput.automaticallyConfiguresOutputBufferDimensions = false
        videoOutput.deliversPreviewSizedOutputBuffers = true
        videoOutput.setSampleBufferDelegate(analyzer, queue: analyzer.queue)
        photoOutput.maxPhotoQualityPrioritization = .balanced
        configurePhotoDimensions()
        applyRotation()
        configured = true
        emitLenses()
    }
    private func configurePhotoDimensions() {
        guard let device = input?.device else { return }
        let dimensions = device.activeFormat.supportedMaxPhotoDimensions
        // Favor normal ~12MP capture latency and memory use. This is HEIC/JPEG, not RAW.
        let selected = dimensions.filter { Int64($0.width) * Int64($0.height) <= 13_000_000 }
            .max { Int64($0.width) * Int64($0.height) < Int64($1.width) * Int64($1.height) }
            ?? dimensions.min { Int64($0.width) * Int64($0.height) < Int64($1.width) * Int64($1.height) }
        if let selected { photoOutput.maxPhotoDimensions = selected }
        if device.activeFormat.videoSupportedFrameRateRanges.contains(where: { $0.minFrameRate <= 30 && $0.maxFrameRate >= 30 }) {
            do {
                try device.lockForConfiguration()
                defer { device.unlockForConfiguration() }
                device.activeVideoMinFrameDuration = CMTime(value: 1, timescale: 30)
                device.activeVideoMaxFrameDuration = CMTime(value: 1, timescale: 30)
            } catch { /* Keep system-selected cadence if the device rejects this preference. */ }
        }
    }
    private func applyRotation() {
        for output in [videoOutput as AVCaptureOutput, photoOutput as AVCaptureOutput] {
            if let connection = output.connection(with: .video) {
                if connection.isVideoRotationAngleSupported(angle) { connection.videoRotationAngle = angle }
                if connection.isVideoMirroringSupported {
                    connection.automaticallyAdjustsVideoMirroring = false
                    connection.isVideoMirrored = false // original is never mirrored
                }
            }
        }
    }
    private func emitLenses() {
        let lenses = devices.map { device in
            let title: String
            if device.position == .front { title = "前置" }
            else if device.deviceType == .builtInUltraWideCamera { title = "超广角" }
            else if device.deviceType == .builtInTelephotoCamera { title = "长焦" }
            else { title = "主摄" }
            return Lens(id: device.uniqueID, title: title, front: device.position == .front)
        }
        emit(.lenses(lenses, selected: input?.device.uniqueID ?? ""))
    }
    private func refreshAnalysis(forceOff: Bool = false) {
        analyzer.configure(enabled: !forceOff && desiredRunning && session.isRunning && !capturing && !interrupted && policy.mayCapture,
                           mirrored: input?.device.position == .front, policy: policy)
    }
    private func refreshPolicy() { sessionQueue.async { self.updatePolicy(); self.resumeIfNeeded() } }
    private func updatePolicy() {
        let heat: Heat
        switch ProcessInfo.processInfo.thermalState {
        case .nominal: heat = .nominal
        case .fair: heat = .fair
        case .serious: heat = .serious
        case .critical: heat = .critical
        @unknown default: heat = .serious
        }
        policy = .make(heat: heat, lowPower: ProcessInfo.processInfo.isLowPowerModeEnabled, memoryPressure: memoryPressure)
        refreshAnalysis()
    }
    private func resumeIfNeeded() {
        guard desiredRunning, configured else { return }
        guard !interrupted, !capturing else { return }
        guard policy.mayCapture else {
            if session.isRunning { session.stopRunning() }
            refreshAnalysis(forceOff: true)
            emit(.state("设备过热 · 降温后自动恢复", ready: false)); return
        }
        if !session.isRunning { session.startRunning() }
        refreshAnalysis()
        emit(.state(session.isRunning ? "就绪 · App 不自动向模型上传照片" : "相机启动失败，请重试", ready: session.isRunning && !capturing))
    }
    private func emit(_ event: CameraEvent) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            if case .analysis(let result) = event, !self.analyzer.isCurrent(result.revision) { return }
            if case .sceneChanged(let revision) = event, !self.analyzer.isCurrent(revision) { return }
            if case .preview(let id, .success(let sample)) = event, !self.analyzer.isCurrent(sample.revision) {
                self.onEvent?(.preview(id, .failure(.invalidated))); return
            }
            self.onEvent?(event)
        }
    }
    enum CameraError: LocalizedError {
        case unavailable
        var errorDescription: String? { "没有可用的相机输入或输出" }
    }
}

extension CameraEngine: AVCapturePhotoCaptureDelegate {
    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        let bytes = error == nil ? photo.fileDataRepresentation() : nil
        let resolvedID = photo.resolvedSettings.uniqueID
        sessionQueue.async {
            guard self.captureID == resolvedID else { return }
            if let error { self.emit(.failure("拍摄失败：\(error.localizedDescription)")); return }
            guard let bytes else { self.emit(.failure("未收到完整原图")); return }
            self.emit(.captured(bytes)) // bytes are persisted without decoding or re-encoding
        }
    }
    func photoOutput(_ output: AVCapturePhotoOutput, didFinishCaptureFor resolvedSettings: AVCaptureResolvedPhotoSettings, error: Error?) {
        sessionQueue.async {
            guard self.captureID == resolvedSettings.uniqueID else { return }
            self.captureID = nil
            self.capturing = false
            self.applyRotation()
            if let error { self.emit(.failure("拍摄未完成：\(error.localizedDescription)")) }
            self.resumeIfNeeded()
        }
    }
}
