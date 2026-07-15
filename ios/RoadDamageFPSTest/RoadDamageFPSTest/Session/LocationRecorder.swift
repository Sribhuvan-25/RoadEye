import Combine
import CoreLocation
import QuartzCore

/// Logs GPS fixes during a recording session, timestamped as seconds from a
/// shared session start so the log lines up with the video clock. Writes the
/// CSV format the Python backend (pipeline/geo.py load_csv) already reads:
/// columns t_s, lat, lon, heading.
final class LocationRecorder: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published var authorized = false
    @Published var lastFix: CLLocation?

    private let manager = CLLocationManager()
    private var sessionStart: CFTimeInterval?
    private var rows: [(t: Double, lat: Double, lon: Double, heading: Double)] = []

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.requestWhenInUseAuthorization()
    }

    func startSession(at start: CFTimeInterval) {
        sessionStart = start
        rows = []
        manager.startUpdatingLocation()
    }

    func stopSession() {
        manager.stopUpdatingLocation()
        sessionStart = nil
    }

    /// CSV text ready to write alongside the session video.
    func csv() -> String {
        var out = "t_s,lat,lon,heading\n"
        for r in rows {
            out += "\(r.t),\(r.lat),\(r.lon),\(r.heading)\n"
        }
        return out
    }

    /// Fixes for on-device processing (SessionProcessor).
    func fixes() -> [SessionProcessor.GpsFix] {
        rows.map { .init(t: $0.t, lat: $0.lat, lon: $0.lon, heading: $0.heading) }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        authorized = status == .authorizedWhenInUse || status == .authorizedAlways
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let loc = locations.last else { return }
        lastFix = loc
        guard let start = sessionStart else { return }
        let t = CACurrentMediaTime() - start
        // CLLocation.course is -1 when heading is unavailable (stationary)
        let heading = loc.course >= 0 ? loc.course : 0
        rows.append((t: t, lat: loc.coordinate.latitude, lon: loc.coordinate.longitude, heading: heading))
    }
}
