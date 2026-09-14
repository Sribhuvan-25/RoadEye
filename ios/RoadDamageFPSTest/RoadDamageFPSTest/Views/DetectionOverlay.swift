import SwiftUI

/// Draws live detection boxes over the camera preview so the driver can see
/// what the model is picking up while recording. Boxes arrive normalised
/// (origin top-left) and are scaled to whatever size the preview occupies.
struct DetectionOverlay: View {
    let boxes: [CameraFPSController.LiveBox]
    /// Aspect ratio (w/h) of the frame the boxes were measured against. The
    /// preview letterboxes when it does not match the screen, so boxes must
    /// be mapped into the displayed image rect, not the whole view.
    var sourceAspect: CGFloat?

    var body: some View {
        GeometryReader { geo in
            let area = displayRect(in: geo.size)
            ForEach(boxes) { box in
                let r = CGRect(x: area.minX + box.rect.minX * area.width,
                               y: area.minY + box.rect.minY * area.height,
                               width: box.rect.width * area.width,
                               height: box.rect.height * area.height)
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

    /// Where the frame actually appears on screen under scaledToFit.
    private func displayRect(in size: CGSize) -> CGRect {
        guard let aspect = sourceAspect, aspect > 0 else {
            return CGRect(origin: .zero, size: size)
        }
        let viewAspect = size.width / size.height
        if viewAspect > aspect {          // pillarboxed
            let w = size.height * aspect
            return CGRect(x: (size.width - w) / 2, y: 0, width: w, height: size.height)
        } else {                          // letterboxed
            let h = size.width / aspect
            return CGRect(x: 0, y: (size.height - h) / 2, width: size.width, height: h)
        }
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
