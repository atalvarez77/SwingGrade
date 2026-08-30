import Foundation

class PersistenceService {
    
    // The name of the file where we save our swing array
    private static let swingsFileName = "SwingGrade_History.json"
    
    // --- 1. Get the URL to the save file ---
    private static func getArchiveURL() -> URL {
        // We save to the App's document directory
        let documentDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        return documentDirectory.appendingPathComponent(swingsFileName)
    }

    // --- 2. Load All Saved Swings ---
    func loadSwings() -> [SwingRecord] {
        let archiveURL = PersistenceService.getArchiveURL()
        
        guard let data = try? Data(contentsOf: archiveURL) else {
            return [] // Return empty array if file doesn't exist
        }
        
        do {
            let decoder = JSONDecoder()
            // Decode the array of SwingRecord objects
            var savedSwings = try decoder.decode([SwingRecord].self, from: data)
            // Check 2: Filter out expired non-permanent swings
            performCleanup(swings: &savedSwings)
            
            // Check 3: If we deleted any, resave the cleaned list immediately.
            if savedSwings.count < (try decoder.decode([SwingRecord].self, from: data)).count {
                saveSwings(savedSwings) // Resave the array to disk
            }
            
            return savedSwings
        } catch {
            print("Persistence Error: Failed to decode saved swings: \(error)")
            return []
        }
        
    }

    // --- 3. Save the Current List of Swings ---
    public func saveSwings(_ swings: [SwingRecord]) {
        let archiveURL = PersistenceService.getArchiveURL()
        
        do {
            let encoder = JSONEncoder()
            // Encode the array of SwingRecord objects
            let data = try encoder.encode(swings)
            try data.write(to: archiveURL, options: .atomic)
        } catch {
            print("Persistence Error: Failed to encode or save swings: \(error)")
        }
    }
    
    // --- 4. The 24-Hour Cleanup Logic ---
    func performCleanup(swings: inout [SwingRecord]) {
        // 1. Calculate the cutoff time (24 hours ago)
        let twentyFourHoursAgo = Date().addingTimeInterval(-24 * 60 * 60)
        
        let initialCount = swings.count

        // 2. Filter the array: Keep records that meet EITHER condition:
        //    a) isPermanent is true
        //    b) date is more recent than twentyFourHoursAgo (orderedDescending)
        let swingsToKeep = swings.filter { record in
            return record.isPermanent || record.date.compare(twentyFourHoursAgo) == .orderedDescending
        }
        
        // 3. Replace the original array with the cleaned one
        swings = swingsToKeep
        
        if swings.count < initialCount {
            print("Persistence Cleanup: Deleted \(initialCount - swings.count) expired temporary swings.")
        }
    }
}
