import Foundation
import SwiftUI

struct HistoryCardView: View {
    let record: SwingRecord
    
    // Helper to calculate the color based on score (0=Red, 100=Green)
    private func scoreColor(for score: Int) -> Color {
        let hue = (Double(score) / 100.0) * 0.33
        return Color(hue: hue, saturation: 0.8, brightness: 0.9)
    }
    
    var body: some View {
        let card = HStack(spacing: 15) {

            // --- 1. Mini Skeleton Preview ---
            ZStack {
                Color.white.opacity(0.1) // Background box
                // Try to get Impact data, otherwise Address
                if let impactPose = record.analysis.impact?.bodyPose {
                    MiniSkeletonView(poseData: impactPose)
                        .padding(10) // Give it some breathing room
                } else if let addressPose = record.analysis.address?.bodyPose {
                    MiniSkeletonView(poseData: addressPose)
                        .padding(10)
                } else {
                    // Fallback icon if no data exists
                    Image(systemName: "figure.golf")
                        .font(.largeTitle)
                        .foregroundColor(.gray)
                }
            }
            .frame(width: 80, height: 80)
            .cornerRadius(8)

            // --- 2. Main Info ---
            VStack(alignment: .leading, spacing: 4) {
                Text(record.mainFlawName)
                    .font(.headline)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                
                Text("Taken: \(record.date, style: .date) at \(record.date, style: .time)")
                    .font(.caption)
                    .foregroundColor(.gray)
            }
            .padding(.vertical, 5)

            Spacer()

            // --- 3. Score Badge ---
            VStack {
                Text("\(record.score)")
                    .font(.title2)
                    .fontWeight(.heavy)
                    .foregroundColor(.black)
            }
            .frame(width: 50, height: 50)
            .background(scoreColor(for: record.score))
            .cornerRadius(10)
        }
        .padding(10)
        .background(record.isPermanent ? Color.teal.opacity(0.15) : Color.white.opacity(0.1))
        .cornerRadius(15)
        
        if record.isPermanent { card } else {
            card.modifier(DiagonalLinesModifier())
            .clipShape(RoundedRectangle(cornerRadius: 15))
        }
    }
}

struct DiagonalLine: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        // Draw a line from the top-left corner to the bottom-right corner
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        return path
    }
}

struct DiagonalLinesModifier: ViewModifier {
    let color: Color = .gray.opacity(0.05)
    let spacing: CGFloat = 20
    
    func body(content: Content) -> some View {
        // Use a ZStack to place the lines underneath the card content
        content
            .overlay(
                ZStack {
                    // We iterate through an arbitrary range (e.g., -20 to 20)
                    // and offset each line to cover the entire diagonal area.
                    ForEach(-20..<20) { i in
                        DiagonalLine()
                            .stroke(color, style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
                            // Shift each line diagonally using a calculated offset
                            .offset(x: CGFloat(i) * spacing, y: CGFloat(i) * spacing)
                    }
                }
                // Clip the lines so they don't extend beyond the card's boundary
                .clipped()
            )
    }
}
