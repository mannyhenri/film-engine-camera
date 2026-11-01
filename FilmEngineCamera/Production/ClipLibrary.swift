import Foundation
import SwiftUI

struct SavedClip: Identifiable {
    var id: URL { url }
    let url: URL
    let size: Int64
    let date: Date
    let metadata: ShotMetadata?
    var title: String { metadata.map { "\($0.scene) · \($0.shot) · Take \($0.take)" } ?? url.deletingPathExtension().lastPathComponent }
    var receiptURL: URL { url.deletingPathExtension().appendingPathExtension("upload.json") }
    var isUploaded: Bool { FileManager.default.fileExists(atPath: receiptURL.path) }
}

@MainActor
final class ClipLibrary: ObservableObject {
    @Published var clips: [SavedClip] = []
    @Published var message = ""
    @Published var freeBytes: Int64 = 0
    var usedBytes: Int64 { clips.reduce(0) { $0 + $1.size } }
    let directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    func refresh() {
        do {
            let urls = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.fileSizeKey, .creationDateKey])
            clips = urls.filter { $0.pathExtension.lowercased() == "mov" }.map { url in
                let values = try? url.resourceValues(forKeys: [.fileSizeKey, .creationDateKey])
                let data = try? Data(contentsOf: url.deletingPathExtension().appendingPathExtension("json"))
                let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
                return SavedClip(url: url, size: Int64(values?.fileSize ?? 0), date: values?.creationDate ?? .distantPast, metadata: data.flatMap { try? decoder.decode(ShotMetadata.self, from: $0) })
            }.sorted { $0.date > $1.date }
            freeBytes = (try directory.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])).volumeAvailableCapacityForImportantUsage ?? 0
        } catch { message = error.localizedDescription }
    }
    func delete(_ clip: SavedClip) {
        do {
            try FileManager.default.removeItem(at: clip.url)
            for sidecar in [clip.url.deletingPathExtension().appendingPathExtension("json"), clip.receiptURL] where FileManager.default.fileExists(atPath: sidecar.path) {
                try FileManager.default.removeItem(at: sidecar)
            }
            message = "Deleted from this iPhone. Photos and Film Engine copies are unchanged."
        } catch { message = error.localizedDescription }
        refresh()
    }
    static func size(_ bytes: Int64) -> String { ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file) }
}
