import AVFoundation
import SwiftUI

struct ManualExposure: Equatable {
    var iso: Float = 100
    var shutterDenominator: Int32 = 48
    var locked = false
}

extension CameraController {
    func setExposure(iso: Float, shutterDenominator: Int32) {
        guard isReady, !isRecording, !isConfiguring else { return }
        sessionQueue.async { [weak self] in
            guard let self, let device = self.capture.videoDevice else { return }
            do {
                try device.lockForConfiguration()
                defer { device.unlockForConfiguration() }
                guard device.isExposureModeSupported(.custom), shutterDenominator > 0 else { return }
                let clampedISO = max(device.activeFormat.minISO, min(device.activeFormat.maxISO, iso))
                let requested = CMTime(value: 1, timescale: shutterDenominator)
                let duration = CMTimeMaximum(device.activeFormat.minExposureDuration, CMTimeMinimum(device.activeFormat.maxExposureDuration, requested))
                device.setExposureModeCustom(duration: duration, iso: clampedISO)
                Task { @MainActor in
                    self.manualExposure = ManualExposure(iso: clampedISO, shutterDenominator: shutterDenominator, locked: true)
                }
            } catch { Task { @MainActor in self.status = "Exposure control failed: \(error.localizedDescription)" } }
        }
    }

    func setAutoExposure() {
        guard isReady, !isRecording, !isConfiguring else { return }
        sessionQueue.async { [weak self] in
            guard let self, let device = self.capture.videoDevice else { return }
            do {
                try device.lockForConfiguration()
                if device.isExposureModeSupported(.continuousAutoExposure) { device.exposureMode = .continuousAutoExposure }
                device.unlockForConfiguration()
                Task { @MainActor in self.manualExposure.locked = false }
            } catch { Task { @MainActor in self.status = "Auto exposure failed" } }
        }
    }

    func setWhiteBalance(kelvin: Float) {
        guard isReady, !isRecording, !isConfiguring else { return }
        sessionQueue.async { [weak self] in
            guard let self, let device = self.capture.videoDevice, device.isWhiteBalanceModeSupported(.locked) else { return }
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
        guard isReady, !isRecording, !isConfiguring else { return }
        sessionQueue.async { [weak self] in
            guard let self, let device = self.capture.videoDevice, device.isFocusModeSupported(.locked), device.isLockingFocusWithCustomLensPositionSupported else { return }
            do {
                try device.lockForConfiguration()
                device.setFocusModeLocked(lensPosition: min(1, max(0, normalizedLensPosition)))
                device.unlockForConfiguration()
                Task { @MainActor in self.focusPosition = normalizedLensPosition }
            } catch { Task { @MainActor in self.status = "Focus adjustment failed" } }
        }
    }

    func setZoom(_ factor: CGFloat) {
        guard isReady, !isRecording, !isConfiguring else { return }
        sessionQueue.async { [weak self] in
            guard let self, let device = self.capture.videoDevice else { return }
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
