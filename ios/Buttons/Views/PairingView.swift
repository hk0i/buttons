import AVFoundation
import SwiftUI
import VisionKit

/// Landing / "Scan to Pair" / connecting / failed states, plus the three
/// camera-permission states.
///
/// The QR scanner is never shown automatically — only an explicit "Scan QR
/// Code" tap enters the camera-check flow. Landing itself is driven by
/// `session.autoReconnectState`, not the camera: the silent mDNS reconnect
/// runs independently of whether the user ever opens the scanner.
// Camera is queryable and soft-askable, unlike Local Network — see slice
// 07 spec, § Implementation Notes, "Two permissions, two different
// shapes." `.notDetermined` gets an explanatory screen before the native
// prompt ever fires, `.denied` routes to "Open Settings" instead of a
// dead scanner.
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
            // Cancels automatically when view disappears.
            .task { await session.watchDeviceRows() }
            // Returning from Settings (the "Open Settings" affordance
            // below) re-activates the app but doesn't trigger onAppear —
            // without this, granting camera access there leaves the user
            // stuck on the denied screen with no way back to the scanner.
            // Only escapes `.cameraDenied` specifically — an active
            // `.scanning`/`.connecting`/`.failed` attempt must survive an
            // unrelated foreground event (e.g. Control Center).
            .onReceive(
                NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)
            ) { _ in
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

    /// The silent reconnect (`autoReconnectStatus`, below) is a background
    /// convenience layered on top — never a gate on the manual "Scan QR
    /// Code" row, still present even when Local Network is confirmed
    /// denied (scanning fails the same way pairing would, with a definite
    /// `failedView` message instead of a quietly disabled row).
    // Open Settings shows whenever denial is confirmed
    // (`session.isLocalNetworkDenied`), independent of
    // `autoReconnectState` — denial affects `.idle` and `.notFound`
    // equally now. See Discovery.swift and slice 07 spec, §
    // Implementation Notes, "Local Network (mDNS/`NWBrowser`)," amended
    // 2026-09-13.
    private var landingView: some View {
        VStack(spacing: 20) {
            VStack(spacing: 8) {
                Text("Select a desktop to connect")
                    .font(.headline)
                autoReconnectStatus
            }
            deviceRowsList
            if session.isLocalNetworkDenied {
                Button("Open Settings", action: openSystemSettings)
                    .buttonStyle(.bordered)
            }
        }
    }

    /// Known desktops (annotated by live discovery), freshly-discovered
    /// unpaired ones, and a "Scan QR Code" row — always present, so a
    /// fresh install with nothing known yet still sees one tappable row
    /// and learns the same interaction the real list later uses.
    private var deviceRowsList: some View {
        VStack(spacing: 8) {
            ForEach(session.deviceRows) { row in
                deviceRow(row)
            }
            if !session.deviceRows.isEmpty {
                Divider()
            }
            Button {
                checkCameraAndAdvance()
            } label: {
                deviceRowLabel("Scan QR Code…", trailing: "Scan", isInteractive: true)
            }
            .buttonStyle(.plain)
            .accessibilityHint("Opens the camera to pair a new desktop")
        }
    }

    @ViewBuilder
    private func deviceRow(_ row: PairedDeviceRow) -> some View {
        switch row.status {
        case .connectable:
            Button {
                state = .connecting
                session.connect(to: row)
            } label: {
                deviceRowLabel(row.name, trailing: "Connect", isInteractive: true)
            }
            .buttonStyle(.plain)
            .accessibilityHint("Connects to this desktop")
        case .offline:
            deviceRowLabel(row.name, trailing: "Offline", isInteractive: false)
                .foregroundStyle(.secondary)
                .accessibilityLabel("\(row.name), offline")
        case .pairable:
            Button {
                checkCameraAndAdvance()
            } label: {
                deviceRowLabel(row.name, trailing: "Pair", isInteractive: true)
            }
            .buttonStyle(.plain)
            .accessibilityHint("Opens the camera to pair this desktop")
        }
    }

    /// `isInteractive` tints the trailing label with the app's accent
    /// color — the system's own primary-action mechanism, so a real theme
    /// at step 12 needs no change here, just a new `AccentColor` asset.
    private func deviceRowLabel(_ name: String, trailing: String, isInteractive: Bool) -> some View {
        HStack {
            Text(name)
            Spacer()
            Text(trailing)
                .foregroundStyle(isInteractive ? Color.accentColor : Color.secondary)
        }
        .padding()
        .frame(maxWidth: .infinity, minHeight: 44)
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(.secondary.opacity(0.3)))
    }

    @ViewBuilder
    private var autoReconnectStatus: some View {
        switch session.autoReconnectState {
        case .idle where session.isLocalNetworkDenied:
            localNetworkDeniedText
        case .idle:
            EmptyView()
        case .searching:
            VStack(spacing: 8) {
                ProgressView()
                Text("Looking for your paired desktop on this network…")
                    .multilineTextAlignment(.center)
            }
        case .notFound where session.isLocalNetworkDenied:
            localNetworkDeniedText
        case .notFound:
            Text("Couldn't find it automatically — select it below if it's listed, or scan its QR code.")
                .multilineTextAlignment(.center)
        }
    }

    /// Shared copy for both `.idle` and `.notFound` once denial is
    /// confirmed — doesn't suggest "scan the QR code instead," since a
    /// denied Local Network permission blocks the QR/connect path too
    /// (`URLSessionWebSocketTask` just reports it as -1009, "offline"),
    /// not only mDNS discovery. See slice 07 spec, § Implementation
    /// Notes, "Local Network (mDNS/`NWBrowser`)," amended 2026-09-13.
    private var localNetworkDeniedText: some View {
        Text(
            "Buttons needs Local Network access to find or connect to your desktop. Turn it on in Settings to continue."
        )
        .multilineTextAlignment(.center)
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
    /// `session.isLocalNetworkDenied` resolves one specific ambiguity —
    /// when true, the failure is definitely permission, not a stale token
    /// or wrong network, and the copy says so instead of showing
    /// `message`. Otherwise this stays a genuine hedge: a stale token and
    /// an unconfirmed blocked Local Network permission both surface as
    /// the same generic connect failure, with no way to tell them apart
    /// from the error alone. Offering both actions either way is what
    /// closes the gap without guessing wrong.
    private func failedView(_ message: String) -> some View {
        VStack(spacing: 16) {
            if session.isLocalNetworkDenied {
                localNetworkDeniedText
                    .foregroundStyle(.red)
            } else {
                Text(message)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
            }
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
/// feed.
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
    PairingView(
        session: PairingSession(
            connection: DesktopConnection(), discovery: DesktopDiscovery(), pairingStore: PairingStore()))
}
