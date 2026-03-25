//
//  BarcodeScannerView.swift
//  MacroBitt
//

import SwiftUI
import AVFoundation

// MARK: - Private Types

private struct ScannedFoodItem: Identifiable {
    let id = UUID()
    let foodItem: NutritionixFoodItem
}

private enum FallbackMode: Identifiable {
    case search, manual
    var id: Self { self }
}

// MARK: - BarcodeScannerView

struct BarcodeScannerView: View {
    let service: any NutritionixServiceProtocol
    let targetDate: Date

    @State private var isPaused = false
    @State private var isLoading = false
    @State private var foundItem: ScannedFoodItem? = nil
    @State private var showNotFoundAlert = false
    @State private var showErrorAlert = false
    @State private var errorMessage: String? = nil
    @State private var fallbackMode: FallbackMode? = nil

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            CameraPreviewView(isPaused: isPaused, onDetected: handleScan)
                .ignoresSafeArea()

            viewfinderOverlay

            if isLoading {
                Color.black.opacity(0.5).ignoresSafeArea()
                ProgressView("Looking up barcode…")
                    .tint(.white)
                    .foregroundStyle(.white)
            }
        }
        .alert("Barcode Not Found", isPresented: $showNotFoundAlert) {
            Button("Search Food")  { fallbackMode = .search }
            Button("Add Manually") { fallbackMode = .manual }
            Button("Try Again", role: .cancel) { isPaused = false }
        } message: {
            Text("No nutrition data found for this barcode.")
        }
        .alert("Error", isPresented: $showErrorAlert) {
            Button("Try Again", role: .cancel) { isPaused = false }
        } message: {
            Text(errorMessage ?? "An unknown error occurred.")
        }
        .sheet(item: $foundItem) { wrapper in
            AddFoodEntryView(nutritionixItem: wrapper.foodItem, date: targetDate)
        }
        .sheet(item: $fallbackMode) { mode in
            switch mode {
            case .search: FoodSearchView(targetDate: targetDate, service: service)
            case .manual: AddFoodEntryView(date: targetDate)
            }
        }
    }

    // MARK: - Viewfinder Overlay

    private var viewfinderOverlay: some View {
        VStack {
            Spacer()
            RoundedRectangle(cornerRadius: 12)
                .stroke(.white, lineWidth: 2)
                .frame(width: 260, height: 160)
                .overlay(alignment: .bottom) {
                    Text("Align barcode within frame")
                        .font(.caption)
                        .foregroundStyle(.white)
                        .padding(.bottom, -20)
                }
            Spacer()
            Button("Cancel") { dismiss() }
                .buttonStyle(.bordered)
                .tint(.white)
                .padding(.bottom, 48)
        }
    }

    // MARK: - Scan Handler

    private func handleScan(_ code: String) {
        guard !isPaused, !isLoading else { return }
        isPaused = true
        isLoading = true
        Task {
            do {
                let item = try await service.barcodeSearch(upc: code)
                foundItem = ScannedFoodItem(foodItem: item)
            } catch NutritionixError.noResults {
                showNotFoundAlert = true
            } catch {
                errorMessage = (error as? NutritionixError)?.errorDescription
                               ?? error.localizedDescription
                showErrorAlert = true
            }
            isLoading = false
        }
    }
}

// MARK: - Camera Preview (UIViewRepresentable)

private struct CameraPreviewView: UIViewRepresentable {
    let isPaused: Bool
    let onDetected: (String) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onDetected: onDetected)
    }

    func makeUIView(context: Context) -> _PreviewUIView {
        let view = _PreviewUIView()
        context.coordinator.setup(in: view)
        return view
    }

    func updateUIView(_ uiView: _PreviewUIView, context: Context) {
        let session = context.coordinator.session
        if isPaused {
            DispatchQueue.global(qos: .userInitiated).async { session?.stopRunning() }
        } else if !(session?.isRunning ?? false) {
            DispatchQueue.global(qos: .userInitiated).async { session?.startRunning() }
        }
    }
}

// MARK: - Preview UIView

private final class _PreviewUIView: UIView {
    var previewLayer: AVCaptureVideoPreviewLayer?

    override func layoutSubviews() {
        super.layoutSubviews()
        previewLayer?.frame = bounds
    }
}

// MARK: - Coordinator

private final class BarcodeScannerCoordinator: NSObject, AVCaptureMetadataOutputObjectsDelegate {
    var session: AVCaptureSession?
    private let onDetected: (String) -> Void

    init(onDetected: @escaping (String) -> Void) {
        self.onDetected = onDetected
    }

    func setup(in view: _PreviewUIView) {
        let session = AVCaptureSession()

        guard let device = AVCaptureDevice.default(for: .video),
              let input = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(input) else { return }
        session.addInput(input)

        let output = AVCaptureMetadataOutput()
        guard session.canAddOutput(output) else { return }
        session.addOutput(output)
        output.setMetadataObjectsDelegate(self, queue: .main)
        output.metadataObjectTypes = [.ean8, .ean13, .upce, .code128]

        let preview = AVCaptureVideoPreviewLayer(session: session)
        preview.videoGravity = .resizeAspectFill
        view.layer.addSublayer(preview)
        view.previewLayer = preview

        self.session = session
        DispatchQueue.global(qos: .userInitiated).async { session.startRunning() }
    }

    func metadataOutput(_ output: AVCaptureMetadataOutput,
                        didOutput metadataObjects: [AVMetadataObject],
                        from connection: AVCaptureConnection) {
        guard let obj = metadataObjects.first as? AVMetadataMachineReadableCodeObject,
              let value = obj.stringValue else { return }
        onDetected(value)
    }
}

// MARK: - Coordinator typealias (UIViewRepresentable conformance)

private extension CameraPreviewView {
    typealias Coordinator = BarcodeScannerCoordinator
}
