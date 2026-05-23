import SwiftUI
import WebKit

struct WebView: UIViewRepresentable {
  @Binding var url: URL
  @Binding var currentWebViewInstance: WKWebView?
  var onPageFinishLoad: ((URL) -> Void)?  // Callback for when page finishes loading

  private func normalizedURL(_ input: URL?) -> URL? {
    guard let input else { return nil }
    guard var components = URLComponents(url: input, resolvingAgainstBaseURL: false) else {
      return input
    }

    let ignoredQueryItems: Set<String> = [
      "vd_source",
      "spm_id_from",
      "from_source",
      "search_source",
    ]

    if let queryItems = components.queryItems, !queryItems.isEmpty {
      let filteredItems = queryItems.filter { !ignoredQueryItems.contains($0.name) }
      components.queryItems = filteredItems.isEmpty ? nil : filteredItems
    }

    if components.path.hasSuffix("/") && components.path.count > 1 {
      components.path.removeLast()
    }

    return components.url ?? input
  }

  private func normalizedURLString(_ input: URL?) -> String {
    normalizedURL(input)?.absoluteString ?? ""
  }

  func makeUIView(context: Context) -> WKWebView {
    print("WebView: makeUIView called. Creating new WKWebView for URL: \(url.absoluteString)")  // DEBUG
    let config = WKWebViewConfiguration()

    // 基础媒体配置
    config.allowsInlineMediaPlayback = true
    config.allowsAirPlayForMediaPlayback = true
    config.allowsPictureInPictureMediaPlayback = true
    config.mediaTypesRequiringUserActionForPlayback = []

    // 启用现代Web特性
    let preferences = WKWebpagePreferences()
    preferences.allowsContentJavaScript = true
    config.defaultWebpagePreferences = preferences
    config.preferences.javaScriptCanOpenWindowsAutomatically = true

    // 启用高性能和硬件加速配置
    config.preferences.setValue(true, forKey: "allowFileAccessFromFileURLs")
    config.preferences.setValue(true, forKey: "developerExtrasEnabled")
    config.setValue(true, forKey: "allowUniversalAccessFromFileURLs")

    // 优化渲染性能
    config.suppressesIncrementalRendering = false

    let wkWebView = WKWebView(frame: .zero, configuration: config)

    // 设置高版本Safari UserAgent，避免版本过低提示和画质限制
    wkWebView.customUserAgent =
      "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.2 Safari/605.1.15"

    // 设置页面缩放以适配VisionOS（降低默认缩放以避免画质限制）
    wkWebView.scrollView.minimumZoomScale = 0.5
    wkWebView.scrollView.maximumZoomScale = 3.0
    wkWebView.scrollView.zoomScale = 1.1  // 默认放大10%，减少对画质的影响
    wkWebView.scrollView.bouncesZoom = true

    wkWebView.navigationDelegate = context.coordinator
    wkWebView.uiDelegate = context.coordinator  // Set the UIDelegate
    context.coordinator.onPageFinishLoad = onPageFinishLoad  // Pass the callback to coordinator

    // Update the binding to provide the WKWebView instance to the parent view
    // Doing this asynchronously ensures the view is fully set up.
    DispatchQueue.main.async {
      context.coordinator.parent.currentWebViewInstance = wkWebView
    }
    return wkWebView
  }

  func updateUIView(_ uiView: WKWebView, context: Context) {
    print(
      "WebView: updateUIView called. Target URL: \(url.absoluteString). Current uiView.url: \(uiView.url?.absoluteString ?? "nil")"
    )  // DEBUG
    context.coordinator.onPageFinishLoad = onPageFinishLoad  // Ensure coordinator has the latest callback
    // 规范化 bilibili 跟踪参数后再比较，避免打开推荐面板等普通状态更新时误触发 reload。
    let normalizedCurrentURL = normalizedURLString(uiView.url)
    let normalizedTargetURL = normalizedURLString(url)
    print(
      "WebView: normalized compare. target=\(normalizedTargetURL), current=\(normalizedCurrentURL)"
    )

    if normalizedCurrentURL != normalizedTargetURL {
      print(
        "WebView: Reloading - target URL (\(url.absoluteString)) is different from uiView.url (\(uiView.url?.absoluteString ?? "nil"))."
      )  // DEBUG
      let request = URLRequest(url: url)
      uiView.load(request)
    } else {
      print("WebView: Not reloading - URL strings match.")  // DEBUG
    }
  }

  func makeCoordinator() -> Coordinator {
    Coordinator(self, onPageFinishLoad: onPageFinishLoad)
  }

  class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {  // Add WKUIDelegate
    var parent: WebView
    var onPageFinishLoad: ((URL) -> Void)?

    init(_ parent: WebView, onPageFinishLoad: ((URL) -> Void)?) {
      self.parent = parent
      self.onPageFinishLoad = onPageFinishLoad
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
      // If navigation finishes and the URL is different, update the binding.
      // This allows ContentView to know the current URL even if the user navigates within the WebView.
      if let newURL = webView.url {
        let normalizedNewURL = parent.normalizedURL(newURL) ?? newURL
        if normalizedNewURL.absoluteString != parent.normalizedURL(parent.url)?.absoluteString {
          DispatchQueue.main.async {
            self.parent.url = normalizedNewURL
          }
        }

        // 注入CSS样式来优化VisionOS显示效果
        injectVisionOSOptimizedCSS(webView: webView)

        // Call the onPageFinishLoad callback
        print("WebView: didFinish navigation. URL=\(newURL.absoluteString)")
        onPageFinishLoad?(normalizedNewURL)
      }
    }

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
      print("WebView: didStartProvisionalNavigation. URL=\(webView.url?.absoluteString ?? "nil")")
    }

    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
      print("WebView: didCommit navigation. URL=\(webView.url?.absoluteString ?? "nil")")
    }

    func webView(
      _ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse,
      decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void
    ) {
      if let httpResp = navigationResponse.response as? HTTPURLResponse {
        print("WebView: HTTP \(httpResp.statusCode) <- \(httpResp.url?.absoluteString ?? "nil")")
      }
      decisionHandler(.allow)
    }

    func webView(
      _ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
      decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
    ) {
      print(
        "WebView: decidePolicyFor \(navigationAction.navigationType.rawValue) -> \(navigationAction.request.url?.absoluteString ?? "nil")"
      )
      decisionHandler(.allow)
    }

    private func injectVisionOSOptimizedCSS(webView: WKWebView) {
      let cssCode = """
          /* VisionOS触控优化 */
          button, a, input {
            min-height: 44px !important;
            min-width: 44px !important;
          }

          /* 优化滚动条 */
          ::-webkit-scrollbar {
            width: 16px !important;
            height: 10px !important;
          }

          /* 轨道：深色背景，比 SwiftUI 玻璃面板更深 */
          ::-webkit-scrollbar-track {
            background-color: rgba(10, 10, 15, 0.85) !important;
            border-radius: 8px !important;
          }

          ::-webkit-scrollbar-thumb {
            background-color: rgba(80, 140, 255, 0.75) !important;
            border-radius: 8px !important;
          }

          ::-webkit-scrollbar-thumb:hover {
            background-color: rgba(100, 160, 255, 0.95) !important;
          }

          /* B站视频播放器进度条优化 */
          .bpx-player-progress {
            height: 16px !important;
            min-height: 16px !important;
          }

          .bpx-player-progress-schedule {
            height: 16px !important;
          }

          .bpx-player-progress-schedule-wrap {
            height: 16px !important;
          }

          /* B站播放器控制按钮优化 */
          .bpx-player-ctrl-btn {
            min-height: 44px !important;
            min-width: 44px !important;
            padding: 8px 12px !important;
          }

          .bpx-player-ctrl-quality,
          .bpx-player-ctrl-playbackrate,
          .bpx-player-ctrl-subtitle {
            min-height: 44px !important;
            min-width: 44px !important;
          }

          /* 播放器菜单项优化 */
          .bpx-player-ctrl-quality-menu-item,
          .bpx-player-ctrl-playbackrate-menu-item {
            min-height: 44px !important;
            padding: 8px 16px !important;
            line-height: 28px !important;
          }

          /* nav buttons */
          .v-popover-wrap {
            min-width: 56px !important;
          }
          .download-client-trigger {
            display: none !important;
          }
        """

      // 末尾加 ; null 避免 evaluateJavaScript 返回不可序列化的 DOM element
      let jsCode =
        "var style = document.createElement('style'); style.innerHTML = `\(cssCode)`; document.head.appendChild(style); null;"

      webView.evaluateJavaScript(jsCode) { _, error in
        if let error = error {
          print("WebView: CSS注入失败: \(error.localizedDescription)")
        } else {
          print("WebView: CSS注入成功")
        }
      }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
      print("WebView navigation failed: \(error.localizedDescription)")
    }

    func webView(
      _ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!,
      withError error: Error
    ) {
      print("WebView provisional navigation failed: \(error.localizedDescription)")
    }

    // Handle requests to open new windows
    func webView(
      _ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
      for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
      if navigationAction.targetFrame == nil {
        webView.load(navigationAction.request)
      }
      return nil
    }
  }
}
