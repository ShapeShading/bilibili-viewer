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

}
