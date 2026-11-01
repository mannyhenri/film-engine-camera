import AVFoundation
import CoreVideo

/// A requested capture configuration, not a promise that a device supports it.
enum RecordingProfile: String, CaseIterable, Identifiable {
    case hevcHLG = "HEVC · 10-bit HLG"
    case proResHLG = "ProRes 422 HQ · HLG"
    case proResLog = "ProRes 422 HQ · Apple Log"
    case sdr = "HEVC · SDR"

    var id: String { rawValue }
    var codec: AVVideoCodecType {
        switch self {
        case .proResHLG, .proResLog: return .proRes422HQ
        case .hevcHLG, .sdr: return .hevc
        }
    }
    var colorSpace: AVCaptureColorSpace {
        switch self {
        case .hevcHLG, .proResHLG: return .HLG_BT2020
        case .proResLog: return .appleLog
        case .sdr: return .sRGB
        }
    }
    var requiresTenBit: Bool { self != .sdr }
    var requires422: Bool { self == .proResHLG || self == .proResLog }
    var explanation: String {
        switch self {
        case .hevcHLG: return "10-bit HEVC, BT.2020 HLG · HDR delivery and grading"
        case .proResHLG: return "10-bit ProRes 422 HQ, HLG · high-bitrate HDR master"
        case .proResLog: return "10-bit ProRes 422 HQ, Apple Log · grading master"
        case .sdr: return "HEVC SDR fallback · not an HDR or Log recording"
        }
    }
}

struct FormatChoice {
    let format: AVCaptureDevice.Format
    let width: Int32
    let height: Int32
    let pixelSubtype: FourCharCode
}

/// Selects a real, compatible sensor format; codec support must be checked after activation.
enum FormatSelector {
    static func frameRates(for device: AVCaptureDevice, profile: RecordingProfile) -> [Int] {
        [24, 25, 30, 48, 50, 60, 120].filter { select(for: device, profile: profile, fps: Double($0)) != nil }
    }
    static func select(for device: AVCaptureDevice, profile: RecordingProfile, fps: Double = 24) -> FormatChoice? {
        let candidates = device.formats.compactMap { format -> FormatChoice? in
            let d = CMVideoFormatDescriptionGetDimensions(format.formatDescription)
            let pixel = CMFormatDescriptionGetMediaSubType(format.formatDescription)
            guard d.width >= 1920, d.height >= 1080,
                  format.videoSupportedFrameRateRanges.contains(where: { $0.minFrameRate <= fps && $0.maxFrameRate >= fps }),
                  format.supportedColorSpaces.contains(profile.colorSpace) else { return nil }
            if profile.requires422 {
                guard pixel == kCVPixelFormatType_422YpCbCr10BiPlanarVideoRange else { return nil }
            } else if profile.requiresTenBit {
                guard pixel == kCVPixelFormatType_420YpCbCr10BiPlanarVideoRange || pixel == kCVPixelFormatType_422YpCbCr10BiPlanarVideoRange else { return nil }
            }
            return FormatChoice(format: format, width: d.width, height: d.height, pixelSubtype: pixel)
        }
        // Prefer 4K 16:9 rather than accidentally choosing an oversized sensor format.
        return candidates.sorted {
            func score(_ c: FormatChoice) -> Int64 {
                let pixels = Int64(c.width) * Int64(c.height)
                let target: Int64 = 3840 * 2160
                return abs(pixels - target) + (c.width * 9 == c.height * 16 ? 0 : 10_000_000)
            }
            return score($0) < score($1)
        }.first
    }
}
