import SwiftUI

/// Full-screen, pinch-to-zoom view of one defect's crop photo -- opened by
/// tapping its thumbnail in SessionDetailView. Presented modally; the Done
/// button or a swipe-down dismisses it.
struct DefectPhotoView: View {
    let image: UIImage
    let title: String
    let subtitle: String?

    @Environment(\.dismiss) private var dismiss
    @State private var scale: CGFloat = 1
    @State private var lastScale: CGFloat = 1

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .scaleEffect(scale)
                .gesture(
                    MagnificationGesture()
                        .onChanged { value in
                            scale = max(1, min(4, lastScale * value))
                        }
                        .onEnded { _ in lastScale = scale }
                )
                .onTapGesture(count: 2) {
                    withAnimation { scale = 1; lastScale = 1 }
                }

            VStack {
                HStack {
                    Text(title)
                        .font(.headline)
                        .foregroundStyle(.white)
                        .padding(.leading)
                    Spacer()
                    Button("Done") { dismiss() }
                        .foregroundStyle(.white)
                        .padding()
                }
                Spacer()
                if let subtitle {
                    Text(subtitle)
                        .font(.footnote)
                        .foregroundStyle(.white.opacity(0.8))
                        .padding(10)
                        .frame(maxWidth: .infinity)
                        .background(.black.opacity(0.6))
                }
            }
        }
    }
}
