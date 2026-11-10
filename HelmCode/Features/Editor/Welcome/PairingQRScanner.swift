//
//  PairingQRScanner.swift
//  HelmCode
//
//  In-app QR scan for `helmcode://pair?url=&c=` (runner setup page).
//

import SwiftUI
import Vision
import VisionKit

struct PairingQRScannerSheet: View {
    var onCode: (String) -> Void
    var onLink: (URL) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if DataScannerViewController.isSupported,
                   DataScannerViewController.isAvailable {
                    DataScannerRepresentable(
                        onCode: { text in
                            onCode(text)
                            dismiss()
                        },
                        onLink: { url in
                            onLink(url)
                            dismiss()
                        }
                    )
                    .ignoresSafeArea()
                } else {
                    ContentUnavailableView(
                        "Camera unavailable",
                        systemImage: "qrcode.viewfinder",
                        description: Text("Type the setup code from the runner terminal instead.")
                    )
                }
            }
            .helmInlineNavigationTitle("Scan pairing QR")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
    }
}

private struct DataScannerRepresentable: UIViewControllerRepresentable {
    var onCode: (String) -> Void
    var onLink: (URL) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onCode: onCode, onLink: onLink)
    }

    func makeUIViewController(context: Context) -> DataScannerHostController {
        let host = DataScannerHostController()
        host.scanner.delegate = context.coordinator
        context.coordinator.scanner = host.scanner
        return host
    }

    func updateUIViewController(_ uiViewController: DataScannerHostController, context: Context) {
        context.coordinator.onCode = onCode
        context.coordinator.onLink = onLink
        uiViewController.scanner.delegate = context.coordinator
        context.coordinator.scanner = uiViewController.scanner
    }

    static func dismantleUIViewController(
        _ uiViewController: DataScannerHostController,
        coordinator: Coordinator
    ) {
        uiViewController.stopIfNeeded()
    }

    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        var onCode: (String) -> Void
        var onLink: (URL) -> Void
        weak var scanner: DataScannerViewController?
        private var handled = false

        init(onCode: @escaping (String) -> Void, onLink: @escaping (URL) -> Void) {
            self.onCode = onCode
            self.onLink = onLink
        }

        func dataScanner(
            _ dataScanner: DataScannerViewController,
            didAdd addedItems: [RecognizedItem],
            allItems: [RecognizedItem]
        ) {
            guard !handled else { return }
            for item in addedItems {
                if case .barcode(let barcode) = item, let payload = barcode.payloadStringValue {
                    handled = true
                    dataScanner.stopScanning()
                    if let url = URL(string: payload), RunnerPairingLink.parse(url) != nil {
                        onLink(url)
                    } else {
                        onCode(payload)
                    }
                    return
                }
            }
        }
    }
}

/// Starts scanning only after the camera view is in the window hierarchy.
/// Calling `startScanning()` from `updateUIViewController` is racy and can
/// tear down a nested presentation on iPad.
private final class DataScannerHostController: UIViewController {
    let scanner: DataScannerViewController = {
        DataScannerViewController(
            recognizedDataTypes: [.barcode(symbologies: [.qr])],
            qualityLevel: .fast,
            recognizesMultipleItems: false,
            isHighFrameRateTrackingEnabled: false,
            isHighlightingEnabled: true
        )
    }()

    private var didStart = false

    override func viewDidLoad() {
        super.viewDidLoad()
        addChild(scanner)
        scanner.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scanner.view)
        NSLayoutConstraint.activate([
            scanner.view.topAnchor.constraint(equalTo: view.topAnchor),
            scanner.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            scanner.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scanner.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ])
        scanner.didMove(toParent: self)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        startIfNeeded()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        stopIfNeeded()
    }

    func startIfNeeded() {
        guard !didStart, !scanner.isScanning else { return }
        guard view.window != nil else { return }
        do {
            try scanner.startScanning()
            didStart = true
        } catch {
            didStart = false
        }
    }

    func stopIfNeeded() {
        if scanner.isScanning {
            scanner.stopScanning()
        }
        didStart = false
    }
}
