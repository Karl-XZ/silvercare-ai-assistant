import AVFoundation
import CoreImage
import SwiftUI
import UIKit

enum NativeCameraError: LocalizedError {
    case permissionDenied
    case cameraUnavailable
    case cannotAddInput
    case cannotAddOutput
    case noFrame
    case imageEncodingFailed

    var errorDescription: String? {
        switch self {
        case .permissionDenied:
            return "摄像头权限未开启。请在 iPhone 设置中允许银龄智护使用摄像头。"
        case .cameraUnavailable:
            return "没有找到可用的后置摄像头。"
        case .cannotAddInput:
            return "摄像头输入初始化失败。"
        case .cannotAddOutput:
            return "摄像头画面输出初始化失败。"
        case .noFrame:
            return "摄像头正在启动，请稍等。"
        case .imageEncodingFailed:
            return "摄像头画面编码失败。"
        }
    }
}

final class NativeCameraService: NSObject, ObservableObject, AVCaptureVideoDataOutputSampleBufferDelegate, @unchecked Sendable {
    @Published private(set) var isRunning = false

    let session = AVCaptureSession()

    var canStartCamera: Bool {
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        guard status != .denied && status != .restricted else { return false }
        return hardwareAvailable
    }

    var hardwareAvailable: Bool {
        return AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) != nil
            || AVCaptureDevice.default(for: .video) != nil
    }

    var authorizationStatusLabel: String {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            return "authorized"
        case .denied:
            return "denied"
        case .notDetermined:
            return "not_determined"
        case .restricted:
            return "restricted"
        @unknown default:
            return "unknown"
        }
    }

    private let sessionQueue = DispatchQueue(label: "com.silvercare.aiassistant.camera.session")
    private let sampleQueue = DispatchQueue(label: "com.silvercare.aiassistant.camera.samples")
    private let lock = NSLock()
    private let ciContext = CIContext(options: [.cacheIntermediates: false])
    private var configured = false
    private var latestPixelBuffer: CVPixelBuffer?

    func start() async throws {
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        if status == .notDetermined {
            let allowed = await AVCaptureDevice.requestAccess(for: .video)
            guard allowed else { throw NativeCameraError.permissionDenied }
        } else if status != .authorized {
            throw NativeCameraError.permissionDenied
        }

        try await withCheckedThrowingContinuation { continuation in
            sessionQueue.async {
                do {
                    try self.configureIfNeeded()
                    if !self.session.isRunning {
                        self.session.startRunning()
                    }
                    DispatchQueue.main.async {
                        self.isRunning = true
                    }
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    func stop() async {
        await withCheckedContinuation { continuation in
            sessionQueue.async {
                if self.session.isRunning {
                    self.session.stopRunning()
                }
                self.lock.lock()
                self.latestPixelBuffer = nil
                self.lock.unlock()
                DispatchQueue.main.async {
                    self.isRunning = false
                    continuation.resume()
                }
            }
        }
    }

    func captureFrameDataURL(maxWidth: CGFloat = 480, quality: CGFloat = 0.48) throws -> String {
        lock.lock()
        let pixelBuffer = latestPixelBuffer
        lock.unlock()

        guard let pixelBuffer else { throw NativeCameraError.noFrame }

        let sourceImage = CIImage(cvPixelBuffer: pixelBuffer)
        let sourceWidth = max(sourceImage.extent.width, 1)
        let scale = min(1, maxWidth / sourceWidth)
        let image = sourceImage.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        let bounds = image.extent.integral

        guard let cgImage = ciContext.createCGImage(image, from: bounds) else {
            throw NativeCameraError.imageEncodingFailed
        }

        let uiImage = UIImage(cgImage: cgImage)
        guard let data = uiImage.jpegData(compressionQuality: quality) else {
            throw NativeCameraError.imageEncodingFailed
        }

        return "data:image/jpeg;base64,\(data.base64EncodedString())"
    }

    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        lock.lock()
        latestPixelBuffer = pixelBuffer
        lock.unlock()
    }

    private func configureIfNeeded() throws {
        guard !configured else { return }

        session.beginConfiguration()
        session.sessionPreset = .medium
        defer { session.commitConfiguration() }

        let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back)
            ?? AVCaptureDevice.default(for: .video)
        guard let camera else { throw NativeCameraError.cameraUnavailable }

        let input = try AVCaptureDeviceInput(device: camera)
        guard session.canAddInput(input) else { throw NativeCameraError.cannotAddInput }
        session.addInput(input)

        let output = AVCaptureVideoDataOutput()
        output.alwaysDiscardsLateVideoFrames = true
        output.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
        ]
        output.setSampleBufferDelegate(self, queue: sampleQueue)
        guard session.canAddOutput(output) else { throw NativeCameraError.cannotAddOutput }
        session.addOutput(output)

        if let connection = output.connection(with: .video), connection.isVideoOrientationSupported {
            connection.videoOrientation = .portrait
        }

        configured = true
    }
}

struct NativeCameraPreview: UIViewRepresentable {
    let cameraService: NativeCameraService

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.previewLayer.session = cameraService.session
        view.previewLayer.videoGravity = .resizeAspectFill
        return view
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {
        uiView.previewLayer.session = cameraService.session
        uiView.previewLayer.videoGravity = .resizeAspectFill
        if let connection = uiView.previewLayer.connection, connection.isVideoOrientationSupported {
            connection.videoOrientation = .portrait
        }
    }

    final class PreviewView: UIView {
        override class var layerClass: AnyClass {
            AVCaptureVideoPreviewLayer.self
        }

        var previewLayer: AVCaptureVideoPreviewLayer {
            layer as! AVCaptureVideoPreviewLayer
        }
    }
}
