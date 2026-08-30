import SwiftUI
import Vision
import Combine

// MARK: - PoseAnimatorView
struct PoseAnimatorView: View {
    
    @ObservedObject var viewModel: SwingGradeViewModel
    
    // This state tracks which pose we are currently showing
    @State private var currentPoseIndex: Int = 0
    
    // This timer drives the "looping video" animation
    private let timer = Timer.publish(every: 1.5, on: .main, in: .common).autoconnect()
    
    // This struct holds the data for our animation
    private struct AnimatedPose {
        let name: String
        let pose: VNHumanBodyPoseObservation? // For Live
        let savedPose: CodableBodyPose?       // For History
    }
    
    // This builds our list of poses to animate
    private var poses: [AnimatedPose] {
        var validPoses: [AnimatedPose] = []
        let analysis = viewModel.currentAnalysis
        
        // Helper to safely unwrap and add a pose
        func addPose(_ name: String, _ data: SwingDataPointLive?) {
            guard let data = data else { return }
            
            // Check if we have EITHER live data OR saved data
            if data.bodyPose != nil || data.bodyPoseData != nil {
                validPoses.append(AnimatedPose(
                    name: name,
                    pose: data.bodyPose,
                    savedPose: data.bodyPoseData
                ))
            }
        }
        
        addPose("Address", analysis?.address)
        addPose("Top", analysis?.topOfBackswing)
        addPose("Impact", analysis?.impact)
        addPose("Finish", analysis?.finish)
        
        return validPoses
    }

    var body: some View {
        VStack(spacing: 10) {
            
            // --- 1. SKELETON VIEWER ---
            ZStack {
                Color.clear
                
                if !poses.isEmpty {
                    
                    GeometryReader { geometry in
                        
                        // FIX: We call the helper function here instead of writing logic inline
                        let jointData = extractJoints(from: poses[currentPoseIndex])
                        
                        SkeletonOverlayView(
                            joints: jointData,
                            scores: viewModel.detailedScores,
                            geometry: geometry
                        )
                        .id(currentPoseIndex)
                        .shadow(color: .black.opacity(0.3), radius: 10, x: 0, y: 0)
                    }
                    
                } else {
                    Text("No Pose Data Available")
                        .foregroundColor(.gray)
                }
            }
        }
        // Loop Animation Logic
        .onReceive(timer) { _ in
            guard !poses.isEmpty else { return }
            
            var nextIndex = currentPoseIndex + 1
            if nextIndex >= poses.count {
                nextIndex = 0
            }
            
            withAnimation(.easeInOut(duration: 0.5)) {
                currentPoseIndex = nextIndex
            }
        }
        .onAppear {
            if let impactIndex = poses.firstIndex(where: { $0.name == "Impact" }) {
                currentPoseIndex = impactIndex
            }
        }
    }
    
    // --- HELPER FUNCTION (The Logic Extractor) ---
    // This converts whatever data we have (Live or Saved) into a simple dictionary
    private func extractJoints(from animatedPose: AnimatedPose) -> [String: CGPoint] {
        var finalJoints: [String: CGPoint] = [:]
        
        // Scenario A: LIVE DATA (Convert Vision Object -> Dictionary)
        if let visionPose = animatedPose.pose {
            for jointName in visionPose.availableJointNames {
                if let point = try? visionPose.recognizedPoint(jointName), point.confidence > 0.1 {
                    // CLEAN THE KEY (e.g., "neck_1_joint" -> "neck")
                    let rawString = jointName.rawValue
                    let cleanKey = rawString.rawValue
                        .replacingOccurrences(of: "_1_joint", with: "")
                        .replacingOccurrences(of: "_joint", with: "")
                    finalJoints[cleanKey] = point.location
                }
            }
        }
        // Scenario B: SAVED DATA (Already a Dictionary, just convert keys/types)
        else if let savedPose = animatedPose.savedPose {
            for (key, codablePoint) in savedPose {
                // Saved data keys are already clean ("neck")
                finalJoints[key] = CGPoint(x: codablePoint.x, y: codablePoint.y)
            }
        }
        
        return finalJoints
    }
}
