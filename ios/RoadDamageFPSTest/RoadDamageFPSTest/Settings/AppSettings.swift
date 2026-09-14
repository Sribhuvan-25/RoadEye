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
    /// Detections below this confidence are ignored. The detector's own
    /// default is a research threshold that surfaces a lot of marginal boxes;
    /// a higher floor trades a few real defects for a much cleaner list.
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
        minConfidence = defaults.object(forKey: Keys.minConfidence) as? Double ?? 0.50
    }
}
