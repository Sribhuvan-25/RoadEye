import AVFoundation
import SwiftUI

/// Measurement setup. Mount height is typed in; the horizon is set visually by
/// dragging a line over the live camera feed to sit on the real horizon --
/// far more reliable than guessing a fraction. Both persist via AppSettings.
struct SettingsView: View {
    @ObservedObject var settings = AppSettings.shared
    let session: AVCaptureSession
    @State private var apiKeyInput = ""
    @State private var hasStoredKey = KeychainStore.load() != nil

    var body: some View {
        Form {
            Section("Mount height") {
                HStack {
                    Text("Height above road")
                    Spacer()
                    Text(String(format: "%.2f m", settings.mountHeightM))
                        .foregroundStyle(.secondary)
                }
                Slider(value: $settings.mountHeightM, in: 0.5...2.5, step: 0.05)
                Text("Measure from the road surface to the phone camera. Scales every dimension, so get it close.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("Horizon line") {
                horizonPreview
                    .frame(height: 220)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                Text("Drag the green line onto the real horizon (where road meets sky). Sets the camera tilt.")
                    .font(.caption).foregroundStyle(.secondary)
                Text(String(format: "Horizon at %.0f%% down the frame", settings.horizonFraction * 100))
                    .font(.caption).foregroundStyle(.secondary)
                Text("Defects near or above this line cannot be measured — the geometry becomes unreliable there, so those are reported without a size rather than with a wrong one.")
                    .font(.caption2).foregroundStyle(.secondary)
            }

            Section("Detection") {
                HStack {
                    Text("Minimum confidence")
                    Spacer()
                    Text(String(format: "%.0f%%", settings.minConfidence * 100))
                        .foregroundStyle(.secondary)
                }
                Slider(value: $settings.minConfidence, in: 0.25...0.85, step: 0.05)
                Text("Detections below this are ignored. Higher is cleaner but misses more real damage — at 50% roughly a third fewer defects are found than at 35%. Raise it only if the list is too noisy to review.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("Recording") {
                Toggle("Keep drive video", isOn: $settings.keepVideo)
                Text("Off by default. Detection, measurement and photos all work without it; the raw video is only worth keeping if you want to re-process the drive later. A long drive can be several gigabytes.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("Inspection report") {
                SecureField("OpenRouter API key (sk-or-...)", text: $apiKeyInput)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                Button("Save key to Keychain") {
                    let trimmed = apiKeyInput.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !trimmed.isEmpty else { return }
                    KeychainStore.save(trimmed)
                    apiKeyInput = ""
                    hasStoredKey = true
                }
                .disabled(apiKeyInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                Text(hasStoredKey
                     ? "A key is stored. Reports can be generated from Past Sessions."
                     : "No key stored. Report generation is disabled until one is saved.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Measurement Setup")
    }

    private var horizonPreview: some View {
        GeometryReader { geo in
            ZStack(alignment: .top) {
                CameraPreviewView(session: session)
                Rectangle()
                    .fill(.green)
                    .frame(height: 2)
                    .offset(y: geo.size.height * settings.horizonFraction)
                    .gesture(
                        DragGesture().onChanged { v in
                            let frac = max(0, min(1, v.location.y / geo.size.height))
                            settings.horizonFraction = frac
                        }
                    )
            }
        }
    }
}
