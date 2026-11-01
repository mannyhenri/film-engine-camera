import AVFoundation
import SwiftUI

struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession
    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.videoPreviewLayer.session = session
        view.videoPreviewLayer.videoGravity = .resizeAspectFill
        return view
    }
    func updateUIView(_ uiView: PreviewView, context: Context) {}
}

final class PreviewView: UIView {
    override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
    var videoPreviewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
}

struct CameraView: View {
    @StateObject private var camera = CameraController()
    @State private var showGuides = true
    @State private var showSettings = false
    @State private var showLookEditor = false
    @State private var showSlate = false
    @State private var showGrid = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            CameraPreview(session: camera.session).ignoresSafeArea()
            if camera.monitoringEnabled, let frame = camera.monitorFrame {
                Image(decorative: frame, scale: 1)
                    .resizable().scaledToFill().ignoresSafeArea().clipped()
                    .allowsHitTesting(false)
            }
            if showGrid {
                GeometryReader { geo in
                    Path { p in
                        for x in [geo.size.width/3, geo.size.width*2/3] { p.move(to: CGPoint(x:x,y:0)); p.addLine(to: CGPoint(x:x,y:geo.size.height)) }
                        for y in [geo.size.height/3, geo.size.height*2/3] { p.move(to: CGPoint(x:0,y:y)); p.addLine(to: CGPoint(x:geo.size.width,y:y)) }
                    }.stroke(.white.opacity(0.28), lineWidth: 0.6)
                }.allowsHitTesting(false)
            }
            if showGuides {
                GeometryReader { geo in
                    let height = geo.size.width / 2.39
                    Rectangle()
                        .strokeBorder(.white.opacity(0.8), lineWidth: 1)
                        .frame(width: geo.size.width, height: height)
                        .position(x: geo.size.width / 2, y: geo.size.height / 2)
                    Path { path in
                        let top = (geo.size.height - height) / 2
                        for x in [geo.size.width / 3, geo.size.width * 2 / 3] {
                            path.move(to: CGPoint(x: x, y: top))
                            path.addLine(to: CGPoint(x: x, y: top + height))
                        }
                    }.stroke(.white.opacity(0.25), lineWidth: 0.5)
                }.allowsHitTesting(false)
            }
            VStack(spacing: 9) {
                HStack {
                    Label("FILM ENGINE CAMERA", systemImage: "camera.aperture")
                    Spacer()
                    Text(camera.isRecording ? "● REC \(timeString)" : "STANDBY")
                        .foregroundStyle(camera.isRecording ? .red : .white)
                }
                .font(.system(size: 12, weight: .bold, design: .monospaced))
                .padding(12)
                .background(.black.opacity(0.75), in: RoundedRectangle(cornerRadius: 10))
                HStack(spacing: 10) {
                    Button("EXPOSURE") { showSettings = true }
                    Button("LOOK") { showLookEditor = true }
                    Button("SLATE") { showSlate = true }
                    Button(showGrid ? "GRID ON" : "GRID") { showGrid.toggle() }
                }.buttonStyle(.bordered).tint(.white).font(.system(size: 10, weight: .bold))
                Spacer()
                VStack(alignment: .leading, spacing: 10) {
                    Text(camera.status).foregroundStyle(.white)
                    Text(camera.captureDetails).foregroundStyle(.green)
                    if camera.lastFile != nil {
                        Text(camera.inspection).foregroundStyle(.yellow)
                            .textSelection(.enabled)
                    }
                    Picker("Recording format", selection: Binding(
                        get: { camera.selectedProfile },
                        set: { camera.select($0) }
                    )) {
                        ForEach(camera.profiles) { profile in
                            Text(profile.rawValue).tag(profile)
                        }
                    }
                    .pickerStyle(.menu)
                    .tint(.white)
                    .disabled(!camera.isReady || camera.isRecording || camera.isConfiguring)
                    Text("LOOK: \(camera.filmLook.name) · \(camera.monitoringStatus)")
                        .foregroundStyle(.cyan)
                    Text(camera.selectedProfile.explanation).foregroundStyle(.white.opacity(0.85))
                    HStack {
                        Button(showGuides ? "2.39 GUIDES ON" : "GUIDES OFF") { showGuides.toggle() }
                        Spacer()
                        Text("24 FPS")
                    }
                    .foregroundStyle(.white)
                }
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.black.opacity(0.82), in: RoundedRectangle(cornerRadius: 12))

                HStack(spacing: 18) {
                    if camera.lastFile != nil {
                        Button { camera.saveToPhotos() } label: {
                            Label("SAVE", systemImage: "square.and.arrow.down")
                        }
                    } else {
                        Text("10-BIT / PRORES")
                    }
                    Spacer()
                    Button { camera.toggleRecording() } label: {
                        Circle()
                            .fill(camera.isRecording ? .red : .white)
                            .frame(width: 64, height: 64)
                            .overlay(Circle().stroke(.white, lineWidth: 3).padding(-6))
                    }
                    .accessibilityLabel(camera.isRecording ? "Stop recording" : "Start recording")
                    .disabled(!camera.isReady || camera.isConfiguring)
                    Spacer()
                    Text("0.3 FIELD")
                }
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(.white)
                .frame(height: 80)
            }
            .padding(15)
        }
        .preferredColorScheme(.dark)
        .onAppear { camera.start() }
        .sheet(isPresented: $showSettings) { ExposureSheet(camera: camera) }
        .sheet(isPresented: $showLookEditor) { LookSheet(camera: camera) }
        .sheet(isPresented: $showSlate) { SlateSheet(camera: camera) }
    }

    private var timeString: String {
        String(format: "%02d:%02d", camera.recordSeconds / 60, camera.recordSeconds % 60)
    }
}


private struct ExposureSheet: View {
    @ObservedObject var camera: CameraController
    @Environment(\.dismiss) private var dismiss
    @State private var iso: Double = 100
    @State private var shutter: Int = 48
    @State private var kelvin: Double = 5600
    @State private var focus: Double = 0.5
    @State private var zoom: Double = 1
    var body: some View {
        NavigationStack {
            Form {
                Section("Exposure · 24 fps") {
                    Toggle("Lock manual exposure", isOn: Binding(get: { camera.manualExposure.locked }, set: { if !$0 { camera.setAutoExposure() } else { camera.setExposure(iso: Float(iso), shutterDenominator: Int32(shutter)) } }))
                    LabeledContent("ISO", value: "\(Int(iso))")
                    Slider(value: $iso, in: 25...1600, step: 25)
                    Picker("Shutter", selection: $shutter) { ForEach([24, 48, 50, 60, 96, 120, 240], id: \.self) { Text("1/\($0) s").tag($0) } }
                    Button("Apply manual exposure") { camera.setExposure(iso: Float(iso), shutterDenominator: Int32(shutter)) }
                }
                Section("Lens & White Balance") {
                    LabeledContent("White balance", value: "\(Int(kelvin)) K")
                    Slider(value: $kelvin, in: 2500...9000, step: 100)
                    Button("Lock white balance") { camera.setWhiteBalance(kelvin: Float(kelvin)) }
                    LabeledContent("Focus lens position", value: String(format: "%.2f", focus))
                    Slider(value: $focus, in: 0...1)
                    Button("Lock focus") { camera.setFocus(Float(focus)) }
                    LabeledContent("Digital zoom", value: String(format: "%.1f×", zoom))
                    Slider(value: $zoom, in: 1...3, step: 0.1)
                    Button("Set zoom") { camera.setZoom(zoom) }
                }
                Text("Controls are locked during recording. ISO and lens availability vary by device. The iPhone applies hardware bounds.")
                    .font(.footnote)
            }
            .navigationTitle("Camera Controls")
            .toolbar { Button("Done") { dismiss() } }
        }
    }
}

private struct LookSheet: View {
    @ObservedObject var camera: CameraController
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            Form {
                Section("Live look") {
                    Toggle("Enable experimental live monitor", isOn: $camera.monitoringEnabled)
                    Picker("Preset", selection: $camera.filmLook.name) {
                        ForEach(["Cinematic Neutral", "Tungsten Night", "Soft Negative"], id: \.self) { Text($0).tag($0) }
                    }.onChange(of: camera.filmLook.name) { _, name in
                        switch name {
                        case "Tungsten Night": camera.filmLook = .tungsten
                        case "Soft Negative": camera.filmLook = .soft
                        default: camera.filmLook = .neutral
                        }
                    }
                    lookSlider("Exposure EV", value: $camera.filmLook.exposureEV, range: -2...2)
                    lookSlider("Contrast", value: $camera.filmLook.contrast, range: 0.7...1.4)
                    lookSlider("Saturation", value: $camera.filmLook.saturation, range: 0...1.5)
                    lookSlider("Warmth", value: $camera.filmLook.warmth, range: -1...1)
                    lookSlider("Highlight softness", value: $camera.filmLook.highlightSoftness, range: 0...1)
                    lookSlider("Vignette", value: $camera.filmLook.vignette, range: 0...1)
                    Button("Reset look") { camera.filmLook = .neutral }
                }
                Section("Recording policy") {
                    Text("Preview only. Camera records its native clean HDR/Log file. Look is stored in the JSON shot sidecar and is not burned into footage.")
                    Text("This preview is SDR-oriented and not a color-managed HDR reference. No calibrated scope or film grain/halation yet.")
                }
            }
            .navigationTitle("Color Lab")
            .toolbar { Button("Done") { dismiss() } }
        }
    }
    private func lookSlider(_ title: String, value: Binding<Double>, range: ClosedRange<Double>) -> some View {
        VStack(alignment: .leading) {
            LabeledContent(title, value: String(format: "%.2f", value.wrappedValue))
            Slider(value: value, in: range)
        }
    }
}

private struct SlateSheet: View {
    @ObservedObject var camera: CameraController
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            Form {
                TextField("Project", text: $camera.metadata.project)
                TextField("Scene", text: $camera.metadata.scene)
                TextField("Shot", text: $camera.metadata.shot)
                Stepper("Take \(camera.metadata.take)", value: $camera.metadata.take, in: 1...999)
                TextField("Director notes", text: $camera.metadata.notes, axis: .vertical)
                Text("Each recording saves a matching .json sidecar in the app Documents directory. Shot IDs can be mapped to Film Engine later.")
                    .font(.footnote)
            }
            .navigationTitle("Production Slate")
            .toolbar { Button("Done") { dismiss() } }
        }
    }
}
