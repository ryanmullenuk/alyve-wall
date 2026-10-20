import AVFoundation
import CoreGraphics
import CoreVideo
import Foundation
import ImageIO
import UniformTypeIdentifiers

enum DeviceTarget: String, Codable, CaseIterable, Identifiable, Sendable {
    case iphone, mac
    var id: String { rawValue }
    var title: String { self == .iphone ? "iPhone" : "Mac" }
    var symbol: String { self == .iphone ? "iphone" : "desktopcomputer" }
    /// Width ÷ height of the preview.
    var aspect: Double { self == .iphone ? 9.0 / 19.5 : 16.0 / 10.0 }
}

struct ExportSize: Identifiable, Hashable, Sendable {
    let name: String
    let width: Int
    let height: Int
    let premium: Bool
    var id: String { "\(name)-\(width)x\(height)" }
    var label: String { "\(width) × \(height)" }

    static let iphone: [ExportSize] = [
        ExportSize(name: "Standard", width: 720, height: 1280, premium: false),
        ExportSize(name: "Full HD", width: 1080, height: 1920, premium: true),
        ExportSize(name: "iPhone Pro", width: 1206, height: 2622, premium: true),
        ExportSize(name: "iPhone Pro Max", width: 1320, height: 2868, premium: true),
    ]

    static let mac: [ExportSize] = [
        ExportSize(name: "Standard", width: 1280, height: 720, premium: false),
        ExportSize(name: "Full HD", width: 1920, height: 1080, premium: true),
        ExportSize(name: "QHD", width: 2560, height: 1440, premium: true),
        ExportSize(name: "MacBook Air 13″", width: 2560, height: 1664, premium: true),
        ExportSize(name: "MacBook Pro 14″", width: 3024, height: 1964, premium: true),
        ExportSize(name: "MacBook Pro 16″", width: 3456, height: 2234, premium: true),
        ExportSize(name: "4K UHD", width: 3840, height: 2160, premium: true),
        ExportSize(name: "5K (iMac / Studio Display)", width: 5120, height: 2880, premium: true),
    ]

    static let livePhotoFree = ExportSize(name: "Standard", width: 720, height: 1280, premium: false)
    static let livePhotoPremium = ExportSize(name: "Full HD", width: 1080, height: 1920, premium: true)

    static func sizes(for target: DeviceTarget) -> [ExportSize] { target == .iphone ? iphone : mac }
}

enum ExportError: LocalizedError {
    case writerFailed(String)
    case cancelled

    var errorDescription: String? {
        switch self {
        case .writerFailed(let why): "The video couldn't be written. \(why)"
        case .cancelled: "Export cancelled."
        }
    }
}

/// Wraps a CGImage so it can cross into the background export task.
struct SendableImage: @unchecked Sendable {
    let image: CGImage?
}

/// Thread-safe cancel flag and progress callback for a running export.
final class ExportControl: @unchecked Sendable {
    private let lock = NSLock()
    private var _cancelled = false
    var isCancelled: Bool { lock.withLock { _cancelled } }
    func cancel() { lock.withLock { _cancelled = true } }
}

enum Exporter {
    static let livePhotoSeconds = 3.0

    private static func tempURL(_ ext: String) -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("AlyveWall", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let stamp = Int(Date().timeIntervalSince1970)
        return dir.appendingPathComponent("ALYVE-WALL-\(stamp)-\(UUID().uuidString.prefix(4)).\(ext)")
    }

    /// One seamless loop as an MP4. H.264 where it fits (best compatibility), HEVC above 4K.
    static func exportMP4(config: WallpaperConfig, overlay: SendableImage, size: ExportSize, fps: Int, watermark: Bool,
                          control: ExportControl, progress: @escaping @Sendable (Double) -> Void) throws -> URL {
        let url = tempURL("mp4")
        let renderer = WallpaperRenderer(config: config, width: size.width, height: size.height, overlay: overlay.image, watermark: watermark)
        let frames = Int((config.loopSeconds * Double(fps)).rounded())
        try writeVideo(to: url, fileType: .mp4, renderer: renderer, fps: fps, frames: frames, loopSeconds: config.loopSeconds,
                       liveIdentifier: nil, control: control, progress: progress)
        return url
    }

    /// A Live Photo: a JPEG and a short MOV tied together by a shared content identifier, with the
    /// still frame marked in the video, which is what Photos and the Lock Screen look for.
    static func exportLivePhoto(config: WallpaperConfig, overlay: SendableImage, size: ExportSize, watermark: Bool,
                                control: ExportControl, progress: @escaping @Sendable (Double) -> Void) throws -> (photo: URL, video: URL) {
        let id = UUID().uuidString
        let videoURL = tempURL("mov")
        let photoURL = tempURL("jpg")
        let fps = 30
        let frames = Int(livePhotoSeconds * Double(fps))
        let renderer = WallpaperRenderer(config: config, width: size.width, height: size.height, overlay: overlay.image, watermark: watermark)
        try writeVideo(to: videoURL, fileType: .mov, renderer: renderer, fps: fps, frames: frames, loopSeconds: config.loopSeconds,
                       liveIdentifier: id, control: control, progress: progress)

        let stillPhase = (livePhotoSeconds / 2) / config.loopSeconds
        guard let still = renderer.makeImage(phase: stillPhase),
              let dest = CGImageDestinationCreateWithURL(photoURL as CFURL, UTType.jpeg.identifier as CFString, 1, nil)
        else { throw ExportError.writerFailed("The still frame couldn't be made.") }
        let props: [CFString: Any] = [
            kCGImagePropertyMakerAppleDictionary: ["17": id],
            kCGImageDestinationLossyCompressionQuality: 0.95,
        ]
        CGImageDestinationAddImage(dest, still, props as CFDictionary)
        guard CGImageDestinationFinalize(dest) else { throw ExportError.writerFailed("The still frame couldn't be saved.") }
        return (photoURL, videoURL)
    }

    static func exportStill(config: WallpaperConfig, overlay: SendableImage, size: ExportSize, phase: Double, watermark: Bool) throws -> URL {
        let url = tempURL("png")
        let renderer = WallpaperRenderer(config: config, width: size.width, height: size.height, overlay: overlay.image, watermark: watermark)
        guard let img = renderer.makeImage(phase: phase),
              let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)
        else { throw ExportError.writerFailed("The image couldn't be made.") }
        CGImageDestinationAddImage(dest, img, nil)
        guard CGImageDestinationFinalize(dest) else { throw ExportError.writerFailed("The image couldn't be saved.") }
        return url
    }

    // MARK: - Writer

    private static func writeVideo(to url: URL, fileType: AVFileType, renderer: WallpaperRenderer, fps: Int, frames: Int,
                                   loopSeconds: Double, liveIdentifier: String?, control: ExportControl,
                                   progress: @escaping @Sendable (Double) -> Void) throws {
        try? FileManager.default.removeItem(at: url)
        let w = renderer.width, h = renderer.height
        let writer = try AVAssetWriter(outputURL: url, fileType: fileType)

        let useHEVC = max(w, h) > 4096 || w * h > 4096 * 2304
        let bitsPerPixel = useHEVC ? 0.12 : 0.2
        let bitrate = Int(Double(w * h * fps) * bitsPerPixel)
        var compression: [String: Any] = [
            AVVideoAverageBitRateKey: bitrate,
            AVVideoExpectedSourceFrameRateKey: fps,
            AVVideoMaxKeyFrameIntervalKey: fps,
        ]
        if !useHEVC { compression[AVVideoProfileLevelKey] = AVVideoProfileLevelH264HighAutoLevel }
        let settings: [String: Any] = [
            AVVideoCodecKey: useHEVC ? AVVideoCodecType.hevc : AVVideoCodecType.h264,
            AVVideoWidthKey: w,
            AVVideoHeightKey: h,
            AVVideoCompressionPropertiesKey: compression,
            AVVideoColorPropertiesKey: [
                AVVideoColorPrimariesKey: AVVideoColorPrimaries_ITU_R_709_2,
                AVVideoTransferFunctionKey: AVVideoTransferFunction_ITU_R_709_2,
                AVVideoYCbCrMatrixKey: AVVideoYCbCrMatrix_ITU_R_709_2,
            ],
        ]
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
        input.expectsMediaDataInRealTime = false
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: w,
            kCVPixelBufferHeightKey as String: h,
            kCVPixelBufferCGBitmapContextCompatibilityKey as String: true,
        ])
        guard writer.canAdd(input) else { throw ExportError.writerFailed("This size isn't supported on this device.") }
        writer.add(input)

        var metadataAdaptor: AVAssetWriterInputMetadataAdaptor?
        if let id = liveIdentifier {
            let item = AVMutableMetadataItem()
            item.keySpace = .quickTimeMetadata
            item.key = AVMetadataKey.quickTimeMetadataKeyContentIdentifier as NSString
            item.value = id as NSString
            item.dataType = kCMMetadataBaseDataType_UTF8 as String
            writer.metadata = [item]

            let spec: NSDictionary = [
                kCMMetadataFormatDescriptionMetadataSpecificationKey_Identifier as NSString: "mdta/com.apple.quicktime.still-image-time",
                kCMMetadataFormatDescriptionMetadataSpecificationKey_DataType as NSString: "com.apple.metadata.datatype.int8",
            ]
            var desc: CMFormatDescription?
            CMMetadataFormatDescriptionCreateWithMetadataSpecifications(allocator: kCFAllocatorDefault, metadataType: kCMMetadataFormatType_Boxed,
                                                                         metadataSpecifications: [spec] as CFArray, formatDescriptionOut: &desc)
            let metaInput = AVAssetWriterInput(mediaType: .metadata, outputSettings: nil, sourceFormatHint: desc)
            metaInput.expectsMediaDataInRealTime = false
            if writer.canAdd(metaInput) {
                writer.add(metaInput)
                metadataAdaptor = AVAssetWriterInputMetadataAdaptor(assetWriterInput: metaInput)
            }
        }

        guard writer.startWriting() else { throw ExportError.writerFailed(writer.error?.localizedDescription ?? "") }
        writer.startSession(atSourceTime: .zero)

        if let meta = metadataAdaptor {
            let item = AVMutableMetadataItem()
            item.keySpace = .quickTimeMetadata
            item.key = "com.apple.quicktime.still-image-time" as NSString
            item.value = 0 as NSNumber
            item.dataType = "com.apple.metadata.datatype.int8"
            let stillTime = CMTime(value: CMTimeValue(frames / 2), timescale: CMTimeScale(fps))
            let range = CMTimeRange(start: stillTime, duration: CMTime(value: 1, timescale: CMTimeScale(fps)))
            while !meta.assetWriterInput.isReadyForMoreMediaData { Thread.sleep(forTimeInterval: 0.002) }
            meta.append(AVTimedMetadataGroup(items: [item], timeRange: range))
            meta.assetWriterInput.markAsFinished()
        }

        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        for i in 0..<frames {
            if control.isCancelled {
                writer.cancelWriting()
                throw ExportError.cancelled
            }
            while !input.isReadyForMoreMediaData {
                if writer.status == .failed { throw ExportError.writerFailed(writer.error?.localizedDescription ?? "") }
                Thread.sleep(forTimeInterval: 0.002)
            }
            guard let pool = adaptor.pixelBufferPool else { throw ExportError.writerFailed("No frame buffers.") }
            var buffer: CVPixelBuffer?
            CVPixelBufferPoolCreatePixelBuffer(nil, pool, &buffer)
            guard let pb = buffer else { throw ExportError.writerFailed("Out of memory.") }
            CVPixelBufferLockBaseAddress(pb, [])
            if let ctx = CGContext(data: CVPixelBufferGetBaseAddress(pb), width: w, height: h, bitsPerComponent: 8,
                                   bytesPerRow: CVPixelBufferGetBytesPerRow(pb), space: space,
                                   bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue) {
                let t = Double(i) / Double(fps)
                renderer.draw(in: ctx, phase: t / loopSeconds)
            }
            CVPixelBufferUnlockBaseAddress(pb, [])
            let time = CMTime(value: CMTimeValue(i), timescale: CMTimeScale(fps))
            guard adaptor.append(pb, withPresentationTime: time) else {
                throw ExportError.writerFailed(writer.error?.localizedDescription ?? "")
            }
            progress(Double(i + 1) / Double(frames))
        }
        input.markAsFinished()
        writer.endSession(atSourceTime: CMTime(value: CMTimeValue(frames), timescale: CMTimeScale(fps)))

        let done = DispatchSemaphore(value: 0)
        writer.finishWriting { done.signal() }
        done.wait()
        if writer.status != .completed { throw ExportError.writerFailed(writer.error?.localizedDescription ?? "") }
    }
}
