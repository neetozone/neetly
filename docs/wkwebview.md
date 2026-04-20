# WKWebView

  WKWebView is Apple's modern web view component (introduced in iOS 8 / macOS 10.10), part of the WebKit framework. It replaced the older UIWebView.

  ## Key Points

  - **Out-of-process rendering**: Runs web content in a separate process, so crashes don't kill your app and memory pressure is isolated.
  - **Nitro JavaScript engine**: Same JIT-compiled JS engine as Safari — dramatically faster than UIWebView's interpreted JS.
  - **Async APIs**: Navigation, script evaluation (`evaluateJavaScript:`), and message handling are all asynchronous.
  - **JS ↔ native bridge**: `WKUserContentController` lets you inject scripts and receive messages from JS via `window.webkit.messageHandlers`.
  - **Configuration**: `WKWebViewConfiguration` controls data stores, process pools, preferences, and content rules.
  - **Cookies/storage**: `WKHTTPCookieStore` and `WKWebsiteDataStore` (including `.nonPersistent()` for private browsing).
  - **Content blocking**: Supports declarative JSON-based content blockers compiled into bytecode.

  ## Common Gotchas

  - Cookies don't automatically sync with `HTTPCookieStorage` — you manage them via `WKHTTPCookieStore`.
  - File/local content loading requires `loadFileURL:allowingReadAccessToURL:` or a custom `WKURLSchemeHandler`.
  - POST body is stripped on cross-origin redirects.
  - No direct synchronous JS evaluation — everything is callback/async-await based.

  ## 1. JavaScript ↔ Native Bridge

  ### Native → JS — Inject and execute JavaScript

  ```swift
  // One-off evaluation
  webView.evaluateJavaScript("document.title") { result, error in
      print(result as? String)
  }

  // async/await (iOS 15+)
  let title = try await webView.evaluateJavaScript("document.title") as? String

  JS → Native — Message handlers

  // Swift side: register a handler
  let controller = webView.configuration.userContentController
  controller.add(self, name: "nativeAction")

  // Conform to WKScriptMessageHandler
  func userContentController(_ controller: WKScriptMessageHandler,
                             didReceive message: WKScriptMessage) {
      print(message.body) // whatever JS sent
  }

  // JS side: post a message
  window.webkit.messageHandlers.nativeAction.postMessage({
    action: "share",
    url: "https://example.com"
  });

  User scripts — inject JS at document start or end

  let script = WKUserScript(
      source: "window.isNativeApp = true;",
      injectionTime: .atDocumentStart,
      forMainFrameOnly: true
  )
  controller.addUserScript(script)

  2. Navigation & Delegates

  Two delegates control behavior:

  - WKNavigationDelegate — controls loading lifecycle:
    - decidePolicyFor navigationAction — intercept link clicks, block/allow URLs, handle deep links
    - didStartProvisionalNavigation, didFinish, didFail — track load progress
    - didReceive challenge — handle SSL/auth challenges
  - WKUIDelegate — handles UI events from web content:
    - createWebViewWith configuration — handle target="_blank" links
    - runJavaScriptAlertPanelWithMessage — custom alert/confirm/prompt dialogs

  func webView(_ webView: WKWebView,
               decidePolicyFor action: WKNavigationAction,
               decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
      if action.navigationType == .linkActivated,
         let url = action.request.url,
         url.host != "myapp.com" {
          UIApplication.shared.open(url)  // open external links in Safari
          decisionHandler(.cancel)
          return
      }
      decisionHandler(.allow)
  }

  3. Cookies & Storage

  let dataStore = webView.configuration.websiteDataStore
  let cookieStore = dataStore.httpCookieStore

  // Set a cookie before loading
  let cookie = HTTPCookie(properties: [
      .name: "session",
      .value: "abc123",
      .domain: "myapp.com",
      .path: "/",
      .secure: true
  ])!
  await cookieStore.setCookie(cookie)

  // Read all cookies
  let cookies = await cookieStore.allCookies()

  // Observe changes
  cookieStore.add(self)  // WKHTTPCookieStoreObserver

  Non-persistent (private browsing)

  let config = WKWebViewConfiguration()
  config.websiteDataStore = .nonPersistent()

  4. Custom URL Schemes

  Handle custom protocols like myapp:// for loading local resources:

  class MySchemeHandler: NSObject, WKURLSchemeHandler {
      func webView(_ webView: WKWebView, start task: WKURLSchemeTask) {
          // Read from bundle, database, etc.
          let data = loadResource(for: task.request.url!)
          let response = URLResponse(url: task.request.url!, mimeType: "text/html",
                                     expectedContentLength: data.count, textEncodingName: "utf-8")
          task.didReceive(response)
          task.didReceive(data)
          task.didFinish()
      }
      func webView(_ webView: WKWebView, stop task: WKURLSchemeTask) {}
  }

  config.setURLSchemeHandler(MySchemeHandler(), forURLScheme: "myapp")

  5. SwiftUI Integration (iOS 14+)

  No first-party WKWebView SwiftUI wrapper, so you use UIViewRepresentable:

  struct WebView: UIViewRepresentable {
      let url: URL

      func makeUIView(context: Context) -> WKWebView {
          let webView = WKWebView()
          webView.navigationDelegate = context.coordinator
          return webView
      }

      func updateUIView(_ webView: WKWebView, context: Context) {
          webView.load(URLRequest(url: url))
      }

      func makeCoordinator() -> Coordinator { Coordinator() }

      class Coordinator: NSObject, WKNavigationDelegate { ... }
  }

  6. Performance Tips

  - Reuse WKProcessPool across web views to share cookies/sessions.
  - Pre-warm a web view at app launch (create one off-screen) — the first WKWebView init is expensive.
  - Content rules (JSON blockers) are faster than intercepting requests in decidePolicyFor.
  - WKWebpagePreferences.allowsContentJavaScript — disable JS for static content to save resources.
