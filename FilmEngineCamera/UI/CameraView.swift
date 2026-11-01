import AVFoundation
import AVKit
import SwiftUI

struct CameraPreview: UIViewRepresentable {
    let camera: CameraController
    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.videoPreviewLayer.session = camera.session
        view.videoPreviewLayer.videoGravity = .resizeAspectFill
        view.orientationChanged = { camera.updateOrientation($0) }
        return view
    }
    func updateUIView(_ uiView: PreviewView, context: Context) { uiView.setNeedsLayout() }
}
final class PreviewView: UIView {
    var orientationChanged: ((CGFloat) -> Void)?
    private var lastAngle: CGFloat?
    override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
    var videoPreviewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    override func layoutSubviews() {
        super.layoutSubviews()
        guard let orientation = window?.windowScene?.interfaceOrientation else { return }
        let angle = CaptureOrientation.angle(for: orientation)
        if let c = videoPreviewLayer.connection, c.isVideoRotationAngleSupported(angle) { c.videoRotationAngle = angle }
        if lastAngle != angle { lastAngle = angle; orientationChanged?(angle) }
    }
}

private enum CameraPanel: String, CaseIterable, Identifiable {
    case exposure = "Exposure", focus = "Focus", whiteBalance = "WB", zoom = "Zoom", format = "Format", look = "Look", guides = "Guides", slate = "Slate", info = "Info"
    var id: String { rawValue }
    var icon: String {
        switch self {
        case .exposure: return "plusminus.circle"
        case .focus: return "viewfinder"
        case .whiteBalance: return "thermometer.sun"
        case .zoom: return "plus.magnifyingglass"
        case .format: return "film"
        case .look: return "camera.filters"
        case .guides: return "square.dashed"
        case .slate: return "clapperboard"
        case .info: return "info.circle"
        }
    }
}

struct CameraView: View {
    @StateObject private var camera = CameraController()
    @StateObject private var library = ClipLibrary()
    @StateObject private var engine = FilmEngineConnection()
    @State private var panel: CameraPanel?
    @State private var showGuides = true
    @State private var showGrid = false
    @State private var showClips = false
    @State private var showConnection = false

    var body: some View {
        GeometryReader { geo in
            let landscape = geo.size.width > geo.size.height
            ZStack {
                Color.black.ignoresSafeArea()
                CameraPreview(camera: camera).ignoresSafeArea()
                if camera.monitoringEnabled, let frame = camera.monitorFrame {
                    Image(decorative: frame, scale: 1).resizable().scaledToFill()
                        .frame(width: geo.size.width, height: geo.size.height).clipped().allowsHitTesting(false)
                }
                compositionGuides(size: geo.size)
                if landscape {
                    HStack(spacing: 10) {
                        toolRail(vertical: true)
                        if let panel { panelView(panel).frame(width: min(300, geo.size.width * 0.4), height: max(120, geo.size.height - 52)) }
                        Spacer(minLength: 0)
                        VStack { libraryButton; connectionButton; Spacer(); recordButton; Spacer(); Text("\(camera.fps) FPS").font(.caption2.monospaced()) }
                            .padding(8).background(.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 16))
                    }.padding(.top, 30).padding(.bottom, 8).padding(.horizontal, 8)
                } else {
                    VStack(spacing: 8) {
                        Spacer(minLength: 0)
                        if let panel { panelView(panel).frame(maxWidth: 380).frame(height: min(240, geo.size.height * 0.34)) }
                        HStack { libraryButton; connectionButton; Spacer(); recordButton; Spacer(); Text("\(camera.fps) FPS").font(.caption.monospaced()) }.padding(.horizontal, 18)
                        toolRail(vertical: false)
                    }.padding(.bottom, 6)
                }
                VStack {
                    HStack(spacing: 8) {
                        Image("FilmEngineLogo").resizable().scaledToFit().frame(width: 24, height: 24)
                        Button { panel = panel == .info ? nil : .info } label: {
                            Text(camera.isRecording ? "● REC \(timeString)" : camera.isReady ? camera.selectedProfile.rawValue : camera.status)
                                .lineLimit(1).font(.system(size: 11, weight: .semibold, design: .monospaced))
                        }
                        Spacer()
                        if engine.busy { ProgressView().tint(.white) }
                    }.padding(.horizontal, 12).padding(.vertical, 4).background(.black.opacity(0.5))
                    Spacer()
                }.allowsHitTesting(true)
            }.foregroundStyle(.white)
        }
        .preferredColorScheme(.dark)
        .onAppear { camera.start(); library.refresh() }
        .onChange(of: camera.completedTake) { _, url in
            library.refresh()
            if let url, engine.autoUpload { engine.enqueue(url) }
        }
        .onChange(of: camera.isRecording) { _, _ in UIApplication.shared.isIdleTimerDisabled = camera.isRecording || engine.busy }
        .onChange(of: engine.busy) { _, _ in UIApplication.shared.isIdleTimerDisabled = camera.isRecording || engine.busy; library.refresh() }
        .sheet(isPresented: $showClips) { ClipLibraryView(library: library, engine: engine, camera: camera) }
        .sheet(isPresented: $showConnection) { EngineConnectionView(engine: engine) }
    }
    private var timeString: String { String(format: "%02d:%02d", camera.recordSeconds / 60, camera.recordSeconds % 60) }
    private var recordButton: some View {
        Button { camera.toggleRecording() } label: {
            Circle().fill(camera.isRecording ? .red : .white).frame(width: 54, height: 54)
                .overlay(Circle().stroke(.white, lineWidth: 2).padding(-4))
        }.accessibilityLabel(camera.isRecording ? "Stop recording" : "Start recording")
            .disabled(!camera.isReady || camera.isConfiguring)
    }
    private var libraryButton: some View {
        Button { library.refresh(); showClips = true } label: { Image(systemName: "photo.stack").font(.title2).frame(width: 44, height: 44) }
            .accessibilityLabel("Saved clips").disabled(camera.isRecording || camera.isConfiguring)
    }
    private var connectionButton: some View {
        Button { showConnection = true } label: { Image(systemName: engine.autoUpload ? "arrow.up.circle.fill" : "network").font(.title2).frame(width: 44, height: 44) }
            .accessibilityLabel("Film Engine connection").disabled(camera.isRecording || camera.isConfiguring)
    }
    private func toolRail(vertical: Bool) -> some View {
        ScrollView(vertical ? .vertical : .horizontal, showsIndicators: false) {
            let layout = vertical ? AnyLayout(VStackLayout(spacing: 3)) : AnyLayout(HStackLayout(spacing: 4))
            layout {
                ForEach(CameraPanel.allCases) { item in
                    Button { panel = panel == item ? nil : item } label: {
                        VStack(spacing: 2) { Image(systemName: item.icon).font(.system(size: 18)); Text(item.rawValue).font(.system(size: 8, weight: .medium)) }
                            .frame(width: 49, height: 43).background(panel == item ? Color.pink.opacity(0.65) : Color.clear, in: RoundedRectangle(cornerRadius: 9))
                    }.accessibilityLabel(item.rawValue)
                }
            }.padding(5)
        }.frame(width: vertical ? 59 : nil, height: vertical ? nil : 55)
            .background(.black.opacity(0.65), in: RoundedRectangle(cornerRadius: 14))
    }
    private func compositionGuides(size: CGSize) -> some View {
        Path { path in
            if showGuides {
                let w = min(size.width, size.height * 2.39), h = w / 2.39
                path.addRect(CGRect(x: (size.width-w)/2, y: (size.height-h)/2, width: w, height: h))
            }
            if showGrid {
                for n in [1.0, 2.0] {
                    path.move(to: CGPoint(x: size.width*n/3, y: 0)); path.addLine(to: CGPoint(x: size.width*n/3, y: size.height))
                    path.move(to: CGPoint(x: 0, y: size.height*n/3)); path.addLine(to: CGPoint(x: size.width, y: size.height*n/3))
                }
            }
        }.stroke(.white.opacity(0.4), lineWidth: 0.6).allowsHitTesting(false)
    }
    private func panelView(_ selected: CameraPanel) -> some View {
        VStack(spacing: 5) {
            HStack { Text(selected.rawValue).font(.headline); Spacer(); Button { panel = nil } label: { Image(systemName: "xmark.circle.fill") }.accessibilityLabel("Close controls") }
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    switch selected {
                    case .exposure: ExposureControls(camera: camera)
                    case .focus:
                        Text("Manual lens position")
                        Slider(value: Binding(get: { Double(camera.focusPosition) }, set: { camera.setFocus(Float($0)) }), in: 0...1)
                    case .whiteBalance:
                        Text("\(Int(camera.whiteBalanceKelvin)) K")
                        Slider(value: Binding(get: { Double(camera.whiteBalanceKelvin) }, set: { camera.setWhiteBalance(kelvin: Float($0)) }), in: 2500...9000, step: 100)
                    case .zoom:
                        Text(String(format: "%.1f×", camera.zoomFactor))
                        Slider(value: Binding(get: { camera.zoomFactor }, set: { camera.setZoom($0) }), in: 1...max(1.01, camera.maxZoom), step: 0.1)
                    case .format:
                        Picker("Profile", selection: Binding(get: { camera.selectedProfile }, set: { camera.select($0) })) { ForEach(camera.profiles) { Text($0.rawValue).tag($0) } }.pickerStyle(.menu)
                        Picker("FPS", selection: Binding(get: { camera.fps }, set: { camera.select(camera.selectedProfile, fps: $0) })) { ForEach(camera.availableFPS, id: \.self) { Text("\($0) fps").tag($0) } }.pickerStyle(.menu)
                        Text("Change format and FPS between takes. Changing profile starts at 24 fps.").font(.caption2)
                    case .look: LookControls(camera: camera)
                    case .guides:
                        Toggle("2.39:1 frame guide", isOn: $showGuides)
                        Toggle("Thirds grid", isOn: $showGrid)
                    case .slate:
                        TextField("Project label", text: $camera.metadata.project)
                        TextField("Scene", text: $camera.metadata.scene)
                        TextField("Shot", text: $camera.metadata.shot)
                        Stepper("Take \(camera.metadata.take)", value: $camera.metadata.take, in: 1...999)
                        TextField("Notes", text: $camera.metadata.notes, axis: .vertical)
                        Text("Saved beside each clip as JSON; never burned into the picture. Edits during recording apply to the next take. Choose the upload project under Connection.").font(.caption2)
                    case .info:
                        Text(camera.status); Text(camera.captureDetails).foregroundStyle(.green)
                        Text(camera.inspection).foregroundStyle(.yellow).textSelection(.enabled)
                        Text(engine.message).foregroundStyle(.cyan)
                        Text("v0.4 · clean master recording").font(.caption2)
                    }
                }.font(.subheadline).tint(.pink).textFieldStyle(.roundedBorder)
                    .disabled((selected == .format && camera.isRecording) || camera.isConfiguring)
            }
        }.padding(12).background(.black.opacity(0.82), in: RoundedRectangle(cornerRadius: 16))
    }
}

private struct ExposureControls: View {
    @ObservedObject var camera: CameraController
    @State private var iso = 100.0
    @State private var shutter = 48
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("ISO \(Int(camera.manualExposure.iso)) · 1/\(camera.manualExposure.shutterDenominator) s")
            Slider(value: $iso, in: camera.isoRange) { editing in if !editing { apply() } }
            Picker("Shutter", selection: $shutter) {
                ForEach([24,25,30,48,50,60,96,100,120,240,500,1000].filter { $0 >= camera.fps }, id: \.self) { Text("1/\($0)").tag($0) }
            }.onChange(of: shutter) { _, _ in apply() }
            Button(camera.manualExposure.locked ? "Return to auto exposure" : "Auto exposure is on") { camera.setAutoExposure() }
            Text("Adjustments remain visible in the preview.").font(.caption2)
        }.onAppear { iso = min(camera.isoRange.upperBound, max(camera.isoRange.lowerBound, Double(camera.manualExposure.iso))); shutter = max(camera.fps, Int(camera.manualExposure.shutterDenominator)) }
    }
    private func apply() { camera.setExposure(iso: Float(iso), shutterDenominator: Int32(shutter)) }
}
private struct LookControls: View {
    @ObservedObject var camera: CameraController
    var body: some View {
        Toggle("Live monitor", isOn: $camera.monitoringEnabled)
        HStack {
            Button("Neutral") { camera.filmLook = .neutral }
            Button("Night") { camera.filmLook = .tungsten }
            Button("Soft") { camera.filmLook = .soft }
        }.font(.caption)
        lookSlider("Exposure", value: $camera.filmLook.exposureEV, range: -2...2)
        lookSlider("Contrast", value: $camera.filmLook.contrast, range: 0.7...1.4)
        lookSlider("Saturation", value: $camera.filmLook.saturation, range: 0...1.5)
        lookSlider("Warmth", value: $camera.filmLook.warmth, range: -1...1)
        lookSlider("Highlights", value: $camera.filmLook.highlightSoftness, range: 0...1)
        lookSlider("Vignette", value: $camera.filmLook.vignette, range: 0...1)
        Text("SDR creative preview only. The saved HDR/Log master remains clean.").font(.caption2)
    }
    private func lookSlider(_ title: String, value: Binding<Double>, range: ClosedRange<Double>) -> some View {
        VStack(spacing: 0) { HStack { Text(title); Spacer(); Text(String(format: "%.2f", value.wrappedValue)) }; Slider(value: value, in: range) }
    }
}

struct EngineConnectionView: View {
    @ObservedObject var engine: FilmEngineConnection
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            Form {
                Section("Film Engine on your Mac") {
                    TextField("http://your-mac.local:5392", text: $engine.server).textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL)
                    SecureField("Pairing key", text: $engine.token)
                    Button("Connect / refresh projects") { Task { await engine.connect() } }
                }.disabled(engine.busy)
                Section("Destination") {
                    Picker("Project", selection: $engine.selectedProject) {
                        Text("Choose a project").tag("")
                        ForEach(engine.projects) { Text($0.title).tag($0.id) }
                    }.disabled(engine.busy)
                    Toggle("Send new takes automatically", isOn: $engine.autoUpload).disabled(engine.selectedProject.isEmpty || engine.busy)
                    Text("Clips go to the selected project’s Clips folder. Originals stay on this phone. Keep the app open while sending; failed transfers can be retried from Clips.").font(.footnote)
                }
                Section { Text(engine.message); if engine.busy { ProgressView() } }
            }.navigationTitle("Film Engine").toolbar { Button("Done") { dismiss() } }
                .task { if engine.projects.isEmpty && !engine.server.isEmpty { await engine.connect() } }
        }
    }
}

struct ClipLibraryView: View {
    @ObservedObject var library: ClipLibrary
    @ObservedObject var engine: FilmEngineConnection
    @ObservedObject var camera: CameraController
    @Environment(\.dismiss) private var dismiss
    @State private var playing: SavedClip?
    @State private var deleting: SavedClip?
    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("\(library.clips.count) clips · \(ClipLibrary.size(library.usedBytes)) used")
                    Text("\(ClipLibrary.size(library.freeBytes)) free on iPhone").foregroundStyle(.secondary)
                    if !library.message.isEmpty { Text(library.message).font(.caption) }
                    if !engine.message.isEmpty { Text(engine.message).font(.caption) }
                }
                ForEach(library.clips) { clip in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(clip.title).font(.headline)
                        Text("\(clip.date.formatted()) · \(ClipLibrary.size(clip.size))").font(.caption)
                        if clip.isUploaded { Label("Sent to Film Engine", systemImage: "checkmark.icloud").font(.caption).foregroundStyle(.green) }
                        HStack(spacing: 18) {
                            Button { playing = clip } label: { Image(systemName: "play.circle") }.accessibilityLabel("Play clip")
                            Button { camera.saveToPhotos(clip.url); library.message = "Saving to Photos…" } label: { Image(systemName: "square.and.arrow.down") }.accessibilityLabel("Save to Photos")
                            ShareLink(item: clip.url) { Image(systemName: "square.and.arrow.up") }
                            Button { Task { await engine.upload(clip.url); library.refresh() } } label: { Image(systemName: "arrow.up.icloud") }.accessibilityLabel("Send to Film Engine").disabled(engine.busy || engine.selectedProject.isEmpty)
                            Spacer()
                            Button(role: .destructive) { deleting = clip } label: { Image(systemName: "trash") }.accessibilityLabel("Delete local clip").disabled(engine.isPending(clip.url))
                        }.buttonStyle(.borderless)
                    }.padding(.vertical, 4)
                }
            }.navigationTitle("Clips").toolbar { Button("Done") { dismiss() } }
                .onAppear { library.refresh() }
                .onChange(of: camera.status) { _, status in library.message = status }
                .sheet(item: $playing) { ClipPlayer(url: $0.url) }
                .alert("Delete from iPhone?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })) {
                    Button("Delete clip and slate", role: .destructive) { if let clip = deleting { library.delete(clip); if camera.lastFile == clip.url { camera.lastFile = nil } }; deleting = nil }
                    Button("Cancel", role: .cancel) { deleting = nil }
                } message: { Text("This removes the local MOV and its metadata. Copies in Photos or Film Engine are kept. This cannot be undone.") }
        }
    }
}
private struct ClipPlayer: View {
    @State private var player: AVPlayer
    init(url: URL) { _player = State(initialValue: AVPlayer(url: url)) }
    var body: some View { VideoPlayer(player: player).onAppear { player.play() }.onDisappear { player.pause() } }
}
