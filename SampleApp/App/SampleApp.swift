#if os(visionOS)
import CompositorServices
#endif
import SwiftUI

@main
struct SampleApp: App {
    @StateObject private var sharePlayIntegration = SharePlayIntegrationHelper()
    
    var body: some Scene {
        WindowGroup("MetalSplatter Sample App", id: "main") {
            ContentView()
                .environmentObject(sharePlayIntegration.sessionManager)
        }
#if os(visionOS)
        .windowResizability(.contentSize)
#endif

#if os(macOS)
        WindowGroup(for: ModelConfiguration.self) { configuration in
            MetalKitSceneView(modelIdentifier: configuration.wrappedValue?.modelIdentifier)
                .navigationTitle(configuration.wrappedValue?.modelIdentifier.description ?? "No Model")
        }
#endif // os(macOS)

#if os(visionOS)
        ImmersiveSpace(for: ModelConfiguration.self) { configuration in
            CompositorLayer(configuration: ContentStageConfiguration()) { layerRenderer in
                let renderer = VisionSceneRenderer(layerRenderer)
                sharePlayIntegration.configureForRenderer(renderer)
                Task {
                    do {
                        try await renderer.load(configuration.wrappedValue?.modelIdentifier, usePreprocessComputeShader: configuration.wrappedValue?.usePreprocessComputeShader ?? false)
                    } catch {
                        print("Error loading model: \(error.localizedDescription)")
                    }
                    renderer.startRenderLoop()
                }
            }
        }
        .immersionStyle(selection: .constant(immersionStyle), in: immersionStyle)
#endif // os(visionOS)
    }

#if os(visionOS)
    var immersionStyle: ImmersionStyle {
        if #available(visionOS 2, *) {
            .mixed
        } else {
            .full
        }
    }
#endif // os(visionOS)
}

