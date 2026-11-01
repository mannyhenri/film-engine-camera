import UIKit

enum CaptureOrientation {
    static func angle(for orientation: UIInterfaceOrientation) -> CGFloat {
        switch orientation {
        case .landscapeRight: return 0
        case .landscapeLeft: return 180
        case .portraitUpsideDown: return 270
        default: return 90
        }
    }
}
