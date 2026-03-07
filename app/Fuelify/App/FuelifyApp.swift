import SwiftUI
import SwiftData

@main
struct FuelifyApp: App {
    let modelContainer: ModelContainer
    @State private var preferences: UserPreferences?

    init() {
        do {
            let schema = Schema(versionedSchema: UserPreferencesSchemaV2.self)
            let config = ModelConfiguration(schema: schema)
            self.modelContainer = try ModelContainer(
                for: schema,
                migrationPlan: UserPreferencesMigrationPlan.self,
                configurations: [config]
            )
        } catch {
            fatalError("Failed to create ModelContainer: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if let preferences {
                    ContentView(preferences: preferences)
                } else {
                    ProgressView()
                }
            }
            .task {
                if preferences == nil {
                    preferences = UserPreferences.resolve(in: modelContainer.mainContext)
                }
            }
        }
        .modelContainer(modelContainer)
    }
}
