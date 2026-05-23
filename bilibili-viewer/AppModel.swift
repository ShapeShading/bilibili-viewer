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
