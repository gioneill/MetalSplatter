import SwiftUI
import GroupActivities

struct SharePlayTestingView: View {
    @ObservedObject var integrationHelper: SharePlayIntegrationHelper
    @State private var showingDebugInfo = false
    @State private var testMessage = ""
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Session Status
            HStack {
                Circle()
                    .fill(integrationHelper.sessionManager.isSharePlayActive ? Color.green : Color.red)
                    .frame(width: 12, height: 12)
                
                Text(integrationHelper.sessionManager.isSharePlayActive ? "SharePlay Active" : "SharePlay Inactive")
                    .font(.headline)
                
                Spacer()
                
                Button("Debug Info") {
                    showingDebugInfo.toggle()
                }
                .buttonStyle(.bordered)
            }
            
            // Participant Info
            if integrationHelper.sessionManager.isSharePlayActive {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Participants")
                        .font(.subheadline)
                        .fontWeight(.medium)
                    
                    HStack {
                        Label("\(integrationHelper.sessionManager.nearbyParticipants.count) Nearby", 
                              systemImage: "location")
                        .foregroundColor(.blue)
                        
                        Spacer()
                        
                        Label("\(integrationHelper.sessionManager.remoteParticipants.count) FaceTime", 
                              systemImage: "video")
                        .foregroundColor(.green)
                    }
                    .font(.caption)
                }
                .padding()
                .background(Color.secondary.opacity(0.1))
                .cornerRadius(8)
            }
            
            // Performance Metrics
            PerformanceMetricsView(metrics: integrationHelper.performanceMetrics)
            
            // Test Controls
            VStack(alignment: .leading, spacing: 8) {
                Text("Testing Controls")
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                HStack {
                    TextField("Test message", text: $testMessage)
                        .textFieldStyle(.roundedBorder)
                    
                    Button("Send") {
                        sendTestMessage()
                    }
                    .disabled(testMessage.isEmpty || !integrationHelper.sessionManager.isSharePlayActive)
                }
                
                HStack {
                    Button("Test Camera Sync") {
                        testCameraSync()
                    }
                    .buttonStyle(.bordered)
                    
                    Button("Test Model Load") {
                        testModelLoad()
                    }
                    .buttonStyle(.bordered)
                    
                    Button("Test Spatial Content") {
                        testSpatialContent()
                    }
                    .buttonStyle(.bordered)
                }
            }
            
            Spacer()
        }
        .padding()
        .sheet(isPresented: $showingDebugInfo) {
            SharePlayDebugView(integrationHelper: integrationHelper)
        }
    }
    
    private func sendTestMessage() {
        // Test message sending
        let annotation = SyncMessage.AnnotationMessage(
            id: UUID().uuidString,
            position: SIMD3<Float>(0, 1, -1),
            text: testMessage,
            participantID: "test",
            timestamp: CACurrentMediaTime()
        )
        
        integrationHelper.sessionManager.sendAnnotation(annotation)
        
        testMessage = ""
    }
    
    private func testCameraSync() {
        // Test camera synchronization
        let testPosition = SIMD3<Float>(
            Float.random(in: -2...2),
            Float.random(in: 0...2),
            Float.random(in: -3...0)
        )
        let testRotation = simd_quatf(angle: Float.random(in: 0...(.pi * 2)), axis: SIMD3<Float>(0, 1, 0))
        
        integrationHelper.cameraSync.sendCameraUpdate(position: testPosition, rotation: testRotation)
    }
    
    private func testModelLoad() {
        // Test model synchronization
        Task {
            await integrationHelper.modelSync.selectModel(.sampleBox)
        }
    }
    
    private func testSpatialContent() {
        // Test spatial content placement
        let testPosition = SIMD3<Float>(
            Float.random(in: -1...1),
            Float.random(in: 0...2),
            Float.random(in: -2...0)
        )
        
        Task {
            await integrationHelper.spatialContentManager.placeSharedContent(at: testPosition)
        }
    }
}

struct PerformanceMetricsView: View {
    let metrics: SharePlayPerformanceMetrics
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Performance")
                .font(.subheadline)
                .fontWeight(.medium)
            
            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 4) {
                GridRow {
                    Text("Memory:")
                        .foregroundColor(.secondary)
                    Text("\(metrics.memoryUsageMB, specifier: "%.1f") MB")
                        .font(.system(.body, design: .monospaced))
                }
                
                GridRow {
                    Text("Latency:")
                        .foregroundColor(.secondary)
                    Text("\(metrics.networkLatencyMs, specifier: "%.0f") ms")
                        .font(.system(.body, design: .monospaced))
                        .foregroundColor(metrics.networkLatencyMs > 100 ? Color.orange : Color.primary)
                }
                
                GridRow {
                    Text("Participants:")
                        .foregroundColor(.secondary)
                    Text("\(metrics.totalParticipants)")
                        .font(.system(.body, design: .monospaced))
                }
            }
            .font(.caption)
        }
        .padding()
        .background(Color.secondary.opacity(0.1))
        .cornerRadius(8)
    }
}

struct SharePlayDebugView: View {
    @ObservedObject var integrationHelper: SharePlayIntegrationHelper
    @Environment(\.dismiss) private var dismiss
    
    var sessionStateSection: some View {
        Section("Session State") {
            LabeledContent("Status", value: integrationHelper.sessionManager.sessionState.description)
            LabeledContent("Active", value: integrationHelper.sessionManager.isSharePlayActive.description)
            LabeledContent("Participants", value: "\(integrationHelper.sessionManager.activeParticipants.count)")
        }
    }
    
    var participantsSection: some View {
        Section("Participants") {
            ForEach(Array(integrationHelper.sessionManager.activeParticipants), id: \.self) { participant in
                VStack(alignment: .leading) {
                    Text(String(participant.id.uuidString.prefix(8)))
                        .font(.system(.caption, design: .monospaced))
                    
                    HStack {
                        if integrationHelper.sessionManager.nearbyParticipants.contains(participant) {
                            Label("Nearby", systemImage: "location")
                                .foregroundColor(.blue)
                        } else {
                            Label("FaceTime", systemImage: "video")
                                .foregroundColor(.green)
                        }
                        
                        Spacer()
                    }
                    .font(.caption2)
                }
            }
        }
    }
    
    var body: some View {
        NavigationView {
            List {
                sessionStateSection
                participantsSection
                
                Section("Camera Sync") {
                    LabeledContent("Remote Viewports", value: "\(integrationHelper.cameraSync.remoteViewports.count)")
                    LabeledContent("Synced Rotation", value: String(format: "%.1f°", integrationHelper.cameraSync.syncedRotation.degrees))
                }
                
                Section("Performance") {
                    LabeledContent("Memory", value: String(format: "%.1f MB", integrationHelper.performanceMetrics.memoryUsageMB))
                    LabeledContent("Network Latency", value: String(format: "%.0f ms", integrationHelper.performanceMetrics.networkLatencyMs))
                    LabeledContent("Spatial Objects", value: "\(integrationHelper.performanceMetrics.spatialObjectsCount)")
                }
                
                Section("Spatial Content") {
                    LabeledContent("Participant Indicators", value: "\(integrationHelper.spatialContentManager.participantIndicators.count)")
                    LabeledContent("Annotations", value: "\(integrationHelper.spatialContentManager.sharedAnnotations.count)")
                    LabeledContent("Pointers", value: "\(integrationHelper.spatialContentManager.participantPointers.count)")
                    LabeledContent("World Anchors", value: "\(integrationHelper.nearbyHandler.sharedWorldAnchors.count)")
                }
            }
            .navigationTitle("SharePlay Debug")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}

extension GroupSession.State: @retroactive CustomStringConvertible {
    public var description: String {
        switch self {
        case .waiting: return "waiting"
        case .joined: return "joined"
        case .invalidated: return "invalidated"
        @unknown default: return "unknown"
        }
    }
}
