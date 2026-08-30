import SwiftUI

struct SettingsPageView: View {
    @ObservedObject var viewModel: SwingGradeViewModel
    
    // State variables for temporary user input (matching the ViewModel)
    @State private var userName: String = ""
    @State private var userHandicap: Double = 20.0
    @State private var userHeight: Double = 68.0 // (Inches)

    var body: some View {
        ZStack {
            // Background Gradient (Same as History Page)
            LinearGradient(
                gradient: Gradient(colors: [Color.black, Color(hue: 0.6, saturation: 0.5, brightness: 0.2)]),
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
            
            VStack(alignment: .leading, spacing: 20) {
                
                // --- TOP BAR (Title + Dismiss Button) ---
                HStack {
                    Text("Settings")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                    
                    Spacer()
                    
                    // DISMISS BUTTON
                    Button(action: {
                        viewModel.showSettings = false // Trigger return to Camera Page
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title)
                            .foregroundColor(.white.opacity(0.8))
                    }
                }
                
                // --- USER PROFILE SETTINGS ---
                GroupBox(label: Text("User Profile").foregroundColor(.white)) {
                    VStack(spacing: 15) {
                        // 1. Name
                        HStack {
                            Text("Name:").foregroundColor(.gray)
                            Spacer()
                            TextField("Enter Name", text: $userName)
                                .foregroundColor(.white)
                                .textFieldStyle(.roundedBorder)
                                .background(.ultraThinMaterial)
                        }
                        
                        // 2. Handicap (Uses a Stepper)
                        HStack {
                            Text("Handicap:").foregroundColor(.gray)
                            Spacer()
                            Stepper(value: $userHandicap, in: 0...50, step: 1.0) {
                                Text(String(format: "%.1f", userHandicap))
                                    .foregroundColor(.white)
                            }
                        }
                        
                        // 3. Height (Uses a Slider)
                        VStack(alignment: .leading) {
                            Text("Height: \(String(format: "%.0f", userHeight)) inches")
                                .foregroundColor(.gray)
                            Slider(value: $userHeight, in: 55...80, step: 1.0)
                                .tint(.yellow)
                        }
                    }
                }
                .groupBoxStyle(DefaultGroupBoxStyle())
                
                // --- HISTORY ACTIONS ---
                GroupBox(label: Text("Data Management").foregroundColor(.white)) {
                    Button(action: {
                        // TODO: Implement Clear History Logic
                    }) {
                        Label("Clear Swing History", systemImage: "trash.fill")
                            .foregroundColor(.red)
                    }
                }
                .groupBoxStyle(DefaultGroupBoxStyle())
                
                Spacer()
                
                // Save Button (to persist changes)
                Button("Save Settings") {
                    // TODO: Implement saving userName, userHandicap, userHeight to Persistence
                    viewModel.userHeightInInches = userHeight // Update ViewModel directly for testing
                    viewModel.showSettings = false
                }
                .padding()
                .frame(maxWidth: .infinity)
                .background(Color.yellow)
                .foregroundColor(.black)
                .cornerRadius(10)
                
            }
            .padding(30)
        }
        // Load initial values from ViewModel when view appears
        .onAppear {
            self.userHeight = viewModel.userHeightInInches
            // This is where you would load the saved name and handicap from Persistence
        }
    }
}
