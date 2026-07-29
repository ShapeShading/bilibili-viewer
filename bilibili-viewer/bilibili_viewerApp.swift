//
//  bilibili_viewerApp.swift
//  bilibili-viewer
//
//  Created by chen on 2025/5/11.
//

import SwiftUI

@main
struct bilibili_viewerApp: App {
  @StateObject private var appModel = AppModel()

  var body: some Scene {
    WindowGroup {  // Default window
      ContentView()
        .environment(appModel)
        .persistentSystemOverlays(.hidden)  // 隐藏系统 UI（关闭按钮等），用户直视时才显示
    }
    .windowStyle(.plain)
    .windowResizability(.contentSize)  // 允许窗口根据内容调整大小
    .defaultSize(width: 1800, height: 1000)

    // 独立的推荐/搜索窗口：与视频窗口并列摆放，不遮挡视频，选中视频后仍在原视频窗口播放
    WindowGroup(id: AppModel.browsePanelWindowID) {
      BrowsePanelWindowView()
        .environment(appModel)
    }
    .windowStyle(.plain)
    .windowResizability(.contentSize)
    .defaultSize(width: 1400, height: 620)
  }
}
