//
//  OpenInMaps.swift
//  Fuelify
//
//  Created by Xander Smith on 06/03/2026.
//

import MapKit

func openInMaps(station: StationResponse) {
    let location = CLLocation(
        latitude: station.latitude,
        longitude: station.longitude
    )
    let mapItem = MKMapItem(location: location, address: nil)
    mapItem.name = station.tradingName
    openInMaps(mapItem: mapItem)
}

func openInMaps(mapItem: MKMapItem) {
    mapItem.openInMaps(launchOptions: [
        MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeDriving
    ])
}

func findMapItem(station: StationResponse) async -> MKMapItem? {
    let poiItems = await proximityPOISearch(station: station)
    
    if poiItems.count == 1, let match = poiItems.first {
        return match
    }
    
    // Disambiguate multiple matching POIs
    if poiItems.count > 1 {
        let apiBrand = station.brandName.lowercased()
        
        // Tiebreaker A: Try to match the brand name (e.g., "tesco" inside "Tesco Extra")
        if let nameMatch = poiItems.first(where: { poi in
            let appleName = poi.name?.lowercased() ?? ""
            return appleName.contains(apiBrand) || apiBrand.contains(appleName)
        }) {
            return nameMatch
        }
        
        // Tiebreaker B: If names don't align, pick the one physically closest to the API coordinate
        let centreLocation = station.clLocation
        if let closestPOI = poiItems.min(by: { a, b in
            let distA = a.location.distance(from: centreLocation)
            let distB = b.location.distance(from: centreLocation)
            return distA < distB
        }) {
            return closestPOI
        }
    }
    
    // If no POIs, use reverse geocoding
    if let item = await reverseGeocode(station: station) {
        if item.name == nil {
            item.name = station.tradingName
        }
        
        return item
    }
    
    // If no results from reverse geocode
    return nil
}

func stationToMapItem(station: StationResponse) -> MKMapItem {
    let fullAddress = [
        station.addressLine1,
        station.addressLine2,
        station.city,
        station.postcode,
    ]
        .filter { !$0.isEmpty }
        .joined(separator: ", ")
    let mapItem = MKMapItem(location: station.clLocation, address: MKAddress(fullAddress: fullAddress, shortAddress: nil))
    mapItem.name = station.tradingName
    return mapItem
}

private func proximityPOISearch(station: StationResponse) async -> [MKMapItem] {
    let request = MKLocalPointsOfInterestRequest(center: station.clLocation.coordinate, radius: 100)
    request.pointOfInterestFilter = MKPointOfInterestFilter(including: [.gasStation])
    
    let search = MKLocalSearch(request: request)
    
    let response = try? await search.start()
    
    return response?.mapItems ?? []
}

private func reverseGeocode(station: StationResponse) async -> MKMapItem? {
    let query = [
        station.tradingName,
        station.addressLine1,
        station.addressLine2,
        station.city,
        station.county,
        station.postcode
    ]
        .filter { !$0.isEmpty }
        .joined(separator: ", ")

    let request = MKLocalSearch.Request()
    request.naturalLanguageQuery = query
    request.region = MKCoordinateRegion(
        center: CLLocationCoordinate2D(
            latitude: station.latitude,
            longitude: station.longitude
        ),
        latitudinalMeters: 500,
        longitudinalMeters: 500
    )
    request.resultTypes = [.pointOfInterest, .address]

    let search = MKLocalSearch(request: request)
    let response = try? await search.start()
    return response?.mapItems.first
}

private extension StationResponse {
    var clLocation: CLLocation {
        CLLocation(latitude: latitude, longitude: longitude)
    }
}
