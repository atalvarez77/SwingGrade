import SwiftUI
import Vision

// MARK: - SkeletonOverlayView (Unified)
struct SkeletonOverlayView: View {
    
    // NOW ACCEPTS GENERIC POINTS (Clean Keys: "neck", "root", etc.)
    let joints: [String: CGPoint]
    let scores: [SwingScore]
    let geometry: GeometryProxy
    
    // We define the lines we want to draw (using CLEAN keys)
    public let jointPairs: [(String, String)] = [
        // Spine
        ("neck", "root"),
        
        // Left Arm
        ("neck", "left_shoulder"),
        ("left_shoulder", "left_forearm"), // left_forearm = Elbow
        ("left_forearm", "left_hand"),     // left_hand = Wrist
        
        // Right Arm
        ("neck", "right_shoulder"),
        ("right_shoulder", "right_forearm"), // right_forearm = Elbow
        ("right_forearm", "right_hand"),     // right_hand = Wrist
        
        // Left Leg
        ("root", "left_upLeg"),      // left_upLeg = Hip
        ("left_upLeg", "left_leg"),  // left_leg = Knee
        ("left_leg", "left_foot"),   // left_foot = Ankle
        
        // Right Leg
        ("root", "right_upLeg"),     // right_upLeg = Hip
        ("right_upLeg", "right_leg"),// right_leg = Knee
        ("right_leg", "right_foot"), // right_foot = Ankle
        
        // Face (Using 'head' since 'nose' was missing in log)
        ("neck", "head"),
        ("head", "left_eye"), ("head", "right_eye"),
        ("left_eye", "left_ear"), ("right_eye", "right_ear")
    ]
    
    // This map links the CLEAN bone names to the metric ID
    public var boneToMetricMap: [String: String] = [
        // --- Spine/Head ---
        "neck_root": "spine_tilt_address",
        "root_neck": "spine_tilt_address",
        "neck_head": "head_movement_lateral",
        "head_neck": "head_movement_lateral",
        
        // --- Shoulders ---
        "neck_left_shoulder": "spine_tilt_address",
        "left_shoulder_neck": "spine_tilt_address",
        "neck_right_shoulder": "spine_tilt_address",
        "right_shoulder_neck": "spine_tilt_address",
        "left_shoulder_right_shoulder": "shoulder_plane_top",
        "right_shoulder_left_shoulder": "shoulder_plane_top",

        // --- Arms (Lag) ---
        // Forearm = Elbow, Hand = Wrist
        "left_forearm_left_hand": "lag_loss_downswing",
        "left_hand_left_forearm": "lag_loss_downswing",
        "right_forearm_right_hand": "lag_loss_downswing",
        "right_hand_right_forearm": "lag_loss_downswing",
        
        // Shoulders to Elbows
        "left_shoulder_left_forearm": "lag_loss_downswing",
        "right_shoulder_right_forearm": "lag_loss_downswing",

        // --- Hips/Legs (Sway & Flex) ---
        // upLeg = Hip
        "root_left_upLeg": "hip_sway_backswing",
        "left_upLeg_root": "hip_sway_backswing",
        "root_right_upLeg": "hip_sway_backswing",
        "right_upLeg_root": "hip_sway_backswing",

        // Trail Leg Flex (Right Leg = Knee, Right Foot = Ankle)
        "right_upLeg_right_leg": "trail_leg_flex_top", // Hip to Knee
        "right_leg_right_upLeg": "trail_leg_flex_top",
        "right_leg_right_foot": "trail_leg_flex_top",  // Knee to Ankle
        "right_foot_right_leg": "trail_leg_flex_top",
        
        // Fallbacks
        "left_upLeg_left_leg": "hip_sway_backswing",
        "left_leg_left_foot": "hip_sway_backswing"
    ]

    var body: some View {
        Canvas { context, size in
            
            // --- 1. DRAW THE "BONES" (Lines) ---
            for (name1, name2) in jointPairs {
                // USE THE FUZZY MATCHER
                guard let p1 = getFuzzyPoint(for: name1, from: joints),
                      let p2 = getFuzzyPoint(for: name2, from: joints) else {
                    continue
                }
                
                var path = Path()
                path.move(to: convert(point: p1, in: geometry.size))
                path.addLine(to: convert(point: p2, in: geometry.size))
                
                // Construct key for color lookup
                let boneKey = "\(name1)_\(name2)"
                let color = getColor(for: boneKey)
                
                context.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: 5, lineCap: .round))
            }
            
            // --- 2. DRAW THE "JOINTS" (Dots) ---
            for (_, point) in joints {
                let cgPoint = convert(point: point, in: geometry.size)
                context.fill(
                    Path(ellipseIn: CGRect(x: cgPoint.x - 4, y: cgPoint.y - 4, width: 8, height: 8)),
                    with: .color(.white)
                )
            }
        }
    }
    
    // --- ROBUST HELPER FUNCTION ---
    private func getFuzzyPoint(for key: String, from joints: [String: CGPoint]) -> CGPoint? {
        // 1. Try Exact Match
        if let p = joints[key] { return p }
        
        // 2. Try Fuzzy Match (Contains)
        // This finds "left_shoulder" even if the key is "VNHuman...left_shoulder_1..."
        if let fuzzyKey = joints.keys.first(where: { $0.contains(key) }) {
            return joints[fuzzyKey]
        }
        
        return nil
    }
    
    // --- HELPER FUNCTIONS ---
    
    private func getColor(for boneKey: String) -> Color {
        // Try the key, or its reverse
        let lookupKey = boneToMetricMap[boneKey] ?? boneToMetricMap[boneKey.components(separatedBy: "_").reversed().joined(separator: "_")]
        
        guard let metricID = lookupKey,
              let score = scores.first(where: { $0.metricID == metricID })?.score else {
            return .white.opacity(0.8)
        }
        
        let hue = (Double(score) / 100.0) * 0.33
        return Color(hue: hue, saturation: 1.0, brightness: 1.0)
    }
    
    private func convert(point: CGPoint, in size: CGSize) -> CGPoint {
        // Vision coordinates are 0-1 with Y=0 at BOTTOM
        // SwiftUI coordinates are 0-width/height with Y=0 at TOP
        return CGPoint(
            x: point.x * size.width,
            y: (1.0 - point.y) * size.height
        )
    }
}
