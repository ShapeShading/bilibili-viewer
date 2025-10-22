//
//  bilibili_viewerApp.swift
//  bilibili-viewer
//
//  Created by chen on 2025/5/11.
//

import SwiftUI
import WebKit  // Add this import

@main
struct bilibili_viewerApp: App {
    @StateObject private var appModel = AppModel()
    @State private var mainWebView: WKWebView? = nil
    // Removed playerWebView as it's no longer needed
    // @State private var playerWebView: WKWebView? = nil

    var body: some Scene {
        WindowGroup {  // Default window
            ContentView()
                .environment(appModel)
        }
        .windowStyle(.plain)
        .defaultSize(width: 1600, height: 1000)

        // Removed the separate WindowGroup for videoPlayerWindow as it's no longer needed
        // WindowGroup(id: "videoPlayerWindow") { ... }

        ImmersiveSpace(id: "ImmersiveSpace") {
            ImmersiveView()
                .environment(appModel)
        }
    }
}
