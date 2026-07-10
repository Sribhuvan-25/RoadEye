import AVFoundation
import Combine
import CoreML
import Vision
import SwiftUI

/// Throwaway Phase 0 test harness: runs the road-damage CoreML model on every
/// live camera frame and reports sustained FPS. No UI polish, no persistence --
/// the only thing that matters is the number on screen after a couple of
/// minutes of pointing the phone at pavement.
final class CameraFPSController: NSObject, ObservableObject {
    @Published var currentFPS: Double = 0
    @Published var averageFPS: Double = 0
    @Published var detectionCount: Int = 0
    @Published var statusText: String = "Starting..."

    let session = AVCaptureSession()
    private let videoQueue = DispatchQueue(label: "camera.frame.queue")
    private var visionRequest: VNCoreMLRequest?

    // FPS bookkeeping
    private var frameTimestamps: [CFTimeInterval] = []
    private var sessionStart: CFTimeInterval = 0
    private var totalFramesProcessed: Int = 0
    private var isProcessing = false

    override init() {
        super.init()
        setupModel()
        setupCamera()
    }

    private func setupModel() {
        do {
            let config = MLModelConfiguration()
            // .all / .cpuAndGPU currently crash on iPhone 17 Pro + iOS 26.5
            // (CoreML/Metal graph-compile bug on new silicon). .cpuOnly is a
            // stopgap; retry the ANE path after an Xcode/iOS update.
            config.computeUnits = .cpuOnly
            let model = try RoadDamageDetector(configuration: config)
            let vnModel = try VNCoreMLModel(for: model.model)
            let request = VNCoreMLRequest(model: vnModel) { [weak self] request, error in
                self?.handleResults(request: request, error: error)
            }
            request.imageCropAndScaleOption = .scaleFill
            self.visionRequest = request
            statusText = "Model loaded"
        } catch {
            statusText = "Model load FAILED: \(error.localizedDescription)"
        }
    }

    private func setupCamera() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            configureSession()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                DispatchQueue.main.async {
                    if granted {
                        self?.configureSession()
                    } else {
                        self?.statusText = "Camera permission DENIED"
                    }
                }
            }
        case .denied, .restricted:
            statusText = "Camera permission DENIED -- enable in Settings > RoadDamageFPSTest"
        @unknown default:
            statusText = "Camera permission: unknown state"
        }
    }

    private func configureSession() {
        session.beginConfiguration()
        session.sessionPreset = .hd1280x720

        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
              let input = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(input) else {
            statusText = "Camera setup FAILED (no camera -- run on a physical iPhone, not the Simulator)"
            session.commitConfiguration()
            return
        }
        session.addInput(input)

        let output = AVCaptureVideoDataOutput()
        output.setSampleBufferDelegate(self, queue: videoQueue)
        output.alwaysDiscardsLateVideoFrames = true
        if session.canAddOutput(output) {
            session.addOutput(output)
        }
        session.commitConfiguration()

        videoQueue.async { [weak self] in
            self?.session.startRunning()
            DispatchQueue.main.async {
                if self?.statusText.hasPrefix("Camera") != false {
                    self?.statusText = "Camera running, waiting for first inference..."
                }
            }
        }
    }

    func start() {
        sessionStart = CACurrentMediaTime()
        totalFramesProcessed = 0
        frameTimestamps = []
        // session is started once permission resolves in configureSession();
        // if it's already running (e.g. view re-appeared), this is a harmless no-op.
        videoQueue.async { [weak self] in
            if self?.session.isRunning == false {
                self?.session.startRunning()
            }
        }
    }

    func stop() {
        session.stopRunning()
    }

    private func handleResults(request: VNRequest, error: Error?) {
        if let error = error {
            DispatchQueue.main.async {
                self.statusText = "Vision error: \(error.localizedDescription)"
            }
            return
        }
        let now = CACurrentMediaTime()
        totalFramesProcessed += 1
        frameTimestamps.append(now)
        // keep a rolling ~2 second window for "current" FPS
        frameTimestamps.removeAll { now - $0 > 2.0 }

        let count = (request.results as? [VNRecognizedObjectObservation])?.count ?? 0
        let elapsed = now - sessionStart

        DispatchQueue.main.async {
            self.currentFPS = Double(self.frameTimestamps.count) / 2.0
            self.averageFPS = elapsed > 0 ? Double(self.totalFramesProcessed) / elapsed : 0
            self.detectionCount = count
            self.statusText = "Running"
        }
    }
}

extension CameraFPSController: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        // Drop frames if inference is still busy on the previous one --
        // measuring SUSTAINED throughput, not queuing up a backlog.
        guard !isProcessing, let request = visionRequest,
              let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        isProcessing = true

        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .right)
        do {
            try handler.perform([request])
        } catch {
            DispatchQueue.main.async {
                self.statusText = "Inference error: \(error.localizedDescription)"
            }
        }
        isProcessing = false
    }
}
