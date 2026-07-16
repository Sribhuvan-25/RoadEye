import AVFoundation
import Combine
import CoreImage
import CoreML
import UIKit
import Vision

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
    let movieOutput = AVCaptureMovieFileOutput()
    /// Set while a drive is recording; receives tracked detections + crops.
    var collector: DetectionCollector?
    private let videoQueue = DispatchQueue(label: "camera.frame.queue")
    private var visionRequest: VNCoreMLRequest?
    private var latestFrame: UIImage?
    private var frameSize: CGSize = .zero

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
        if session.canAddOutput(movieOutput) {
            session.addOutput(movieOutput)
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
        frameTimestamps.removeAll { now - $0 > 2.0 }

        let observations = (request.results as? [VNRecognizedObjectObservation]) ?? []
        let count = observations.count
        let elapsed = now - sessionStart

        if let collector = collector, collector.active, frameSize != .zero {
            feedCollector(observations, collector: collector, elapsed: elapsed)
        }

        DispatchQueue.main.async {
            self.currentFPS = Double(self.frameTimestamps.count) / 2.0
            self.averageFPS = elapsed > 0 ? Double(self.totalFramesProcessed) / elapsed : 0
            self.detectionCount = count
            self.statusText = "Running"
        }
    }

    /// Convert Vision observations (normalized, bottom-left origin) into
    /// top-left pixel boxes and hand them to the collector with the frame.
    private func feedCollector(
        _ obs: [VNRecognizedObjectObservation],
        collector: DetectionCollector, elapsed: TimeInterval
    ) {
        let w = frameSize.width, h = frameSize.height
        var classes: [String] = [], confs: [Double] = [], boxes: [CGRect] = []
        for o in obs {
            guard let label = o.labels.first else { continue }
            let bb = o.boundingBox   // normalized, origin bottom-left
            let rect = CGRect(x: bb.minX * w, y: (1 - bb.maxY) * h,
                              width: bb.width * w, height: bb.height * h)
            classes.append(label.identifier)
            confs.append(Double(o.confidence))
            boxes.append(rect)
        }
        collector.add(timestamp: elapsed, classes: classes,
                      confidences: confs, boxes: boxes, frame: latestFrame)
    }
}

extension CameraFPSController: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        guard !isProcessing, let request = visionRequest,
              let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        isProcessing = true

        if let collector = collector, collector.active {
            let ci = CIImage(cvPixelBuffer: pixelBuffer)
            let ctx = CIContext()
            if let cg = ctx.createCGImage(ci, from: ci.extent) {
                let img = UIImage(cgImage: cg, scale: 1, orientation: .right)
                latestFrame = img
                frameSize = img.size
            }
        }

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
