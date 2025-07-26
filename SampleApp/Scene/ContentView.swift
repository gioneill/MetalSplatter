import SwiftUI
import RealityKit
import UniformTypeIdentifiers

struct ContentView: View {
    @State private var isPickingFile = false
    @State private var usePreprocessComputeShader = false

#if os(macOS)
    @Environment(\.openWindow) private var openWindow
#elseif os(iOS)
    @State private var navigationPath = NavigationPath()

    private func openWindow(value: ModelConfiguration) {
        navigationPath.append(value)
    }
#elseif os(visionOS)
    @Environment(\.openImmersiveSpace) var openImmersiveSpace
    @Environment(\.dismissImmersiveSpace) var dismissImmersiveSpace

    @State var immersiveSpaceIsShown = false

    private func openWindow(value: ModelConfiguration) {
        Task {
            switch await openImmersiveSpace(value: value) {
            case .opened:
                immersiveSpaceIsShown = true
            case .error, .userCancelled:
                break
            @unknown default:
                break
            }
        }
    }
#endif

    var body: some View {
#if os(macOS) || os(visionOS)
        mainView
#elseif os(iOS)
        NavigationStack(path: $navigationPath) {
            mainView
                .navigationDestination(for: ModelConfiguration.self) { configuration in
                    MetalKitSceneView(modelIdentifier: configuration.modelIdentifier)
                        .navigationTitle(configuration.modelIdentifier.description)
                }
        }
#endif // os(iOS)
    }

    @ViewBuilder
    var mainView: some View {
        VStack(spacing: 20) {
            Text("MetalSplatter SampleApp")
                .font(.title)

            Button("Read Scene File") {
                isPickingFile = true
            }
            .padding()
            .buttonStyle(.borderedProminent)
            .disabled(isPickingFile)
#if os(visionOS)
            .disabled(immersiveSpaceIsShown)
#endif
            .fileImporter(isPresented: $isPickingFile,
                          allowedContentTypes: [
                            UTType(filenameExtension: "ply")!,
                            UTType(filenameExtension: "splat")!,
                          ]) {
                isPickingFile = false
                switch $0 {
                case .success(let url):
                    _ = url.startAccessingSecurityScopedResource()
                    Task {
                        // This is a sample app. In a real app, this should be more tightly scoped, not using a silly timer.
                        try await Task.sleep(for: .seconds(10))
                        url.stopAccessingSecurityScopedResource()
                    }
                    openWindow(value: ModelConfiguration(modelIdentifier: ModelIdentifier.gaussianSplat(url), usePreprocessComputeShader: usePreprocessComputeShader))
                case .failure:
                    break
                }
            }

            Button("Show Sample Box") {
                openWindow(value: ModelConfiguration(modelIdentifier: ModelIdentifier.sampleBox, usePreprocessComputeShader: usePreprocessComputeShader))
            }
            .padding()
            .buttonStyle(.borderedProminent)
#if os(visionOS)
            .disabled(immersiveSpaceIsShown)
#endif
            
            Button("Show RV Sample") {
                if let rvModel = ModelIdentifier.rvSample {
                    openWindow(value: ModelConfiguration(modelIdentifier: rvModel, usePreprocessComputeShader: usePreprocessComputeShader))
                }
            }
            .padding()
            .buttonStyle(.borderedProminent)
#if os(visionOS)
            .disabled(immersiveSpaceIsShown)
#endif
            
#if os(visionOS)
            Button("Dismiss Immersive Space") {
                Task {
                    await dismissImmersiveSpace()
                    immersiveSpaceIsShown = false
                }
            }
            .disabled(!immersiveSpaceIsShown)
#endif

            Toggle("Use Preprocess Compute Shader", isOn: $usePreprocessComputeShader)
                .frame(width: 500)
                .padding(.horizontal)
        }
        .padding(30)
    }
}

#if os(visionOS) && DEBUG
#Preview {
    ContentView()
}
#endif
