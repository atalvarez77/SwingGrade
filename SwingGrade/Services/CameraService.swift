import Foundation
import AVFoundation
import Combine
import CoreImage
import Vision

class CameraService: NSObject, ObservableObject, AVCaptureFileOutputRecordingDelegate, AVCaptureVideoDataOutputSampleBufferDelegate {
    
    // --- 1. Published Properties ---
    @Published var isConfigured: Bool = false
    @Published var isRecording: Bool = false
    @Published var videoURLReady: URL?
    
    @Published var currentFrame: CGImage?
    
    private let analysisService = AnalysisService()
    
    // --- 2. Core AVFoundation Properties ---
    var session = AVCaptureSession()
    private var videoDevice: AVCaptureDevice!
    private var videoInput: AVCaptureDeviceInput!
    var movieOutput = AVCaptureMovieFileOutput()
    
    // --- 3. New Properties for Frame Grabbing ---
    private let videoOutputQueue = DispatchQueue(label: "VideoOutputQueue", qos: .userInitiated)
    private let ciContext = CIContext() // This converts frames to displayable images
    

    // --- 4. The Main Setup Function (Corrected) ---
    func configureSession() {
        session.beginConfiguration()
        session.sessionPreset = .inputPriority
        
        // --- Find and Configure the 240 FPS Camera ---
        let discoverySession = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInWideAngleCamera, .builtInUltraWideCamera, .builtInTelephotoCamera],
            mediaType: .video,
            position: .back
        )
        
        // Loop through list and find the specific 1x camera
        guard let device = discoverySession.devices.first(where: { $0.deviceType == .builtInWideAngleCamera}) else {
            print("Error: Could not find the 1x Wide Angle camera.")
            session.commitConfiguration()
            return
        }
        
        print("INFO: Successfully found and selected the 1x Wide Angle camera")
        
        self.videoDevice = device
        
        var bestFormat: AVCaptureDevice.Format?
        let targetFrameRate: Double = 240.0
        
        for format in device.formats {
            for range in format.videoSupportedFrameRateRanges {
                if range.maxFrameRate >= targetFrameRate {
                    bestFormat = format
                    break
                }
            }
            if bestFormat != nil { break }
        }
        
        guard let finalFormat = bestFormat else {
            print("Error: No 240 FPS format found.")
            return
        }
        
        // --- Lock the Device and Apply the 240 FPS Format ---
        do {
            try device.lockForConfiguration()
            device.activeFormat = finalFormat
            let frameDuration = CMTimeMake(value: 1, timescale: Int32(targetFrameRate))
            device.activeVideoMinFrameDuration = frameDuration
            device.activeVideoMaxFrameDuration = frameDuration
            device.unlockForConfiguration()
            print("INFO: Successfully set 240 FPS.")
        } catch {
            print("Error locking device for configuration: \(error.localizedDescription)")
            session.commitConfiguration()
            return
        }
        
        // --- Add All Inputs and Outputs ---
        do {
            // Add video input
            self.videoInput = try AVCaptureDeviceInput(device: device)
            if session.canAddInput(self.videoInput) {
                session.addInput(self.videoInput)
            }
            
            // Add microphone input
            guard let audioDevice = AVCaptureDevice.default(for: .audio) else {
                print("Error: Could not find microphone.")
                session.commitConfiguration()
                return
            }
            let audioInput = try AVCaptureDeviceInput(device: audioDevice)
            if session.canAddInput(audioInput) {
                print("Microphone successfully found.")
                session.addInput(audioInput)
            }

            // Add movie file output (for saving the final video)
            if session.canAddOutput(self.movieOutput) {
                session.addOutput(self.movieOutput)
            }
            
            // Add the Video Data Output (for the live preview)
            let videoDataOutput = AVCaptureVideoDataOutput()
            videoDataOutput.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
            videoDataOutput.setSampleBufferDelegate(self, queue: videoOutputQueue)
            
            if session.canAddOutput(videoDataOutput) {
                session.addOutput(videoDataOutput)
            }
            // ---------------------
            
            // Finalize the configuration
            session.commitConfiguration()
            
            DispatchQueue.main.async {
                self.isConfigured = true
            }
            
            // Start the session (on a background thread)
            DispatchQueue.global(qos: .userInitiated).async {
                self.session.startRunning()
            }
            
        } catch {
            print("Error setting up session: \(error.localizedDescription)")
        }
    }
    
    // --- 5. Recording Controls ---
    func startRecording() {
        guard !isRecording, isConfigured, session.isRunning else { return }
        
        // We set the orientation for the *saved file* just before we record
        if let connection = self.movieOutput.connection(with: .video), connection.isVideoRotationAngleSupported(0) {
            connection.videoRotationAngle = 0 
        }
        
        // 1. Get the path to the app's "Documents" folder
        guard let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { return }

        // 2. Create a unique file name
        let fileURL = documentsURL.appendingPathComponent(UUID().uuidString).appendingPathExtension("mp4")

        // 3. Set this as our output and start recording
        self.videoURLReady = nil
        movieOutput.startRecording(to: fileURL, recordingDelegate: self)
        
        DispatchQueue.main.async {
            self.isRecording = true
        }
    }
    
    func stopRecording() {
        guard isRecording else { return }
        movieOutput.stopRecording()
        DispatchQueue.main.async {
            self.isRecording = false
        }
    }
    
    // --- 6. Delegate Callbacks ---
    
    // This is called when the saved file is finished
    func fileOutput(_ output: AVCaptureFileOutput, didFinishRecordingTo outputFileURL: URL, from connections: [AVCaptureConnection], error: Error?) {
        if let error = error {
            print("Error saving video: \(error.localizedDescription)")
            return
        }

        print("Video saved successfully to: \(outputFileURL.path)")

        DispatchQueue.main.async {
            self.videoURLReady = outputFileURL // Publish the URL to ContentView
        }
    }
    
    // This is required
    func fileOutput(_ output: AVCaptureFileOutput, didStartRecordingTo fileURL: URL, from connections: [AVCaptureConnection]) {
        // Required, but we don't need to do anything
    }
    
    // --- 7. THIS IS THE NEW FUNCTION ---
    // This is called 240 times per second
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        
        // Convert the video frame (CMSampleBuffer) to a displayable image (CGImage)
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        
        guard let cgImage = self.ciContext.createCGImage(ciImage, from: ciImage.extent) else { return }
        
        // Send the new image to the UI
        DispatchQueue.main.async {
            self.currentFrame = cgImage
        }
    }
}
