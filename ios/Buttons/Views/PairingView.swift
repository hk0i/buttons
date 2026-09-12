import SwiftUI
import AVFoundation
import VisionKit

/// Landing / "Scan to Pair" / connecting / failed states, plus the three
/// camera-permission states. The QR scanner is never shown automatically —
/// only `landing`'s explicit "Scan QR Code" tap enters the camera-check
/// flow (Implementation Notes #10.1: camera is queryable and soft-askable,
/// unlike Local Network #10.2 — `.notDetermined` gets an explanatory
/// screen before the native prompt ever fires, `.denied` routes to "open
/// Settings" instead of a dead scanner). Landing itself is driven by
/// `session.autoReconnectPhase`, not the camera — the silent mDNS
/// reconnect (Files to Touch #17) runs independently of whether the user
/// ever opens the scanner.
struct PairingView: View {
    let session: PairingSession

    @State private var phase: Phase = .landing

    private enum Phase: Equatable {
        case landing
        case cameraPreAsk
        case cameraDenied
        case scanning
        case connecting
        case failed(String)
    }

    var body: some View {
        content
            .padding()
            // Returning from Settings (the "Open Settings" affordance
            // below) re-activates the app but doesn't trigger onAppear —
            // without this, granting camera access there leaves the user
            // stuck on the denied screen with no way back to the scanner.
            // Only escapes `.cameraDenied` specifically — an active
            // `.scanning`/`.connecting`/`.failed` attempt must survive an
            // unrelated foreground event (e.g. Control Center).
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
                if phase == .cameraDenied {
                    checkCameraAndAdvance()
                }
            }
            .onChange(of: session.lastError) { _, newError in
                if let newError {
                    phase = .failed(newError)
                }
            }
    }

    @ViewBuilder
    private var content: some View {
        switch phase {
        case .landing:
            landingView
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

    /// Always shows "Scan QR Code" as an action, regardless of
    /// `autoReconnectPhase` — the silent reconnect is a background
    /// convenience, never a gate on the manual path. `statusText` is the
    /// only thing that changes with the reconnect's progress.
    private var landingView: some View {
        VStack(spacing: 20) {
            statusText
            Button("Scan QR Code") { checkCameraAndAdvance() }
                .buttonStyle(.borderedProminent)
        }
    }

    @ViewBuilder
    private var statusText: some View {
        switch session.autoReconnectPhase {
        case .idle:
            Text("Scan your desktop's QR code to pair.")
                .multilineTextAlignment(.center)
        case .searching:
            VStack(spacing: 8) {
                ProgressView()
                Text("Looking for your paired desktop on this network…")
                    .multilineTextAlignment(.center)
            }
        case .notFound:
            Text("Couldn't find your paired desktop automatically — scan its QR code to reconnect.")
                .multilineTextAlignment(.center)
        }
    }

    /// Entry point into the camera-permission flow — only reached by an
    /// explicit tap (the landing button, or the foreground-return check
    /// below), never on appear.
    private func checkCameraAndAdvance() {
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
            session.pair(scannedQR: payload)
        }
        .ignoresSafeArea()
    }

    private func failedView(_ message: String) -> some View {
        VStack(spacing: 16) {
            Text(message)
                .foregroundStyle(.red)
                .multilineTextAlignment(.center)
            Button("Scan again") { checkCameraAndAdvance() }
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
    PairingView(session: PairingSession(connection: DesktopConnection()))
}
