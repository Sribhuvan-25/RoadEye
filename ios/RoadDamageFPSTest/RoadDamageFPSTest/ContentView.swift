//
//  ContentView.swift
//  RoadDamageFPSTest
//
//  Created by Sribhuvan Reddy on 7/9/26.
//

import SwiftUI

struct ContentView: View {
    @StateObject private var controller = CameraFPSController()

    var body: some View {
        ZStack(alignment: .top) {
            CameraPreviewView(session: controller.session)
                .ignoresSafeArea()

            VStack(spacing: 8) {
                Text(controller.statusText)
                    .font(.subheadline)
                    .foregroundStyle(.white)

                Text("Current: \(controller.currentFPS, specifier: "%.1f") FPS")
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .foregroundStyle(.green)

                Text("Session avg: \(controller.averageFPS, specifier: "%.1f") FPS")
                    .font(.headline)
                    .foregroundStyle(.white)

                Text("Detections this frame: \(controller.detectionCount)")
                    .font(.subheadline)
                    .foregroundStyle(.yellow)
            }
            .padding()
            .frame(maxWidth: .infinity)
            .background(Color.black.opacity(0.6))
        }
        .onAppear { controller.start() }
        .onDisappear { controller.stop() }
    }
}

#Preview {
    ContentView()
}
