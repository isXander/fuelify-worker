//
//  FuelGagueView.swift
//  Fuelify
//
//  Created by Xander Smith on 06/03/2026.
//

import SwiftUI

struct FuelGagueView: View {
    let segments: Int
    let fullSegments: Int
    let flashingSegments: Int
    
    @State private var isBlinking = false
    
    init(segments: Int, full: Int, flashing: Int = 0) {
        self.segments = segments
        self.fullSegments = full
        self.flashingSegments = flashing
    }
    
    var body: some View {
        HStack(spacing: 10) {
            ForEach(1...segments, id: \.self) { x in
                let isSolid = x <= fullSegments
                let isFlashing = x > fullSegments && x <= (fullSegments + flashingSegments)
                let isIlluminated = isSolid || (isFlashing && isBlinking)
                // TODO: implement, animated, flashing segments
                RoundedRectangle(cornerRadius: 2)
                    .fill(isIlluminated ? .orange : Color(red: 0.2, green: 0.05, blue: 0.0))
                    .shadow(
                        color: isIlluminated ? .orange.opacity(0.9) : .clear,
                        radius: 9,
                        x: 0, y: 0,
                    )
            }
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 20)
        .frame(height: 80)
        .background {
            RoundedRectangle(cornerRadius: 8)
                .fill(.black)
        }
        .onAppear {
            Task {
                // The loop will run as long as the view is on screen
                while !Task.isCancelled {
                    
                    // 1. Turn ON: Instant or very fast ease-in
                    withAnimation(.easeIn(duration: 0.05)) {
                        isBlinking = true
                    }
                    
                    // Wait briefly while the light is fully illuminated
                    try? await Task.sleep(for: .seconds(0.5))
                    
                    // 2. Turn OFF: Slow ease-out to simulate phosphor decay/capacitance
                    withAnimation(.easeOut(duration: 0.7)) {
                        isBlinking = false
                    }
                    
                    // Wait for the fade out to finish before striking again
                    try? await Task.sleep(for: .seconds(0.8))
                }
            }
        }
    }
}

#Preview {
    FuelGagueView(segments: 6, full: 3, flashing: 2)
}
