import AVFoundation
import Vision
import ImageIO
import CoreImage
import UniformTypeIdentifiers

struct PreviewSample {
    let jpeg: Data
    let capturedAt: Double
    let revision: Int
}
enum PreviewSampleError: Error { case unavailable, invalidated, encoding }

struct AnalysisResult {
    let subject: Subject?
    let guidance: Guidance
    let source: String
    let revision: Int
    let durationMS: Double
    let intervalMS: Double?
    let deliveredFPS: Double?
}

/// Delegate work runs on one utility queue. Late buffers are dropped by AVFoundation.
/// No video buffer is retained after this callback. Explicit one-shot JPEGs use a separate consent path.
final class FrameAnalyzer: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    let queue = DispatchQueue(label: "camera.vision", qos: .utility)
    var onResult: ((AnalysisResult) -> Void)?
    var onSceneChange: ((Int) -> Void)?
    var onPreview: ((UUID, Result<PreviewSample, PreviewSampleError>) -> Void)?
    private let lock = NSLock()
    private var validity = AnalysisEpoch()
    private var mirrored = false
    private var policy = AnalysisPolicy.make(heat: .nominal, lowPower: false, memoryPressure: false)
    private var guide = CompositionGuide() // accessed on queue only
    private var gate = FrameGate()
    private var sequence = 0
    private var callbacks = 0
    private var fpsStart = ProcessInfo.processInfo.systemUptime
    private var measuredFPS: Double?
    private var lastAnalysis: Double?
    private var pendingPreview: (id: UUID, revision: Int, deadline: Double)?
    private var sceneGate = FrameGate()
    private var fingerprint = SceneFingerprint()
    private let snapshotContext = CIContext(options: [.cacheIntermediates: false])
    func requestPreview(id: UUID) {
        lock.lock()
        guard let revision = validity.ticket, pendingPreview == nil else {
            lock.unlock(); onPreview?(id, .failure(.unavailable)); return
        }
        pendingPreview = (id, revision, ProcessInfo.processInfo.systemUptime + 2.5)
        lock.unlock()
    }
    func cancelPreview(id: UUID) {
        lock.lock(); if pendingPreview?.id == id { pendingPreview = nil }; lock.unlock()
    }
    func isCurrent(_ revision: Int) -> Bool {
        lock.lock(); defer { lock.unlock() }; return validity.accepts(revision)
    }

    func configure(enabled: Bool, mirrored: Bool, policy: AnalysisPolicy) {
        lock.lock()
        validity.configure(enabled: enabled); self.mirrored = mirrored; self.policy = policy
        let cancelled = pendingPreview?.id; pendingPreview = nil
        lock.unlock()
        if let cancelled { onPreview?(cancelled, .failure(.invalidated)) }
        queue.async {
            self.guide.reset(); self.gate.reset(); self.sequence = 0; self.lastAnalysis = nil
            self.sceneGate.reset(); self.fingerprint.reset(); self.snapshotContext.clearCaches()
        }
    }
    func setStable(_ value: Bool) {
        lock.lock()
        let changed = validity.setStable(value)
        let cancelled = changed ? pendingPreview?.id : nil
        if changed { pendingPreview = nil }
        lock.unlock()
        if let cancelled { onPreview?(cancelled, .failure(.invalidated)) }
        if changed {
            queue.async { self.guide.reset(); self.gate.reset(); self.lastAnalysis = nil }
        }
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        let time = ProcessInfo.processInfo.systemUptime
        callbacks += 1
        if time - fpsStart >= 1 {
            measuredFPS = Double(callbacks) / (time - fpsStart); callbacks = 0; fpsStart = time
        }
        lock.lock()
        let ticket = validity.ticket, mirror = mirrored, p = policy
        lock.unlock()
        guard let revision = ticket, let buffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        if sceneGate.admit(now: time, interval: 0.2), fingerprint.changed(luminance(buffer)) {
            onSceneChange?(revision)
        }
        lock.lock(); let pending = pendingPreview; pendingPreview = nil; lock.unlock()
        if let pending {
            if pending.revision != revision || !isCurrent(revision) || time > pending.deadline {
                onPreview?(pending.id, .failure(.invalidated))
            } else {
                autoreleasepool {
                    guard let jpeg = encodePreview(buffer, mirror: mirror), isCurrent(revision) else {
                        onPreview?(pending.id, .failure(.encoding)); return
                    }
                    onPreview?(pending.id, .success(PreviewSample(jpeg: jpeg, capturedAt: time, revision: revision)))
                }
            }
        }
        guard gate.admit(now: time, interval: p.interval) else { return }
        autoreleasepool {
            let now = ProcessInfo.processInfo.systemUptime
            var subject: Subject?
            var source = "Vision · 人脸 / 人体"
            do {
                // Output buffers have already been physically rotated by videoRotationAngle.
                let handler = VNImageRequestHandler(cvPixelBuffer: buffer, orientation: .up)
                let faces = VNDetectFaceRectanglesRequest()
                let people = VNDetectHumanRectanglesRequest()
                try handler.perform([faces, people])
                let face = faces.results?.filter { $0.confidence >= 0.55 }
                    .max { $0.boundingBox.width * $0.boundingBox.height < $1.boundingBox.width * $1.boundingBox.height }
                let person = people.results?.filter { $0.confidence >= 0.55 }
                    .max { $0.boundingBox.width * $0.boundingBox.height < $1.boundingBox.width * $1.boundingBox.height }
                if let box = face?.boundingBox ?? person?.boundingBox {
                    subject = makeSubject(box, mirror: mirror, confidence: Double(face?.confidence ?? person?.confidence ?? 0))
                } else if p.saliencyEnabled && sequence % 3 == 0 {
                    // Saliency runs at most every third admitted frame (~0.83 Hz nominal).
                    let saliency = VNGenerateAttentionBasedSaliencyImageRequest()
                    try handler.perform([saliency])
                    if let object = saliency.results?.first?.salientObjects?
                        .filter({ $0.confidence >= 0.55 }).max(by: { $0.confidence < $1.confidence }) {
                        subject = makeSubject(object.boundingBox, mirror: mirror, confidence: Double(object.confidence))
                    }
                    source = "Vision · 显著区域（非物体识别）"
                }
            } catch {
                source = "本帧分析不可用"
            }
            sequence += 1
            // Never let an obsolete inference mutate the guide or publish a direction.
            guard isCurrent(revision) else { return }
            let advice = guide.update(subject: subject, stable: true, now: now).cameraAdvice(mirrored: mirror)
            lock.lock(); let valid = validity.accepts(revision); lock.unlock()
            let interval = lastAnalysis.map { (now - $0) * 1000 }
            lastAnalysis = now
            if valid { onResult?(AnalysisResult(subject: subject, guidance: advice, source: source, revision: revision,
                durationMS: (ProcessInfo.processInfo.systemUptime - now) * 1000, intervalMS: interval, deliveredFPS: measuredFPS)) }
        }
    }

    private func makeSubject(_ box: CGRect, mirror: Bool, confidence: Double) -> Subject {
        Subject(x: Double(mirror ? 1 - box.maxX : box.minX), y: Double(1 - box.maxY),
                width: Double(box.width), height: Double(box.height), confidence: confidence)
    }
    private func luminance(_ buffer: CVPixelBuffer) -> [Double] {
        guard CVPixelBufferGetPlaneCount(buffer) > 0 else { return [] }
        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddressOfPlane(buffer, 0) else { return [] }
        let width = CVPixelBufferGetWidthOfPlane(buffer, 0), height = CVPixelBufferGetHeightOfPlane(buffer, 0)
        let stride = CVPixelBufferGetBytesPerRowOfPlane(buffer, 0)
        guard width > 0, height > 0 else { return [] }
        let pixels = base.assumingMemoryBound(to: UInt8.self)
        return (0..<64).map { index in
            let x = min(width - 1, (index % 8 * 2 + 1) * width / 16)
            let y = min(height - 1, (index / 8 * 2 + 1) * height / 16)
            return Double(pixels[y * stride + x]) / 255
        }
    }
    private func encodePreview(_ buffer: CVPixelBuffer, mirror: Bool) -> Data? {
        var image = CIImage(cvPixelBuffer: buffer)
        if mirror { image = image.oriented(.upMirrored) }
        let scale = min(1, 1024 / max(image.extent.width, image.extent.height))
        image = image.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        guard let cg = snapshotContext.createCGImage(image, from: image.extent) else { return nil }
        let bytes = NSMutableData()
        guard let target = CGImageDestinationCreateWithData(bytes, UTType.jpeg.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(target, cg, [kCGImageDestinationLossyCompressionQuality: 0.85] as CFDictionary)
        guard CGImageDestinationFinalize(target) else { return nil }
        return bytes as Data
    }
}
