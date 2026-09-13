import SwiftUI
import AVFoundation
import VisionKit

/// Landing / "Scan to Pair" / connecting / failed states, plus the three
/// camera-permission states.
///
/// The QR scanner is never shown automatically — only an explicit "Scan QR
/// Code" tap enters the camera-check flow. Landing itself is driven by
/// `session.autoReconnectState`, not the camera: the silent mDNS reconnect
/// runs independently of whether the user ever opens the scanner.
// Implementation Notes #10.1: camera is queryable and soft-askable, unlike
// Local Network (#10.2) — `.notDetermined` gets an explanatory screen
// before the native prompt ever fires, `.denied` routes to "Open Settings"
// instead of a dead scanner.
struct PairingView: View {
    let session: PairingSession

    @State private var state: PairingState = .landing

    private enum PairingState: Equatable {
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
                if state == .cameraDenied {
                    checkCameraAndAdvance()
                }
            }
            .onChange(of: session.lastError) { _, newError in
                if let newError {
                    state = .failed(newError)
                }
            }
    }

    @ViewBuilder
    private var content: some View {
        switch state {
        case .landing:
            landingView
        case .cameraPreAsk:
            preAskView
        case .cameraDenied:
            cameraDeniedView
        case .scanning:
            scannerView
        case .connecting:
            ProgressView("Connecting…")
        case .failed(let message):
            failedView(message)
        }
    }

    /// Always shows "Scan QR Code" as an action.
    ///
    /// The silent reconnect (`statusText`, below) is a background
    /// convenience layered on top — never a gate on the manual path.
    // `.notFound` also offers Open Settings alongside the scan action:
    // mDNS browsing produces no error at all when Local Network access is
    // denied (NWBrowser just never calls back with results), so this case
    // can't be attributed to permission-vs-desktop-actually-off the way a
    // WebSocket connect failure can (see Connection.swift's
    // pairingFailureMessage). Naming both possible causes and offering
    // both actions is what actually closes the gap, not a guess.
    private var landingView: some View {
        VStack(spacing: 20) {
            statusText
            Button("Scan QR Code") { checkCameraAndAdvance() }
                .buttonStyle(.borderedProminent)
            if session.autoReconnectState == .notFound {
                Button("Open Settings", action: openSystemSettings)
                    .buttonStyle(.bordered)
            }
        }
    }

    @ViewBuilder
    private var statusText: some View {
        switch session.autoReconnectState {
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
            Text("Couldn't find Buttons desktop automatically. It may not be running, or this app's Local Network access may be blocked — scan the desktop QR code, or check Settings.")
                .multilineTextAlignment(.center)
        }
    }

    /// Entry point into the camera-permission flow — only reached by an
    /// explicit tap (the landing button, or the foreground-return check
    /// below), never on appear.
    private func checkCameraAndAdvance() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            state = .scanning
        case .notDetermined:
            state = .cameraPreAsk
        case .denied, .restricted:
            state = .cameraDenied
        @unknown default:
            state = .cameraDenied
        }
    }

    private var preAskView: some View {
        VStack(spacing: 16) {
            Text("Buttons needs your camera to scan the desktop's pairing code.")
                .multilineTextAlignment(.center)
            Button("Scan QR Code") { requestCameraAccess() }
                .buttonStyle(.borderedProminent)
        }
    }

    private func requestCameraAccess() {
        // The native one-shot prompt fires here, not on appear — the
        // explanatory pre-ask screen above is what makes this a soft ask.
        AVCaptureDevice.requestAccess(for: .video) { granted in
            DispatchQueue.main.async {
                state = granted ? .scanning : .cameraDenied
            }
        }
    }

    private var scannerView: some View {
        QRScannerRepresentable { payload in
            state = .connecting
            session.pair(scannedQR: payload)
        }
        .ignoresSafeArea()
    }

    /// Also offers "Open Settings" alongside the primary retry.
    ///
    /// A pairing failure here can't always be attributed to one cause —
    /// stale token and a blocked Local Network permission both surface as
    /// generic connect failures (Implementation Notes #10.2: Local Network
    /// has no pre-check API, so this can't be resolved to a definite
    /// permission error). Offering both actions instead of guessing wrong.
    private func failedView(_ message: String) -> some View {
        VStack(spacing: 16) {
            Text(message)
                .foregroundStyle(.red)
                .multilineTextAlignment(.center)
            Button("Scan QR Again") { checkCameraAndAdvance() }
                .buttonStyle(.borderedProminent)
            Button("Open Settings", action: openSystemSettings)
                .buttonStyle(.bordered)
        }
    }

    private var cameraDeniedView: some View {
        VStack(spacing: 16) {
            Text("Buttons can't scan without camera access.")
                .multilineTextAlignment(.center)
            Button("Open Settings", action: openSystemSettings)
                .buttonStyle(.borderedProminent)
        }
    }

    private func openSystemSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
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
