import Foundation

struct ShotMetadata: Codable {
    var project = "Untitled Production"
    var scene = "1"
    var shot = "1A"
    var notes = ""
    var take = 1
    var capturedAt: Date = Date()
    var requestedProfile = ""
    var detectedFileProperties = ""
    var filmLook = FilmLook.neutral
    var fps = 24
    var aspectRatio = "2.39:1"
}

/// Sidecar JSON is portable across Film Engine and editing tools. It does not change the MOV.
enum ShotSidecar {
    static func save(_ metadata: ShotMetadata, alongside movie: URL) throws -> URL {
        let path = movie.deletingPathExtension().appendingPathExtension("json")
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(metadata).write(to: path, options: .atomic)
        return path
    }
}
