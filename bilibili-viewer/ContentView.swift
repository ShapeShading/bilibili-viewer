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
  @State private var showSearchPrompt = false
  @State private var webView: WKWebView? = nil  // To control the WebView
  @State private var isPlaying: Bool = false  // 跟踪播放状态
  @State private var isDanmakuEnabled: Bool = false
  @State private var isLiked: Bool = false
  @State private var isFullscreen: Bool = false
  @State private var videoAspectRatio: CGFloat = 16.0 / 9.0  // 视频宽高比，默认 16:9
  @State private var detectedVideoSize: CGSize = .zero  // 检测到的视频尺寸
  @State private var currentPlaybackRate: Double = 1.0  // 当前播放倍速
  @State private var showBrowsePanel = false  // 是否显示视频浏览浮层
  @State private var browseClient = BilibiliAPIClient()

  // 倍速预设
  private let playbackRates: [Double] = [1.0, 1.25, 1.5, 2.0]

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
    let trimmedSearchText = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmedSearchText.isEmpty else { return }

    if let encodedSearchText = trimmedSearchText.addingPercentEncoding(
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
      WebView(url: $currentURL, currentWebViewInstance: $webView) {
        finishedURL in
        // 进入视频页面时，使用 JS 轮询方式快速触发全屏，无需固定延迟
        if isBilibiliVideoPage(url: finishedURL) {
          print("Triggering smart fullscreen for: \(finishedURL)")
          triggerBilibiliFullscreenSmart()
        }
        scheduleVideoControlStateSync(after: 0.6)
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      .onChange(of: webView?.canGoBack) { _, _ in
        print("WebView canGoBack changed: \(webView?.canGoBack ?? false)")
      }
    }
    .onChange(of: webView) { _, newWebView in
      browseClient.attachWebView(newWebView)
      print("BilibiliAPIClient webView attached: \(newWebView != nil)")
    }
    .onAppear {
      browseClient.attachWebView(webView)
    }
    .overlay(alignment: .bottom) {
      if showBrowsePanel {
        BilibiliPanelView(
          currentURL: $currentURL,
          isVisible: $showBrowsePanel,
          client: browseClient
        )
        .containerRelativeFrame(.vertical, count: 2, span: 1, spacing: 0)
        .transition(.move(edge: .bottom).combined(with: .opacity))
      }
    }
    .animation(.easeInOut(duration: 0.25), value: showBrowsePanel)
    .frame(
      minWidth: 800,
      idealWidth: max(appModel.windowAspectRatio * 980, 880),
      maxWidth: .infinity,
      minHeight: 450,
      idealHeight: 980,
      maxHeight: .infinity
    )
    .onChange(of: currentURL) { _, newURL in
      print("Current URL changed to: \(newURL.absoluteString)")
      if isBilibiliPlayablePage(url: newURL) {
        scheduleVideoControlStateSync(after: 0.5)
      } else {
        resetVideoControlStates()
      }
    }
    .onReceive(Timer.publish(every: 1.0, on: .main, in: .common).autoconnect()) { _ in
      guard isBilibiliPlayablePage(url: currentURL) else { return }
      syncVideoControlStates()
    }
    .clipShape(RoundedRectangle(cornerRadius: 10))  // Add this line to round the corners of the VStack
    .ornament(attachmentAnchor: .scene(.bottom), contentAlignment: .center) {
      if isBilibiliPlayablePage(url: currentURL) {
        videoControlsOrnament
      } else {
        navigationOrnament
      }
    }
    .alert("Search Bilibili", isPresented: $showSearchPrompt) {
      TextField("Keyword", text: $searchText)
      Button("Cancel", role: .cancel) {}
      Button("Search") {
        performSearch()
      }
    } message: {
      Text("Enter a keyword to open Bilibili search.")
    }
  }

  // 视频模式工具栏：Home + 视频控制按钮
  @ViewBuilder
  private var videoControlsOrnament: some View {
    HStack(spacing: 16) {
      Button {
        withAnimation(.easeInOut(duration: 0.25)) { showBrowsePanel.toggle() }
      } label: {
        Image(systemName: showBrowsePanel ? "rectangle.grid.2x2.fill" : "rectangle.grid.2x2")
          .font(.title2)
      }

      Divider()
        .frame(height: 24)

      Button {
        currentURL = URL(string: "https://www.bilibili.com")!
      } label: {
        Image(systemName: "house")
          .font(.title2)
      }

      Divider()
        .frame(height: 24)

      Button {
        triggerPlayPause()
      } label: {
        Image(systemName: isPlaying ? "pause.fill" : "play.fill")
          .font(.title)
          .foregroundStyle(isPlaying ? Color.white : Color.white.opacity(0.7))
      }

      Menu {
        ForEach(playbackRates, id: \.self) { rate in
          Button {
            triggerSetPlaybackRate(rate)
          } label: {
            HStack {
              Text(formatPlaybackRate(rate))
              if abs(currentPlaybackRate - rate) < 0.01 {
                Image(systemName: "checkmark")
              }
            }
          }
        }
      } label: {
        Text(formatPlaybackRate(currentPlaybackRate))
          .font(.system(size: 14, weight: .medium))
          .monospacedDigit()
      }

      Divider()
        .frame(height: 24)

      Button {
        triggerDanmakuToggle()
      } label: {
        Image(systemName: "bubble.left.and.bubble.right")
          .font(.title2)
          .foregroundStyle(isDanmakuEnabled ? Color.cyan : Color.white.opacity(0.7))
      }

      Button {
        triggerLike()
      } label: {
        Image(systemName: isLiked ? "hand.thumbsup.fill" : "hand.thumbsup")
          .font(.title2)
          .foregroundStyle(isLiked ? Color.red : Color.white.opacity(0.7))
      }

      Button {
        if isBilibiliVideoPage(url: currentURL) {
          let _ = triggerBilibiliFullscreen()
        } else if isBilibiliBangumiPage(url: currentURL) {
          let _ = triggerBilibiliBangumiFullscreen()
        }
      } label: {
        Image(systemName: "arrow.up.left.and.arrow.down.right")
          .font(.title2)
          .foregroundStyle(isFullscreen ? Color.green : Color.white.opacity(0.7))
      }

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
              appModel.adjustWindowAspectRatio(preset.ratio)
            } label: {
              HStack {
                Text(preset.name)
                if abs(videoAspectRatio - preset.ratio) < 0.1 {
                  Image(systemName: "checkmark")
                }
              }
            }
          }

          if detectedVideoSize != .zero {
            Button {
              appModel.adjustWindowToVideoSize(
                videoWidth: detectedVideoSize.width, videoHeight: detectedVideoSize.height)
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
        Image(systemName: "rectangle.ratio.16.to.9").font(.title2)
      }

    }
    .foregroundStyle(.white.opacity(0.7))
    .padding(.horizontal, 20)
    .padding(.vertical, 12)
    .glassBackgroundEffect()
    .padding(.top, 60)
  }

  // 非视频模式导航栏
  @ViewBuilder
  private var navigationOrnament: some View {
    HStack(spacing: 16) {
      Spacer()

      Button {
        withAnimation(.easeInOut(duration: 0.25)) { showBrowsePanel.toggle() }
      } label: {
        Image(systemName: showBrowsePanel ? "rectangle.grid.2x2.fill" : "rectangle.grid.2x2")
          .font(.title2)
      }

      Divider()
        .frame(height: 24)

      Button {
        webView?.goBack()
      } label: {
        Image(systemName: "arrow.backward")
          .font(.title2)
      }
      .disabled(!(webView?.canGoBack ?? false))

      Button {
        currentURL = URL(string: "https://www.bilibili.com")!
      } label: {
        Image(systemName: "house")
          .font(.title2)
      }

      Divider()
        .frame(height: 24)

      Button {
        showSearchPrompt = true
      } label: {
        Image(systemName: "magnifyingglass")
          .font(.title2)
      }

      Divider()
        .frame(height: 24)

      Button {
        currentURL = URL(string: "https://www.bilibili.com/history")!
      } label: {
        Image(systemName: "clock.arrow.circlepath")
          .font(.title2)
      }

      Button {
        triggerRefresh()
      } label: {
        Image(systemName: "arrow.clockwise")
          .font(.title2)
      }

      Spacer()
    }
    .padding(.horizontal, 20)
    .padding(.vertical, 12)
    .glassBackgroundEffect()
    .padding(.top, 60)
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

  // 智能全屏触发：注入 JS 轮询，发现控件就立刻点击，无需 Swift 端固定延迟
  private func triggerBilibiliFullscreenSmart() {
    let script = """
        (function() {
          var attempts = 0;
          var maxAttempts = 30;  // 最多等待 6 秒 (30 x 200ms)
          function tryFullscreen() {
            attempts++;
            // 已经在网页全屏状态，无需重复触发
            var container = document.querySelector('.bpx-player-container');
            if (container && container.classList.contains('bpx-state-web-fullscreen')) {
              return;
            }
            var el = document.querySelector('.bpx-player-ctrl-web');
            if (el) {
              el.click();
              return;
            }
            if (attempts < maxAttempts) {
              setTimeout(tryFullscreen, 200);
            }
          }
          tryFullscreen();
        })();
      """
    webView?.evaluateJavaScript(script) { _, _ in }

    // 视频宽高比检测：稍候读取（等 JS 轮询完成后）
    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
      self.detectVideoAspectRatio()
    }
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
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
          self.syncVideoControlStates()
        }
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
        self.scheduleVideoControlStateSync(after: 0.1)
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
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
          self.syncVideoControlStates()
        }
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

  // 格式化倍速为 B 站菜单文本格式（如 "1.5x"、"1.0x"）
  private func formatPlaybackRate(_ rate: Double) -> String {
    if rate == floor(rate) {
      return "\(Int(rate)).0x"
    }
    return String(format: "%.4gx", rate)
  }

  // 通过点击 B 站播放器 DOM 菜单项切换倍速
  private func triggerSetPlaybackRate(_ rate: Double) {
    let rateText = formatPlaybackRate(rate)
    let script = """
        (function() {
          var items = Array.from(document.querySelectorAll('.bpx-player-ctrl-playbackrate-menu-item'));
          var target = items.find(function(e) { return e.textContent.trim() === '\(rateText)'; });
          if (target) {
            target.click();
          } else {
            var vid = document.querySelector('video');
            if (vid) vid.playbackRate = \(rate);
          }
          var vid = document.querySelector('video');
          return vid ? vid.playbackRate : null;
        })();
      """
    webView?.evaluateJavaScript(script) { result, error in
      if let error = error {
        print("设置倍速失败: \(error.localizedDescription)")
      } else if let newRate = result as? Double {
        DispatchQueue.main.async {
          self.currentPlaybackRate = newRate
        }
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
        self.scheduleVideoControlStateSync(after: 0.15)
      }
    }
  }

  private func triggerLike() {
    print("Attempting to trigger like.")
    let script = """
        (function() {
          var likeButton = document.querySelector('.video-like.video-toolbar-left-item');
          if (likeButton) {
            likeButton.click();
            return 'liked';
          }

          var fallbackButton = document.querySelector('[title*="点赞"]');
          if (fallbackButton) {
            fallbackButton.click();
            return 'liked_fallback';
          }

          return false;
        })();
      """

    webView?.evaluateJavaScript(script) { result, error in
      if let error = error {
        print("JavaScript execution for like failed: \(error)")
      } else {
        print("Like executed. Result: \(String(describing: result))")
        self.scheduleVideoControlStateSync(after: 0.15)
      }
    }
  }

  private func scheduleVideoControlStateSync(after delay: TimeInterval) {
    DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
      self.syncVideoControlStates()
    }
  }

  private func resetVideoControlStates() {
    isPlaying = false
    isDanmakuEnabled = false
    isLiked = false
    isFullscreen = false
  }

  private func syncVideoControlStates() {
    guard isBilibiliPlayablePage(url: currentURL), let webView else { return }

    let script = """
      (function() {
        var video = document.querySelector('video');
        var danmakuSwitch = document.querySelector('.bpx-player-dm-switch input[type="checkbox"]');
        var danmakuArea = document.querySelector('.bpx-player-dm-switch');
        var likeButton = document.querySelector('.video-like.video-toolbar-left-item, .video-toolbar-left-item.video-like, [title*="点赞"]');
        var container = document.querySelector('.bpx-player-container');

        var liked = false;
        if (likeButton) {
          liked = likeButton.classList.contains('on')
            || likeButton.classList.contains('is-active')
            || likeButton.getAttribute('aria-pressed') === 'true'
            || likeButton.getAttribute('data-selected') === 'true'
            || !!likeButton.querySelector('.on, .is-active, [aria-pressed="true"]');
        }

        var danmakuEnabled = null;
        if (danmakuSwitch) {
          danmakuEnabled = !!danmakuSwitch.checked;
        } else if (danmakuArea) {
          danmakuEnabled = !(danmakuArea.classList.contains('off') || danmakuArea.classList.contains('disabled'));
        }

        return {
          isPlaying: !!(video && !video.paused),
          playbackRate: video ? video.playbackRate : null,
          isDanmakuEnabled: danmakuEnabled,
          isLiked: liked,
          isFullscreen: !!document.fullscreenElement || !!(container && container.classList.contains('bpx-state-web-fullscreen'))
        };
      })();
    """

    webView.evaluateJavaScript(script) { result, error in
      if let error = error {
        print("同步视频按钮状态失败: \(error.localizedDescription)")
        return
      }

      guard let dict = result as? [String: Any] else { return }

      DispatchQueue.main.async {
        if let playing = dict["isPlaying"] as? Bool {
          self.isPlaying = playing
        }
        if let playbackRate = dict["playbackRate"] as? Double {
          self.currentPlaybackRate = playbackRate
        }
        if let danmakuEnabled = dict["isDanmakuEnabled"] as? Bool {
          self.isDanmakuEnabled = danmakuEnabled
        }
        if let liked = dict["isLiked"] as? Bool {
          self.isLiked = liked
        }
        if let fullscreen = dict["isFullscreen"] as? Bool {
          self.isFullscreen = fullscreen
        }
      }
    }
  }
}

#Preview(windowStyle: .automatic) {
  ContentView()
    .environment(AppModel())
}
