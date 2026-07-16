import CoreGraphics
import Foundation

struct FrameDetection {
    let timestamp: TimeInterval
    let trackID: Int
    let className: String
    let confidence: Double
    let bbox: CGRect
}

struct DefectRecord: Codable, Identifiable {
    var id: Int { trackID }
    let trackID: Int
    let className: String
    let confidence: Double
    let firstSeenS: TimeInterval
    let lastSeenS: TimeInterval
    let nFrames: Int
    var cropFilename: String?
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
