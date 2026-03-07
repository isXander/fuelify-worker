import SwiftUI
import SwiftData

struct SettingsView: View {
    @Bindable var preferences: UserPreferences

    var body: some View {
        Form {
            Section {
                NavigationLink("Car Settings") {
                    CarSettingsView(preferences: preferences)
                }
            }
        }
        .navigationTitle("Settings")
    }
}

#Preview {
    NavigationStack {
        SettingsView(preferences: UserPreferences())
    }
    .modelContainer(for: UserPreferences.self, inMemory: true)
}
