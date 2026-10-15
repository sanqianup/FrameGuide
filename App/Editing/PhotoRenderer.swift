import CoreImage
import CoreImage.CIFilterBuiltins
import ImageIO
import UniformTypeIdentifiers

actor PhotoRenderer {
    static let shared = PhotoRenderer()
    private let context = CIContext(options: [.cacheIntermediates: false])

    func render(url: URL, recipe: ToneRecipe, maxDimension: CGFloat? = nil) throws -> Data {
        guard recipe.isSafe, let input = CIImage(contentsOf: url, options: [.applyOrientationProperty: true]) else {
            throw RenderError.failed
        }
        return try render(input, recipe: recipe, maxDimension: maxDimension)
    }
    private func render(_ input: CIImage, recipe: ToneRecipe, maxDimension: CGFloat?) throws -> Data {
        var image = input
        if let maximum = maxDimension, max(image.extent.width, image.extent.height) > maximum {
            let scale = maximum / max(image.extent.width, image.extent.height)
            image = image.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        }
        let exposure = CIFilter.exposureAdjust(); exposure.inputImage = image; exposure.ev = Float(recipe.exposureEV)
        let controls = CIFilter.colorControls(); controls.inputImage = exposure.outputImage
        controls.saturation = Float(recipe.saturation); controls.contrast = Float(recipe.contrast)
        let temperature = CIFilter.temperatureAndTint(); temperature.inputImage = controls.outputImage
        temperature.neutral = CIVector(x: 6500, y: 0)
        temperature.targetNeutral = CIVector(x: 6500 + recipe.warmth * 1800, y: 0)
        guard let output = temperature.outputImage?.cropped(to: image.extent),
              let space = CGColorSpace(name: CGColorSpace.sRGB),
              let data = context.jpegRepresentation(of: output, colorSpace: space,
                   options: [CIImageRepresentationOption(rawValue: kCGImageDestinationLossyCompressionQuality as String): 0.94]) else {
            throw RenderError.failed
        }
        return data
    }
    /// Downsampling strips EXIF/GPS before any explicitly confirmed remote upload.
    func uploadPreview(url: URL) throws -> Data {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: 1024
              ] as CFDictionary) else { throw RenderError.failed }
        let bytes = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(bytes, UTType.jpeg.identifier as CFString, 1, nil) else { throw RenderError.failed }
        // Rebuild from CGImage pixels with no source properties. Never copy EXIF/GPS/IPTC.
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: 0.88] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw RenderError.failed }
        return bytes as Data
    }
    func clearCaches() { context.clearCaches() }
    enum RenderError: LocalizedError {
        case failed
        var errorDescription: String? { "本地调色失败，原图保持可用" }
    }
}
