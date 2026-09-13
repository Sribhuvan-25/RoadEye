import SwiftUI

/// Draws live detection boxes over the camera preview so the driver can see
/// what the model is picking up while recording. Boxes arrive normalised
/// (origin top-left) and are scaled to whatever size the preview occupies.
struct DetectionOverlay: View {
    let boxes: [CameraFPSController.LiveBox]

    var body: some View {
        GeometryReader { geo in
            ForEach(boxes) { box in
                let r = CGRect(x: box.rect.minX * geo.size.width,
                               y: box.rect.minY * geo.size.height,
                               width: box.rect.width * geo.size.width,
                               height: box.rect.height * geo.size.height)
                ZStack(alignment: .topLeading) {
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(color(for: box.label), lineWidth: 2)
                        .frame(width: r.width, height: r.height)
                    Text("\(box.label) \(Int(box.confidence * 100))%")
                        .font(.caption2.bold())
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(color(for: box.label), in: RoundedRectangle(cornerRadius: 3))
                        .foregroundStyle(.black)
                        .offset(y: -14)
                }
                .position(x: r.midX, y: r.midY)
            }
        }
        .allowsHitTesting(false)
    }

    private func color(for label: String) -> Color {
        switch label.lowercased() {
        case "pothole": return .red
        case "crack": return .yellow
        case "manhole": return .cyan
        default: return .green
        }
    }
}
