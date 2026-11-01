import Foundation

enum RecordingTimecode {
    /// Elapsed non-drop-frame timecode derived from the movie output's duration.
    static func format(seconds: Double, fps: Int) -> String {
        guard seconds.isFinite, seconds >= 0, fps > 0 else { return "00:00:00:00" }
        let total = Int((seconds * Double(fps)).rounded(.down))
        let whole = total / fps
        return String(format: fps >= 100 ? "%02d:%02d:%02d:%03d" : "%02d:%02d:%02d:%02d", whole / 3600, (whole / 60) % 60, whole % 60, total % fps)
    }
}
