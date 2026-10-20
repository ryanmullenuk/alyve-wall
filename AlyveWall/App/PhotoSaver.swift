import Foundation
import Photos

enum PhotoSaver {
    enum SaveError: LocalizedError {
        case denied
        var errorDescription: String? {
            "ALYVE WALL needs permission to add to your Photos. You can allow it in Settings › Apps › ALYVE WALL › Photos."
        }
    }

    private static func authorise() async throws {
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else { throw SaveError.denied }
    }

    static func saveVideo(_ url: URL) async throws {
        try await authorise()
        try await PHPhotoLibrary.shared().performChanges {
            PHAssetCreationRequest.forAsset().addResource(with: .video, fileURL: url, options: nil)
        }
    }

    static func saveImage(_ url: URL) async throws {
        try await authorise()
        try await PHPhotoLibrary.shared().performChanges {
            PHAssetCreationRequest.forAsset().addResource(with: .photo, fileURL: url, options: nil)
        }
    }

    static func saveLivePhoto(photo: URL, video: URL) async throws {
        try await authorise()
        try await PHPhotoLibrary.shared().performChanges {
            let request = PHAssetCreationRequest.forAsset()
            request.addResource(with: .photo, fileURL: photo, options: nil)
            request.addResource(with: .pairedVideo, fileURL: video, options: nil)
        }
    }
}
