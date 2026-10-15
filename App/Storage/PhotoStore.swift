import Foundation
import ImageIO
import Photos
import UniformTypeIdentifiers
import CryptoKit

struct PhotoRecord: Codable, Identifiable, Equatable {
    let id: UUID
    let created: Date
    let filename: String
    let sha256: String
    var originalURL: URL { PhotoStore.root.appendingPathComponent(id.uuidString).appendingPathComponent(filename) }
}

actor PhotoStore {
    static let root = URL.applicationSupportDirectory.appendingPathComponent("FrameGuide/Photos", isDirectory: true)
    static let shared = PhotoStore()

    func saveOriginal(_ data: Data) throws -> PhotoRecord {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let type = CGImageSourceGetType(source) else { throw StoreError.invalidImage }
        let ext = UTType(type as String)?.preferredFilenameExtension ?? "jpg"
        let id = UUID()
        let folder = Self.root.appendingPathComponent(id.uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let record = PhotoRecord(id: id, created: Date(), filename: "original.\(ext)",
                                 sha256: SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined())
        // The original bytes supplied by AVCapturePhoto are never re-encoded or overwritten.
        try data.write(to: record.originalURL, options: [.atomic, .completeFileProtection])
        try JSONEncoder().encode(record).write(to: folder.appendingPathComponent("record.json"), options: [.atomic, .completeFileProtection])
        return record
    }
    func records() throws -> [PhotoRecord] {
        guard FileManager.default.fileExists(atPath: Self.root.path) else { return [] }
        return try FileManager.default.contentsOfDirectory(at: Self.root, includingPropertiesForKeys: nil)
            .compactMap { folder -> PhotoRecord? in
                guard let data = try? Data(contentsOf: folder.appendingPathComponent("record.json")),
                      let record = try? JSONDecoder().decode(PhotoRecord.self, from: data),
                      folder.lastPathComponent == record.id.uuidString,
                      !record.filename.contains("/"), !record.filename.contains("\\"),
                      FileManager.default.fileExists(atPath: record.originalURL.path) else { return nil }
                return record
            }.sorted { $0.created > $1.created }
    }
    func verifiedOriginal(_ record: PhotoRecord) throws -> Data {
        let data = try Data(contentsOf: record.originalURL, options: .mappedIfSafe)
        let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        guard digest == record.sha256 else { throw StoreError.corruptOriginal }
        return data
    }
    func exportOriginal(_ record: PhotoRecord) async throws {
        let bytes = try verifiedOriginal(record)
        try await addToPhotos(bytes, name: record.filename)
    }
    func exportEdited(_ data: Data) async throws {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let type = CGImageSourceGetType(source) else { throw StoreError.invalidImage }
        let ext = UTType(type as String)?.preferredFilenameExtension ?? "jpg"
        try await addToPhotos(data, name: "FrameGuide-edit.\(ext)")
    }
    private func addToPhotos(_ data: Data, name: String) async throws {
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else { throw StoreError.photosDenied }
        try await PHPhotoLibrary.shared().performChanges {
            let request = PHAssetCreationRequest.forAsset()
            let options = PHAssetResourceCreationOptions(); options.originalFilename = name
            request.addResource(with: .photo, data: data, options: options)
        }
    }
    enum StoreError: LocalizedError {
        case invalidImage, corruptOriginal, photosDenied
        var errorDescription: String? {
            switch self {
            case .invalidImage: return "照片数据无法读取"
            case .corruptOriginal: return "原图校验失败，已停止导出"
            case .photosDenied: return "没有相册添加权限；原图仍保存在 App 内，可在系统设置中开启权限后重试"
            }
        }
    }
}
