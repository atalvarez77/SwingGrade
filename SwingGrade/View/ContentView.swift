import SwiftUI
import CoreImage.CIFilterBuiltins

struct ContentView: View {
    
    @StateObject private var cameraService = CameraService()
    
    // --- THIS IS THE NEW "BRAIN" ---
    @StateObject private var viewModel = SwingGradeViewModel()
    // -------------------------------
    
    let ciContext = CIContext()

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if let frame = cameraService.currentFrame {
                Image(decorative: frame, scale: 1.0, orientation: .up)
                    .resizable()
                    .scaledToFill()
                    .rotationEffect(.degrees(0)) 
                    .frame(width: UIScreen.main.bounds.width,
                           height: UIScreen.main.bounds.height)
                    .ignoresSafeArea()
            }
            
            VStack {
                HStack {
                    // --- 1. CLUB SELECTOR MENU ---
                    Menu {
                        Picker("Select Club", selection: $viewModel.selectedClub) {
                            ForEach(ClubType.allCases) { club in
                                Text(club.displayName).tag(club)
                            }
                        }
                    } label: {
                        GlassButtonView(
                            title: viewModel.selectedClub.displayName,
                            icon: "figure.golf"
                        )
                    }
                    
                    Spacer() // Pushes the next button to the right
                    
                    // --- 2. VIEW SELECTOR MENU (Toggle) ---
                    Menu {
                        Picker("Select View", selection: $viewModel.selectedView) {
                            ForEach(ViewType.allCases) { view in
                                Text(view.displayName).tag(view)
                            }
                        }
                    } label: {
                        GlassButtonView(
                            title: viewModel.selectedView.displayName,
                            icon: "eye.fill"
                        )
                    }
                }
                .padding(.top, 20)
                .padding(.horizontal, 30) // Horizontal spacing for landscape
                
                // --- NEW NAVIGATION BAR (Right Side) ---
                HStack {
                    Spacer() // Pushes the nav stack to the right edge
                    
                    VStack(spacing: 20) {
                        
                        // --- HISTORY BUTTON (Clock/List) ---
                        Button(action: {
                            viewModel.showHistory = true // Trigger History Page
                        }) {
                            Image(systemName: "clock.fill") // Using 'clock.fill' for History
                                .font(.title2)
                                .padding(12)
                                .background(.ultraThinMaterial)
                                .clipShape(Circle())
                                .foregroundColor(.white)
                        }
                        
                        // --- SETTINGS BUTTON (Cog) ---
                        Button(action: {
                            viewModel.showSettings = true // Trigger Settings Page
                        }) {
                            Image(systemName: "gearshape.fill") // Using 'gearshape.fill' for Settings
                                .font(.title2)
                                .padding(12)
                                .background(.ultraThinMaterial)
                                .clipShape(Circle())
                                .foregroundColor(.white)
                        }
                        
                    }
                    .padding(.trailing, 15) // Flush with the right edge
                    .padding(.top, 40) // Drop it down slightly from the top selectors
                }
                            
                
                Spacer()
                VStack {
                    // --- THIS IS THE UPDATED BUTTON ---
                    Button("Run Test Analysis") {
                        // This will run our *ViewModel's* test function
                        Task {
                            await runTestAnalysis()
                        }
                    }
                    .padding()
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(10)
                    // ----------------------------------
                    
                    Spacer() // Pushes the button to the bottom
                    
                    Button(action: {
                        if cameraService.isRecording {
                            cameraService.stopRecording() // This just triggers the save delegate
                        } else {
                            cameraService.startRecording()
                        }
                    }) {
                        ZStack {
                            Circle()
                                .fill(cameraService.isRecording ? .red : .white)
                                .frame(width: 70, height: 70)
                            
                            if cameraService.isRecording {
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(.white)
                                    .frame(width: 30, height: 30)
                            }
                        }
                        .padding()
                    }
                }
            }
            
            if viewModel.isLoading {
                Color.black.opacity(0.6).ignoresSafeArea()
                VStack {
                    ProgressView().tint(.white)
                    Text("Analyzing Swing...")
                        .foregroundColor(.white)
                        .padding(.top, 10)
                }
            }
        }
        .onChange(of: cameraService.videoURLReady) { oldValue, newURL in
            guard let url = newURL else { return }
            
            // The file is ready! Trigger the analysis with the current state.
            Task {
                await viewModel.runFullAnalysis(
                    on: url,
                    club: viewModel.selectedClub.jsonKey,
                    view: viewModel.selectedView.rawValue
                )
                // Clear the published URL property to listen for the next recording
                cameraService.videoURLReady = nil
            }
        }
        .onAppear {
            cameraService.configureSession()
        }
        .fullScreenCover(isPresented: $viewModel.showHistory) {
            // Implement the History Page UI you just built
            HistoryPageView(viewModel: viewModel)
        }
        .fullScreenCover(isPresented: $viewModel.showSettings) {
            // Implement the Settings Page UI next
            SettingsPageView(viewModel: viewModel)
        }
        .fullScreenCover(isPresented: Binding<Bool>(
            get: {
                // Only present from Root if we have analysis AND we aren't showing other pages
                viewModel.currentAnalysis != nil && !viewModel.showHistory && !viewModel.showSettings
            },
            set: { _ in } // We rely on the ViewModel to clear the data to dismiss
        )) {
            AnalysisResultsView(viewModel: viewModel)
        }
    }
    
    // --- THIS FUNCTION IS NOW UPDATED ---
    func runTestAnalysis() async {
        print("--- TEST: Starting test analysis... ---")
        
        guard let videoURL = Bundle.main.url(forResource: "HODriverTest", withExtension: "mp4") else {
            print("FATAL ERROR: Test video not found."); return
        }
        
        // 1. Copy the file to a temp location
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension("mp4")
        
        do {
            try FileManager.default.copyItem(at: videoURL, to: tempURL)
        } catch {
            print("FATAL ERROR: Could not copy test video: \(error.localizedDescription)")
            return
        }
        
        // 2. Tell the VIEWMODEL to run the analysis
        await viewModel.runFullAnalysis(
            on: tempURL,
            club: viewModel.selectedClub.jsonKey, // e.g., "Driver"
            view: viewModel.selectedView.rawValue // e.g., "dtl_view"
        )
    }
}

#Preview {
    ContentView()
}
