import SwiftUI

// MARK: - Glass Card View Modifier
// This creates our reusable "tinted glass" effect
struct GlassMorphismCard: ViewModifier {
    func body(content: Content) -> some View {
        content
            // Add padding *inside* the card
            .padding(16)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            // 1. The "Glass" layer (Apple's "liquid glass" feel)
            .background(.ultraThinMaterial)
            // 2. The "Tint" layer
            .background(Color.white.opacity(0.05)) // More "glassy"
            .cornerRadius(20)
            // 3. A subtle border to catch the light
            .overlay(
                RoundedRectangle(cornerRadius: 20)
                    .stroke(Color.white.opacity(0.2), lineWidth: 1)
            )
    }
}

// MARK: - Analysis Results View
struct AnalysisResultsView: View {
    
    @ObservedObject var viewModel: SwingGradeViewModel
    var dismissRecord: (() -> Void)? // This will reset selectedRecord to nil
    
    // Add the property to the initializer (or create one):
    init(viewModel: SwingGradeViewModel, dismissRecord: (() -> Void)? = nil) {
        self.viewModel = viewModel
        self.dismissRecord = dismissRecord
    }

    // Add a unified dismissal handler:
    func handleDismissal() {
        if let dismissRecord = dismissRecord {
            // If we came from the History Page, use the custom dismisser
            dismissRecord()
        } else {
            // Otherwise, use the ViewModel's standard dismisser (for new analysis)
            viewModel.dismissResults()
        }
    }
    
    // This helper function creates dynamic red-to-green color
    private func scoreColor(for score: Int) -> Color {
        // 0 = Red (0.0), 100 = Green (0.33)
        let hue = (Double(score) / 100.0) * 0.33
        return Color(hue: hue, saturation: 0.8, brightness: 0.9)
    }
    
    var body: some View {
        ZStack {
            // --- 1. MODERN GRADIENT BACKGROUND ---
            LinearGradient(
                gradient: Gradient(colors: [Color(hue: 0.6, saturation: 0.5, brightness: 0.2), Color.black]),
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
            
            // --- 2. MAIN 50/50 LAYOUT ---
            HStack(spacing: 0) {
                
                // --- LEFT COLUMN: ANIMATED SKELETON + SCORE ---
                ZStack(alignment: .topLeading) {
                    
                    // --- ANIMATED SKELETON PLAYER ---
                    PoseAnimatorView(viewModel: viewModel)
                    
                    // --- Score Box (Top-Left) ---
                    VStack(spacing: 1) {
                        ZStack {
                            Text("\(viewModel.coachingScore)")
                                .font(.system(size: 23, weight: .bold))
                                .foregroundColor(.black)
                        }
                        .frame(width: 50, height: 50)
                        .background(scoreColor(for: viewModel.coachingScore))
                        .cornerRadius(9)
                    }
                    .padding(10)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(10)
                .modifier(GlassMorphismCard()) 
                
                
                // --- RIGHT COLUMN: COACHING & BUTTONS ---
                ZStack(alignment: .topTrailing) {
                    
                    // --- Layer 1: The Info Scroller ---
                    ScrollView(.vertical) {
                        VStack(alignment: .leading, spacing: 15) {
                            
                            // "Root Cause Flaw" Glass Card
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Root Cause Flaw:")
                                    .font(.subheadline)
                                    .foregroundColor(.gray)
                                    .fontWeight(.bold)
                                
                                // --- THIS IS THE FIX YOU REQUESTED ---
                                Text(viewModel.mainFlawName)
                                    .font(.title2)
                                    .fontWeight(.bold)
                                    .foregroundColor(.white)
                                
                                Text(viewModel.mainFlaw)
                                    .font(.body)
                                    .fontWeight(.medium)
                                    .foregroundColor(.white.opacity(0.9))
                            }
                            .modifier(GlassMorphismCard())
                            
                            // "Recommended Drill" Glass Card
                            if let drill = viewModel.coachingDrill {
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("Recommended Drill:")
                                        .font(.subheadline)
                                        .foregroundColor(.gray)
                                        .fontWeight(.bold)
                                    
                                    Text(drill.name)
                                        .font(.title3)
                                        .fontWeight(.medium)
                                        .foregroundColor(.yellow)
                                    
                                    Text(drill.instructions)
                                        .font(.body)
                                        .foregroundColor(.white.opacity(0.9))
                                }
                                .modifier(GlassMorphismCard())
                            }
                            
                            // This spacer adds 100px of empty space
                            // "behind" the floating record button
                            Spacer(minLength: 100)
                            
                        } // End of card VStack
                        .padding(.top, 90) // Make space for Save/Delete buttons
                        .padding(.horizontal, 20) // Padding from screen edges
                        
                    } // End of ScrollView
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    
                    
                    // --- Layer 2: Floating Buttons ---
                    
                    // Top-Right: Save/Delete
                    HStack(spacing: 20) {
                        Button(action: {
                            // Call the save function, passing the non-optional UIImage instance
                            viewModel.saveCurrentAnalysis(isPermanent: true)
                            
                            handleDismissal()
                        }) {
                            Image(systemName: "square.and.arrow.down")
                                .font(.title2)
                                .foregroundColor(.white.opacity(0.7))
                        }
                        
                        Button(action: {
                            // 1. Get the ID of the current analysis
                            let analysisID = viewModel.currentAnalysisID
                            
                            // 2. Perform the delete in the ViewModel
                            viewModel.deleteSwing(id: analysisID)
                            
                            // 3. Dismiss the results and return to History Page
                            handleDismissal() // Calls the dismissRecord callback
                        }) {
                            Image(systemName: "trash")
                                .font(.title2)
                                .foregroundColor(.white.opacity(0.7))
                        }
                    }
                    .padding(30)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                    
                    // Bottom-Right: Record
                    Button(action: {
                        // 1. Capture the image of the pose animator view
                        
                        // 2. Pass the image to the ViewModel for saving
                        viewModel.saveCurrentAnalysis(isPermanent: false)
                        
                        // 3. Dismiss the results view
                        handleDismissal()
                    }) {
                        Image(systemName: "camera.fill")
                            .font(.system(size: 24, weight: .bold))
                            .foregroundColor(.black)
                            .frame(width: 70, height: 70)
                            .background(Color.white)
                            .clipShape(Circle())
                            .shadow(radius: 10)
                    }
                    .padding(30) // Padding from bottom-right edge
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                    
                } // End of ZStack (Right Column)
                .frame(maxWidth: 420) // Give the right column a max width
                
            } // End of main HStack
            
        } // End of main ZStack
        .statusBarHidden(true) // Hide the status bar
    }
}
