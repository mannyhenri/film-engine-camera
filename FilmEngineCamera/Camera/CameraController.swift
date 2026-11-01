import AVFoundation
import Photos
import SwiftUI
import CoreImage

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
    @Published var lastFile: URL?
    @Published var manualExposure = ManualExposure()
    @Published var whiteBalanceKelvin: Float = 5600
    @Published var focusPosition: Float = 0.5
    @Published var zoomFactor: Double = 1
    @Published var filmLook = FilmLook.neutral
    @Published var monitoringEnabled = false
    @Published var monitorFrame: CGImage?
    @Published var metadata = ShotMetadata()
    @Published var monitoringStatus = "Monitor off"
    private var pendingMetadata = ShotMetadata()
    private let monitorOutput = AVCaptureVideoDataOutput()
    private let monitorQueue = DispatchQueue(label: "ai.gridlight.camera.monitor", qos: .userInitiated)
    private let monitorContext = CIContext(options: [.useSoftwareRenderer: false])
    private var monitorCounter = 0

    let session = AVCaptureSession()
    let sessionQueue = DispatchQueue(label: "ai.gridlight.camera.session")
    private let movieOutput = AVCaptureMovieFileOutput()
    var videoDevice: AVCaptureDevice?
    private var timer: Timer?
    private var configured = false

    func start() {
        guard !configured, !isConfiguring else { return }
        isConfiguring = true
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
                guard self.session.canAddOutput(self.movieOutput) else { throw CameraError.unsupported("Movie output unavailable") }
                self.session.addOutput(self.movieOutput)
                self.movieOutput.movieFragmentInterval = CMTime(seconds: 2, preferredTimescale: 600)
                self.videoDevice = device
                // Optional sample buffers for a low-fps creative monitor.
                // Full-resolution file capture is independent from this preview.
                self.monitorOutput.alwaysDiscardsLateVideoFrames = true
                self.monitorOutput.setSampleBufferDelegate(self, queue: self.monitorQueue)
                if self.session.canAddOutput(self.monitorOutput) { self.session.addOutput(self.monitorOutput) }
                self.configured = true
                // A mode is advertised only after both format and codec negotiation succeeds.
                let supported = RecordingProfile.allCases.filter { self.install($0, on: device) != nil }
                let preferred: RecordingProfile = supported.contains(.hevcHLG) ? .hevcHLG : .sdr
                guard supported.contains(preferred), let details = self.install(preferred, on: device) else {
                    throw CameraError.unsupported("No usable video profile on this device")
                }
                self.session.commitConfiguration()
                self.session.startRunning()
                Task { @MainActor in
                    self.profiles = supported
                    self.selectedProfile = preferred
                    self.captureDetails = details
                    self.isConfiguring = false
                    self.isReady = true
                    self.status = micGranted ? "Ready to record" : "Ready · microphone permission denied"
                }
            } catch {
                self.session.commitConfiguration()
                Task { @MainActor in
                    self.isConfiguring = false
                    self.status = "Camera setup failed: \(error.localizedDescription)"
                }
            }
        }
    }

    /// Runs only on sessionQueue. Returns nil instead of quietly selecting another profile.
    private func install(_ profile: RecordingProfile, on device: AVCaptureDevice) -> String? {
        guard let choice = FormatSelector.select(for: device, profile: profile),
              let connection = movieOutput.connection(with: .video) else { return nil }
        do {
            try device.lockForConfiguration()
            device.activeFormat = choice.format
            device.activeColorSpace = profile.colorSpace
            device.activeVideoMinFrameDuration = CMTime(value: 1, timescale: 24)
            device.activeVideoMaxFrameDuration = CMTime(value: 1, timescale: 24)
            device.unlockForConfiguration()
            guard movieOutput.availableVideoCodecTypes.contains(profile.codec) else { return nil }
            // iOS allows only keys returned by supportedOutputSettingsKeys(for:).
            guard movieOutput.supportedOutputSettingsKeys(for: connection).contains(AVVideoCodecKey) else { return nil }
            movieOutput.setOutputSettings([AVVideoCodecKey: profile.codec.rawValue], for: connection)
            let active = movieOutput.outputSettings(for: connection)[AVVideoCodecKey] as? String
            guard active == profile.codec.rawValue, device.activeColorSpace == profile.colorSpace else { return nil }
            return "\(choice.width)×\(choice.height) · 24 fps · \(profile.rawValue) · sensor \(fourCC(choice.pixelSubtype))"
        } catch { return nil }
    }

    func select(_ profile: RecordingProfile) {
        guard isReady, !isRecording, !isConfiguring, profiles.contains(profile) else { return }
        isConfiguring = true
        isReady = false
        sessionQueue.async { [weak self] in
            guard let self, let device = self.videoDevice else { return }
            self.session.beginConfiguration()
            let details = self.install(profile, on: device)
            self.session.commitConfiguration()
            Task { @MainActor in
                self.isConfiguring = false
                self.isReady = true
                if let details {
                    self.selectedProfile = profile
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
        if isRecording {
            sessionQueue.async { [weak self] in self?.movieOutput.stopRecording() }
        } else {
            sessionQueue.async { [weak self] in
                guard let self else { return }
                let folder = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                let url = folder.appendingPathComponent("FEC-\(UUID().uuidString).mov")
                Task { @MainActor in
                    var shot = self.metadata
                    shot.capturedAt = Date()
                    shot.requestedProfile = self.selectedProfile.rawValue
                    shot.filmLook = self.filmLook
                    self.pendingMetadata = shot
                }
                self.movieOutput.startRecording(to: url, recordingDelegate: self)
            }
        }
    }

    func saveToPhotos() {
        guard let url = lastFile else { return }
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
        recordSeconds = 0
        status = "Recording \(selectedProfile.rawValue)"
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.recordSeconds += 1 }
        }
    }

    private func recordingFinished(url: URL, error: Error?) {
        timer?.invalidate(); timer = nil
        isRecording = false
        if let error { status = "Recording failed: \(error.localizedDescription)"; return }
        lastFile = url
        status = "Take saved to app Documents"
        inspection = "Inspecting saved track…"
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
                var sidecar = pendingMetadata
                sidecar.detectedFileProperties = inspection
                do { _ = try ShotSidecar.save(sidecar, alongside: url) }
                catch { status = "MOV saved but JSON metadata failed: \(error.localizedDescription)" }
                metadata.take += 1
            } catch {
                inspection = "Could not inspect file: \(error.localizedDescription)"
            }
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

// Monitor is a lower-rate approximation. SDR display rendering does NOT provide
// HDR-accurate waveform/scopes and cannot be used for exposure-critical work.
extension CameraController: AVCaptureVideoDataOutputSampleBufferDelegate {
    nonisolated func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let pixel = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        Task { @MainActor [weak self] in
            guard let self, self.monitoringEnabled else { return }
            self.monitorCounter += 1
            guard self.monitorCounter % 3 == 0 else { return }
            let look = self.filmLook
            let image = CIImage(cvPixelBuffer: pixel).oriented(.right)
            // Scale preview early to avoid 4K processing and UI stalls.
            let scaled = image.transformed(by: CGAffineTransform(scaleX: 0.4, y: 0.4))
            let rendered = look.process(scaled)
            if let cgImage = self.monitorContext.createCGImage(rendered, from: rendered.extent) {
                self.monitorFrame = cgImage
                self.monitoringStatus = "Creative preview · clean master"
            }
        }
    }
}
