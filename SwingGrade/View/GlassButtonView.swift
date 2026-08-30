import SwiftUI

struct GlassButtonView: View {
    let title: String
    let icon: String
    
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.body)
            Text(title)
                .font(.subheadline)
                .fontWeight(.medium)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial)
        .cornerRadius(10)
        .foregroundColor(.white)
        .shadow(color: .black.opacity(0.4), radius: 5, x: 0, y: 3)
    }
}
