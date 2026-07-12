import CoreGraphics
import Foundation

/// A single detection in one frame, before tracking collapses them.
struct FrameDetection {
    let timestamp: TimeInterval   // seconds from session start
    let trackID: Int
    let className: String
    let confidence: Double
    let bbox: CGRect              // pixels in the source frame
}

/// One physical defect after tracking + dedup: what the user reviews.
/// Codable so a session's defects persist as defects.json on disk.
struct DefectRecord: Codable, Identifiable {
    var id: Int { trackID }
    let trackID: Int
    let className: String
    let confidence: Double
    let firstSeenS: TimeInterval
    let lastSeenS: TimeInterval
    let nFrames: Int
    var cropFilename: String?              // image saved beside defects.json
    var location: GeoPoint?
    var dimensions: Dimensions?
}

struct GeoPoint: Codable {
    let lat: Double
    let lon: Double
    let heading: Double?
}

struct Dimensions: Codable {
    let widthM: Double
    let lengthM: Double
    let areaM2: Double
    let distanceM: Double
}

/// Header for a saved session, listed on the "Past Sessions" screen.
struct SessionSummary: Codable, Identifiable {
    var id: String { sessionID }
    let sessionID: String
    let startedEpoch: Double
    let durationS: TimeInterval
    let defectCount: Int
}
