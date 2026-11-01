import Foundation
import CoreImage
import CoreGraphics

/// Nondestructive monitoring recipe. Recording output is never filtered.
struct FilmLook: Codable, Equatable {
    var name = "Cinematic Neutral"
    var exposureEV: Double = 0
    var contrast: Double = 1.08
    var saturation: Double = 0.94
    var warmth: Double = 0
    var highlightSoftness: Double = 0.15
    var vignette: Double = 0
    var grain: Double = 0

    static let neutral = FilmLook()
    static let tungsten = FilmLook(name: "Tungsten Night", exposureEV: 0, contrast: 1.12, saturation: 0.87, warmth: 0.25, highlightSoftness: 0.28, vignette: 0.65, grain: 0)
    static let soft = FilmLook(name: "Soft Negative", exposureEV: 0, contrast: 0.95, saturation: 0.91, warmth: 0.06, highlightSoftness: 0.32, vignette: 0.15, grain: 0)

    func process(_ input: CIImage) -> CIImage {
        var image = input
        if exposureEV != 0 { image = image.applyingFilter("CIExposureAdjust", parameters: [kCIInputEVKey: exposureEV]) }
        image = image.applyingFilter("CIColorControls", parameters: [kCIInputContrastKey: contrast, kCIInputSaturationKey: saturation])
        if warmth != 0 {
            image = image.applyingFilter("CITemperatureAndTint", parameters: ["inputNeutral": CIVector(x: 6500, y: 0), "inputTargetNeutral": CIVector(x: 6500 - warmth * 1800, y: 0)])
        }
        // A smooth highlight curve for MONITORING only; not an HDR mastering transform.
        if highlightSoftness > 0 {
            image = image.applyingFilter("CIHighlightShadowAdjust", parameters: ["inputHighlightAmount": 1 - highlightSoftness * 0.8, "inputShadowAmount": 0])
        }
        if vignette > 0 { image = image.applyingFilter("CIVignette", parameters: [kCIInputIntensityKey: vignette, kCIInputRadiusKey: 1.6]) }
        return image
    }
}
