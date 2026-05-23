//
//  BilibiliSidebarView.swift
//  bilibili-viewer
//

import SwiftUI
import WebKit

enum SidebarMode: String {
  case recommend
  case upNext
  case search
}

// MARK: - Data Model

struct VideoItem: Identifiable {
  let id: String  // bvid
  let title: String
  let cover: String
  let ownerName: String

  var videoURL: URL? {
    URL(string: "https://www.bilibili.com/video/\(id)")
  }
}

// MARK: - API Client

@MainActor
@Observable
class BilibiliAPIClient {
  var videos: [VideoItem] = []
  var isLoading = false
  var errorMessage: String? = nil
  private var cachedRecommendations: [VideoItem] = []
  private var cachedUpNextVideos: [String: [VideoItem]] = [:]
  weak var webView: WKWebView?

  private struct RecommendationParseResult {
    let code: Int?
    let message: String?
    let items: [[String: Any]]?
  }

  private struct UpNextParseResult {
    let code: Int?
    let message: String?
    let items: [[String: Any]]?
  }

  private struct SearchParseResult {
    let code: Int?
    let message: String?
    let results: [[String: Any]]?
  }

  private struct WebViewFetchResult {
    let status: Int
    let contentType: String?
    let finalURL: String?
    let text: String
  }

  private func bilibiliCookies() async -> [HTTPCookie] {
    await withCheckedContinuation { continuation in
      WKWebsiteDataStore.default().httpCookieStore.getAllCookies { cookies in
        continuation.resume(
          returning: cookies.filter { $0.domain.contains("bilibili.com") })
      }
    }
  }

  private func makeRequest(url: URL) async -> URLRequest {
    let cookies = await bilibiliCookies()
    var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData)
    let cookieHeader = cookies.map { "\($0.name)=\($0.value)" }.joined(separator: "; ")
    if !cookieHeader.isEmpty {
      request.setValue(cookieHeader, forHTTPHeaderField: "Cookie")
    }
    request.setValue("https://www.bilibili.com", forHTTPHeaderField: "Referer")
    request.setValue(
      "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36",
      forHTTPHeaderField: "User-Agent")
    return request
  }

  private func recommendationURL(ps: Int) -> URL? {
    URL(
      string:
        "https://api.bilibili.com/x/web-interface/index/top/rcmd?fresh_type=4&ps=\(ps)&fresh_idx=1&fresh_idx_1h=1&feed_version=V8"
    )
  }

  private func searchURL(encodedKeyword: String, page: Int, pageSize: Int) -> URL? {
    var urlString =
      "https://api.bilibili.com/x/web-interface/search/type?search_type=video&keyword=\(encodedKeyword)"
    urlString += "&page=\(page)&page_size=\(pageSize)"
    return URL(string: urlString)
  }

  private func upNextURL(bvid: String) -> URL? {
    URL(string: "https://api.bilibili.com/x/web-interface/archive/related?bvid=\(bvid)")
  }

  private func parseRecommendationResponse(data: Data) -> RecommendationParseResult {
    guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
      return RecommendationParseResult(code: nil, message: nil, items: nil)
    }

    return RecommendationParseResult(
      code: json["code"] as? Int,
      message: json["message"] as? String,
      items: (json["data"] as? [String: Any])?["item"] as? [[String: Any]]
    )
  }

  private func parseSearchResponse(data: Data) -> SearchParseResult {
    guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
      return SearchParseResult(code: nil, message: nil, results: nil)
    }

    return SearchParseResult(
      code: json["code"] as? Int,
      message: json["message"] as? String,
      results: (json["data"] as? [String: Any])?["result"] as? [[String: Any]]
    )
  }

  private func parseUpNextResponse(data: Data) -> UpNextParseResult {
    guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
      return UpNextParseResult(code: nil, message: nil, items: nil)
    }

    return UpNextParseResult(
      code: json["code"] as? Int,
      message: json["message"] as? String,
      items: json["data"] as? [[String: Any]]
    )
  }

  private func responsePreview(_ data: Data, limit: Int = 240) -> String {
    let raw = String(data: data, encoding: .utf8) ?? "(unreadable)"
    return String(raw.prefix(limit))
  }

  private func responsePreview(_ text: String, limit: Int = 240) -> String {
    String(text.prefix(limit))
  }

  private func errorSummary(_ error: Error) -> String {
    let nsError = error as NSError
    return
      "domain=\(nsError.domain) code=\(nsError.code) desc=\(nsError.localizedDescription)"
  }

  private func normalizedCoverURL(_ raw: String) -> String {
    if raw.hasPrefix("//") {
      return "https:\(raw)"
    }
    if raw.hasPrefix("http://") {
      return "https://" + raw.dropFirst("http://".count)
    }
    return raw
  }

  private func bvid(from url: URL) -> String? {
    let components = url.pathComponents
    guard let videoIndex = components.firstIndex(of: "video") else { return nil }
    let nextIndex = components.index(after: videoIndex)
    guard components.indices.contains(nextIndex) else { return nil }

    let candidate = components[nextIndex]
    guard candidate.uppercased().hasPrefix("BV") else { return nil }
    return candidate
  }

  private func makeRecommendationVideoItem(from item: [String: Any]) -> VideoItem? {
    guard
      let bvid = item["bvid"] as? String,
      let title = item["title"] as? String,
      let pic = item["pic"] as? String
    else { return nil }
    let owner = (item["owner"] as? [String: Any])?["name"] as? String ?? ""
    return VideoItem(id: bvid, title: title, cover: normalizedCoverURL(pic), ownerName: owner)
  }

  private func makeSearchVideoItem(from item: [String: Any]) -> VideoItem? {
    guard
      let bvid = item["bvid"] as? String,
      let rawTitle = item["title"] as? String,
      let pic = item["pic"] as? String
    else { return nil }
    let title = rawTitle.replacingOccurrences(
      of: "<[^>]+>", with: "", options: .regularExpression)
    let author = item["author"] as? String ?? ""
    return VideoItem(id: bvid, title: title, cover: normalizedCoverURL(pic), ownerName: author)
  }

  private func makeUpNextVideoItem(from item: [String: Any]) -> VideoItem? {
    guard
      let bvid = item["bvid"] as? String,
      let title = item["title"] as? String,
      let pic = item["pic"] as? String
    else { return nil }
    let owner = (item["owner"] as? [String: Any])?["name"] as? String ?? ""
    return VideoItem(id: bvid, title: title, cover: normalizedCoverURL(pic), ownerName: owner)
  }

  func attachWebView(_ webView: WKWebView?) {
    self.webView = webView
  }

  private func fetchTextViaWebView(url: URL) async throws -> WebViewFetchResult {
    guard let webView else {
      throw NSError(
        domain: "BilibiliAPIClient", code: -1,
        userInfo: [NSLocalizedDescriptionKey: "WKWebView unavailable for in-page fetch"])
    }

    let script = """
      const response = await fetch(requestURL, {
        credentials: "include",
        headers: {
          Accept: "application/json, text/plain, */*"
        }
      });
      const text = await response.text();
      return {
        status: response.status,
        contentType: response.headers.get("content-type"),
        finalURL: response.url,
        text: text
      };
    """

    return try await withCheckedThrowingContinuation { continuation in
      webView.callAsyncJavaScript(
        script,
        arguments: ["requestURL": url.absoluteString],
        in: nil,
        in: .page,
        completionHandler: { result in
        switch result {
        case .success(let value):
          guard
            let dict = value as? [String: Any],
            let status = dict["status"] as? Int,
            let text = dict["text"] as? String
          else {
            continuation.resume(
              throwing: NSError(
                domain: "BilibiliAPIClient", code: -2,
                userInfo: [NSLocalizedDescriptionKey: "Unexpected webView fetch result shape"])
            )
            return
          }

          continuation.resume(
            returning: WebViewFetchResult(
              status: status,
              contentType: dict["contentType"] as? String,
              finalURL: dict["finalURL"] as? String,
              text: text
            ))
        case .failure(let error):
          continuation.resume(throwing: error)
        }
      })
    }
  }

  func loadRecommendationsIfNeeded() async {
    if !cachedRecommendations.isEmpty {
      videos = cachedRecommendations
      errorMessage = nil
      print("API 推荐命中缓存: videos=\(videos.count)")
      return
    }
    await fetchRecommendations(force: false)
  }

  func fetchRecommendations(force: Bool = true) async {
    if !force && !cachedRecommendations.isEmpty {
      videos = cachedRecommendations
      errorMessage = nil
      print("API 推荐跳过请求，直接复用缓存: videos=\(videos.count)")
      return
    }

    isLoading = true
    errorMessage = nil
    defer { isLoading = false }

    // 浏览器实测 ps=16 会返回 -400，请求成功区间至少包含 10~14。
    // 这里按较大到较小回退，避免接口参数波动时整个推荐面板失效。
    let psCandidates = [14, 12, 10, 8]
    var failureSummaries: [String] = []

    for ps in psCandidates {
      guard let url = recommendationURL(ps: ps) else { continue }
      let request = await makeRequest(url: url)
      let cookieBytes = request.value(forHTTPHeaderField: "Cookie")?.count ?? 0
      print(
        "API 推荐请求: ps=\(ps), url=\(url.absoluteString), cookieBytes=\(cookieBytes), referer=\(request.value(forHTTPHeaderField: "Referer") ?? "nil")"
      )

      do {
        let (data, response) = try await URLSession.shared.data(for: request)
        let httpResponse = response as? HTTPURLResponse
        let parsed = parseRecommendationResponse(data: data)
        let contentType = httpResponse?.value(forHTTPHeaderField: "Content-Type") ?? "nil"
        let finalURL = httpResponse?.url?.absoluteString ?? url.absoluteString
        let preview = responsePreview(data)

        print(
          "API 推荐响应: ps=\(ps), requestURL=\(url.absoluteString), finalURL=\(finalURL), http=\(httpResponse?.statusCode ?? -1), contentType=\(contentType), bytes=\(data.count), code=\(parsed.code?.description ?? "nil"), message=\(parsed.message ?? "nil"), preview=\(preview)"
        )

        guard let items = parsed.items, !items.isEmpty else {
          failureSummaries.append(
            "ps=\(ps) url=\(url.absoluteString) http=\(httpResponse?.statusCode ?? -1) code=\(parsed.code?.description ?? "nil") message=\(parsed.message ?? "nil")"
          )
          continue
        }

        let mappedVideos = items.compactMap(makeRecommendationVideoItem(from:))
        cachedRecommendations = mappedVideos
        videos = mappedVideos
        errorMessage = nil
        print("API 推荐加载成功: ps=\(ps), videos=\(videos.count)")
        return
      } catch {
        let summary = "ps=\(ps) url=\(url.absoluteString) networkError=\(errorSummary(error))"
        failureSummaries.append(summary)
        print("API 推荐请求失败: \(summary)")
      }
    }

    videos = []
    errorMessage = "推荐加载失败"
    print("API 推荐全部尝试失败: \(failureSummaries.joined(separator: " | "))")
  }

  func loadUpNextIfNeeded(for currentURL: URL) async {
    guard let bvid = bvid(from: currentURL) else {
      videos = []
      errorMessage = "当前页面暂无接下来播放"
      print("API 接下来播放跳过: url=\(currentURL.absoluteString), reason=missing-bvid")
      return
    }

    if let cachedVideos = cachedUpNextVideos[bvid], !cachedVideos.isEmpty {
      videos = cachedVideos
      errorMessage = nil
      print("API 接下来播放命中缓存: bvid=\(bvid), videos=\(videos.count)")
      return
    }

    await fetchUpNext(for: currentURL, force: false)
  }

  func fetchUpNext(for currentURL: URL, force: Bool = true) async {
    guard let bvid = bvid(from: currentURL), let url = upNextURL(bvid: bvid) else {
      videos = []
      errorMessage = "当前页面暂无接下来播放"
      print("API 接下来播放跳过: url=\(currentURL.absoluteString), reason=missing-bvid")
      return
    }

    if !force, let cachedVideos = cachedUpNextVideos[bvid], !cachedVideos.isEmpty {
      videos = cachedVideos
      errorMessage = nil
      print("API 接下来播放跳过请求，直接复用缓存: bvid=\(bvid), videos=\(videos.count)")
      return
    }

    isLoading = true
    errorMessage = nil
    defer { isLoading = false }

    let request = await makeRequest(url: url)
    let cookieBytes = request.value(forHTTPHeaderField: "Cookie")?.count ?? 0
    print(
      "API 接下来播放请求: bvid=\(bvid), url=\(url.absoluteString), cookieBytes=\(cookieBytes), referer=\(request.value(forHTTPHeaderField: "Referer") ?? "nil")"
    )

    do {
      let (data, response) = try await URLSession.shared.data(for: request)
      let httpResponse = response as? HTTPURLResponse
      let parsed = parseUpNextResponse(data: data)
      let contentType = httpResponse?.value(forHTTPHeaderField: "Content-Type") ?? "nil"
      let finalURL = httpResponse?.url?.absoluteString ?? url.absoluteString
      let preview = responsePreview(data)

      print(
        "API 接下来播放响应: bvid=\(bvid), requestURL=\(url.absoluteString), finalURL=\(finalURL), http=\(httpResponse?.statusCode ?? -1), contentType=\(contentType), bytes=\(data.count), code=\(parsed.code?.description ?? "nil"), message=\(parsed.message ?? "nil"), preview=\(preview)"
      )

      guard let items = parsed.items, !items.isEmpty else {
        videos = []
        errorMessage = "接下来播放加载失败"
        print(
          "API 接下来播放结果为空: bvid=\(bvid), http=\(httpResponse?.statusCode ?? -1), code=\(parsed.code?.description ?? "nil"), message=\(parsed.message ?? "nil")"
        )
        return
      }

      let mappedVideos = items.compactMap(makeUpNextVideoItem(from:))
      cachedUpNextVideos[bvid] = mappedVideos
      videos = mappedVideos
      errorMessage = nil
      print("API 接下来播放加载成功: bvid=\(bvid), videos=\(videos.count)")
    } catch {
      videos = []
      errorMessage = "接下来播放加载失败"
      print(
        "API 接下来播放请求失败: bvid=\(bvid), url=\(url.absoluteString), networkError=\(errorSummary(error))"
      )
    }
  }

  func searchVideos(keyword: String, page: Int = 1, pageSize: Int = 10) async {
    guard !keyword.trimmingCharacters(in: .whitespaces).isEmpty else { return }
    isLoading = true
    errorMessage = nil
    defer { isLoading = false }

    let encoded = keyword.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? keyword
    let attempts = [(label: "page=\(page)", page: page)]
    var failureSummaries: [String] = []

    for attempt in attempts {
      guard let url = searchURL(encodedKeyword: encoded, page: attempt.page, pageSize: pageSize)
      else { continue }
      let hasWebView = webView != nil
      print(
        "API 搜索环境: keyword=\(keyword), page=\(page), pageSize=\(pageSize), variant=\(attempt.label), hasWebView=\(hasWebView)"
      )

      if hasWebView {
        do {
          let result = try await fetchTextViaWebView(url: url)
          let data = Data(result.text.utf8)
          let parsed = parseSearchResponse(data: data)
          let preview = responsePreview(result.text)
          let finalURL = result.finalURL ?? url.absoluteString

          print(
            "API 搜索响应(webView): keyword=\(keyword), variant=\(attempt.label), requestURL=\(url.absoluteString), finalURL=\(finalURL), http=\(result.status), contentType=\(result.contentType ?? "nil"), bytes=\(data.count), code=\(parsed.code?.description ?? "nil"), message=\(parsed.message ?? "nil"), preview=\(preview)"
          )

          if let searchResults = parsed.results {
            videos = searchResults.compactMap(makeSearchVideoItem(from:))
            errorMessage = nil
            print(
              "API 搜索加载成功(webView): keyword=\(keyword), page=\(page), variant=\(attempt.label), videos=\(videos.count)"
            )
            return
          }

          failureSummaries.append(
            "variant=\(attempt.label) transport=webView url=\(url.absoluteString) http=\(result.status) code=\(parsed.code?.description ?? "nil") message=\(parsed.message ?? "nil") contentType=\(result.contentType ?? "nil")"
          )
        } catch {
          let summary =
            "variant=\(attempt.label) transport=webView url=\(url.absoluteString) networkError=\(errorSummary(error))"
          failureSummaries.append(summary)
          print("API 搜索请求失败(webView): keyword=\(keyword), \(summary)")
        }
      }

      let request = await makeRequest(url: url)
      let cookieBytes = request.value(forHTTPHeaderField: "Cookie")?.count ?? 0
      print(
        "API 搜索请求: keyword=\(keyword), encoded=\(encoded), variant=\(attempt.label), url=\(url.absoluteString), cookieBytes=\(cookieBytes), referer=\(request.value(forHTTPHeaderField: "Referer") ?? "nil")"
      )

      do {
        let (data, response) = try await URLSession.shared.data(for: request)
        let httpResponse = response as? HTTPURLResponse
        let parsed = parseSearchResponse(data: data)
        let contentType = httpResponse?.value(forHTTPHeaderField: "Content-Type") ?? "nil"
        let finalURL = httpResponse?.url?.absoluteString ?? url.absoluteString
        let preview = responsePreview(data)

        print(
          "API 搜索响应: keyword=\(keyword), variant=\(attempt.label), requestURL=\(url.absoluteString), finalURL=\(finalURL), http=\(httpResponse?.statusCode ?? -1), contentType=\(contentType), bytes=\(data.count), code=\(parsed.code?.description ?? "nil"), message=\(parsed.message ?? "nil"), preview=\(preview)"
        )

        guard let result = parsed.results else {
          failureSummaries.append(
            "variant=\(attempt.label) url=\(url.absoluteString) http=\(httpResponse?.statusCode ?? -1) code=\(parsed.code?.description ?? "nil") message=\(parsed.message ?? "nil")"
          )
          continue
        }

        videos = result.compactMap(makeSearchVideoItem(from:))
        errorMessage = nil
        print(
          "API 搜索加载成功: keyword=\(keyword), page=\(page), variant=\(attempt.label), videos=\(videos.count)"
        )
        return
      } catch {
        let summary =
          "variant=\(attempt.label) url=\(url.absoluteString) networkError=\(errorSummary(error))"
        failureSummaries.append(summary)
        print("API 搜索请求失败: keyword=\(keyword), \(summary)")
      }
    }

    videos = []
    errorMessage = "搜索加载失败"
    print("API 搜索全部尝试失败: keyword=\(keyword), \(failureSummaries.joined(separator: " | "))")
  }
}

// MARK: - Panel View (floating overlay, covers bottom 2/3 of the video)

struct BilibiliPanelView: View {
  @Binding var currentURL: URL
  @Binding var isVisible: Bool
  var client: BilibiliAPIClient
  @AppStorage("bilibili.panel.mode") private var modeRawValue = SidebarMode.recommend.rawValue
  @State private var searchText = ""
  @State private var searchPage = 1

  private let coverAspectRatio: CGFloat = 16.0 / 9.0
  private let visibleColumnCount: CGFloat = 5
  private let itemSpacing: CGFloat = 14
  private let contentPadding: CGFloat = 14

  private var mode: SidebarMode {
    SidebarMode(rawValue: modeRawValue) ?? .recommend
  }

  private var modeBinding: Binding<SidebarMode> {
    Binding(
      get: { mode },
      set: { modeRawValue = $0.rawValue }
    )
  }

  @ViewBuilder
  private func modeTab(_ title: String, mode targetMode: SidebarMode) -> some View {
    Button {
      modeBinding.wrappedValue = targetMode
    } label: {
      VStack(spacing: 8) {
        Text(title)
          .font(.system(size: 15, weight: mode == targetMode ? .semibold : .regular))
          .foregroundStyle(mode == targetMode ? Color.white.opacity(0.96) : Color.white.opacity(0.72))

        Rectangle()
          .fill(mode == targetMode ? Color.primary.opacity(0.9) : Color.clear)
          .frame(height: 1.5)
      }
      .padding(.horizontal, 4)
      .padding(.vertical, 2)
      .overlay(alignment: .bottom) {
        Rectangle()
          .fill(Color.white.opacity(0.08))
          .frame(height: 1)
      }
    }
    .buttonStyle(.plain)
  }

  private func runSearch(page: Int) {
    let trimmedSearchText = searchText.trimmingCharacters(in: .whitespaces)
    guard !trimmedSearchText.isEmpty else {
      searchPage = 1
      client.videos = []
      client.errorMessage = nil
      return
    }

    searchPage = max(page, 1)
    Task {
      await client.searchVideos(keyword: trimmedSearchText, page: searchPage, pageSize: 10)
    }
  }

  private func loadCurrentMode(force: Bool = false) {
    switch mode {
    case .recommend:
      Task {
        if force {
          await client.fetchRecommendations()
        } else {
          await client.loadRecommendationsIfNeeded()
        }
      }
    case .upNext:
      Task {
        if force {
          await client.fetchUpNext(for: currentURL)
        } else {
          await client.loadUpNextIfNeeded(for: currentURL)
        }
      }
    case .search:
      if searchText.trimmingCharacters(in: .whitespaces).isEmpty {
        client.videos = []
        client.errorMessage = nil
      } else {
        runSearch(page: searchPage)
      }
    }
  }

  var body: some View {
    VStack(spacing: 0) {
      // Header
      HStack(spacing: 16) {
        Spacer(minLength: 0)

        HStack(spacing: 18) {
          modeTab("Feed", mode: .recommend)
          modeTab("Up Next", mode: .upNext)
          modeTab("Search", mode: .search)
        }
        .padding(.horizontal, 4)
        .frame(maxWidth: 320)

        if mode == .recommend {
          Button {
            Task { await client.fetchRecommendations() }
          } label: {
            Label("Suggest", systemImage: "arrow.clockwise")
          }
        } else if mode == .search {
          HStack(spacing: 8) {
            TextField("Search videos...", text: $searchText)
              .textFieldStyle(.roundedBorder)
              .frame(maxWidth: 260)
              .onSubmit { runSearch(page: 1) }
            Button {
              runSearch(page: 1)
            } label: {
              Label("Search", systemImage: "magnifyingglass")
            }
            .disabled(searchText.trimmingCharacters(in: .whitespaces).isEmpty)

            Button {
              runSearch(page: searchPage + 1)
            } label: {
              Label("Next Page", systemImage: "arrow.right.circle")
            }
            .disabled(searchText.trimmingCharacters(in: .whitespaces).isEmpty)

            Text("Page \(searchPage)")
              .font(.caption)
              .foregroundStyle(.secondary)
          }
        }

        Divider()
          .frame(height: 24)

        Button {
          withAnimation(.easeInOut(duration: 0.25)) { isVisible = false }
        } label: {
          Image(systemName: "chevron.down")
            .font(.title2)
            .foregroundStyle(.secondary)
            .frame(width: 36, height: 36)
            .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
              RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)

        Spacer(minLength: 0)
      }
      .padding(.horizontal, 16)
      .padding(.vertical, 10)

      Divider()

      // Content
      Group {
        if client.isLoading {
          ProgressView("加载中...")
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let err = client.errorMessage {
          HStack(spacing: 12) {
            Text(err).font(.caption).foregroundStyle(.secondary)
            Button("Retry") {
              Task {
                if mode == .recommend {
                  await client.fetchRecommendations()
                } else if mode == .upNext {
                  await client.fetchUpNext(for: currentURL)
                } else {
                  await client.searchVideos(keyword: searchText, page: searchPage, pageSize: 10)
                }
              }
            }
          }
          .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if client.videos.isEmpty {
          Text(mode == .search ? "Search to start" : "No content")
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
          GeometryReader { proxy in
            let availableWidth = max(proxy.size.width - contentPadding * 2, 0)
            let totalSpacing = itemSpacing * max(visibleColumnCount - 1, 0)
            let itemWidth = max((availableWidth - totalSpacing) / visibleColumnCount, 190)
            let rowHeight = itemWidth / coverAspectRatio
            let rows = [
              GridItem(.fixed(rowHeight), spacing: itemSpacing, alignment: .top),
              GridItem(.fixed(rowHeight), spacing: itemSpacing, alignment: .top),
            ]

            ScrollView(.horizontal, showsIndicators: false) {
              LazyHGrid(rows: rows, alignment: .top, spacing: itemSpacing) {
                ForEach(client.videos) { video in
                  Button {
                    if let url = video.videoURL {
                      currentURL = url
                    }
                  } label: {
                    VideoThumbnailView(video: video)
                      .frame(width: itemWidth)
                  }
                  .buttonStyle(.plain)
                }
              }
              .frame(minWidth: availableWidth, alignment: .center)
              .padding(.horizontal, contentPadding)
              .padding(.vertical, 10)
            }
          }
        }
      }
    }
    .background(.ultraThinMaterial)
    .clipShape(
      UnevenRoundedRectangle(
        topLeadingRadius: 16, bottomLeadingRadius: 0,
        bottomTrailingRadius: 0, topTrailingRadius: 16,
        style: .continuous)
    )
    .task {
      loadCurrentMode()
    }
    .onChange(of: modeRawValue) { _, newValue in
      let selectedMode = SidebarMode(rawValue: newValue) ?? .recommend
      if selectedMode == .search {
        searchPage = max(searchPage, 1)
      }
      loadCurrentMode()
    }
    .onChange(of: currentURL) { _, newURL in
      guard mode == .upNext else { return }
      Task { await client.loadUpNextIfNeeded(for: newURL) }
    }
  }
}

// MARK: - Thumbnail Cell

struct VideoThumbnailView: View {
  let video: VideoItem
  @State private var isHovering = false
  private let cornerRadius: CGFloat = 12
  private let coverAspectRatio: CGFloat = 16.0 / 9.0

  var body: some View {
    ZStack(alignment: .bottomLeading) {
      ZStack {
        Rectangle()
          .fill(.quaternary)

        AsyncImage(url: URL(string: video.cover)) { phase in
          switch phase {
          case .success(let image):
            image
              .resizable()
              .scaledToFill()
              .frame(maxWidth: .infinity, maxHeight: .infinity)
          case .failure:
            Image(systemName: "photo")
              .foregroundStyle(.tertiary)
          default:
            ProgressView()
              .scaleEffect(0.6)
          }
        }
      }
      .aspectRatio(coverAspectRatio, contentMode: .fit)
      .clipped()
      .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))

      LinearGradient(
        colors: [.clear, Color.black.opacity(0.18), Color.black.opacity(0.62)],
        startPoint: .top,
        endPoint: .bottom
      )
      .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))

      VStack(alignment: .leading, spacing: 3) {
        Text(video.title)
          .font(.caption)
          .fontWeight(.semibold)
          .lineLimit(2)
          .foregroundStyle(.white.opacity(0.96))

        Text(video.ownerName)
          .font(.system(size: 10, weight: .regular))
          .lineLimit(1)
          .foregroundStyle(.white.opacity(0.72))
      }
      .padding(.horizontal, 10)
      .padding(.vertical, 8)
      .background(
        Color.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 10, style: .continuous)
      )
      .overlay(
        RoundedRectangle(cornerRadius: 10, style: .continuous)
          .stroke(.white.opacity(0.14), lineWidth: 0.8)
      )
      .padding(.horizontal, 10)
      .padding(.bottom, 10)
      .offset(y: isHovering ? -2 : 0)
    }
    .overlay(
      RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        .stroke(
          isHovering ? Color.accentColor.opacity(0.95) : Color.white.opacity(0.08),
          lineWidth: isHovering ? 3 : 1)
    )
    .shadow(color: isHovering ? Color.accentColor.opacity(0.22) : .clear, radius: 10)
    .scaleEffect(1.0)
    .animation(.easeInOut(duration: 0.16), value: isHovering)
    .hoverEffect(.highlight)
    .onHover { hovering in
      isHovering = hovering
    }
    .contentShape(Rectangle())
  }
}
