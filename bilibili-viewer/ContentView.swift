//
//  ContentView.swift
//  bilibili-viewer
//
//  Created by chen on 2025/5/11.
//

import RealityKit
import RealityKitContent
import SwiftUI
import WebKit

struct ContentView: View {
  @Environment(AppModel.self) var appModel
  @State private var currentURL: URL
  @State private var searchText: String = ""
  @State private var webView: WKWebView? = nil  // To control the WebView
  @State private var isPlaying: Bool = false  // 跟踪播放状态
  @State private var videoAspectRatio: CGFloat = 16.0 / 9.0  // 视频宽高比，默认 16:9
  @State private var detectedVideoSize: CGSize = .zero  // 检测到的视频尺寸

  // 窗口尺寸预设
  private let aspectRatioPresets: [(name: String, ratio: CGFloat)] = [
    ("16:9", 16.0 / 9.0),
    ("4:3", 4.0 / 3.0),
    ("21:9", 21.0 / 9.0),
    ("1:1", 1.0),
  ]

  init() {
    _currentURL = State(
      initialValue: URL(string: "https://www.bilibili.com")!)
  }

  private func performSearch() {
    if let encodedSearchText = searchText.addingPercentEncoding(
      withAllowedCharacters: .urlQueryAllowed),
      let searchURL = URL(
        string:
          "\(appModel.bilibiliSearchURLBase)\(encodedSearchText)&from_source=webtop_search&spm_id_from=333.788&search_source=3"
      )
    {
      currentURL = searchURL
    }
  }

  var body: some View {
    VStack(spacing: 0) {
      HStack {
        Spacer()  // Add spacer at the beginning to push content to center

        Button {
          webView?.goBack()
        } label: {
          Label("Back", systemImage: "arrow.backward")
        }
        .disabled(!(webView?.canGoBack ?? false))

        Button {
          currentURL = URL(string: "https://www.bilibili.com")!
        } label: {
          Label("Home", systemImage: "house")
        }

        TextField("Search on Bilibili", text: $searchText)
          .textFieldStyle(.roundedBorder)
          .frame(maxWidth: 300)
          .onSubmit {
            performSearch()
          }

        Button {
          performSearch()
        } label: {
          Label("Search", systemImage: "magnifyingglass")
        }
        .disabled(searchText.isEmpty)

        Button {
          currentURL = URL(string: "https://www.bilibili.com/history")!
        } label: {
          Label("", systemImage: "clock.arrow.circlepath")
        }

        Button {
          triggerRefresh()
        } label: {
          Label("Refresh", systemImage: "arrow.clockwise")
        }

        Spacer()  // Add spacer at the end to push content to center
      }
      .padding()
      .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
      .background(Color.black.opacity(0.3))

      WebView(url: $currentURL, currentWebViewInstance: $webView) {
        finishedURL in
        // Check if it's a video page and trigger fullscreen
        if isBilibiliVideoPage(url: finishedURL) {
          // Delay slightly to ensure the page elements are available
          DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {  // 1 second delay
            print("Attempting to trigger fullscreen for video page: \(finishedURL)")
            let ret = triggerBilibiliFullscreen()

            // 获取视频宽高比
            detectVideoAspectRatio()

            if !ret {
              // another 2 seconds delay
              DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                let ret = triggerBilibiliFullscreen()

                // 再次尝试获取视频宽高比
                detectVideoAspectRatio()

                if !ret {
                  print("Failed to trigger fullscreen again.")
                }
              }
            }
          }
        }
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      .onChange(of: webView?.canGoBack) { _, _ in
        print("WebView canGoBack changed: \\(webView?.canGoBack ?? false)")
      }
    }
    .aspectRatio(appModel.windowAspectRatio, contentMode: .fit)  // 保持宽高比，允许缩放
    .frame(minWidth: 800, minHeight: 450)  // 最小尺寸
    .onChange(of: currentURL) { _, newURL in
      // This ensures that if the user navigates within the WebView,
      // the 'Toggle Fullscreen' button's state is updated.
      print("Current URL changed to: \\(newURL)")
    }
    .clipShape(RoundedRectangle(cornerRadius: 10))  // Add this line to round the corners of the VStack
    .ornament(attachmentAnchor: .scene(.bottom), contentAlignment: .center) {
      HStack(spacing: 16) {
        Button {
          if isBilibiliPlayablePage(url: currentURL) {
            triggerSeekBackward()
          }
        } label: {
          Image(systemName: "gobackward.15")
            .font(.title2)
        }
        .disabled(isNotBilibiliPlayablePage(url: currentURL))

        Button {
          if isBilibiliPlayablePage(url: currentURL) {
            triggerPlayPause()
          }
        } label: {
          Image(systemName: isPlaying ? "pause.fill" : "play.fill")
            .font(.title)
        }
        .disabled(isNotBilibiliPlayablePage(url: currentURL))

        Button {
          if isBilibiliPlayablePage(url: currentURL) {
            triggerSeekForward()
          }
        } label: {
          Image(systemName: "goforward.15")
            .font(.title2)
        }
        .disabled(isNotBilibiliPlayablePage(url: currentURL))

        Divider()
          .frame(height: 24)

        Button {
          if isBilibiliPlayablePage(url: currentURL) {
            triggerDanmakuToggle()
          }
        } label: {
          Image(systemName: "bubble.left.and.bubble.right")
            .font(.title2)
        }
        .disabled(isNotBilibiliPlayablePage(url: currentURL))

        Button {
          if isBilibiliVideoPage(url: currentURL) {
            let _ = triggerBilibiliFullscreen()
          } else if isBilibiliBangumiPage(url: currentURL) {
            let _ = triggerBilibiliBangumiFullscreen()
          }
        } label: {
          Image(systemName: "arrow.up.left.and.arrow.down.right")
            .font(.title2)
        }
        .disabled(isNotBilibiliPlayablePage(url: currentURL))

        Divider()
          .frame(height: 24)

        // 视频宽高比信息和快捷调整
        Menu {
          Section("检测到的视频尺寸") {
            if detectedVideoSize != .zero {
              Text("\(Int(detectedVideoSize.width)) × \(Int(detectedVideoSize.height))")
            } else {
              Text("未检测到视频")
            }
          }

          Section("窗口比例预设") {
            ForEach(aspectRatioPresets, id: \.name) { preset in
              Button {
                // 调整窗口比例
                appModel.adjustWindowAspectRatio(preset.ratio)
                print(
                  "Selected aspect ratio: \(preset.name), ratio: \(appModel.windowAspectRatio)"
                )
              } label: {
                HStack {
                  Text(preset.name)
                  if abs(videoAspectRatio - preset.ratio) < 0.1 {
                    Image(systemName: "checkmark")
                  }
                }
              }
            }

            // 添加“匹配视频”选项
            if detectedVideoSize != .zero {
              Button {
                appModel.adjustWindowToVideoSize(
                  videoWidth: detectedVideoSize.width, videoHeight: detectedVideoSize.height)
                print("匹配视频比例: \(detectedVideoSize.width) x \(detectedVideoSize.height)")
              } label: {
                HStack {
                  Text("匹配视频 (\(getAspectRatioName()))")
                  Image(systemName: "wand.and.stars")
                }
              }
            }
          }

          Section {
            Button {
              detectVideoAspectRatio()
            } label: {
              Label("重新检测", systemImage: "arrow.clockwise")
            }
          }
        } label: {
          HStack(spacing: 4) {
            Image(systemName: "rectangle.ratio.16.to.9")
              .font(.title2)
            if detectedVideoSize != .zero {
              Text(getAspectRatioName())
                .font(.caption)
            }
          }
        }
        .disabled(isNotBilibiliPlayablePage(url: currentURL))
      }
      .padding(.horizontal, 20)
      .padding(.vertical, 12)
      .glassBackgroundEffect()
      .padding(.top, 60)  // 与视频内容保持距离，避免遮挡
    }
  }

  // 获取最接近的宽高比名称
  private func getAspectRatioName() -> String {
    for preset in aspectRatioPresets {
      if abs(videoAspectRatio - preset.ratio) < 0.1 {
        return preset.name
      }
    }
    // 如果没有匹配的预设，显示实际比例
    let gcd = gcdFunc(Int(detectedVideoSize.width), Int(detectedVideoSize.height))
    if gcd > 0 {
      return "\(Int(detectedVideoSize.width) / gcd):\(Int(detectedVideoSize.height) / gcd)"
    }
    return String(format: "%.2f", videoAspectRatio)
  }

  // 计算最大公约数
  private func gcdFunc(_ a: Int, _ b: Int) -> Int {
    if b == 0 { return a }
    return gcdFunc(b, a % b)
  }

  // 检测视频宽高比
  private func detectVideoAspectRatio() {
    let script = """
        (function() {
          var video = document.querySelector('video');
          if (video) {
            return {
              videoWidth: video.videoWidth,
              videoHeight: video.videoHeight,
              displayWidth: video.clientWidth,
              displayHeight: video.clientHeight
            };
          }
          return null;
        })();
      """

    webView?.evaluateJavaScript(script) { result, error in
      if let error = error {
        print("获取视频尺寸失败: \(error)")
        return
      }

      if let dict = result as? [String: Any],
        let videoWidth = dict["videoWidth"] as? CGFloat,
        let videoHeight = dict["videoHeight"] as? CGFloat,
        videoWidth > 0 && videoHeight > 0
      {
        DispatchQueue.main.async {
          self.detectedVideoSize = CGSize(width: videoWidth, height: videoHeight)
          self.videoAspectRatio = videoWidth / videoHeight
          print("检测到视频尺寸: \(Int(videoWidth)) × \(Int(videoHeight)), 宽高比: \(self.videoAspectRatio)")

          // 自动调整窗口大小以匹配视频宽高比
          self.appModel.adjustWindowToVideoSize(videoWidth: videoWidth, videoHeight: videoHeight)
        }
      } else {
        print("未找到视频元素或视频尺寸无效")
      }
    }
  }

  // Helper function to check if the current URL is a Bilibili video page
  private func isBilibiliVideoPage(url: URL) -> Bool {
    guard let host = url.host else { return false }
    if host.contains(appModel.bilibiliVideoHost) {
      if url.path.starts(with: appModel.bilibiliVideoPathPrefix) {
        return true
      }
    }
    return false
  }
  // Helper function to check if the current URL is a Bilibili Bangumi page
  private func isBilibiliBangumiPage(url: URL) -> Bool {
    guard let host = url.host else { return false }
    if host.contains(appModel.bilibiliVideoHost) {
      if url.path.starts(with: appModel.bilibiliBangumiPathPrefix) {
        return true
      }
    }
    return false
  }

  // Helper function to check if the current URL is a Bilibili video or bangumi page
  private func isBilibiliPlayablePage(url: URL) -> Bool {
    return isBilibiliVideoPage(url: url) || isBilibiliBangumiPage(url: url)
  }

  // Helper function to check if the current URL is NOT a Bilibili video or bangumi page
  private func isNotBilibiliPlayablePage(url: URL) -> Bool {
    return !isBilibiliPlayablePage(url: url)
  }

  // Function to execute JavaScript for fullscreen
  private func triggerBilibiliFullscreen() -> Bool {

    print("Attempting to trigger fullscreen for video page.")
    // Create a completion group to wait for the JS evaluation
    var success = false
    let group = DispatchGroup()
    group.enter()

    let script = "el = document.querySelector('.bpx-player-ctrl-web'); el.click()"
    webView?.evaluateJavaScript(script) { result, error in
      if let error = error {
        print("JavaScript execution failed: \(error)")
        success = false
      } else {
        success = true
      }
      group.leave()
    }

    // Wait for JavaScript to complete with timeout
    let _ = group.wait(timeout: .now() + 0.2)
    return success
  }

  private func triggerPlayPause() {
    print("Attempting to trigger play/pause.")
    let script = """
        (function() {
          var video = document.querySelector('video');
          if (video) {
            if (video.paused) {
              video.play();
              console.log('视频播放成功');
              return 'played';
            } else {
              video.pause();
              console.log('视频暂停成功');
              return 'paused';
            }
          }
          return false;
        })();
      """

    webView?.evaluateJavaScript(script) { result, error in
      if let error = error {
        print("JavaScript execution for play/pause failed: \(error)")
      } else {
        print("Play/pause executed. Result: \(String(describing: result))")
        // 更新播放状态
        if let resultString = result as? String {
          DispatchQueue.main.async {
            self.isPlaying = (resultString == "played")
          }
        }
      }
    }
  }

  /// with class `bpx-player-ctrl-web-enter`
  private func triggerBilibiliBangumiFullscreen() -> Bool {
    print("Attempting to trigger fullscreen for Bangumi page.")
    // Create a completion group to wait for the JS evaluation
    var success = false
    let group = DispatchGroup()
    group.enter()

    // TODO for some reasons, the element is unreachable, although DOM exists
    let script = "el = document.querySelector('.bpx-player-ctrl-web-enter'); el.click()"
    // let script = "Array.from(document.getElementsByClassName('bpx-player-ctrl-btn')).map(function(el) { return el.className; }).join(',')"
    // let script = "document.getElementsByClassName('bpx-player-control-bottom-left').outterHTML"
    webView?.evaluateJavaScript(script) { result, error in
      if let error = error {
        print("JavaScript execution failed: \(error)")
        success = false
      } else {
        print("JavaScript execution result: \(String(describing: result))")
        success = true
      }
      group.leave()
    }

    // Wait for JavaScript to complete with timeout
    let _ = group.wait(timeout: .now() + 0.2)
    return success
  }

  private func triggerRefresh() {
    print("Attempting to trigger refresh.")

    // First try to find and click the "换一换" (refresh) button
    let refreshButtonScript = """
        var refreshBtn = document.querySelector('.feed-roll-btn .roll-btn');
        if (refreshBtn) {
          refreshBtn.click();
          'refresh_button_clicked';
        } else {
          'refresh_button_not_found';
        }
      """

    webView?.evaluateJavaScript(refreshButtonScript) { result, error in
      if let error = error {
        print("JavaScript execution for refresh button failed: \(error)")
        // Fallback to page reload
        DispatchQueue.main.async {
          self.webView?.reload()
        }
      } else if let resultString = result as? String {
        print("Refresh button script result: \(resultString)")
        if resultString == "refresh_button_not_found" {
          // Fallback to page reload
          DispatchQueue.main.async {
            self.webView?.reload()
          }
        }
      }
    }
  }

  private func triggerSeekBackward() {
    print("Attempting to seek backward 15 seconds.")
    let script = """
        (function() {
          var video = document.querySelector('video');
          if (video) {
            video.currentTime = video.currentTime - 15;
            console.log('后退 15 秒成功');
            return true;
          }
          return false;
        })();
      """

    webView?.evaluateJavaScript(script) { result, error in
      if let error = error {
        print("JavaScript execution for seek backward failed: \(error)")
      } else {
        print("Seek backward executed. Result: \(String(describing: result))")
      }
    }
  }

  private func triggerSeekForward() {
    print("Attempting to seek forward 15 seconds.")
    let script = """
        (function() {
          var video = document.querySelector('video');
          if (video) {
            video.currentTime = video.currentTime + 15;
            console.log('前进 15 秒成功');
            return true;
          }
          return false;
        })();
      """

    webView?.evaluateJavaScript(script) { result, error in
      if let error = error {
        print("JavaScript execution for seek forward failed: \(error)")
      } else {
        print("Seek forward executed. Result: \(String(describing: result))")
      }
    }
  }

  private func triggerDanmakuToggle() {
    print("Attempting to toggle danmaku display.")
    let script = """
        (function() {
          // 尝试找到弹幕开关元素
          var danmakuSwitch = document.querySelector('.bpx-player-dm-switch input[type="checkbox"]');
          if (danmakuSwitch) {
            danmakuSwitch.click();
            console.log('弹幕切换成功');
            return true;
          }

          // 备用方案：尝试点击整个弹幕开关区域
          var danmakuArea = document.querySelector('.bpx-player-dm-switch');
          if (danmakuArea) {
            danmakuArea.click();
            console.log('弹幕切换成功（备用方案）');
            return true;
          }

          console.log('未找到弹幕开关元素');
          return false;
        })();
      """

    webView?.evaluateJavaScript(script) { result, error in
      if let error = error {
        print("JavaScript execution for danmaku toggle failed: \(error)")
      } else {
        print("Danmaku toggle executed. Result: \(String(describing: result))")
      }
    }
  }
}

#Preview(windowStyle: .automatic) {
  ContentView()
    .environment(AppModel())
}
