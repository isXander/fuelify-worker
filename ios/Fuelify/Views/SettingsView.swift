import SwiftUI
import SwiftData

struct SettingsView: View {
    @Bindable var preferences: UserPreferences
    
    @State private var averagePencePerL: Double? = nil
    
    private var fullTankMileage: Double {
        let mpg = preferences.fuelEconomy
        let mpl = mpg / 4.546
        let l = preferences.tankCapacity
        return l * mpl
    }
    
    private var fullTankCost: Double? {
        if let ppl = averagePencePerL {
            return ppl * preferences.tankCapacity / 100.0
        }
        return nil
    }
    
    private var pencePerMile: Double? {
        if let fullTankCost = fullTankCost {
            return fullTankCost / fullTankMileage * 100.0
        }
        return nil
    }

    var body: some View {
        Form {
            Section(
                header: Text("Fuel Tank"),
                footer: Text("Fuelify uses this information to calculate how much it will cost to add your desired amount of fuel.")
            ) {
                HStack {
                    Picker("Fuel Type", selection: $preferences.selectedFuelTypeRaw) {
                        ForEach(FuelType.allCases) { fuelType in
                            Text(fuelType.displayName).tag(fuelType.rawValue)
                        }
                    }
                }
                
                HStack {
                    Text("Tank Capacity")
                    
                    Spacer()
                    
                    TextField("0.0", value: $preferences.tankCapacity, format: .number)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .frame(maxWidth: 80)
                    
                    Text("L")
                        .foregroundColor(.secondary)
                }
                
                HStack {
                    Text("Average Fuel Economy")
                    
                    Spacer()
                    
                    TextField("0.0", value: $preferences.fuelEconomy, format: .number)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .frame(maxWidth: 80)
                    
                    Text("mpg")
                        .foregroundColor(.secondary)
                }
                
                Link("Learn how to get this data", destination: URL(string: "https://google.com/")!)
            }
            
            Section(
                header: Text("Estimates"),
                footer: Text("These estimates are based off the average fuel price in the UK."),
            ) {
                LabeledContent("Range", value: "\(String(format: "%0.0f", fullTankMileage)) miles / tank")
                
                if let ftc = fullTankCost {
                    LabeledContent("Cost per tank", value: "£\(String(format: "%0.2f", ftc))")
                }
                
                if let ppm = pencePerMile {
                    LabeledContent("Cost per mile", value: "\(String(format: "%0.0f", ppm))p")
                }
            }
            
            Section(
                header: Text("Display"),
                footer: Text("You should match these settings with your car."),
            ) {
                VStack(alignment: .leading) {
                    HStack {
                        Text("Fuel Gague Segments")
                        
                        Spacer()
                        
                        Text("\(preferences.tankPrecision)")
                            .foregroundStyle(.secondary)
                    }
                    
                    Slider(
                        value: Binding(
                            get: { Double(preferences.tankPrecision) },
                            set: { preferences.tankPrecision = Int($0) },
                        ),
                        in: 4.0...10.0,
                        step: 1.0,
                    ) {
                        Text("Fuel Gague Segments Slider")
                    }
                    
                    FuelGagueView(
                        segments: preferences.tankPrecision,
                        full: Int((Double(preferences.tankPrecision) / 2.0).rounded(.up))
                    )
                }
            }
        }
        .navigationTitle("Settings")
        .task {
            await getAverageFuelCost()
        }
    }
    
    private func getAverageFuelCost() async {
        // TODO
        averagePencePerL = 132.3
    }
}

#Preview {
    NavigationStack {
        SettingsView(preferences: UserPreferences())
    }
    .modelContainer(for: UserPreferences.self, inMemory: true)
}
