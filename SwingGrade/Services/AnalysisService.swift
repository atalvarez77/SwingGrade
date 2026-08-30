import Foundation
import AVFoundation
import Vision
import CoreML
import Combine
import UIKit

// This struct holds a single point of club data for our Velocity Scan
struct ClubMovementData {
    let time: Double
    let clubCenter: CGPoint // Normalized (0.0 - 1.0)
}

class AnalysisService: ObservableObject {
    
    // --- 1. Load Custom AI Model ---
    private lazy var clubModel: VNCoreMLModel? = {
        do {
            // This loads the "brain"
            let model = try SwingGrade_Tracker(configuration: MLModelConfiguration()).model
            return try VNCoreMLModel(for: model)
        } catch {
            print("FATAL ERROR: Failed to load SwingGrade_Tracker.mlmodel: \(error.localizedDescription)")
            return nil
        }
    }()
    
    
    // --- 2. The Main "THREE-Pass" Analysis Function ---
    func performAnalysis(on videoURL: URL, view: String) async -> (analysis: SwingAnalysis, videoURL: URL)? {
        
        print("Analysis Engine: Starting analysis...")
        var analysisResults = SwingAnalysis()
        let asset = AVURLAsset(url: videoURL)
        let videoDuration = (try? await asset.load(.duration))?.seconds ?? 3.0

        // ==========================================================
        // PASS 1: FIND IMPACT (AUDIO ANALYSIS)
        // ==========================================================
        
        guard let impactTime = await findImpactTime(from: asset) else {
            print("Analysis Engine: Could not find impact time. Aborting analysis.")
            defer { self.deleteVideoFile(at: videoURL) }
            return nil
        }
        print("PASS 1 (AUDIO): Impact found at \(impactTime)s.")
        
        // ==========================================================
        // PASS 2: VELOCITY SCAN (Find Key Poses)
        // ==========================================================
        
        print("PASS 2 (VELOCITY): Starting club velocity scan...")
        
        // --- THE "CHICKEN HEAD" (ORIENTATION) FIX ---
        let videoOrientation = await getCorrectVideoOrientation(from: asset)
        
        // We pass the asset AND its orientation info to the scan
        let clubMovements = await performVelocityScan(on: asset, upTo: impactTime, orientation: videoOrientation)
        
        // We now pass the 'view' to findKeyPoses
        guard let (addressTime, topOfSwingTime) = findKeyPoses(from: clubMovements, impactTime: impactTime, view: view) else {
            print("Analysis Engine: Could not find address or top of swing. Aborting.")
            defer { self.deleteVideoFile(at: videoURL) }
            return nil
        }

        print("PASS 2 (VELOCITY): Found Address at \(addressTime)s.")
        print("PASS 2 (VELOCITY): Found Top of Swing at \(topOfSwingTime)s.")
        
        // ==========================================================
        // PASS 3: ANALYZE KEY FRAMES (AI SPRINT)
        // ==========================================================
        
        let imageGenerator = AVAssetImageGenerator(asset: asset)
        // --- "CHICKEN HEAD" FIX #2 ---
        imageGenerator.appliesPreferredTrackTransform = true
        imageGenerator.requestedTimeToleranceBefore = .zero
        imageGenerator.requestedTimeToleranceAfter = .zero
        
        let keyTimes: [String: Double] = [
            "address": addressTime,
            "top":     topOfSwingTime,
            // (We still use relative times for high-speed frames)
            "downswing_parallel": (topOfSwingTime + impactTime) / 2, // Halfway down
            "pre_impact": impactTime - 0.02, // 20ms before impact
            "impact":  impactTime,
            "finish":  impactTime + 0.5
        ]
        
        for (name, timeInSeconds) in keyTimes {
            // Ensure the time is valid and within the video's length
            guard timeInSeconds > 0 && timeInSeconds < videoDuration else {
                print("PASS 3 (AI): Skipping frame '\(name)' - time is out of bounds.")
                continue
            }
            
            let time = CMTime(seconds: timeInSeconds, preferredTimescale: 600)
            
            do {
                let cgImage = try await imageGenerator.image(at: time).image
                
                // We pass the *true* orientation of the video frame
                let dataPoint = try await analyzeFrame(cgImage: cgImage, at: timeInSeconds, orientation: videoOrientation)
                
                switch name {
                case "address": analysisResults.address = dataPoint
                case "top": analysisResults.topOfBackswing = dataPoint
                case "downswing_parallel": analysisResults.downswingParallel = dataPoint
                case "pre_impact": analysisResults.preImpact = dataPoint
                case "impact": analysisResults.impact = dataPoint
                case "finish": analysisResults.finish = dataPoint
                default: break
                }
                
                print("PASS 3 (AI): Successfully analyzed frame: \(name)")
                
            } catch {
                print("Error analyzing frame at \(timeInSeconds)s: \(error.localizedDescription)")
            }
        }
        
        // --- 4. The "Delete" Step ---
        defer {
            self.deleteVideoFile(at: videoURL)
        }
        
        print("Analysis Engine: Analysis complete.")
        return (analysisResults, videoURL)
    }
    
    
    // --- 4. "PASS 1" AUDIO ANALYZER ---
    
    private func findImpactTime(from asset: AVAsset) async -> Double? {
        print("PASS 1 (Audio): Starting audio analysis...")
        do {
            guard let audioTrack = try? await asset.loadTracks(withMediaType: .audio).first else {
                print("Audio Analyzer: No audio track found in this video."); return nil
            }

            let outputSettings: [String: Any] = [
                AVFormatIDKey: kAudioFormatLinearPCM,
                AVSampleRateKey: 44100,
                AVNumberOfChannelsKey: 1
            ]
            
            let trackOutput = AVAssetReaderTrackOutput(track: audioTrack, outputSettings: outputSettings)
            let reader = try AVAssetReader(asset: asset)

            if reader.canAdd(trackOutput) { reader.add(trackOutput) }
            else { print("Audio Analyzer: Cannot add audio track output."); return nil }

            reader.startReading()

            var maxAmplitude: Float = 0.0
            var maxFrame: AVAudioFramePosition = 0
            var totalFrames: AVAudioFramePosition = 0

            while reader.status == .reading, let sampleBuffer = trackOutput.copyNextSampleBuffer() {
                var audioBufferList = AudioBufferList()
                var blockBuffer: CMBlockBuffer?
                CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(
                    sampleBuffer,
                    bufferListSizeNeededOut: nil,
                    bufferListOut: &audioBufferList,
                    bufferListSize: MemoryLayout<AudioBufferList>.size,
                    blockBufferAllocator: kCFAllocatorDefault,
                    blockBufferMemoryAllocator: kCFAllocatorDefault,
                    flags: kCMSampleBufferFlag_AudioBufferList_Assure16ByteAlignment,
                    blockBufferOut: &blockBuffer
                )
                let buffer = audioBufferList.mBuffers
                guard let mData = buffer.mData else { continue }
                let data = mData.assumingMemoryBound(to: Float.self)
                let sampleCount = Int(buffer.mDataByteSize) / MemoryLayout<Float>.size

                for i in 0..<sampleCount {
                    let amplitude = abs(data[i])
                    if amplitude > maxAmplitude {
                        maxAmplitude = amplitude
                        maxFrame = totalFrames + AVAudioFramePosition(i)
                    }
                }
                totalFrames += AVAudioFramePosition(sampleCount)
            }
            reader.cancelReading()

            let naturalTimeScale = try await audioTrack.load(.naturalTimeScale)
            let impactTime = Double(maxFrame) / Double(naturalTimeScale)

            print("PASS 1 (Audio): Finished. Max amplitude \(maxAmplitude) found at time \(impactTime)s.")
            guard impactTime > 0.01 else {
                print("Audio Analyzer: Failed to find valid impact sound."); return nil
            }
            return impactTime

        } catch {
            print("Audio Analyzer: Error reading audio asset: \(error.localizedDescription)"); return nil
        }
    }
    
    // --- 5. "PASS 2" VELOCITY SCAN ---
    
    // --- THIS IS THE NEW, MORE ROBUST VELOCITY SCAN FUNCTION ---
    private func performVelocityScan(on asset: AVAsset, upTo impactTime: Double, orientation: CGImagePropertyOrientation) async -> [ClubMovementData] {
        var movements: [ClubMovementData] = []
        guard let clubModel = self.clubModel else { return [] }

        let imageGenerator = AVAssetImageGenerator(asset: asset)
        imageGenerator.appliesPreferredTrackTransform = true
        imageGenerator.requestedTimeToleranceBefore = .zero
        imageGenerator.requestedTimeToleranceAfter = .zero
        
        let totalDuration = impactTime
        let frameRate: Double = 20.0 // Scan 20 frames per second
        let frameCount = Int(totalDuration * frameRate)
        
        // Instead of the 'images(for:)' function, we will loop
        // and get each image one-by-one, just like in Pass 3.
        
        for i in 0...frameCount {
            let timeSeconds = (Double(i) / frameRate)
            let cmTime = CMTime(seconds: timeSeconds, preferredTimescale: 600)
            
            do {
                // 1. Get the single image
                let cgImage = try await imageGenerator.image(at: cmTime).image
                let timestamp = cmTime.seconds // Use the requested time
                
                // 2. Run our AI model on it
                let clubRequest = VNCoreMLRequest(model: clubModel)
                let handler = VNImageRequestHandler(cgImage: cgImage, orientation: orientation)
                try handler.perform([clubRequest])
                
                // 3. Save the data
                if let club = (clubRequest.results as? [VNRecognizedObjectObservation])?
                    .filter({ $0.confidence > 0.3 }).first {
                    let clubCenter = CGPoint(x: club.boundingBox.midX, y: club.boundingBox.midY)
                    movements.append(ClubMovementData(time: timestamp, clubCenter: clubCenter))
                }
                
            } catch {
                // If one frame fails, we just print and continue
                print("Velocity Scan: Warning - Could not analyze frame at \(timeSeconds)s: \(error.localizedDescription)")
            }
        }
        // --- END OF NEW LOOP ---
        
        print("PASS 2 (VELOCITY): Velocity scan complete. Found \(movements.count) club positions.")
        
        print("\n--- BEGIN VELOCITY SCAN LOG ---")
        print("Timestamp | Club Center (X, Y)")
        print("---------------------------------")
        for (index, move) in movements.enumerated() {
            if index % 2 == 0 {
                let xPos = String(format: "%.3f", move.clubCenter.x)
                let yPos = String(format: "%.3f", move.clubCenter.y)
                print("\(String(format: "%.2f", move.time))s      | (\(xPos), \(yPos))")
            }
        }
        print("--- END VELOCITY SCAN LOG ---\n")
        
        return movements
    }
    
    // --- THIS IS THE NEW, "SMARTER" POSE FINDER (WITH DEBUGGING) ---
    private func findKeyPoses(from movements: [ClubMovementData], impactTime: Double, view: String) -> (addressTime: Double, topOfSwingTime: Double)? {
        guard movements.count > 10 else {
            print("Velocity Scan: Not enough data to find poses. Using hard-coded times.")
            return (impactTime - 1.0, impactTime - 0.3)
        }
        
        // --- 1. FIND ADDRESS (SIMPLIFIED FOR HO STABILITY) ---
        var stillFrames = 0
        var addressTime = movements.first?.time ?? 0.0
        var foundAddress = false
        
        // Use a less aggressive stillness check for the first few frames
        for i in 1..<movements.count {
            if movements[i].time >= impactTime { break }
            
            // Check for change in position
            let dx = abs(movements[i].clubCenter.x - movements[i-1].clubCenter.x)
            let dy = abs(movements[i].clubCenter.y - movements[i-1].clubCenter.y)
            
            // If we find 8 consecutive 'still' frames, we assume address found.
            // NOTE: We lower the threshold slightly to catch subtle starts.
            if dx < 0.007 && dy < 0.007 {
                stillFrames += 1
            } else if stillFrames >= 8 { // Changed from 5 to 8 to avoid false positives.
                addressTime = movements[i-1].time
                foundAddress = true
                break
            } else {
                stillFrames = 0
            }
        }
        
        if !foundAddress {
            print("Velocity Scan: Could not find a still 'Address'. Falling back to first moving frame.")
            // A more robust fallback: use the earliest time *before* impact.
            addressTime = movements.first(where: { $0.time > 0.0 })?.time ?? 0.0
        }

        // --- 2. FIND TOP OF SWING (DTL vs. HO LOGIC) ---
        var topOfSwingTime = movements.last(where: { $0.time < impactTime })?.time ?? (impactTime - 0.3)
        
        let swingMovements = movements.filter { $0.time > addressTime && $0.time < impactTime }
        
        if view == "head_on_view" {
            // HO: Find the frame with the "highest" Y position (max backswing height)
            let topPose = swingMovements.max(by: { $0.clubCenter.y < $1.clubCenter.y })
            topOfSwingTime = topPose?.time ?? topOfSwingTime
            
            if topPose == nil { print("HO Check: Could not find a HO top pose. Using fallback.") }
        } else {
            // DTL: Find the frame with the "left-most" X position (max backswing width)
            let topPose = swingMovements.min(by: { $0.clubCenter.x < $1.clubCenter.x })
            topOfSwingTime = topPose?.time ?? topOfSwingTime
            
            if topPose == nil { print("DTL Check: Could not find a DTL top pose. Using fallback.") }
        }
        
        return (addressTime, topOfSwingTime)
    }
    
    // --- 6. "PASS 3" FRAME ANALYZER ---
    
    private func analyzeFrame(cgImage: CGImage, at timeInSeconds: Double, orientation: CGImagePropertyOrientation) async throws -> SwingDataPointLive {
        
        let bodyPoseRequest = VNDetectHumanBodyPoseRequest()
        guard let clubModel = self.clubModel else {
            throw NSError(domain: "AnalysisService", code: 1, userInfo: [NSLocalizedDescriptionKey: "Club model not loaded"])
        }
        let clubRequest = VNCoreMLRequest(model: clubModel)
        
        let handler = VNImageRequestHandler(cgImage: cgImage, orientation: orientation)
        
        try handler.perform([bodyPoseRequest, clubRequest])
        
        let allClubs = (clubRequest.results as? [VNRecognizedObjectObservation])?
            .filter { $0.confidence > 0.5 }
        
        let bodyPose = self.findMainUser(from: bodyPoseRequest.results)
        let clubObservation = self.findClub(for: bodyPose, from: allClubs)
        
        return SwingDataPointLive(
            time: timeInSeconds,
            bodyPose: bodyPose,
            clubObservation: clubObservation
        )
    }
    
    // --- 7. NEW ORIENTATION HELPER ---
    
    private func getCorrectVideoOrientation(from asset: AVAsset) async -> CGImagePropertyOrientation {
        guard let track = try? await asset.loadTracks(withMediaType: .video).first else {
            return .up // Default
        }
        
        let transform = try? await track.load(.preferredTransform)
        guard let transform = transform else { return .up }

        // This math figures out the rotation
        if transform.a == 0 && transform.b == 1.0 && transform.c == -1.0 && transform.d == 0 {
            return .right // Landscape Right
        } else if transform.a == 0 && transform.b == -1.0 && transform.c == 1.0 && transform.d == 0 {
            return .left // Landscape Left
        } else if transform.a == 1.0 && transform.b == 0 && transform.c == 0 && transform.d == 1.0 {
            return .up // Portrait
        } else if transform.a == -1.0 && transform.b == 0 && transform.c == 0 && transform.d == -1.0 {
            return .down // Portrait Upside Down
        } else {
            return .up
        }
    }
    
    // --- 8. SMART FILTER HELPER FUNCTIONS ---
    
    private func findMainUser(from poses: [VNHumanBodyPoseObservation]?) -> VNHumanBodyPoseObservation? {
        guard let poses = poses, !poses.isEmpty else { return nil }
        var largestPose: VNHumanBodyPoseObservation? = nil
        var maxArea: CGFloat = 0.0
        
        for pose in poses {
            guard let allPoints = try? pose.recognizedPoints(.all) else { continue }
            let validPoints = allPoints.values.filter { $0.confidence > 0.1 }
            guard !validPoints.isEmpty else { continue }
            
            let minX = validPoints.map { $0.location.x }.min() ?? 0
            let maxX = validPoints.map { $0.location.x }.max() ?? 0
            let minY = validPoints.map { $0.location.y }.min() ?? 0
            let maxY = validPoints.map { $0.location.y }.max() ?? 0
            
            let area = (maxX - minX) * (maxY - minY)
            
            if area > maxArea {
                maxArea = area
                largestPose = pose
            }
        }
        return largestPose
    }
    
    private func findClub(for user: VNHumanBodyPoseObservation?, from clubs: [VNRecognizedObjectObservation]?) -> VNRecognizedObjectObservation? {
        guard let clubs = clubs, !clubs.isEmpty else { return nil }
        
        // If we don't have a user, just return the biggest club
        guard let user = user, let torsoCenter = getTorsoCenter(for: user) else {
            return clubs.sorted(by: { $0.boundingBox.width * $0.boundingBox.height > $1.boundingBox.width * $1.boundingBox.height }).first
        }
        
        var closestClub: VNRecognizedObjectObservation? = nil
        var minDistance: CGFloat = .infinity
        
        for club in clubs {
            let clubCenter = CGPoint(x: club.boundingBox.midX, y: club.boundingBox.midY)
            let distance = distance(from: torsoCenter, to: clubCenter)
            if distance < minDistance {
                minDistance = distance
                closestClub = club
            }
        }
        return closestClub
    }
    
    private func getTorsoCenter(for pose: VNHumanBodyPoseObservation) -> CGPoint? {
        guard let neckPoint = try? pose.recognizedPoint(.neck),
              let rootPoint = try? pose.recognizedPoint(.root),
              neckPoint.confidence > 0.1, rootPoint.confidence > 0.1 else {
            return nil
        }
        let centerX = (neckPoint.location.x + rootPoint.location.x) / 2
        let centerY = (neckPoint.location.y + rootPoint.location.y) / 2
        return CGPoint(x: centerX, y: centerY)
    }
    
    private func distance(from p1: CGPoint, to p2: CGPoint) -> CGFloat {
        return sqrt(pow(p1.x - p2.x, 2) + pow(p1.y - p2.y, 2))
    }
    
    // --- 9. FILE DELETION HELPER ---
    private func deleteVideoFile(at url: URL) {
        do {
            try FileManager.default.removeItem(at: url)
            print("Analysis Engine: Successfully deleted temporary video file.")
        } catch {
            print("Analysis Engine: ERROR deleting temporary file: \(error.localizedDescription)")
        }
    }
}
