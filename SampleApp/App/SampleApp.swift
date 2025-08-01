#if os(visionOS)
import CompositorServices
import GroupActivities
#endif
import SwiftUI

@main
struct SampleApp: App {
    @StateObject private var sharePlayIntegration = SharePlayIntegrationHelper()
    @State private var currentRenderer: VisionSceneRenderer?
    
    var body: some Scene {
        WindowGroup("MetalSplatter Sample App", id: "main") {
            ContentView()
                .environmentObject(sharePlayIntegration.sessionManager)
        }
#if os(visionOS)
        .windowResizability(.contentSize)
        // visionOS 26: Scene association for SharePlay activities
        .handlesExternalEvents(matching: Set([SplatViewingActivity.activityIdentifier]))
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
                print("🎨 CompositorLayer created with configuration: \(String(describing: configuration.wrappedValue))")
                let renderer = VisionSceneRenderer(layerRenderer)

                // Keep a strong ref
                currentRenderer = renderer
                print("🔒 Renderer stored at app level")

                sharePlayIntegration.configureForRenderer(renderer)
                
                // Start the rendering pipeline in the CompositorLayer closure
                Task { @MainActor in
                    print("🔄 Starting model load task...")
                    do {
                        let modelId = configuration.wrappedValue?.modelIdentifier
                        let usePreprocess = configuration.wrappedValue?.usePreprocessComputeShader ?? false
                        print("📦 Loading model: \(String(describing: modelId)), usePreprocess: \(usePreprocess)")
                        try await renderer.load(modelId, usePreprocessComputeShader: usePreprocess)
                        print("✅ Model loaded successfully")
                    } catch {
                        print("❌ Error loading model: \(error.localizedDescription)")
                        print("❌ Full error: \(error)")
                    }
                    print("🏃 Starting render loop...")
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

