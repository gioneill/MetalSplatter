import SwiftUI
import RealityKit
import UniformTypeIdentifiers

struct ContentView: View {
    @State private var isPickingFile = false
    @State private var usePreprocessComputeShader = false
    @State private var isLoadingModel = false
    @State private var showOriginSavedMessage = false
    @EnvironmentObject private var sharePlaySessionManager: SharePlaySessionManager

#if os(macOS)
    @Environment(\.openWindow) private var openWindow
    
    init(immersiveSpaceIsShown: Bool = false) {
        // No-op init for macOS
    }
#elseif os(iOS)
    @State private var navigationPath = NavigationPath()
    
    init(immersiveSpaceIsShown: Bool = false) {
        // No-op init for iOS
    }

    private func openWindow(value: ModelConfiguration) {
        navigationPath.append(value)
    }
#elseif os(visionOS)
    @Environment(\.openImmersiveSpace) var openImmersiveSpace
    @Environment(\.dismissImmersiveSpace) var dismissImmersiveSpace

    @State var immersiveSpaceIsShown = false
    
    init(immersiveSpaceIsShown: Bool = false) {
        self._immersiveSpaceIsShown = State(initialValue: immersiveSpaceIsShown)
    }

    private func openWindow(value: ModelConfiguration) {
        print("🪟 openWindow called with value: \(value)")
        isLoadingModel = true
        Task {
            print("🪟 About to open immersive space...")
            switch await openImmersiveSpace(value: value) {
            case .opened:
                print("✅ Immersive space opened successfully")
                immersiveSpaceIsShown = true
                
                // Notify SharePlay about immersive scene
                if sharePlaySessionManager.isSharePlayActive {
                    sharePlaySessionManager.sendImmersiveSceneUpdate(
                        isActive: true,
                        modelIdentifier: value.modelIdentifier
                    )
                }
                
                // Wait a bit for the model to load
                try? await Task.sleep(for: .seconds(3))
                isLoadingModel = false
            case .error:
                print("❌ Error opening immersive space")
                isLoadingModel = false
            case .userCancelled:
                print("❌ User cancelled immersive space")
                isLoadingModel = false
            @unknown default:
                print("❌ Unknown result from openImmersiveSpace")
                isLoadingModel = false
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
            
#if os(visionOS)
            if isLoadingModel {
                ProgressView("Loading model...")
                    .padding()
            }
#endif

            Button("Read Scene File") {
                isPickingFile = true
            }
            .buttonStyle(.borderedProminent)
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
                    print("📁 File selected: \(url.lastPathComponent)")
                    print("📁 Full URL: \(url)")
                    _ = url.startAccessingSecurityScopedResource()
                    Task {
                        // This is a sample app. In a real app, this should be more tightly scoped, not using a silly timer.
                        try await Task.sleep(for: .seconds(10))
                        url.stopAccessingSecurityScopedResource()
                    }
                    let modelConfig = ModelConfiguration(modelIdentifier: ModelIdentifier.gaussianSplat(url), usePreprocessComputeShader: usePreprocessComputeShader)
                    print("📁 Created model configuration: \(modelConfig)")
                    openWindow(value: modelConfig)
                case .failure:
                    break
                }
            }

            Button("Show Sample Box") {
                openWindow(value: ModelConfiguration(modelIdentifier: ModelIdentifier.sampleBox, usePreprocessComputeShader: usePreprocessComputeShader))
            }
            .buttonStyle(.borderedProminent)
#if os(visionOS)
            .disabled(immersiveSpaceIsShown)
#endif
            
#if os(visionOS)
            if immersiveSpaceIsShown {
                Button("Dismiss Immersive Space") {
                    Task {
                        await dismissImmersiveSpace()
                        immersiveSpaceIsShown = false
                        isLoadingModel = false
                        
                        // Notify SharePlay about exiting immersive scene
                        if sharePlaySessionManager.isSharePlayActive {
                            sharePlaySessionManager.sendImmersiveSceneUpdate(
                                isActive: false,
                                modelIdentifier: nil
                            )
                        }
                    }
                }
                .disabled(isLoadingModel)
                
                Button("Set new origin") {
                    NotificationCenter.default.post(
                        name: NSNotification.Name("SetNewOrigin"),
                        object: nil
                    )
                    
                    // If SharePlay is active, sync the origin change
                    if sharePlaySessionManager.isSharePlayActive {
                        NotificationCenter.default.post(
                            name: NSNotification.Name("SharePlaySyncOrigin"),
                            object: nil
                        )
                    }
                }
                .disabled(isLoadingModel)
            }
#endif

            Toggle("Use Preprocess Compute Shader", isOn: $usePreprocessComputeShader)
                .frame(width: 500)
                .padding(.horizontal)
        }
        .padding()
        .overlay(
            // Origin saved feedback message
            Group {
                if showOriginSavedMessage {
                    Text("New origin saved!")
                        .font(.headline)
                        .foregroundColor(.white)
                        .padding()
                        .background(Color.green.opacity(0.8))
                        .cornerRadius(10)
                        .transition(.opacity)
                }
            }
        )
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("OriginSaved"))) { _ in
            withAnimation(.easeInOut(duration: 0.3)) {
                showOriginSavedMessage = true
            }
            
            // Hide message after 2 seconds
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                withAnimation(.easeInOut(duration: 0.3)) {
                    showOriginSavedMessage = false
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("EnterImmersiveSpaceRequested"))) { notification in
            if let modelIdentifier = notification.userInfo?["modelIdentifier"] as? ModelIdentifier,
               !immersiveSpaceIsShown {
                let config = ModelConfiguration(modelIdentifier: modelIdentifier, usePreprocessComputeShader: usePreprocessComputeShader)
                openWindow(value: config)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("ExitImmersiveSpaceRequested"))) { _ in
            if immersiveSpaceIsShown {
                Task {
                    await dismissImmersiveSpace()
                    immersiveSpaceIsShown = false
                }
            }
        }
    }
}

#if os(visionOS) && DEBUG
#Preview("Immersive Space Inactive") {
    ContentView()
}

#Preview("Immersive Space Active") {
    ContentView(immersiveSpaceIsShown: true)
}
#endif
