import Foundation
import SwiftUI
import Security

struct FilmProject: Decodable, Identifiable, Hashable { let id: String; let title: String }
private struct ProjectList: Decodable { let projects: [FilmProject] }
private enum PairingKey {
    static let service = "ai.gridlight.filmenginecamera.bridge"
    static func load() -> String {
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecReturnData as String: true]
        var value: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &value) == errSecSuccess, let data = value as? Data else { return "" }
        return String(data: data, encoding: .utf8) ?? ""
    }
    static func save(_ value: String) {
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service]
        SecItemDelete(q as CFDictionary)
        guard !value.isEmpty else { return }
        var entry = q; entry[kSecValueData as String] = Data(value.utf8)
        entry[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(entry as CFDictionary, nil)
    }
}

private final class TransferProgress: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    let report: @Sendable (Int64, Int64) -> Void
    init(report: @escaping @Sendable (Int64, Int64) -> Void) { self.report = report }
    func urlSession(_ session: URLSession, task: URLSessionTask, didSendBodyData bytesSent: Int64, totalBytesSent: Int64, totalBytesExpectedToSend: Int64) {
        report(totalBytesSent, totalBytesExpectedToSend)
    }
}

@MainActor
final class FilmEngineConnection: ObservableObject {
    @Published var server: String { didSet { UserDefaults.standard.set(server, forKey: "engine.server"); projects = []; selectedProject = "" } }
    @Published var token: String { didSet { PairingKey.save(token) } }
    @Published var selectedProject: String { didSet { UserDefaults.standard.set(selectedProject, forKey: "engine.project") } }
    @Published var autoUpload: Bool { didSet { UserDefaults.standard.set(autoUpload, forKey: "engine.auto") } }
    @Published var projects: [FilmProject] = []
    @Published var busy = false
    @Published var uploadProgress = 0.0
    @Published var transferDetails = ""
    @Published var message = "Choose a project to send clips to Film Engine."
    @Published var uploadingFile: URL?
    private var pending: [(URL, String)] = []
    private var draining = false
    func isPending(_ url: URL) -> Bool { uploadingFile == url || pending.contains { $0.0 == url } }
    func enqueue(_ url: URL) {
        guard !selectedProject.isEmpty else { message = "Choose an upload project first. Clip saved locally."; return }
        pending.append((url, selectedProject))
        guard !draining else { return }
        draining = true
        Task {
            while !pending.isEmpty {
                if busy { try? await Task.sleep(for: .milliseconds(300)); continue }
                let next = pending.removeFirst()
                await upload(next.0, projectID: next.1)
            }
            draining = false
        }
    }
    private let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 120
        config.timeoutIntervalForResource = 7200
        return URLSession(configuration: config)
    }()
    init() {
        let bundledURL = Bundle.main.object(forInfoDictionaryKey: "CameraBridgeURL") as? String ?? ""
        let bundledToken = Bundle.main.object(forInfoDictionaryKey: "CameraBridgeToken") as? String ?? ""
        server = UserDefaults.standard.string(forKey: "engine.server") ?? (bundledURL.hasPrefix("http") ? bundledURL : "")
        let saved = PairingKey.load()
        token = saved.isEmpty && !bundledToken.hasPrefix("$(") ? bundledToken : saved
        selectedProject = UserDefaults.standard.string(forKey: "engine.project") ?? ""
        autoUpload = UserDefaults.standard.bool(forKey: "engine.auto")
    }
    private func request(_ path: String, method: String = "GET") throws -> URLRequest {
        guard let base = URL(string: server.trimmingCharacters(in: .whitespacesAndNewlines)), ["http", "https"].contains(base.scheme), base.host != nil, !token.isEmpty else {
            throw URLError(.badURL)
        }
        var req = URLRequest(url: base.appendingPathComponent(path)); req.httpMethod = method
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        return req
    }
    private func validate(_ data: Data, _ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            let body = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
            throw NSError(domain: "FilmEngine", code: (response as? HTTPURLResponse)?.statusCode ?? 0, userInfo: [NSLocalizedDescriptionKey: body?["error"] as? String ?? "Film Engine did not accept the request."])
        }
    }
    func connect() async {
        guard !busy else { return }
        busy = true; defer { busy = false }
        do {
            let (data, response) = try await session.data(for: request("projects"))
            try validate(data, response)
            projects = try JSONDecoder().decode(ProjectList.self, from: data).projects
            if !projects.contains(where: { $0.id == selectedProject }) { selectedProject = "" }
            message = "Connected · \(projects.count) projects. Choose the destination below."
        } catch { message = "Connection failed: \(error.localizedDescription)" }
    }
    func upload(_ url: URL, projectID: String? = nil) async {
        guard !busy, !(projectID ?? selectedProject).isEmpty else { message = "Connect and select a project first."; return }
        let project = projectID ?? selectedProject
        busy = true; uploadingFile = url
        uploadProgress = 0; transferDetails = "Preparing transfer…"
        UIApplication.shared.isIdleTimerDisabled = true
        defer { busy = false; uploadingFile = nil; UIApplication.shared.isIdleTimerDisabled = false }
        message = "Sending \(url.lastPathComponent)… Keep the app open."
        do {
            var req = try request("projects/\(project)/clips/\(url.lastPathComponent)", method: "PUT")
            req.setValue("video/quicktime", forHTTPHeaderField: "Content-Type")
            let bytes = Int64(try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0)
            guard bytes > 0 else { throw URLError(.fileDoesNotExist) }
            req.setValue(String(bytes), forHTTPHeaderField: "Content-Length")
            let started = Date()
            let progress = TransferProgress { [weak self] sent, expected in
                Task { @MainActor in
                    guard let self else { return }
                    let total = expected > 0 ? expected : bytes
                    self.uploadProgress = min(1, Double(sent) / Double(total))
                    let speed = Double(sent) / max(0.1, Date().timeIntervalSince(started))
                    let left = Int(Double(max(0, total - sent)) / max(1, speed))
                    self.transferDetails = "\(ClipLibrary.size(sent)) / \(ClipLibrary.size(total)) · \(String(format: "%.1f", speed / 1_000_000)) MB/s · ~\(left / 60)m \(left % 60)s left"
                    if sent >= total { self.message = "Transfer received; verifying and registering the MOV on your Mac…" }
                }
            }
            let sidecar = url.deletingPathExtension().appendingPathExtension("json")
            if let data = try? Data(contentsOf: sidecar) {
                guard data.count <= 24000 else { throw NSError(domain: "FilmEngine", code: 0, userInfo: [NSLocalizedDescriptionKey: "Slate metadata exceeds 24 KB. Shorten the notes before sending."]) }
                req.setValue(data.base64EncodedString(), forHTTPHeaderField: "X-Camera-Metadata")
            }
            // URLSession streams the MOV from disk, never loading a ProRes take into RAM.
            let (data, response) = try await session.upload(for: req, fromFile: url, delegate: progress)
            try validate(data, response)
            guard let receipt = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  receipt["asset_id"] is String, receipt["project_id"] as? String == project,
                  receipt["sha256"] is String else {
                throw NSError(domain: "FilmEngine", code: 0, userInfo: [NSLocalizedDescriptionKey: "The server did not return a valid saved-clip receipt."])
            }
            try data.write(to: url.deletingPathExtension().appendingPathExtension("upload.json"), options: .atomic)
            message = "Saved MOV + JSON to Film Engine’s project Clips folder. Original retained on iPhone."
            uploadProgress = 1
            transferDetails = "Verified \(ClipLibrary.size(bytes)) · \(projects.first { $0.id == project }?.title ?? "selected project")"
        } catch { message = "Upload failed: \(error.localizedDescription). Original retained; retry from Clips." }
    }
}
