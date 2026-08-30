import Foundation

// This file defines the "structs" that match our ProModel.json
// This allows Swift to read and understand our "brain"

struct ProModel: Codable {
    let Driver: ClubCategory
    let Woods_Hybrids: ClubCategory
    let Long_Irons: ClubCategory
    let Mid_Short_Irons: ClubCategory
    let Wedges: ClubCategory
}

struct ClubCategory: Codable {
    let head_on_view: [String: Metric]
    let dtl_view: [String: Metric]
}

struct Metric: Codable, Identifiable {
    // We can use an enum for a cleaner 'id'
    enum CodingKeys: String, CodingKey {
        case metric_name, pro_target, pro_range, units, priority_beginner, priority_advanced, root_cause_for, symptom_of, human_explanation, why_it_matters, drills
    }
    
    // This makes it easy to use in SwiftUI lists
    var id: String { metric_name }
    
    let metric_name: String
    let pro_target: Double
    let pro_range: Double
    enum UnitType: String, Codable {
        case degrees // "Target-centric" (e.g., hip sway)
        case degrees_positive // "One-sided" (more is better, like AOA)
        case degrees_negative // "One-sided" (less is better, like steepness)
        case inches_normalized
        case degrees_change
        case head_widths
        case ratio
        
        // This helps us handle "unknown" types from the JSON
        init(from decoder: Decoder) throws {
            let label = try decoder.singleValueContainer().decode(String.self)
            self = UnitType(rawValue: label) ?? .degrees // Default to .degrees
        }
    }
        
    let units: UnitType
    let priority_beginner: Int
    let priority_advanced: Int
    
    // These are optional, as not all metrics have them
    let root_cause_for: [String]?
    let symptom_of: [String]?
    
    let human_explanation: String
    let why_it_matters: String
    let drills: [Drill]
}

struct Drill: Codable, Identifiable {
    var id: String { name }
    let name: String
    let instructions: String
    let difficulty: String
    let flaw_type: String? 
}

struct SwingScore {
    let metricID: String
    let metricName: String
    let score: Int
    let priority: Int
    
    let symptomOf: [String]?
}
