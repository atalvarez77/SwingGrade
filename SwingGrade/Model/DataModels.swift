import Foundation
import Vision
import CoreImage

// Define a simple Codable point representation
struct CodablePoint: Codable {
    let x: Double
    let y: Double
}

// Define a Codable representation of a body pose (maps clean joint name to a point)
typealias CodableBodyPose = [String: CodablePoint]

struct CodableAnalysis: Codable {
    let address: SwingDataPoint?
    let topOfBackswing: SwingDataPoint?
    let impact: SwingDataPoint?
    let finish: SwingDataPoint?
    let preImpact: SwingDataPoint?
    let downswingParallel: SwingDataPoint?
}

// Define a Codable representation of the club (just the center point and confidence)
struct CodableClubObservation: Codable {
    let center: CodablePoint
    let confidence: Double
}

// --- We need a struct to hold the data during the live analysis pass ---
// This temporarily holds the Vision objects before they are converted for saving.
struct SwingDataPointLive {
    let time: Double
    let bodyPose: VNHumanBodyPoseObservation? // Live Object
    let clubObservation: VNRecognizedObjectObservation? // Live Object
    
    // NEW: Optional holder for saved data when loading from history
    var bodyPoseData: CodableBodyPose? = nil
}

// MARK: - Core Data Models

enum ClubType: String, CaseIterable, Identifiable {
    case driver = "Driver"
    case woodsHybrids = "Woods_Hybrids"
    case longIrons = "Long_Irons"
    case midShortIrons = "Mid_Short_Irons"
    case wedges = "Wedges"
    
    var id: String { rawValue }
    
    // Helper to match the key used in ProModel.json
    var jsonKey: String { rawValue }
    
    // UI name
    var displayName: String {
        switch self {
        case .woodsHybrids: return "Woods/Hybrids"
        case .longIrons: return "Long Irons"
        case .midShortIrons: return "Mid/Short Irons"
        default: return rawValue
        }
    }
}

enum ViewType: String, CaseIterable, Identifiable {
    case dtl = "dtl_view"
    case headOn = "head_on_view"
    
    var id: String { rawValue }
    
    var displayName: String {
        switch self {
        case .dtl: return "Down-The-Line (DTL)"
        case .headOn: return "Head-On (HO)"
        }
    }
}

// This struct will hold ALL the data for ONE analyzed swing
struct SwingAnalysis {
    // 1. The 4 poses we already have (using the LIVE struct)
    var address: SwingDataPointLive?
    var topOfBackswing: SwingDataPointLive?
    var impact: SwingDataPointLive?
    var finish: SwingDataPointLive?
    var preImpact: SwingDataPointLive?
    var downswingParallel: SwingDataPointLive?

    // --- Add a Codable version for saving ---
    // This property will hold the data converted for persistence.
    var codableData: CodableAnalysis {
        return CodableAnalysis(
            address: address.map { SwingDataPoint(from: $0) },
            topOfBackswing: topOfBackswing.map { SwingDataPoint(from: $0) },
            impact: impact.map { SwingDataPoint(from: $0) },
            finish: finish.map { SwingDataPoint(from: $0) },
            preImpact: preImpact.map { SwingDataPoint(from: $0) },
            downswingParallel: downswingParallel.map { SwingDataPoint(from: $0) }
        )
    }
}

struct SwingRecord: Identifiable, Codable {
    // Unique ID for the list view
    var id: UUID = UUID()
    
    // Core Card Data
    let date: Date // Used for 24-hour expiry and display
    let score: Int
    let mainFlawName: String
    let mainFlaw: String
    let coachingDrill: Drill?
    let skeletonScreenshotData: Data? // JPEG/PNG data for the small card preview
    
    // Full Analysis Data
    let analysis: CodableAnalysis // The complete results set
    
    var isPermanent: Bool = false
}

// This is the data for a SINGLE frame (no changes)
struct SwingDataPoint: Codable {
    let time: Double
    // The properties we actually save:
    let bodyPose: CodableBodyPose?
    let clubObservation: CodableClubObservation?
}

// --- Add the Conversion Initializer ---
extension SwingDataPoint {
    
    // This initializer runs automatically when data is saved.
    // It converts the live Vision data into the Codable format.
    init(from liveData: SwingDataPointLive) {
        self.time = liveData.time
        
        // 1. Convert Body Pose (VNHumanBodyPoseObservation) to CodableBodyPose
        if let pose = liveData.bodyPose {
            var codablePose: CodableBodyPose = [:]
            
            // Loop through all recognized points
            for jointName in pose.availableJointNames {
                guard let point = try? pose.recognizedPoint(jointName), point.confidence > 0.1 else { continue }
                
                let jointNameString = String(describing: jointName.rawValue)
                let key = jointNameString
                    .replacingOccurrences(of: "_1_joint", with: "")
                    .replacingOccurrences(of: "_joint", with: "")
                
                codablePose[key] = CodablePoint(x: point.location.x, y: point.location.y)
            }
            self.bodyPose = codablePose
        } else {
            self.bodyPose = nil
        }
        
        // 2. Convert Club Observation (VNRecognizedObjectObservation) to CodableClubObservation
        if let club = liveData.clubObservation {
            let center = CodablePoint(x: club.boundingBox.midX, y: club.boundingBox.midY)
            self.clubObservation = CodableClubObservation(center: center, confidence: Double(club.confidence))
        } else {
            self.clubObservation = nil
        }
    }
}

// MARK: - Reconstitution Logic (Loading back from History)

// 1. Helper: Convert CodablePoint back to CGPoint
extension CodablePoint {
    var asCGPoint: CGPoint {
        return CGPoint(x: x, y: y)
    }
}

// 2. Convert SwingDataPoint (Saved) -> SwingDataPointLive (Live)
extension SwingDataPointLive {
    init(from saved: SwingDataPoint) {
        self.time = saved.time
        self.bodyPose = nil
        self.clubObservation = nil
        self.bodyPoseData = saved.bodyPose // <--- STORE THE SAVED DATA HERE
    }
}

// 3. Convert CodableAnalysis (Saved) -> SwingAnalysis (Live)
extension SwingAnalysis {
    init(from codable: CodableAnalysis) {
        self.address = codable.address.map { SwingDataPointLive(from: $0) }
        self.topOfBackswing = codable.topOfBackswing.map { SwingDataPointLive(from: $0) }
        self.impact = codable.impact.map { SwingDataPointLive(from: $0) }
        self.finish = codable.finish.map { SwingDataPointLive(from: $0) }
        self.preImpact = codable.preImpact.map { SwingDataPointLive(from: $0) }
        self.downswingParallel = codable.downswingParallel.map { SwingDataPointLive(from: $0) }
    }
}
