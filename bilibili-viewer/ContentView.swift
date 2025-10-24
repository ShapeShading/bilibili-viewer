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

            if !ret {
              // another 2 seconds delay
              DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                let ret = triggerBilibiliFullscreen()

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
        print("WebView canGoBack changed: \(webView?.canGoBack ?? false)")
      }

      HStack {
        Spacer()  // Add spacer at the beginning to push content to center

        Button {
          if isBilibiliPlayablePage(url: currentURL) {
            triggerSeekBackward()
          }
        } label: {
          Label("", systemImage: "gobackward.15")
        }
        .disabled(isNotBilibiliPlayablePage(url: currentURL))

        Button {
          if isBilibiliVideoPage(url: currentURL) {
            triggerPlayPause()
          }
        } label: {
          Label("Play/Pause", systemImage: "playpause.fill")
        }
        .disabled(isNotBilibiliPlayablePage(url: currentURL))

        Button {
          if isBilibiliPlayablePage(url: currentURL) {
            triggerSeekForward()
          }
        } label: {
          Label("", systemImage: "goforward.15")
        }
        .disabled(isNotBilibiliPlayablePage(url: currentURL))

        // 添加分隔符和间距
        Divider()
          .frame(height: 20)
          .padding(.horizontal, 8)

        Button {
          if isBilibiliPlayablePage(url: currentURL) {
            triggerDanmakuToggle()
          }
        } label: {
          Label("", systemImage: "bubble.left.and.bubble.right")
        }
        .disabled(isNotBilibiliPlayablePage(url: currentURL))

        Button {
          print("currentURL: \(currentURL)")
          // Execute JavaScript to click the fullscreen button
          if isBilibiliVideoPage(url: currentURL) {
            let _ = triggerBilibiliFullscreen()
          } else if isBilibiliBangumiPage(url: currentURL) {
            let _ = triggerBilibiliBangumiFullscreen()
          } else {
            // Optionally, provide feedback that it's not a video page
            print("Not a Bilibili video page or unable to trigger fullscreen.")
          }
        } label: {
          Label("Fullscreen", systemImage: "arrow.up.right.video.fill")
        }
        .disabled(isNotBilibiliPlayablePage(url: currentURL))

        Spacer()  // Add spacer at the end to push content to center
      }
      .padding()
      .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
      .background(Color.black.opacity(0.3))
    }
    .onChange(of: currentURL) { _, newURL in
      // This ensures that if the user navigates within the WebView,
      // the 'Toggle Fullscreen' button's state is updated.
      print("Current URL changed to: \(newURL)")
    }
    .clipShape(RoundedRectangle(cornerRadius: 10))  // Add this line to round the corners of the VStack
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
