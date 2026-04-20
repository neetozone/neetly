# neetly

The code editor that works with agents and is meant for **web development**.

<p align="center">
  <a href="https://github.com/neetozone/neetly/releases/latest/download/neetly-macos.dmg">
    <img src="./docs/assets/macos-badge.png" alt="Download neetly for macOS" width="180" />
  </a>
</p>

## Installation instructions

1. Download [neetly-macos.dmg](https://github.com/neetozone/neetly/releases/latest/download/neetly-macos.dmg) and open the DMG and drag `neetly.app` to Applications.
2. Set up Claude Code notifications (one-time): Execute the following command to do a one-time setup. It adds hooks to `~/.claude/settings.json` so that neetly
   is notified when Claude is done processing and is waiting. When Claude is done, the workspace tab turns "green". 
    If Claude is waiting for permission, then the workspace tab turns "red". Clicking a colored workspace tab also clears the color.

   ```bash
   /Applications/neetly.app/Contents/MacOS/neetly notify_neetly_of_claude_events
   ```
   
3. Open neetly from Applications.
   > macOS may block the first launch with an "unidentified developer" warning (Gatekeeper).
   > To bypass: right-click `neetly.app` → Open → Open, or run `xattr -dr com.apple.quarantine /Applications/neetly.app` once.

### Build from source

```bash
git clone https://github.com/neetozone/neetly.git
cd neetly
swift build

# Symlink the CLI to your PATH
ln -sf $(pwd)/.build/arm64-apple-macosx/debug/neetly /usr/local/bin/neetly

# Run
swift run neetly-app
```

On first launch, add a repo and configure its default layout. Repos are persisted at `~/.config/neetly/repos.json`.

## Tech Stack

<p>
 <a href="https://www.swift.org/"><img src="https://img.shields.io/badge/Swift-F05138?logo=swift&logoColor=white" alt="Swift"></a>
 <a href="https://developer.apple.com/xcode/swiftui/"><img src="https://img.shields.io/badge/SwiftUI-0071E3?logo=swift&logoColor=white" alt="SwiftUI"></a>
 <a href="https://developer.apple.com/documentation/appkit"><img src="https://img.shields.io/badge/AppKit-333333?logo=apple&logoColor=white" alt="AppKit"></a>
 <a href="https://github.com/migueldeicaza/SwiftTerm"><img src="https://img.shields.io/badge/SwiftTerm-191970?logo=terminal&logoColor=white" alt="SwiftTerm"></a>
 <a href="https://developer.apple.com/documentation/webkit/wkwebview"><img src="https://img.shields.io/badge/WKWebView-006AFF?logo=safari&logoColor=white" alt="WKWebView"></a>
 <a href="https://developer.apple.com/swift/"><img src="https://img.shields.io/badge/Swift_Package_Manager-F05138?logo=swift&logoColor=white" alt="SPM"></a>
</p>

## Layout Config

Declarative pane layout using `split`, `tabs`, `run`, and `visit`:

```yaml
split: columns
left:
  run: claude --dangerously-skip-permissions
right:
  tabs:
    run: bin/setup;bin/launch --neetly
    visit: http://localhost:3000
```

| Key | Value | Children |
|---|---|---|
| `split` | `columns` | `left:` and `right:` |
| `split` | `rows` | `top:` and `bottom:` |
| `tabs` | — | Multiple `run`/`visit` as tabs in one pane |
| `run` | `<command>` | Terminal tab |
| `visit` | `<url>` | Browser tab |
| `size` | `35%` | Percentage of the parent split taken by this child. Optional; defaults to 50/50. |

### Sizing splits

By default, every split is 50/50. Add a `size` attribute to any child to change that:

```yaml
split: columns
left:
  size: 35%
  run: claude --dangerously-skip-permissions
right:
  run: bin/setup-mise;bin/launch --neetly
```

The left pane takes 35% of the width, the right pane takes the remaining 65%. If you specify sizes on both sides and they don't add up to 100%, the first one wins and the second gets the remainder — no error. `size` can appear in any child of a `split` (left/right/top/bottom) and nests naturally.

## CLI Commands

The `neetly` CLI runs from inside any terminal spawned by neetly. It communicates with the app via a Unix domain socket.

### List tabs

```bash
neetly tabs
```

```
TAB  PANE  TYPE      TITLE
--------------------------------------------------
1    1     terminal  claude *
2    2     terminal  bin/launch *
3    2     browser   localhost *
```

### Open a browser tab

```bash
# In current pane (default)
neetly browser open http://localhost:3000

# In a specific pane
neetly browser open http://localhost:3000 --pane 3

# Without stealing focus
neetly browser open http://localhost:3000 --background

# Short alias
neetly visit http://localhost:3000
```

### Send text to a terminal tab

```bash
# Send "time" + Enter to tab 1
neetly send 1 "time\n"
```

`\n` is converted to a newline (Enter key). `\t` is converted to a tab.

### Open a new terminal tab

```bash
neetly run "npm test"
```

### Workspace notifications

Change the workspace tab color to signal status across workspaces. Useful when Claude finishes a task while you're working in another workspace.

```bash
neetly notify              # green (task done)
neetly notify red          # red (needs permission)
neetly notify clear        # reset to normal
```

## Keyboard Shortcuts

| Shortcut | Action |
|---|---|
| Cmd+T | New terminal tab in focused pane |
| Cmd+Shift+T | New browser tab in focused pane |
| Cmd+W | Close active tab |
| Cmd+K | Clear terminal |
| Cmd+R | Reload browser |
| Cmd+Shift+] | Next tab |
| Cmd+Shift+[ | Previous tab |
| Cmd+Click | Open a URL displayed in the terminal |

## Taxonomy

```
Workspace (named after your feature/bug, multiple per window)
  Pane (a rectangular region, split horizontally or vertically)
    Tab (terminal or browser — multiple per pane, one visible at a time)
```

## Terminal Appearance

Customize the terminal font, size, and colors by creating `~/.config/neetly/terminal.json`:

```json
{
  "fontFamily": "JetBrains Mono",
  "fontSize": 17,
  "backgroundColor": "#1e1f2e",
  "foregroundColor": "#cdd8f4",
  "selectionColor": "#635b70",
  "linkColor": "#8bb8fa"
}
```

| Field | Description | Default |
|---|---|---|
| `fontFamily` | Any font installed on your system. Falls back to Symbols Nerd Font Mono, Noto Color Emoji, then system monospace. | `JetBrains Mono` |
| `fontSize` | Point size. | `17` |
| `backgroundColor` | Hex color (`#RRGGBB`). | `#1e1f2e` (Catppuccin base) |
| `foregroundColor` | Hex color (`#RRGGBB`). | `#cdd8f4` (Catppuccin text) |
| `selectionColor` | Background color for selected text. | `#635b70` |
| `linkColor` | Overrides ANSI palette blue (colors 4 and 12), where most terminals render URLs. | `#8bb8fa` |
| `scrollback` | Number of lines retained in the scroll-back buffer. | `10000` |

All fields are optional — omit any to use the default. The config is read when each terminal tab is created, so restart neetly to pick up changes.

## Architecture

- **Terminal**: [SwiftTerm](https://github.com/migueldeicaza/SwiftTerm) (pure Swift, CPU-rendered). In the future, we could swap it for [libghostty](https://github.com/ghostty-org/ghostty) (Ghostty's Zig-based engine with Metal GPU rendering) for better performance on 4K displays and large scrollback workloads. It's a "someday maybe" note, not anything planned.
- **Browser**: [WKWebView](https://developer.apple.com/documentation/webkit/wkwebview) is Apple's native web view — the same WebKit engine that powers Safari. It's built into macOS, so neetly ships with zero browser dependencies and no extra download (unlike Electron or CEF which bundle a full Chromium). Every browser tab in neetly is a `WKWebView` embedded directly in the window.

  **Debugging browser tabs with Safari's Web Inspector**: neetly enables `isInspectable` on all browser tabs, so you can use Safari's full Web Inspector (DOM, console, network, breakpoints) against them. One-time setup: Safari → Settings → Advanced → check "Show features for web developers". Then in Safari → Develop → (your Mac name), you'll see all of neetly's open browser tabs listed. Click one to attach the inspector.
- **IPC**: Unix domain socket at `/tmp/neetly-<pid>.sock`
- **Persistence**:
  - `~/.config/neetly/repos.json` — list of added repos and their default layouts
  - `~/.config/neetly/workspaces.json` — open workspaces, restored on relaunch
  - `~/.config/neetly/terminal.json` — terminal font and color overrides
  - `~/neetly/<repo-name>/<workspace-name>` — git worktrees are created here, one per workspace
- **File watcher**: WKWebView (WebKit) does not support HMR (Hot Module Replacement) the way Chrome's DevTools protocol does, so neetly polls the repo every 2 seconds for changes to JavaScript/React/CSS files and triggers a browser reload when anything changes.

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

