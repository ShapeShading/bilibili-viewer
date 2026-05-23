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
        .persistentSystemOverlays(.hidden)  // 隐藏系统 UI（关闭按钮等），用户直视时才显示
    }
    .windowStyle(.plain)
    .windowResizability(.contentSize)  // 允许窗口根据内容调整大小
    .defaultSize(width: 1800, height: 1000)

    // Removed the separate WindowGroup for videoPlayerWindow as it's no longer needed
    // WindowGroup(id: "videoPlayerWindow") { ... }

    ImmersiveSpace(id: "ImmersiveSpace") {
      ImmersiveView()
        .environment(appModel)
    }
  }
}
