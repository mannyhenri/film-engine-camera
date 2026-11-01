import Foundation
@main struct TimecodeTests {
    static func main() {
        let cases: [(Double, Int, String)] = [(0,24,"00:00:00:00"), (1.5,24,"00:00:01:12"), (61.5,30,"00:01:01:15"), (3601.5,60,"01:00:01:30"), (0.5,120,"00:00:00:060"), (.nan,24,"00:00:00:00"), (-1,24,"00:00:00:00")]
        for (seconds, fps, expected) in cases { precondition(RecordingTimecode.format(seconds: seconds, fps: fps) == expected) }
        print("7 timecode cases passed")
    }
}
