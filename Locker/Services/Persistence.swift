import Foundation
import SwiftData

enum Persistence {
    static let schema = Schema([
        SchoolClass.self,
        Assignment.self,
        GradeCategory.self,
        Deck.self,
        Card.self,
        ReviewLog.self,
        FocusSession.self,
        AppSettings.self,
    ])

    static func container(inMemory: Bool = false) -> ModelContainer {
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: inMemory)
        do {
            return try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            // A store that can't open would otherwise crash on every launch with no
            // way out, so fall back to memory and let the UI say what happened.
            let fallback = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
            return try! ModelContainer(for: schema, configurations: [fallback])
        }
    }
}
