//
//  AppModel.swift
//  bilibili-viewer
//
//  Created by chen on 2025/5/11.
//

import Combine  // Ensure Combine is imported for ObservableObject
import SwiftUI

/// Maintains app-wide state
@MainActor
@Observable  // This macro should provide ObservableObject conformance automatically
class AppModel: ObservableObject {  // Explicitly conform to ObservableObject
  let immersiveSpaceID = "ImmersiveSpace"
  enum ImmersiveSpaceState {
    case closed
    case inTransition
    case open
  }
  var immersiveSpaceState = ImmersiveSpaceState.closed

  // Constants for Bilibili URLs
  let bilibiliSearchURLBase = "https://search.bilibili.com/all?keyword="
  let bilibiliVideoHost = "www.bilibili.com"  // Keep for checking if it's a video page
  let bilibiliVideoPathPrefix = "/video/BV"  // Keep for checking if it's a video page
  let bilibiliBangumiPathPrefix = "/bangumi/play/"

  // 独立"推荐/浏览"窗口的场景 ID，主视频窗口与该窗口都会用到这个常量
  static let browsePanelWindowID = "BrowsePanel"

  // 主视频窗口当前播放/浏览的地址，供独立浏览窗口读取（例如"接下来播放"需要基于它请求）
  var browsingURL: URL = URL(string: "https://www.bilibili.com")!

  // 独立浏览窗口中用户点选的视频地址；主窗口观察到变化后据此切换播放地址
  var pendingBrowseSelectionURL: URL?

  // 独立浏览窗口当前是否已打开，供主窗口切换按钮显示状态
  var isBrowsePanelWindowOpen = false

  // 主视频窗口与浏览窗口共享同一个 API 客户端，这样浏览窗口发起的 WebView 内请求
  // 依然复用主窗口 WKWebView 已登录的 Cookie 上下文
  let browseClient = BilibiliAPIClient()

  // 窗口宽高比状态
  var windowAspectRatio: CGFloat = 16.0 / 9.0

  // 调整窗口比例
  func adjustWindowAspectRatio(_ ratio: CGFloat) {
    windowAspectRatio = ratio
  }

  // 根据视频尺寸调整窗口
  func adjustWindowToVideoSize(videoWidth: CGFloat, videoHeight: CGFloat) {
    let ratio = videoWidth / videoHeight
    // 竖屏视频最小保证 8:5，避免工具栏被压缩
    let clampedRatio = max(ratio, 8.0 / 5.0)
    adjustWindowAspectRatio(clampedRatio)
  }
}
