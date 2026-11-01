import AVFoundation
import Photos
import SwiftUI
import CoreImage

// Capture objects are accessed only on queue, apart from attaching session to the
// preview layer. UI state stays on CameraController's main actor.
final class CaptureHardware: @unchecked Sendable {
    let queue = DispatchQueue(label: "ai.gridlight.camera.session")
    let session = AVCaptureSession()
    let movieOutput = AVCaptureMovieFileOutput()
    let monitorOutput = AVCaptureVideoDataOutput()
    let monitorQueue = DispatchQueue(label: "ai.gridlight.camera.monitor", qos: .userInitiated)
    var videoDevice: AVCaptureDevice?
}

@MainActor
final class CameraController: NSObject, ObservableObject {
    @Published var isRecording = false
    @Published var isReady = false
    @Published var isConfiguring = false
    @Published var status = "Starting camera…"
    @Published var profiles: [RecordingProfile] = [.sdr]
    @Published var selectedProfile: RecordingProfile = .sdr
    @Published var captureDetails = "Checking sensor formats…"
    @Published var inspection = "No take to inspect"
    @Published var recordSeconds = 0
    @Published var recordTimecode = "00:00:00:00"
    @Published var lastFile: URL?
    @Published var manualExposure = ManualExposure()
    @Published var whiteBalanceKelvin: Float = 5600
    @Published var focusPosition: Float = 0.5
    @Published var zoomFactor: Double = 1
    @Published var filmLook = FilmLook.neutral { didSet { updateMonitor() } }
    @Published var monitoringEnabled = false { didSet { updateMonitor(); if !monitoringEnabled { monitorFrame = nil } } }
    @Published var monitorFrame: CGImage?
    @Published var metadata = ShotMetadata()
    @Published var monitoringStatus = "Monitor off"
    private var pendingMetadata = ShotMetadata()
    nonisolated let renderer = MonitorRenderer()
    @Published var fps = 24
    @Published var availableFPS = [24]
    @Published var isoRange: ClosedRange<Double> = 25...1600
    @Published var maxZoom: Double = 3
    @Published var completedTake: URL?
    private var previewAngle: CGFloat = 90

    private func updateMonitor() {
        renderer.configure(enabled: monitoringEnabled, look: filmLook, angle: previewAngle)
        monitoringStatus = monitoringEnabled ? "Creative monitor · clean master" : "Monitor off"
    }
    func updateOrientation(_ angle: CGFloat) {
        previewAngle = angle
        monitorFrame = nil
        updateMonitor()
    }


    nonisolated let capture = CaptureHardware()
    nonisolated var session: AVCaptureSession { capture.session }
    nonisolated var sessionQueue: DispatchQueue { capture.queue }
    private var timer: Timer?
    private var configured = false

    func start() {
        guard !configured, !isConfiguring else { return }
        isConfiguring = true
        renderer.receive = { [weak self] frame in
            MainActor.assumeIsolated {
                guard let self, self.monitoringEnabled else { return }
                self.monitorFrame = frame
            }
        }
        Task {
            let cameraGranted = await AVCaptureDevice.requestAccess(for: .video)
            let micGranted = await AVCaptureDevice.requestAccess(for: .audio)
            guard cameraGranted else {
                status = "Camera access denied in iOS Settings."
                isConfiguring = false
                return
            }
            setup(micGranted: micGranted)
        }
    }

    private func setup(micGranted: Bool) {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            self.session.beginConfiguration()
            self.session.sessionPreset = .inputPriority
            self.session.automaticallyConfiguresCaptureDeviceForWideColor = false
            do {
                guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else {
                    throw CameraError.unsupported("Rear camera not found")
                }
                let input = try AVCaptureDeviceInput(device: device)
                guard self.session.canAddInput(input) else { throw CameraError.unsupported("Video input unavailable") }
                self.session.addInput(input)
                if micGranted, let microphone = AVCaptureDevice.default(for: .audio) {
                    let mic = try AVCaptureDeviceInput(device: microphone)
                    if self.session.canAddInput(mic) { self.session.addInput(mic) }
                }
                guard self.session.canAddOutput(self.capture.movieOutput) else { throw CameraError.unsupported("Movie output unavailable") }
                self.session.addOutput(self.capture.movieOutput)
                self.capture.movieOutput.movieFragmentInterval = CMTime(seconds: 2, preferredTimescale: 600)
                self.capture.videoDevice = device
                // Dedicated low-latency monitor queue; recording remains unfiltered.
                // Full-resolution file capture is independent from this preview.
                self.capture.monitorOutput.alwaysDiscardsLateVideoFrames = true
                self.capture.monitorOutput.setSampleBufferDelegate(self.renderer, queue: self.capture.monitorQueue)
                if self.session.canAddOutput(self.capture.monitorOutput) { self.session.addOutput(self.capture.monitorOutput) }
                // A mode is advertised only after both format and codec negotiation succeeds.
                let supported = RecordingProfile.allCases.filter { self.install($0, on: device) != nil }
                let preferred: RecordingProfile = supported.contains(.hevcHLG) ? .hevcHLG : .sdr
                guard supported.contains(preferred), let details = self.install(preferred, on: device) else {
                    throw CameraError.unsupported("No usable video profile on this device")
                }
                let rates = FormatSelector.frameRates(for: device, profile: preferred)
                let isoRange = Double(device.activeFormat.minISO)...Double(device.activeFormat.maxISO)
                let maxZoom = min(10, Double(device.activeFormat.videoMaxZoomFactor))
                self.session.commitConfiguration()
                self.session.startRunning()
                Task { @MainActor in
                    self.configured = true
                    self.profiles = supported
                    self.selectedProfile = preferred
                    self.captureDetails = details
                    self.availableFPS = rates
                    self.isoRange = isoRange
                    self.maxZoom = maxZoom
                    self.isConfiguring = false
                    self.isReady = true
                    self.status = micGranted ? "Ready to record" : "Ready · microphone permission denied"
                }
            } catch {
                for input in self.session.inputs { self.session.removeInput(input) }
                for output in self.session.outputs { self.session.removeOutput(output) }
                self.capture.videoDevice = nil
                self.session.commitConfiguration()
                Task { @MainActor in
                    self.isConfiguring = false
                    self.status = "Camera setup failed: \(error.localizedDescription)"
                }
            }
        }
    }

    /// Runs only on sessionQueue. Returns nil instead of quietly selecting another profile.
    nonisolated private func install(_ profile: RecordingProfile, on device: AVCaptureDevice, fps: Int = 24) -> String? {
        guard let choice = FormatSelector.select(for: device, profile: profile, fps: Double(fps)),
              let connection = capture.movieOutput.connection(with: .video) else { return nil }
        do {
            try device.lockForConfiguration()
            device.activeFormat = choice.format
            if device.isExposureModeSupported(.continuousAutoExposure) { device.exposureMode = .continuousAutoExposure }
            device.activeColorSpace = profile.colorSpace
            device.activeVideoMinFrameDuration = CMTime(value: 1, timescale: Int32(fps))
            device.activeVideoMaxFrameDuration = CMTime(value: 1, timescale: Int32(fps))
            device.unlockForConfiguration()
            guard capture.movieOutput.availableVideoCodecTypes.contains(profile.codec) else { return nil }
            // iOS allows only keys returned by supportedOutputSettingsKeys(for:).
            guard capture.movieOutput.supportedOutputSettingsKeys(for: connection).contains(AVVideoCodecKey) else { return nil }
            capture.movieOutput.setOutputSettings([AVVideoCodecKey: profile.codec.rawValue], for: connection)
            let active = capture.movieOutput.outputSettings(for: connection)[AVVideoCodecKey] as? String
            guard active == profile.codec.rawValue, device.activeColorSpace == profile.colorSpace else { return nil }
            return "\(choice.width)×\(choice.height) · \(fps) fps · \(profile.rawValue) · sensor \(fourCC(choice.pixelSubtype))"
        } catch { return nil }
    }

    func select(_ profile: RecordingProfile, fps requestedFPS: Int? = nil) {
        guard isReady, !isRecording, !isConfiguring, profiles.contains(profile) else { return }
        isConfiguring = true
        isReady = false
        let previous = selectedProfile
        let previousFPS = fps
        let targetFPS = requestedFPS ?? 24
        sessionQueue.async { [weak self] in
            guard let self, let device = self.capture.videoDevice else { return }
            self.session.beginConfiguration()
            let details = self.install(profile, on: device, fps: targetFPS)
            let restored = details == nil ? self.install(previous, on: device, fps: previousFPS) : nil
            let rates = FormatSelector.frameRates(for: device, profile: details != nil ? profile : previous)
            let isoRange = Double(device.activeFormat.minISO)...Double(device.activeFormat.maxISO)
            let maxZoom = min(10, Double(device.activeFormat.videoMaxZoomFactor))
            self.session.commitConfiguration()
            Task { @MainActor in
                self.isConfiguring = false
                self.isReady = details != nil || restored != nil
                if let details {
                    self.selectedProfile = profile
                    self.fps = targetFPS
                    self.availableFPS = rates
                    self.isoRange = isoRange
                    self.maxZoom = maxZoom
                    self.manualExposure.locked = false
                    self.captureDetails = details
                    self.status = "Profile configured"
                } else {
                    self.status = "Requested profile cannot be activated on this camera"
                }
            }
        }
    }

    func toggleRecording() {
        guard isReady, !isConfiguring else { return }
        isConfiguring = true // Debounce taps until the delegate confirms start/finish.
        if isRecording {
            sessionQueue.async { [weak self] in self?.capture.movieOutput.stopRecording() }
        } else {
            var shot = metadata
            shot.capturedAt = Date()
            shot.requestedProfile = selectedProfile.rawValue
            shot.filmLook = filmLook
            shot.fps = fps
            pendingMetadata = shot
            let recordingAngle = previewAngle
            sessionQueue.async { [weak self] in
                guard let self else { return }
                let folder = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                let url = folder.appendingPathComponent("FEC-\(UUID().uuidString).mov")
                if let connection = self.capture.movieOutput.connection(with: .video), connection.isVideoRotationAngleSupported(recordingAngle) {
                    connection.videoRotationAngle = recordingAngle
                }
                self.capture.movieOutput.startRecording(to: url, recordingDelegate: self)
            }
        }
    }

    func saveToPhotos(_ file: URL? = nil) {
        guard let url = file ?? lastFile else { return }
        Task {
            let auth = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
            guard auth == .authorized || auth == .limited else { status = "Photos permission denied. File remains in app Documents."; return }
            do {
                try await PHPhotoLibrary.shared().performChanges {
                    PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: url)
                }
                status = "Saved to Photos · original retained in app Documents"
            } catch { status = "Photos export failed: \(error.localizedDescription)" }
        }
    }

    private func recordingStarted() {
        isRecording = true
        isConfiguring = false
        recordSeconds = 0
        recordTimecode = "00:00:00:00"
        status = "Recording \(selectedProfile.rawValue)"
        timer?.invalidate()
        let rate = fps
        timer = Timer(timeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.sessionQueue.async {
                let seconds = CMTimeGetSeconds(self.capture.movieOutput.recordedDuration)
                guard seconds.isFinite, seconds >= 0 else { return }
                Task { @MainActor in
                    self.recordSeconds = Int(seconds)
                    self.recordTimecode = RecordingTimecode.format(seconds: seconds, fps: rate)
                }
            }
        }
        if let timer { RunLoop.main.add(timer, forMode: .common) }
    }

    private func recordingFinished(url: URL, error: Error?) {
        timer?.invalidate(); timer = nil
        isRecording = false
        isConfiguring = false
        if let error, (error as NSError).userInfo[AVErrorRecordingSuccessfullyFinishedKey] as? Bool != true { status = "Recording failed: \(error.localizedDescription)"; return }
        lastFile = url
        status = "Take saved to app Documents"
        inspection = "Inspecting saved track…"
        let completedMetadata = pendingMetadata
        metadata.take += 1
        do { _ = try ShotSidecar.save(completedMetadata, alongside: url) }
        catch { status = "MOV saved; metadata failed: \(error.localizedDescription)" }
        Task {
            do {
                let asset = AVURLAsset(url: url)
                let tracks = try await asset.loadTracks(withMediaType: .video)
                guard let track = tracks.first else { throw CameraError.unsupported("No video track") }
                let descriptions = try await track.load(.formatDescriptions)
                guard let description = descriptions.first else { throw CameraError.unsupported("No video format description") }
                let codec = fourCC(CMFormatDescriptionGetMediaSubType(description))
                let extensions = CMFormatDescriptionGetExtensions(description) as? [String: Any] ?? [:]
                let primaries = String(describing: extensions[String(describing: kCMFormatDescriptionExtension_ColorPrimaries)] ?? "not tagged")
                let transfer = String(describing: extensions[String(describing: kCMFormatDescriptionExtension_TransferFunction)] ?? "not tagged")
                let size = try await track.load(.naturalSize)
                inspection = "FILE: \(Int(size.width))×\(Int(size.height)) | codec \(codec) | primaries \(primaries) | transfer \(transfer)"
                var sidecar = completedMetadata
                sidecar.detectedFileProperties = inspection
                do { _ = try ShotSidecar.save(sidecar, alongside: url) }
                catch { status = "MOV saved but JSON metadata failed: \(error.localizedDescription)" }
            } catch {
                inspection = "Could not inspect file: \(error.localizedDescription)"
            }
            completedTake = url
        }
    }
}

extension CameraController: AVCaptureFileOutputRecordingDelegate {
    nonisolated func fileOutput(_ output: AVCaptureFileOutput, didStartRecordingTo fileURL: URL, from connections: [AVCaptureConnection]) {
        Task { @MainActor in self.recordingStarted() }
    }
    nonisolated func fileOutput(_ output: AVCaptureFileOutput, didFinishRecordingTo outputFileURL: URL, from connections: [AVCaptureConnection], error: Error?) {
        Task { @MainActor in self.recordingFinished(url: outputFileURL, error: error) }
    }
}

private func fourCC(_ code: FourCharCode) -> String {
    let bytes: [UInt8] = [24, 16, 8, 0].map { UInt8((code >> $0) & 0xff) }
    return String(bytes: bytes, encoding: .ascii) ?? String(code)
}

private enum CameraError: LocalizedError {
    case unsupported(String)
    var errorDescription: String? { if case .unsupported(let message) = self { return message }; return "Unsupported" }
}
