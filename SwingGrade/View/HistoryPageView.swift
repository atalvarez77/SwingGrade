import Foundation
import SwiftUI

struct HistoryPageView: View {
    @ObservedObject var viewModel: SwingGradeViewModel
    @State private var selectedRecord: SwingRecord? // Tracks the swing being viewed
    
    var body: some View {
        NavigationView {
            ZStack{
                // Background Gradient
                LinearGradient(
                    gradient: Gradient(colors: [Color.black, Color(hue: 0.6, saturation: 0.5, brightness: 0.2)]),
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()
                
                ScrollView(.vertical) {
                    VStack() {
                        
                        if viewModel.historySwings.isEmpty {
                            Text("Swing more to fill this up!")
                                .foregroundColor(.gray)
                                .padding(.top, 50)
                        } else {
                            // Display the list of saved cards
                            ForEach(viewModel.historySwings.reversed()) { record in
                                Button(action: {
                                    print("Swing Card Pressed -- History Page")
                                    // STEP 1: Load the record's data into the ViewModel's published properties.
                                    viewModel.loadHistoricalAnalysis(record: record)
                                    
                                    // STEP 2: Now that the ViewModel is ready, trigger the navigation.
                                    selectedRecord = record
                                }) {
                                    HistoryCardView(record: record)
                                        .foregroundColor(.white)
                                }
                            }
                        }
                    }
                    .padding(.top, 90)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                
                // --- TOP BAR WITH DISMISS BUTTON ---
                HStack {
                    Text("Swing History")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                    
                    Spacer()
                    
                    // DISMISS BUTTON (Using xmark.circle)
                    Button(action: {
                        viewModel.closeHistory()
                        print("Dismiss Button Pressed -- History Page")
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title)
                            .foregroundColor(.white.opacity(0.8))
                    }
                }
                .padding(30)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
            }
            .navigationBarHidden(true)
            .onAppear {
                viewModel.loadHistoryFromPersistence()
            }
            .fullScreenCover(item: $selectedRecord) { record in
                // We present the analysis LOCALLY from the History Page stack
                AnalysisResultsView(viewModel: viewModel, dismissRecord: {
                    selectedRecord = nil // Dismisses this specific cover
                })
                .id(UUID())
                .onAppear {
                    // Ensure the ViewModel is loaded with the data for this specific record
                    // (This runs if the button didn't catch it in time, or just as a safeguard)
                    if viewModel.currentAnalysis == nil {
                         viewModel.loadHistoricalAnalysis(record: record)
                    }
                }
            }
        }
    }
}

