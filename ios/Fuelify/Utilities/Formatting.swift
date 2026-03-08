//
//  Formatting.swift
//  Fuelify
//
//  Created by Xander Smith on 08/03/2026.
//

import Foundation

func formatStationName(_ name: String) -> String {
    var name = name.localizedCapitalized
    name = name.replacingOccurrences(of: "Service Station", with: "")
    name = name.replacingOccurrences(of: "Filling Station", with: "")
    name = name.replacingOccurrences(of: "Petrol Station", with: "")
    name = name.trimmingCharacters(in: [" "])
    
    return name
}
