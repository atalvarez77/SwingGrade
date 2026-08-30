import Foundation
import SwiftUI
import Combine
import Vision // We need this for all the geometry
import UIKit // We need this for CGPoint

extension View {
    // Converts a SwiftUI View into a UIImage
    func snapshot() -> UIImage {
        let controller = UIHostingController(rootView: self)
        let view = controller.view

        // Set the view size (e.g., 200x200 for a thumbnail card)
        let targetSize = CGSize(width: 200, height: 200)
        view?.bounds = CGRect(origin: .zero, size: targetSize)
        view?.backgroundColor = .clear

        let renderer = UIGraphicsImageRenderer(size: targetSize)
        return renderer.image { _ in
            view?.drawHierarchy(in: view!.bounds, afterScreenUpdates: true)
        }
    }
}

// MARK: - SwingGradeViewModel (The "Brain")
class SwingGradeViewModel: ObservableObject {
    
    // --- 1. Published Properties (What the UI watches) ---
    @Published var currentAnalysis: SwingAnalysis?
    @Published var isLoading: Bool = false
    @Published var coachingScore: Int = 0
    @Published var mainFlawName: String = "No analysis yet." 
    @Published var mainFlaw: String = "No analysis yet."
    @Published var coachingDrill: Drill?
    @Published var detailedScores: [SwingScore] = []
    @Published var analysisVideoURL: URL?
    @Published var selectedClub: ClubType = .driver
    @Published var selectedView: ViewType = .dtl
    @Published var historySwings: [SwingRecord] = []
    @Published var showHistory: Bool = false
    @Published var showSettings: Bool = false
    @Published var currentAnalysisID: UUID = UUID()
    
    // --- 2. Our "Brains" ---
    private var proModel: ProModel?
    private var analysisService = AnalysisService()
    private let persistenceService = PersistenceService()
    
    // --- 3. User Profile (For Normalization) ---
    var userHeightInInches: Double = 68.0 // (Default: 5' 8")
    
    
    // --- 4. The "Initializer" ---
    init() {
        print("ViewModel: Initializing and loading ProModel.json...")
        loadProModel()
    }
    
    // --- 5. The "Brain" Loader ---
    private func loadProModel() {
        guard let url = Bundle.main.url(forResource: "ProModel", withExtension: "json") else {
            fatalError("FATAL ERROR: ProModel.json not found in bundle. Did you drag it in?")
        }
        
        do {
            let data = try Data(contentsOf: url)
            self.proModel = try JSONDecoder().decode(ProModel.self, from: data)
            print("✅ SUCCESS: ProModel.json loaded successfully.")
        } catch {
            fatalError("FATAL ERROR: Failed to decode ProModel.json: \(error)")
        }
    }
    
    // --- 6. The Main "Run Analysis" Function ---
    func runFullAnalysis(on videoURL: URL, club: String, view: String) async {
        
        DispatchQueue.main.async { self.isLoading = true; self.mainFlawName = "Analyzing..."; self.mainFlaw = "" }
        
        // --- THIS IS THE FIX ---
        // We now get back *both* the results and the URL
        guard let (analysisResult, processedURL) = await analysisService.performAnalysis(on: videoURL, view: "dtl_view") else {
            DispatchQueue.main.async { self.isLoading = false; self.mainFlawName = "Analysis failed."; self.mainFlaw = "Please try again." }
            return
        }
        
        DispatchQueue.main.async {
            self.currentAnalysis = analysisResult
            self.analysisVideoURL = processedURL // <-- We save the URL
            self.currentAnalysisID = UUID()
        }
        
        // Call our "Smart Coach" logic
        await performRootCauseAnalysis(with: analysisResult, club: club, view: view)
        
        // Tell the UI we are "done"
        DispatchQueue.main.async {
            self.isLoading = false
            print("===================================")
            print("SwingGrade Analysis Complete!")
            print("Final Score: \(self.coachingScore)")
            print("Root Cause Flaw: \(self.mainFlawName)")
            print("===================================")
        }
    }
    
    // --- 7. The "Smart Coach" (Root Cause Analysis Engine) ---
    private func performRootCauseAnalysis(with analysis: SwingAnalysis, club: String, view: String) async {
        guard let proModel = self.proModel else { return }

        // --- STEP 1: Get the correct "rulebook" for the club/view ---
        let viewRules: [String: Metric]?
        
        switch club {
        case "Driver":
            viewRules = (view == "head_on_view") ? proModel.Driver.head_on_view : proModel.Driver.dtl_view
        case "Woods_Hybrids":
            viewRules = (view == "head_on_view") ? proModel.Woods_Hybrids.head_on_view : proModel.Woods_Hybrids.dtl_view
        case "Long_Irons":
            viewRules = (view == "head_on_view") ? proModel.Long_Irons.head_on_view : proModel.Long_Irons.dtl_view
        case "Mid_Short_Irons":
            viewRules = (view == "head_on_view") ? proModel.Mid_Short_Irons.head_on_view : proModel.Mid_Short_Irons.dtl_view
        case "Wedges":
            viewRules = (view == "head_on_view") ? proModel.Wedges.head_on_view : proModel.Wedges.dtl_view
        default:
            print("ERROR: Invalid club type given: \(club)"); viewRules = nil
        }
        
        guard let viewRules = viewRules else {
            print("ERROR: Could not find a rulebook for \(club) / \(view).")
            return
        }

        // --- STEP 2: Calculate Metrics (This is REAL!) ---
        let allScores = calculateAllMetrics(with: analysis, using: viewRules, view: view)
        DispatchQueue.main.async { self.detailedScores = allScores } // <-- SAVE SCORES
        
        // --- STEP 3: Find all FAILED metrics (Score < 70) ---
        var failedScores = allScores.filter { $0.score < 70 }
        failedScores.sort { $0.priority > $1.priority } // Sort most important first
        
        print("\n--- Smart Coach: Finding Root Cause ---")
        print("Total Failed Metrics: \(failedScores.count)")
        
        var rootCauseFlaw: SwingScore? = nil
        
        // --- STEP 4: The Root Cause Logic ---
        for flaw in failedScores {
            print("Analyzing flaw: \(flaw.metricName) (Priority: \(flaw.priority), Score: \(flaw.score))")
            
            let isSymptom = failedScores.contains { otherFlaw in
                // Check if any *other* failed flaw lists this one as a symptom
                return (viewRules[otherFlaw.metricID]?.root_cause_for ?? []).contains(flaw.metricID)
            }
            
            if isSymptom {
                print("-> STATUS: This is a SYMPTOM. Ignoring for now.")
            } else {
                // This is the first high-priority flaw that is NOT a symptom.
                // This is our Root Cause.
                print("-> STATUS: ROOT CAUSE FOUND!")
                rootCauseFlaw = flaw
                break // We're done
            }
        }
        
        // --- STEP 5: Get the Coaching Plan ---
        let finalScore = allScores.isEmpty ? (failedScores.isEmpty ? 100 : 0) : allScores.map { $0.score }.reduce(0, +) / allScores.count
        
        if let rootCauseFlaw = rootCauseFlaw {
            if let metric = viewRules[rootCauseFlaw.metricID] {
                // Find the first "beginner" drill for this flaw
                let drill = metric.drills.first { $0.difficulty == "beginner" }
                
                DispatchQueue.main.async {
                    self.coachingScore = finalScore
                    self.mainFlawName = metric.metric_name // <-- SET THE FLAW NAME
                    self.mainFlaw = metric.human_explanation
                    self.coachingDrill = drill
                }
            }
        } else if allScores.isEmpty {
            DispatchQueue.main.async {
                self.coachingScore = 0 // No scores were calculated
                self.mainFlawName = "Analysis Failed"
                self.mainFlaw = "Could not calculate scores. Please try again."
                self.coachingDrill = nil
            }
        } else {
            // No flaws found!
            DispatchQueue.main.async {
                self.coachingScore = 100
                self.mainFlawName = "Great Swing!"
                self.mainFlaw = "No major flaws detected in this swing. Keep up the great work!"
                self.coachingDrill = nil
            }
        }
    }
    
    // --- 8. REAL METRIC CALCULATION ENGINE ---
    
    private func calculateAllMetrics(with analysis: SwingAnalysis, using rules: [String: Metric], view: String) -> [SwingScore] {
        print("--- REAL: Calculating all metrics... ---")
        var scores: [SwingScore] = []
        
        // --- 1. Get Key Poses & Clubs ---
        guard let addressPose = analysis.address?.bodyPose,
              let topPose = analysis.topOfBackswing?.bodyPose,
              let impactPose = analysis.impact?.bodyPose
        else {
            print("ERROR: Missing key poses (Address, Top, or Impact). Cannot calculate metrics.")
            return []
        }
        
        // Get clubs (they are optional, so we nil-check later)
        let addressClub = analysis.address?.clubObservation
        let topClub = analysis.topOfBackswing?.clubObservation
        let impactClub = analysis.impact?.clubObservation
        let preImpactClub = analysis.preImpact?.clubObservation
        let downswingClub = analysis.downswingParallel?.clubObservation

        // --- 2. Calculate Normalization Factor (UPDATED LOGIC) ---
        let inchesPerUnit: Double?
        
        if view == "head_on_view" {
            print("Normalizing using Head-On (Shoulder Width) ruler.")
            inchesPerUnit = getInchesPerUnit(from: addressPose)
        } else {
            print("Normalizing using DTL (User Height) ruler.")
            inchesPerUnit = getInchesPerUnitDTL(from: addressPose)
        }

        guard let inchesPerUnit = inchesPerUnit else {
            print("ERROR: Could not get normalization factor for view: \(view).")
            return []
        }
        print("Normalization Factor (Inches per AI Unit): \(inchesPerUnit)")
        
        // --- 3. Loop through every rule in our "rulebook" ---
        for (metricID, rule) in rules {
            
            var calculatedValue: Double? = nil
            
            // --- This is the "brain" that calls the right math function ---
            switch metricID {
                
            // === HEAD-ON VIEW METRICS ===
            
            case "spine_tilt_address": // HO
                calculatedValue = getSpineTiltHO(from: addressPose)
                
            case "hip_sway_backswing": // HO
                calculatedValue = getHipSwayHO(from: addressPose, at: topPose, inchesPerUnit: inchesPerUnit)
                
            case "head_movement_lateral": // HO
                calculatedValue = getHeadSwayHO(from: addressPose, at: topPose, inchesPerUnit: inchesPerUnit)
                
            case "hip_sway_impact": // HO
                calculatedValue = getHipSwayHO(from: addressPose, at: impactPose, inchesPerUnit: inchesPerUnit)
            
            case "head_position_impact": // HO
                calculatedValue = getHeadSwayHO(from: addressPose, at: impactPose, inchesPerUnit: inchesPerUnit)
                
            case "spine_tilt_impact": // HO
                calculatedValue = getSpineTiltHO(from: impactPose)
                
            case "lag_loss_downswing": // HO
                if let clubAtTop = topClub {
                    calculatedValue = getLagAngle(from: topPose, club: clubAtTop)
                }
            
            case "shaft_lean_address": // HO
                if let clubAtAddress = addressClub {
                    calculatedValue = getShaftLeanHO(from: clubAtAddress)
                }
            
            case "shaft_lean_impact": // HO
                if let clubAtImpact = impactClub {
                    calculatedValue = getShaftLeanHO(from: clubAtImpact)
                }
            
            // === DTL VIEW METRICS ===
            
            case "spine_bend_address": // DTL
                calculatedValue = getSpineBendDTL(from: addressPose)

            case "shoulder_plane_top": // DTL
                calculatedValue = getShoulderPlaneDTL(from: topPose)
                
            case "hip_depth_top": // DTL
                calculatedValue = getHipDepthDTL(from: addressPose, at: topPose, inchesPerUnit: inchesPerUnit)
                
            case "trail_leg_flex_top": // DTL
                calculatedValue = getTrailLegFlexChange(from: addressPose, at: topPose)
                
            case "wrist_set_top": // DTL
                if let clubAtTop = topClub {
                    calculatedValue = getWristSetDTL(from: topPose, club: clubAtTop)
                }
            
            case "takeaway_path": // DTL
                // This metric needs a frame between address and top
                // We'll re-use 'downswingParallel' frame as a proxy for now
                if let clubAtP2 = analysis.downswingParallel?.clubObservation {
                     calculatedValue = getTakeawayPath(from: addressPose, clubAtP2: clubAtP2, inchesPerUnit: inchesPerUnit)
                }
                
            case "backswing_width": // DTL
                 calculatedValue = getBackswingWidth(from: topPose)
            
            case "angle_of_attack": // DTL
                if let preImpactClub = preImpactClub, let impactClub = impactClub {
                    calculatedValue = getAngleOfAttack(from: preImpactClub, to: impactClub)
                }
                
            case "shaft_shallowing": // DTL
                if let topClub = topClub, let downswingClub = downswingClub {
                    calculatedValue = getShaftShallowing(clubAtTop: topClub, clubAtDownswing: downswingClub)
                }

            default:
                continue
            }
            
            // --- 4. Score the Metric ---
            if let actual = calculatedValue {
                
                // We pass the *entire rule* to our new, "smart" calculator.
                let score = calculateScore(actual: actual, rule: rule)
                
                scores.append(SwingScore(metricID: metricID,
                                       metricName: rule.metric_name,
                                       score: score,
                                       priority: rule.priority_beginner,
                                       symptomOf: rule.symptom_of))
                
                print("METRIC (\(metricID)): Actual: \(String(format: "%.1f", actual)) | Target: \(rule.pro_target) | Range: \(rule.pro_range) | Score: \(score)")
            } else {
                 print("METRIC (\(metricID)): SKIPPED (missing required data)")
            }
        }
        
        return scores
    }
    
    // --- 9. GEOMETRY HELPER FUNCTIONS ---
    
    // MARK: - Normalization
    
    private func getInchesPerUnit(from pose: VNHumanBodyPoseObservation) -> Double? {
        // FIX: Using Hip Width for stability instead of Shoulder Width
        let averageHipWidthInches = 16.0
        
        guard let lHip = getJoint(.leftHip, from: pose),
              let rHip = getJoint(.rightHip, from: pose) else { return nil }
              
        // Calculate the width between the hips in normalized units (0.0-1.0)
        let hipWidth = distance(from: lHip.location, to: rHip.location)
        
        guard hipWidth > 0 else { return nil }
        
        // Return the new, stabilized ruler value
        return averageHipWidthInches / hipWidth
    }
    
    // MARK: - Head-On (HO) Math
    
    private func getSpineTiltHO(from pose: VNHumanBodyPoseObservation) -> Double? {
        guard let neck = getJoint(.neck, from: pose),
              let root = getJoint(.root, from: pose) else { return nil }
              
        // Angle of the spine relative to the horizontal
        let rawAngle = angle(from: neck.location, to: root.location)
        
        // This calculates the tilt *away* from the vertical (90 degrees).
        // Standard HO Spine Tilt is measured relative to vertical.
        let tilt = 90.0 - abs(rawAngle)
        
        return round(tilt * 10) / 10
    }

    private func getLagAngle(from pose: VNHumanBodyPoseObservation, club: VNRecognizedObjectObservation) -> Double? {
        guard let lElbow = getJoint(.leftElbow, from: pose),
              let lWrist = getJoint(.leftWrist, from: pose) else { return nil }
        let forearmAngle = angle(from: lElbow, to: lWrist)
        let clubCenter = CGPoint(x: club.boundingBox.midX, y: club.boundingBox.midY)
        let clubAngle = angle(from: lWrist.location, to: clubCenter)
        var lagAngle = abs(forearmAngle - clubAngle)
        if lagAngle > 180 { lagAngle = 360 - lagAngle }
        if lagAngle > 90 { lagAngle = 180 - lagAngle }
        return round(lagAngle * 10) / 10
    }

    private func getHipSwayHO(from addressPose: VNHumanBodyPoseObservation, at keyPose: VNHumanBodyPoseObservation, inchesPerUnit: Double) -> Double? {
            
            // 1. Get hip centers
            guard let lHipAddress = getJoint(.leftHip, from: addressPose),
                  let rHipAddress = getJoint(.rightHip, from: addressPose),
                  let lHipKey = getJoint(.leftHip, from: keyPose),
                  let rHipKey = getJoint(.rightHip, from: keyPose) else { return nil }
            
            // 2. Get spine anchors to create a stable Torso Length reference
            guard let neck = getJoint(.neck, from: addressPose),
                  let root = getJoint(.root, from: addressPose) else { return nil }
                  
            // 3. Calculate Torso Length (Ruler in AI Units)
            let torsoLength = distance(from: neck.location, to: root.location)
            guard torsoLength > 0.01 else { return nil } // Safety check

            // 4. Calculate the horizontal displacement (Actual Sway)
            let addressMidX = (lHipAddress.location.x + rHipAddress.location.x) / 2
            let keyMidX = (lHipKey.location.x + rHipKey.location.x) / 2
            let displacement = abs(keyMidX - addressMidX)
            
            // 5. Calculate the Sway Ratio: (Displacement / Torso Length)
            // This is the absolute, unit-less measure of the sway.
            let swayRatio = displacement / torsoLength

            // 6. Define a new Pro Target Ratio (4.0 inches Target / 18.0 inches avg torso length)
            // This creates a stable, target-based ratio for scoring.
            let proTargetRatio = 0.22
            let proRangeRatio = 0.05
            
            // 7. Score the Ratio (We must call the original scoring engine using the ratio)
            // NOTE: We temporarily cast the ratio to a Double, then score it.
            let ruleForScoring = Metric(
                metric_name: "Hip Sway Ratio",
                pro_target: proTargetRatio,
                pro_range: proRangeRatio,
                units: Metric.UnitType.ratio,
                priority_beginner: 10,
                priority_advanced: 8,
                root_cause_for: [],
                symptom_of: [],
                human_explanation: "Placeholder",
                why_it_matters: "Placeholder",
                drills: []
            )
            
        _ = calculateScore(actual: Double(swayRatio), rule: ruleForScoring)
            
            // We will return the final Ratio for the log, not the score.
            return round(swayRatio * 100) / 100 // Return the ratio (e.g., 0.15) for comparison
        }
    
    private func getHeadSwayHO(from addressPose: VNHumanBodyPoseObservation, at keyPose: VNHumanBodyPoseObservation, inchesPerUnit: Double) -> Double? {
        guard let addressNose = getJoint(.nose, from: addressPose),
              let keyNose = getJoint(.nose, from: keyPose) else { return nil }
        let deltaX = keyNose.location.x - addressNose.location.x
        let swayInInches = deltaX * inchesPerUnit
        return round(swayInInches * 10) / 10
    }
    
    private func getShaftLeanHO(from club: VNRecognizedObjectObservation) -> Double? {
        let angle = getClubAngle(from: club)
        
        // FIX: The club angle needs to be flipped by 180 degrees to align with
        // the HO coordinate system. We then calculate deviation from vertical (90 degrees).
        var correctedAngle = angle + 180.0
        
        // Ensure angle is within +/- 180 range
        while correctedAngle > 180.0 { correctedAngle -= 360.0 }
        while correctedAngle < -180.0 { correctedAngle += 360.0 }
        
        let lean = correctedAngle - 90.0
        return round(lean * 10) / 10
    }
    
    // MARK: - DTL Geometry Helpers
    
    private func getSpineBendDTL(from pose: VNHumanBodyPoseObservation) -> Double? {
        guard let neck = getJoint(.neck, from: pose),
              let root = getJoint(.root, from: pose) else { return nil }
        
        let rawAngle = angle(from: neck.location, to: root.location)
        
        // This is the correct, common golf math: Angle from vertical (90 degrees)
        // If rawAngle is 135, tilt is 45. If rawAngle is 45, tilt is 45.
        // We use abs(rawAngle) to handle the sign, and abs(90.0 - ...) to get the deviation.
        let bend = abs(90.0 - abs(rawAngle))
        
        return round(bend * 10) / 10
    }
    
    private func getShoulderPlaneDTL(from pose: VNHumanBodyPoseObservation) -> Double? {
        guard let lShoulder = getJoint(.leftShoulder, from: pose),
              let rShoulder = getJoint(.rightShoulder, from: pose) else { return nil }
        
        let rawAngle = angle(from: lShoulder, to: rShoulder)
        
        // The angle is being read on the wrong side of the plane (180 degrees off)
        // The tilt is the deviation from the horizontal plane (0 or 180).
        let correctedAngle = rawAngle + 180.0
        let tilt = abs(correctedAngle).truncatingRemainder(dividingBy: 180)
        
        // We measure the deviation from 90 (vertical) in the final geometry.
        let shoulderTilt = abs(90.0 - tilt)
        
        return round(shoulderTilt * 10) / 10
    }

    private func getHipDepthDTL(from addressPose: VNHumanBodyPoseObservation, at topPose: VNHumanBodyPoseObservation, inchesPerUnit: Double) -> Double? {
        // In Landscape DTL, "Depth" is movement along the X-axis (Left/Right).
        // Vision (0,0) is Bottom-Left.
        // Backwards movement (away from ball) is usually negative X in Vision if facing right.
        guard let addressHip = getJoint(.rightHip, from: addressPose),
              let topHip = getJoint(.rightHip, from: topPose) else { return nil }
        
        let deltaX = topHip.location.x - addressHip.location.x
        
        // We use abs() because depth is depth, regardless of which way the player faces
        let depthInInches = abs(deltaX) * inchesPerUnit
        return round(depthInInches * 10) / 10
    }
    
    private func getTrailLegFlexChange(from addressPose: VNHumanBodyPoseObservation, at topPose: VNHumanBodyPoseObservation) -> Double? {
        guard let addressHip = getJoint(.rightHip, from: addressPose),
              let addressKnee = getJoint(.rightKnee, from: addressPose),
              let addressAnkle = getJoint(.rightAnkle, from: addressPose),
              let topHip = getJoint(.rightHip, from: topPose),
              let topKnee = getJoint(.rightKnee, from: topPose),
              let topAnkle = getJoint(.rightAnkle, from: topPose) else { return nil }
        
        let addressFlex = angle(from: addressHip, to: addressKnee, and: addressAnkle)
        let topFlex = angle(from: topHip, to: topKnee, and: topAnkle)
        let change = topFlex - addressFlex
        return round(change * 10) / 10
    }
    
    private func getWristSetDTL(from pose: VNHumanBodyPoseObservation, club: VNRecognizedObjectObservation) -> Double? {
        guard let lWrist = getJoint(.leftWrist, from: pose),
              let lElbow = getJoint(.leftElbow, from: pose) else { return nil }
        
        let forearmAngle = angle(from: lElbow, to: lWrist)
        let clubCenter = CGPoint(x: club.boundingBox.midX, y: club.boundingBox.midY)
        let clubAngle = angle(from: lWrist.location, to: clubCenter)
        
        var wristSet = forearmAngle - clubAngle
        
        // This is the core fix for the 360-degree wrap-around issue, which inflates angles.
        // It ensures we are using the shortest path between the two angles.
        while wristSet > 180.0 { wristSet -= 360.0 }
        while wristSet < -180.0 { wristSet += 360.0 }
        
        // The ProModel uses negative for "bowed/lag" (correct). We flip the sign
        // because Vision's angle convention often results in the inverse.
        // We will apply a damping factor (e.g., 0.5) to compensate for noise/inflation
        // often seen in angle measurements from bounding boxes.
        let dampedSet = -wristSet * 0.5
        
        return round(dampedSet * 10) / 10
    }
    
    private func getTakeawayPath(from pose: VNHumanBodyPoseObservation, clubAtP2: VNRecognizedObjectObservation, inchesPerUnit: Double) -> Double? {
        guard let lHand = getJoint(.leftWrist, from: pose),
              let rHand = getJoint(.rightWrist, from: pose) else { return nil }
        let handsCenterX = (lHand.location.x + rHand.location.x) / 2
        let clubCenterX = clubAtP2.boundingBox.midX
        let deltaX = clubCenterX - handsCenterX
        let pathInInches = deltaX * inchesPerUnit
        return round(pathInInches * 10) / 10
    }
    
    private func getBackswingWidth(from pose: VNHumanBodyPoseObservation) -> Double? {
        guard let lHand = getJoint(.leftWrist, from: pose),
              let rHand = getJoint(.rightWrist, from: pose),
              let nose = getJoint(.nose, from: pose),
              let lEar = getJoint(.leftEar, from: pose),
              let rEar = getJoint(.rightEar, from: pose) else { return nil }
        
        let handsCenter = CGPoint(x: (lHand.location.x + rHand.location.x) / 2,
                                  y: (lHand.location.y + rHand.location.y) / 2)
        let headWidth = distance(from: lEar, to: rEar)
        guard headWidth > 0 else { return nil }
        
        let handToNoseDist = distance(from: handsCenter, to: nose)
        let ratio = handToNoseDist / headWidth
        return round(ratio * 10) / 10
    }
    
    private func getClubAngle(from club: VNRecognizedObjectObservation) -> CGFloat {
        let box = club.boundingBox
        let topPoint = CGPoint(x: box.midX, y: box.maxY)
        let bottomPoint = CGPoint(x: box.midX, y: box.minY)
        return angle(from: topPoint, to: bottomPoint)
    }

    private func getAngleOfAttack(from preImpactClub: VNRecognizedObjectObservation, to impactClub: VNRecognizedObjectObservation) -> Double? {
        let preImpactBox = preImpactClub.boundingBox
        let preImpactPoint = CGPoint(x: preImpactBox.midX, y: preImpactBox.minY)
        let impactBox = impactClub.boundingBox
        let impactPoint = CGPoint(x: impactBox.midX, y: impactBox.minY)
        let angle = angle(from: preImpactPoint, to: impactPoint)
        return round(angle * 10) / 10
    }
    
    private func getShaftShallowing(clubAtTop: VNRecognizedObjectObservation, clubAtDownswing: VNRecognizedObjectObservation) -> Double? {
        let topAngle = getClubAngle(from: clubAtTop)
        let downswingAngle = getClubAngle(from: clubAtDownswing)
        let change = topAngle - downswingAngle
        return round(change * 10) / 10
    }

    // MARK: - Scoring & Math Helpers
    
    // --- THIS IS THE CORRECT "70-POINT GRADIENT" SCORING ENGINE ---
    private func calculateScore(actual: Double, rule: Metric) -> Int {
        let target = rule.pro_target
        let range = rule.pro_range // This is our "70-point" tolerance
        
        // This is the "max error" where the score hits 0.
        // Formula: range + (range * (70.0 / 30.0)) which simplifies to range * (10.0 / 3.0)
        let maxError = range * (10.0 / 3.0)

        let error = abs(actual - target)

        // This handles "target-centric" scores (default for "degrees", "inches_normalized", etc.)
        // 100 at target (0 error), 70 at `range` error, 0 at `maxError`.
        
        // We will add the "one-sided" logic (degrees_positive) back in our next iteration.
        // For now, this robust "target-centric" gradient is the most important logic.
        
        if error >= maxError { return 0 }
        
        if error <= range {
            // We are in the 70-100 "passing" range
            // This is a 30-point drop over the "range"
            let score = 100.0 - (30.0 * (error / range))
            return Int(score)
        } else {
            // We are in the 0-70 "failing" range
            let errorPastPassing = error - range
            let failRangeWidth = maxError - range // This is our (range * 7/3)
            let score = 70.0 * (1.0 - (errorPastPassing / failRangeWidth))
            return Int(max(0, score))
        }
    }
    
    // This is a safe way to get a joint
    private func getJoint(_ jointName: VNHumanBodyPoseObservation.JointName, from pose: VNHumanBodyPoseObservation) -> VNRecognizedPoint? {
        guard let point = try? pose.recognizedPoint(jointName) else { return nil }
        // We only trust points that the AI is at least 10% confident about
        return point.confidence > 0.1 ? point : nil
    }

    // Helper to calculate distance between two normalized 0.0-1.0 points
    private func distance(from p1: VNRecognizedPoint, to p2: VNRecognizedPoint) -> CGFloat {
        // We must check confidence *before* using the point
        guard p1.confidence > 0 && p2.confidence > 0 else { return 0 }
        return sqrt(pow(p1.location.x - p2.location.x, 2) + pow(p1.location.y - p2.location.y, 2))
    }
    
    // Helper to calculate distance between CGPoint and VNRecognizedPoint
    private func distance(from point: CGPoint, to recognizedPoint: VNRecognizedPoint) -> CGFloat {
        guard recognizedPoint.confidence > 0 else { return 0 }
        return sqrt(pow(point.x - recognizedPoint.location.x, 2) + pow(point.y - recognizedPoint.location.y, 2))
    }
    
    // Helper to calculate angle between three points (e.g., knee flex)
    private func angle(from p1: VNRecognizedPoint, to p2: VNRecognizedPoint, and p3: VNRecognizedPoint) -> CGFloat {
        // We must check confidence *before* using the points
        guard p1.confidence > 0, p2.confidence > 0, p3.confidence > 0 else { return 0 }
        
        // Create vectors from p2 to p1 and p2 to p3
        let v1 = (x: p1.location.x - p2.location.x, y: p1.location.y - p2.location.y)
        let v2 = (x: p3.location.x - p2.location.x, y: p3.location.y - p2.location.y)
        
        let dotProduct = v1.x * v2.x + v1.y * v2.y
        
        // Calculate magnitudes
        let mag1 = sqrt(v1.x * v1.x + v1.y * v1.y)
        let mag2 = sqrt(v2.x * v2.x + v2.y * v2.y)
        
        // Prevent division by zero
        if mag1 == 0 || mag2 == 0 { return 0 }
        
        // Calculate cosine of the angle
        let cosTheta = dotProduct / (mag1 * mag2)
        
        // Clamp the value to [-1.0, 1.0] to avoid floating point errors
        let clampedCosTheta = max(-1.0, min(1.0, cosTheta))
        
        // Return angle in degrees
        return acos(clampedCosTheta) * 180.0 / .pi
    }
    
    // Helper to calculate angle of a single line relative to horizontal
    // Note: Vision's coordinate system has Y=0 at the BOTTOM.
    private func angle(from p1: CGPoint, to p2: CGPoint) -> CGFloat {
        let deltaY = p2.y - p1.y
        let deltaX = p2.x - p1.x
        return atan2(deltaY, deltaX) * 180.0 / .pi // in Degrees
    }
    
    private func angle(from p1: VNRecognizedPoint, to p2: VNRecognizedPoint) -> CGFloat {
        guard p1.confidence > 0, p2.confidence > 0 else { return 0 }
        return angle(from: p1.location, to: p2.location)
    }
    
    private func getInchesPerUnitDTL(from pose: VNHumanBodyPoseObservation) -> Double? {
        // We measure "height" from the left ankle to the nose,
        // as these are stable points in a DTL view.
        guard let ankle = getJoint(.leftAnkle, from: pose),
              let nose = getJoint(.nose, from: pose) else {
            print("DTL Normalization Error: Could not find ankle or nose.")
            return nil
        }
        
        // Measure the distance (in AI units 0.0-1.0)
        let heightInUnits = distance(from: ankle.location, to: nose.location)
        guard heightInUnits > 0 else { return nil }
        
        // Create the "ruler"
        // e.g., 68.0 inches / 0.82 units = 82.9 inches per unit
        return self.userHeightInInches / heightInUnits
    }
    
    // Helper function (already in your code, but needed for the one above)
    // Helper to calculate distance between two CGPoint
    private func distance(from p1: CGPoint, to p2: CGPoint) -> CGFloat {
        return sqrt(pow(p1.x - p2.x, 2) + pow(p1.y - p2.y, 2))
    }
    
    // --- 10. UI Control Functions ---
    // This function resets the app back to the camera screen
    func dismissResults() {
        DispatchQueue.main.async {
            self.currentAnalysis = nil
            self.mainFlawName = "No analysis yet." // <-- RESET
            self.mainFlaw = "No analysis yet."
            self.coachingDrill = nil
            self.coachingScore = 0
            self.detailedScores = [] // <-- RESET
            self.analysisVideoURL = nil // <-- RESET
        }
    }
    
    // MARK: - Data Persistence
    func saveCurrentAnalysis(isPermanent: Bool) {
        guard let analysis = currentAnalysis else { return }
        
        // 1. Create the Card/Record using the new .codableData property
        let newRecord = SwingRecord(
            date: Date(),
            score: coachingScore,
            mainFlawName: mainFlawName,
            mainFlaw: mainFlaw,
            coachingDrill: coachingDrill,
            skeletonScreenshotData: nil,
            analysis: analysis.codableData, // <-- FIX: Use the new Codable property
            isPermanent: isPermanent
        )

        // 2. Check for existence (Fixes the "doesn't save if I just go straight to the camera" issue)
        // If the record already exists (i.e., it was auto-saved), update it instead of appending a duplicate.
        if let index = historySwings.firstIndex(where: { $0.id == currentAnalysisID }) {
            historySwings[index] = newRecord
        } else {
            historySwings.append(newRecord)
        }

        // 3. Save to disk
        persistenceService.saveSwings(historySwings)
    }
    
    func loadHistoryFromPersistence() {
        DispatchQueue.main.async {
            // Assume you have access to persistenceService from your previous setup
            self.historySwings = self.persistenceService.loadSwings()
        }
    }
    func deleteSwing(id: UUID) {
        print("Entered deleteSwing -- ViewModel")
        print("UUID to delete: " + id.uuidString)
        for record in historySwings {
            print(record.id.uuidString)
        }
        if let index = historySwings.lastIndex(where: { $0.id == id }) {
            historySwings.remove(at: index)
            persistenceService.saveSwings(historySwings)
            print("Deleted Swing -- ViewModel")
        }
    }
    
    func loadHistoricalAnalysis(record: SwingRecord) {
        print("ViewModel: Loading history for \(record.id)")
        
        // 1. Set ID immediately
        self.currentAnalysisID = record.id
        
        // 2. Load Metadata immediately
        self.coachingScore = record.score
        self.mainFlawName = record.mainFlawName
        self.mainFlaw = record.mainFlaw
        self.coachingDrill = record.coachingDrill
        
        // 3. Rebuild the Analysis Object immediately
        // This ensures 'currentAnalysis' is not nil when the view opens.
        self.currentAnalysis = SwingAnalysis(from: record.analysis)
    }
    
    // Save all swings in history to disk.
    public func saveHistory() {
        persistenceService.saveSwings(historySwings)
    }
    
    func closeHistory() {
            DispatchQueue.main.async {
                self.currentAnalysis = nil // Clear the data so Camera View doesn't react
                self.showHistory = false   // Dismiss the cover
                self.showSettings = false
            }
        }
}

