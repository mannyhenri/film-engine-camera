import AVFoundation
import SwiftUI

struct ManualExposure: Equatable {
    var iso: Float = 100
    var shutterDenominator: Int32 = 48
    var locked = false
}

extension CameraController {
    func setExposure(iso: Float, shutterDenominator: Int32) {
        guard !isRecording else { return }
        sessionQueue.async { [weak self] in
            guard let self, let device = self.videoDevice else { return }
            do {
                try device.lockForConfiguration()
                let clampedISO = max(device.activeFormat.minISO, min(device.activeFormat.maxISO, iso))
                device.setExposureModeCustom(duration: CMTime(value: 1, timescale: shutterDenominator), iso: clampedISO)
                device.unlockForConfiguration()
                Task { @MainActor in
                    self.manualExposure = ManualExposure(iso: clampedISO, shutterDenominator: shutterDenominator, locked: true)
                }
            } catch { Task { @MainActor in self.status = "Exposure control failed: \(error.localizedDescription)" } }
        }
    }

    func setAutoExposure() {
        guard !isRecording else { return }
        sessionQueue.async { [weak self] in
            guard let self, let device = self.videoDevice else { return }
            do {
                try device.lockForConfiguration()
                if device.isExposureModeSupported(.continuousAutoExposure) { device.exposureMode = .continuousAutoExposure }
                device.unlockForConfiguration()
                Task { @MainActor in self.manualExposure.locked = false }
            } catch { Task { @MainActor in self.status = "Auto exposure failed" } }
        }
    }

    func setWhiteBalance(kelvin: Float) {
        guard !isRecording else { return }
        sessionQueue.async { [weak self] in
            guard let self, let device = self.videoDevice else { return }
            do {
                try device.lockForConfiguration()
                let gains = device.deviceWhiteBalanceGains(for: AVCaptureDevice.WhiteBalanceTemperatureAndTintValues(temperature: kelvin, tint: 0))
                let maxGain = device.maxWhiteBalanceGain
                let clamped = AVCaptureDevice.WhiteBalanceGains(redGain: max(1, min(maxGain, gains.redGain)), greenGain: max(1, min(maxGain, gains.greenGain)), blueGain: max(1, min(maxGain, gains.blueGain)))
                device.setWhiteBalanceModeLocked(with: clamped)
                device.unlockForConfiguration()
                Task { @MainActor in self.whiteBalanceKelvin = kelvin }
            } catch { Task { @MainActor in self.status = "White balance failed" } }
        }
    }

    func setFocus(_ normalizedLensPosition: Float) {
        guard !isRecording else { return }
        sessionQueue.async { [weak self] in
            guard let self, let device = self.videoDevice, device.isFocusModeSupported(.locked) else { return }
            do {
                try device.lockForConfiguration()
                device.setFocusModeLocked(lensPosition: normalizedLensPosition)
                device.unlockForConfiguration()
                Task { @MainActor in self.focusPosition = normalizedLensPosition }
            } catch { Task { @MainActor in self.status = "Focus adjustment failed" } }
        }
    }

    func setZoom(_ factor: CGFloat) {
        sessionQueue.async { [weak self] in
            guard let self, let device = self.videoDevice else { return }
            do {
                try device.lockForConfiguration()
                let target = min(device.activeFormat.videoMaxZoomFactor, max(1, factor))
                device.videoZoomFactor = target
                device.unlockForConfiguration()
                Task { @MainActor in self.zoomFactor = Double(target) }
            } catch { Task { @MainActor in self.status = "Zoom adjustment failed" } }
        }
    }
}
