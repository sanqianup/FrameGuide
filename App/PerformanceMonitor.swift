import SwiftUI

@MainActor
final class PerformanceMonitor: ObservableObject {
    static let shared = PerformanceMonitor()
    @Published var analysisMS: Double?
    @Published var guidanceIntervalMS: Double?
    @Published var deliveredFPS: Double?
    @Published var cloudMS: Double?
    @Published var discardedResponses = 0
    @Published var heat = "未采样"
    func record(_ result: AnalysisResult) {
        analysisMS = result.durationMS; guidanceIntervalMS = result.intervalMS
        deliveredFPS = result.deliveredFPS
        switch ProcessInfo.processInfo.thermalState {
        case .nominal: heat = "正常"
        case .fair: heat = "温热"
        case .serious: heat = "较热 · 分析降频"
        case .critical: heat = "过热 · 暂停"
        @unknown default: heat = "未知"
        }
    }
}
