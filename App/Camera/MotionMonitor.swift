import CoreMotion
import SwiftUI

@MainActor
final class MotionMonitor: ObservableObject {
    @Published private(set) var angle: Double?
    @Published private(set) var stable = false
    @Published private(set) var available = true
    var onStability: ((Bool) -> Void)?
    private let motion = CMMotionManager()
    private let queue: OperationQueue = {
        let q = OperationQueue(); q.name = "camera.motion"; q.maxConcurrentOperationCount = 1
        q.qualityOfService = .utility; return q
    }()
    private var quarterTurns = 0
    private var raw: Double?
    private var stillSamples = 0
    private var active = false
    private var epoch = 0

    func start() {
        guard !active else { return }; active = true; epoch += 1
        let revision = epoch
        guard motion.isDeviceMotionAvailable else {
            available = false; stable = true; onStability?(true); return
        }
        motion.deviceMotionUpdateInterval = 1.0 / 15
        motion.startDeviceMotionUpdates(to: queue) { [weak self] sample, _ in
            guard let sample else { return }
            let gx = sample.gravity.x, gy = sample.gravity.y
            let speed = sqrt(pow(sample.rotationRate.x, 2) + pow(sample.rotationRate.y, 2) + pow(sample.rotationRate.z, 2))
            let acceleration = sqrt(pow(sample.userAcceleration.x, 2) + pow(sample.userAcceleration.y, 2) + pow(sample.userAcceleration.z, 2))
            Task { @MainActor [weak self] in
                guard let self, self.active, self.epoch == revision else { return }
                self.raw = LevelMath.angle(gx: gx, gy: gy, clockwiseQuarterTurns: self.quarterTurns)
                let zero = UserDefaults.standard.double(forKey: "level.zero.\(self.quarterTurns)")
                self.angle = self.raw.map { LevelMath.relative($0, zero: zero) }
                if speed < 0.10 && acceleration < 0.035 { self.stillSamples += 1 }
                else { self.stillSamples = 0 }
                let value = self.stillSamples >= 6
                if value != self.stable { self.stable = value; self.onStability?(value) }
            }
        }
    }
    func stop() {
        active = false; epoch += 1; motion.stopDeviceMotionUpdates()
        angle = nil; stable = false; stillSamples = 0; onStability?(false)
    }
    func setQuarterTurns(_ value: Int) {
        guard value != quarterTurns else { return }
        quarterTurns = value; raw = nil; angle = nil; stillSamples = 0
        stable = false; onStability?(false)
    }
    func calibrate() {
        guard let raw, stable else { return }
        UserDefaults.standard.set(raw, forKey: "level.zero.\(quarterTurns)")
        angle = 0
    }
    func resetCalibration() {
        UserDefaults.standard.removeObject(forKey: "level.zero.\(quarterTurns)")
        angle = raw
    }
}
