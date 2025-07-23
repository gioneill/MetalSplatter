import SwiftUI
import GroupActivities

struct SharePlayStatusView: View {
    @ObservedObject var sessionManager: SharePlaySessionManager
    @State private var showParticipantsList = false
    
    var body: some View {
        HStack {
            Button(action: {
                showParticipantsList.toggle()
            }) {
                HStack {
                    Image(systemName: "shareplay")
                        .foregroundColor(.green)
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text("SharePlay Active")
                            .font(.caption)
                            .fontWeight(.medium)
                        
                        Text("\(sessionManager.activeParticipants.count) participants")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    
                    if sessionManager.nearbyParticipants.count > 0 {
                        Image(systemName: "location")
                            .font(.caption2)
                            .foregroundColor(.blue)
                    }
                }
            }
            .buttonStyle(.bordered)
            .popover(isPresented: $showParticipantsList) {
                ParticipantsListView(sessionManager: sessionManager)
            }
            
            Button("End Session") {
                sessionManager.endSession()
            }
            .buttonStyle(.bordered)
            .foregroundColor(.red)
        }
    }
}

struct ParticipantsListView: View {
    @ObservedObject var sessionManager: SharePlaySessionManager
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Participants")
                .font(.headline)
                .padding(.horizontal)
            
            if !sessionManager.nearbyParticipants.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Image(systemName: "location.fill")
                            .foregroundColor(.blue)
                        Text("Nearby")
                            .font(.subheadline)
                            .fontWeight(.medium)
                    }
                    .padding(.horizontal)
                    
                    ForEach(Array(sessionManager.nearbyParticipants), id: \.id) { participant in
                        ParticipantRow(participant: participant, isNearby: true)
                    }
                }
            }
            
            if !sessionManager.remoteParticipants.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Image(systemName: "video.fill")
                            .foregroundColor(.green)
                        Text("FaceTime")
                            .font(.subheadline)
                            .fontWeight(.medium)
                    }
                    .padding(.horizontal)
                    
                    ForEach(Array(sessionManager.remoteParticipants), id: \.id) { participant in
                        ParticipantRow(participant: participant, isNearby: false)
                    }
                }
            }
            
            if sessionManager.activeParticipants.isEmpty {
                Text("No other participants")
                    .foregroundColor(.secondary)
                    .padding(.horizontal)
            }
        }
        .padding(.vertical)
        .frame(minWidth: 200)
    }
}

struct ParticipantRow: View {
    let participant: Participant
    let isNearby: Bool
    
    var body: some View {
        HStack {
            Circle()
                .fill(isNearby ? Color.blue : Color.green)
                .frame(width: 8, height: 8)
            
            Text(String(participant.id.uuidString.prefix(8)))
                .font(.caption)
                .foregroundColor(.primary)
            
            Spacer()
            
            if isNearby {
                Image(systemName: "location")
                    .font(.caption2)
                    .foregroundColor(.blue)
            } else {
                Image(systemName: "video")
                    .font(.caption2)
                    .foregroundColor(.green)
            }
        }
        .padding(.horizontal)
    }
}