import Combine
import Foundation

/// Per-vehicle measurement config, persisted across launches. These drive the
/// inverse perspective mapping: mount height scales every dimension linearly,
/// and the horizon fraction sets the camera pitch. Set them to match the
/// actual phone mount before a drive, or measurements will be off.
final class AppSettings: ObservableObject {
    static let shared = AppSettings()

    @Published var mountHeightM: Double {
        didSet { defaults.set(mountHeightM, forKey: Keys.height) }
    }
    @Published var horizonFraction: Double {
        didSet { defaults.set(horizonFraction, forKey: Keys.horizon) }
    }
    /// Keep the raw drive video. Off by default: nothing in the app reads it
    /// back, and a long drive is gigabytes. Useful only for re-processing or
    /// evidence, so it is an explicit opt-in.
    @Published var keepVideo: Bool {
        didSet { defaults.set(keepVideo, forKey: Keys.keepVideo) }
    }
    /// Detections below this confidence are ignored. Measured on the holdout
    /// set (NMS IoU 0.45): 0.25 -> P 0.58 / R 0.54, 0.35 -> cleaner with most
    /// recall intact, 0.50 -> P 0.75 but R 0.40, i.e. ~60% of real defects
    /// missed. 0.35 keeps the survey useful; raise it only if the list is too
    /// noisy to work through, and accept the misses that come with it.
    @Published var minConfidence: Double {
        didSet { defaults.set(minConfidence, forKey: Keys.minConfidence) }
    }

    private let defaults = UserDefaults.standard
    private enum Keys {
        static let height = "mountHeightM"
        static let horizon = "horizonFraction"
        static let keepVideo = "keepVideo"
        static let minConfidence = "minConfidence"
    }

    private init() {
        let h = defaults.object(forKey: Keys.height) as? Double
        let hz = defaults.object(forKey: Keys.horizon) as? Double
        mountHeightM = h ?? 1.3
        horizonFraction = hz ?? 0.45
        keepVideo = defaults.object(forKey: Keys.keepVideo) as? Bool ?? false
        minConfidence = defaults.object(forKey: Keys.minConfidence) as? Double ?? 0.35
    }
}
