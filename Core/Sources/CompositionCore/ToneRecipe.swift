import Foundation

/// Restricted, local pixel-preserving color controls. Never geometry, retouching or generation.
public struct ToneRecipe: Codable, Equatable, Sendable {
    public var exposureEV: Double
    public var saturation: Double
    public var warmth: Double
    public var contrast: Double
    public init(exposureEV: Double = 0, saturation: Double = 1, warmth: Double = 0, contrast: Double = 1) {
        self.exposureEV = exposureEV; self.saturation = saturation
        self.warmth = warmth; self.contrast = contrast
    }
    public static let natural = ToneRecipe(exposureEV: 0.08, saturation: 1.025, warmth: 0.025, contrast: 1.015)
    public var isSafe: Bool {
        [exposureEV, saturation, warmth, contrast].allSatisfy(\.isFinite)
            && (-0.5...0.5).contains(exposureEV) && (0.85...1.15).contains(saturation)
            && (-0.15...0.15).contains(warmth) && (0.9...1.1).contains(contrast)
    }
}

public struct VisionAdvice: Codable, Equatable, Sendable {
    public let advice: String
    public let tone: ToneRecipe
    public static func decode(_ data: Data) throws -> Self {
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              Set(object.keys) == Set(["advice", "tone"]),
              let tone = object["tone"] as? [String: Any],
              Set(tone.keys) == Set(["exposureEV", "saturation", "warmth", "contrast"]) else { throw AdviceError.invalid }
        let result = try JSONDecoder().decode(Self.self, from: data)
        guard result.tone.isSafe, !result.advice.isEmpty, result.advice.count <= 250 else { throw AdviceError.invalid }
        return result
    }
    public enum AdviceError: Error { case invalid }
}
