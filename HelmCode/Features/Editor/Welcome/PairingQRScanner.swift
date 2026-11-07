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

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let scanner = DataScannerViewController(
            recognizedDataTypes: [.barcode(symbologies: [.qr])],
            qualityLevel: .fast,
            recognizesMultipleItems: false,
            isHighFrameRateTrackingEnabled: false,
            isHighlightingEnabled: true
        )
        scanner.delegate = context.coordinator
        context.coordinator.scanner = scanner
        return scanner
    }

    func updateUIViewController(_ uiViewController: DataScannerViewController, context: Context) {
        context.coordinator.onCode = onCode
        context.coordinator.onLink = onLink
        if !uiViewController.isScanning {
            try? uiViewController.startScanning()
        }
    }

    static func dismantleUIViewController(
        _ uiViewController: DataScannerViewController,
        coordinator: Coordinator
    ) {
        if uiViewController.isScanning {
            uiViewController.stopScanning()
        }
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
