import SwiftUI

struct MiniSkeletonView: View {
    // The saved dictionary of points (e.g., "neck": {x: 0.5, y: 0.5})
    let poseData: CodableBodyPose
    
    // Define the connections (same as your main view)
    private let connections: [(String, String)] = [
        // Spine
        ("neck", "root"),
        
        // Arms (Using Snake Case)
        ("neck", "left_shoulder"), ("left_shoulder", "left_forearm"), ("left_forearm", "left_hand"),
        ("neck", "right_shoulder"), ("right_shoulder", "right_forearm"), ("right_forearm", "right_hand"),
        
        // Legs (Using Snake Case)
        ("root", "left_upLeg"), ("left_upLeg", "left_leg"), ("left_leg", "left_foot"),
        ("root", "right_upLeg"), ("right_upLeg", "right_leg"), ("right_leg", "right_foot")
    ]
    
    var body: some View {
        GeometryReader { geo in
            Path { path in
                for (name1, name2) in connections {
                    // USE FUZZY MATCH HERE TOO
                    if let start = getFuzzyPoint(for: name1, from: poseData),
                       let end = getFuzzyPoint(for: name2, from: poseData) {
                        
                        // Note: poseData uses CodablePoint (x, y), not CGPoint
                        // We convert manually here
                        let p1 = CGPoint(x: start.x * geo.size.width, y: (1 - start.y) * geo.size.height)
                        let p2 = CGPoint(x: end.x * geo.size.width, y: (1 - end.y) * geo.size.height)
                        
                        path.move(to: p1)
                        path.addLine(to: p2)
                    }
                }
            }
            .stroke(Color.white, style: StrokeStyle(lineWidth: 2, lineCap: .round))
        }
    }

    // Add this helper inside MiniSkeletonView
    private func getFuzzyPoint(for key: String, from data: CodableBodyPose) -> CodablePoint? {
        if let p = data[key] { return p }
        if let fuzzyKey = data.keys.first(where: { $0.contains(key) }) {
            return data[fuzzyKey]
        }
        return nil
    }
}
