import AVFoundation
import CoreImage
import Metal

/// One synchronous GPU render on the sample-buffer queue; at most one UI delivery.
/// No queued frames accumulate when the device cannot keep up.
final class MonitorRenderer: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate, @unchecked Sendable {
    private var lastRenderTime = -Double.infinity // sample-buffer queue only
    private let lock = NSLock()
    private let delivery = DispatchSemaphore(value: 1)
    private var enabled = false
    private var look = FilmLook.neutral
    private var orientation: CGImagePropertyOrientation = .right
    private let context: CIContext = {
        if let device = MTLCreateSystemDefaultDevice() { return CIContext(mtlDevice: device, options: [.cacheIntermediates: false]) }
        return CIContext(options: [.cacheIntermediates: false])
    }()
    var receive: (@Sendable (CGImage) -> Void)?

    func configure(enabled: Bool, look: FilmLook, angle: CGFloat) {
        lock.lock(); defer { lock.unlock() }
        self.enabled = enabled; self.look = look
        switch Int(angle) {
        case 0: orientation = .up
        case 180: orientation = .down
        case 270: orientation = .left
        default: orientation = .right
        }
    }
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        lock.lock()
        let active = enabled, recipe = look, rotation = orientation
        lock.unlock()
        let now = CMTimeGetSeconds(CMSampleBufferGetPresentationTimeStamp(sampleBuffer))
        guard active, now - lastRenderTime >= 1.0 / 30.0 - 0.001, delivery.wait(timeout: .now()) == .success else { return }
        lastRenderTime = now
        guard let pixel = CMSampleBufferGetImageBuffer(sampleBuffer) else { delivery.signal(); return }
        let result: CGImage? = autoreleasepool {
            let source = CIImage(cvPixelBuffer: pixel)
            let scale = min(1, 960 / max(source.extent.width, source.extent.height))
            let small = source.transformed(by: CGAffineTransform(scaleX: scale, y: scale)).oriented(rotation)
            let rendered = recipe.process(small)
            return context.createCGImage(rendered, from: rendered.extent)
        }
        guard let result else { delivery.signal(); return }
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.receive?(result)
            self.delivery.signal()
        }
    }
}
