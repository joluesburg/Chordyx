//
//  SessionJoinQR.swift
//  Chordyx
//

import Foundation
import SwiftUI
#if canImport(CoreImage)
import CoreImage.CIFilterBuiltins
#endif

enum SessionJoinQR {
    static let scheme = "chordyx"
    static let host = "join"

    static func deepLink(for code: String) -> URL? {
        let normalized = RemoteJoinCode.normalize(code)
        guard RemoteJoinCode.isValid(normalized) else { return nil }
        var components = URLComponents()
        components.scheme = scheme
        components.host = host
        components.queryItems = [URLQueryItem(name: "code", value: normalized)]
        return components.url
    }

    static func parseCode(from url: URL) -> String? {
        guard url.scheme?.lowercased() == scheme,
              url.host?.lowercased() == host,
              let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems,
              let raw = items.first(where: { $0.name == "code" })?.value else { return nil }
        let normalized = RemoteJoinCode.normalize(raw)
        return RemoteJoinCode.isValid(normalized) ? normalized : nil
    }

    /// Accepts a deep link URL or a bare 6-character join code from a QR payload.
    static func parseScannedValue(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if let url = URL(string: trimmed), let code = parseCode(from: url) {
            return code
        }
        let normalized = RemoteJoinCode.normalize(trimmed)
        return RemoteJoinCode.isValid(normalized) ? normalized : nil
    }

    #if os(iOS) || os(macOS)
    static func image(for code: String, dimension: CGFloat = 240) -> Image? {
        guard let url = deepLink(for: code)?.absoluteString.data(using: .utf8) else { return nil }
        let context = CIContext()
        let filter = CIFilter.qrCodeGenerator()
        filter.message = url
        filter.correctionLevel = "M"
        guard let output = filter.outputImage else { return nil }
        let scale = dimension / output.extent.width
        let scaled = output.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        guard let cgImage = context.createCGImage(scaled, from: scaled.extent) else { return nil }
        #if os(iOS)
        return Image(uiImage: UIImage(cgImage: cgImage))
        #else
        return Image(nsImage: NSImage(cgImage: cgImage, size: NSSize(width: dimension, height: dimension)))
        #endif
    }
    #endif
}

#if os(iOS)
import UIKit
typealias PlatformImage = UIImage
#elseif os(macOS)
import AppKit
typealias PlatformImage = NSImage
#endif

struct SessionJoinQRSheet: View {
    let joinCode: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Text(String(localized: "Scan to join over the Internet"))
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.textSecondary)
                if let qr = SessionJoinQR.image(for: joinCode) {
                    qr
                        .interpolation(.none)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 240, height: 240)
                        .padding()
                        .background(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                Text(joinCode)
                    .font(.system(.title2, design: .monospaced).weight(.bold))
                    .foregroundStyle(AppTheme.accent)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(AppTheme.background)
            .navigationTitle(String(localized: "Join QR"))
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "Done")) { dismiss() }
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}

#if os(iOS)
import AVFoundation

struct SessionJoinQRScannerView: UIViewControllerRepresentable {
    var isScanningEnabled: Bool
    var onCode: (String) -> Void

    func makeUIViewController(context: Context) -> ScannerViewController {
        let controller = ScannerViewController()
        controller.onCode = onCode
        return controller
    }

    func updateUIViewController(_ controller: ScannerViewController, context: Context) {
        controller.setScanningEnabled(isScanningEnabled)
    }

    final class ScannerViewController: UIViewController, AVCaptureMetadataOutputObjectsDelegate {
        var onCode: ((String) -> Void)?
        private let session = AVCaptureSession()
        private let sessionQueue = DispatchQueue(label: "Espinosa.Chordyx.qr-scanner.session")
        private var previewLayer: AVCaptureVideoPreviewLayer?
        private var didScan = false
        private var isConfigured = false
        private let statusLabel = UILabel()

        override func viewDidLoad() {
            super.viewDidLoad()
            view.backgroundColor = .black
            configureStatusLabel()
            requestCameraAccessIfNeeded()
        }

        override func viewDidLayoutSubviews() {
            super.viewDidLayoutSubviews()
            previewLayer?.frame = view.layer.bounds
        }

        override func viewWillDisappear(_ animated: Bool) {
            super.viewWillDisappear(animated)
            stopSession()
        }

        func setScanningEnabled(_ enabled: Bool) {
            if enabled {
                if didScan { didScan = false }
                startSessionIfNeeded()
            } else {
                stopSession()
            }
        }

        private func configureStatusLabel() {
            statusLabel.translatesAutoresizingMaskIntoConstraints = false
            statusLabel.textColor = .white
            statusLabel.font = .preferredFont(forTextStyle: .footnote)
            statusLabel.numberOfLines = 0
            statusLabel.textAlignment = .center
            statusLabel.isHidden = true
            view.addSubview(statusLabel)
            NSLayoutConstraint.activate([
                statusLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
                statusLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor),
                statusLabel.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 16),
                statusLabel.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -16),
            ])
        }

        private func requestCameraAccessIfNeeded() {
            switch AVCaptureDevice.authorizationStatus(for: .video) {
            case .authorized:
                installCameraPreview()
            case .notDetermined:
                AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                    DispatchQueue.main.async {
                        guard let self else { return }
                        if granted {
                            self.installCameraPreview()
                        } else {
                            self.showStatusMessage(String(localized: "Camera access is required to scan QR codes."))
                        }
                    }
                }
            default:
                showStatusMessage(String(localized: "Enable camera access in Settings to scan QR codes."))
            }
        }

        private func installCameraPreview() {
            guard previewLayer == nil else { return }
            let preview = AVCaptureVideoPreviewLayer(session: session)
            preview.videoGravity = .resizeAspectFill
            preview.frame = view.layer.bounds
            view.layer.insertSublayer(preview, at: 0)
            previewLayer = preview
            sessionQueue.async { [weak self] in
                self?.configureSessionIfNeeded()
            }
        }

        private func configureSessionIfNeeded() {
            guard !isConfigured else {
                startSessionIfNeeded()
                return
            }

            session.beginConfiguration()
            defer { session.commitConfiguration() }

            session.inputs.forEach { session.removeInput($0) }
            session.outputs.forEach { session.removeOutput($0) }

            guard let device = AVCaptureDevice.default(for: .video),
                  let input = try? AVCaptureDeviceInput(device: device),
                  session.canAddInput(input) else {
                DispatchQueue.main.async { [weak self] in
                    self?.showStatusMessage(String(localized: "Camera unavailable on this device."))
                }
                return
            }
            session.addInput(input)

            let output = AVCaptureMetadataOutput()
            guard session.canAddOutput(output) else {
                DispatchQueue.main.async { [weak self] in
                    self?.showStatusMessage(String(localized: "Could not start the QR scanner."))
                }
                return
            }
            session.addOutput(output)
            output.setMetadataObjectsDelegate(self, queue: DispatchQueue(label: "Espinosa.Chordyx.qr-scanner.metadata"))
            output.metadataObjectTypes = [.qr]

            isConfigured = true
            startSessionIfNeeded()
        }

        private func startSessionIfNeeded() {
            sessionQueue.async { [weak self] in
                guard let self, self.isConfigured, !self.didScan, !self.session.isRunning else { return }
                self.session.startRunning()
            }
        }

        private func stopSession() {
            sessionQueue.async { [weak self] in
                guard let self, self.session.isRunning else { return }
                self.session.stopRunning()
            }
        }

        private func showStatusMessage(_ message: String) {
            statusLabel.text = message
            statusLabel.isHidden = false
        }

        func metadataOutput(
            _ output: AVCaptureMetadataOutput,
            didOutput metadataObjects: [AVMetadataObject],
            from connection: AVCaptureConnection
        ) {
            guard !didScan else { return }
            guard let object = metadataObjects.first as? AVMetadataMachineReadableCodeObject,
                  object.type == .qr,
                  let value = object.stringValue,
                  let code = SessionJoinQR.parseScannedValue(value) else { return }

            didScan = true
            stopSession()

            DispatchQueue.main.async { [weak self] in
                self?.onCode?(code)
            }
        }
    }
}
#endif
