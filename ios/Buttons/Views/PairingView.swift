import SwiftUI
import AVFoundation
import VisionKit

/// "Scan to Pair" / connecting / failed states, plus the three
/// camera-permission states. Per Implementation Notes #10.1: camera is
/// queryable and soft-askable (unlike Local Network, #10.2) —
/// `.notDetermined` gets an explanatory screen before the native prompt
/// ever fires, `.denied` routes to "open Settings" instead of a dead
/// scanner.
struct PairingView: View {
    let coordinator: PairingCoordinator

    @State private var phase: Phase = .checkingCamera

    private enum Phase: Equatable {
        case checkingCamera
        case cameraPreAsk
        case cameraDenied
        case scanning
        case connecting
        case failed(String)
    }

    var body: some View {
        content
            .padding()
            .onAppear(perform: refreshCameraStatus)
            .onChange(of: coordinator.lastError) { _, newError in
                if let newError {
                    phase = .failed(newError)
                }
            }
    }

    @ViewBuilder
    private var content: some View {
        switch phase {
        case .checkingCamera:
            ProgressView()
        case .cameraPreAsk:
            preAskView
        case .cameraDenied:
            openSettingsView
        case .scanning:
            scannerView
        case .connecting:
            ProgressView("Connecting…")
        case .failed(let message):
            failedView(message)
        }
    }

    private func refreshCameraStatus() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            phase = .scanning
        case .notDetermined:
            phase = .cameraPreAsk
        case .denied, .restricted:
            phase = .cameraDenied
        @unknown default:
            phase = .cameraDenied
        }
    }

    private var preAskView: some View {
        VStack(spacing: 16) {
            Text("Buttons needs your camera to scan the desktop's pairing code.")
                .multilineTextAlignment(.center)
            Button("Scan") { requestCameraAccess() }
                .buttonStyle(.borderedProminent)
        }
    }

    private func requestCameraAccess() {
        // The native one-shot prompt fires here, not on appear — the
        // explanatory pre-ask screen above is what makes this a soft ask.
        AVCaptureDevice.requestAccess(for: .video) { granted in
            DispatchQueue.main.async {
                phase = granted ? .scanning : .cameraDenied
            }
        }
    }

    private var scannerView: some View {
        QRScannerRepresentable { payload in
            phase = .connecting
            coordinator.pair(scannedQR: payload)
        }
        .ignoresSafeArea()
    }

    private func failedView(_ message: String) -> some View {
        VStack(spacing: 16) {
            Text(message)
                .foregroundStyle(.red)
                .multilineTextAlignment(.center)
            Button("Scan again") { phase = .scanning }
                .buttonStyle(.borderedProminent)
        }
    }

    private var openSettingsView: some View {
        VStack(spacing: 16) {
            Text("Buttons can't scan without camera access.")
                .multilineTextAlignment(.center)
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            .buttonStyle(.borderedProminent)
        }
    }
}

/// Wraps `DataScannerViewController` (VisionKit, iOS 16+) for a single QR
/// payload. Requires a real device or a Simulator with a virtual camera
/// feed — see Implementation Notes #11.
private struct QRScannerRepresentable: UIViewControllerRepresentable {
    let onScan: (String) -> Void

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let controller = DataScannerViewController(
            recognizedDataTypes: [.barcode(symbologies: [.qr])],
            qualityLevel: .balanced,
            isHighFrameRateTrackingEnabled: false,
            isPinchToZoomEnabled: false,
            isGuidanceEnabled: true,
            isHighlightingEnabled: false
        )
        controller.delegate = context.coordinator
        try? controller.startScanning()
        return controller
    }

    func updateUIViewController(_ uiViewController: DataScannerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onScan: onScan)
    }

    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        let onScan: (String) -> Void

        init(onScan: @escaping (String) -> Void) {
            self.onScan = onScan
        }

        func dataScanner(
            _ dataScanner: DataScannerViewController,
            didAdd addedItems: [RecognizedItem],
            allItems: [RecognizedItem]
        ) {
            for item in addedItems {
                if case let .barcode(barcode) = item, let payload = barcode.payloadStringValue {
                    dataScanner.stopScanning()
                    onScan(payload)
                    return
                }
            }
        }
    }
}

#Preview {
    PairingView(coordinator: PairingCoordinator(connection: DesktopConnection()))
}
