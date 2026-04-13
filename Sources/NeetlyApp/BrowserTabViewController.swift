import AppKit
import WebKit

class BrowserTabViewController: NSViewController, WKNavigationDelegate, WKUIDelegate {
    let tabId = UUID()
    let seqId = SeqCounter.shared.nextId()
    let initialURL: String
    private(set) var webView: WKWebView!
    private var urlBar: NSTextField!
    private(set) var currentTitle: String = "Browser"
    private(set) var favicon: NSImage?
    private(set) var hasCompletedInitialLoad = false
    private var retryTimer: DispatchSourceTimer?
    /// Used when WebKit asks to create a new webview (target=_blank links).
    /// The pane provides a preinstalled WKWebView from WebKit's configuration.
    private var preinstalledWebView: WKWebView?
    /// Callback when title or favicon changes, so the pane can refresh the tab bar.
    var onTitleChanged: (() -> Void)?
    /// Called when the page wants to open a link in a new tab (target=_blank).
    /// The pane creates a new BrowserTabViewController using the provided webView.
    var onRequestNewTab: ((WKWebView) -> Void)?

    init(url: String, preinstalledWebView: WKWebView? = nil) {
        self.initialURL = url
        self.preinstalledWebView = preinstalledWebView
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func loadView() {
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 800, height: 600))

        // URL bar
        urlBar = NSTextField()
        urlBar.stringValue = initialURL
        urlBar.font = .systemFont(ofSize: 13)
        urlBar.placeholderString = "Enter URL..."
        urlBar.target = self
        urlBar.action = #selector(urlBarAction)
        urlBar.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(urlBar)

        let backButton = NSButton(image: NSImage(systemSymbolName: "chevron.left", accessibilityDescription: "Back")!,
                                  target: self, action: #selector(goBack))
        backButton.bezelStyle = .recessed
        backButton.toolTip = "Back"
        backButton.imagePosition = .imageOnly
        backButton.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(backButton)

        let forwardButton = NSButton(image: NSImage(systemSymbolName: "chevron.right", accessibilityDescription: "Forward")!,
                                     target: self, action: #selector(goForward))
        forwardButton.bezelStyle = .recessed
        forwardButton.toolTip = "Forward"
        forwardButton.imagePosition = .imageOnly
        forwardButton.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(forwardButton)

        let reloadButton = NSButton(title: "R", target: self, action: #selector(reload))
        reloadButton.bezelStyle = .recessed
        reloadButton.toolTip = "Reload"
        reloadButton.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(reloadButton)

        // Web view — use preinstalled one (from a target=_blank link) or create fresh
        if let pre = preinstalledWebView {
            webView = pre
        } else {
            let config = WKWebViewConfiguration()
            webView = WKWebView(frame: .zero, configuration: config)
        }
        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.translatesAutoresizingMaskIntoConstraints = false
        webView.addObserver(self, forKeyPath: "URL", options: [.new], context: nil)

        // Expose to Safari's Web Inspector.
        if #available(macOS 13.3, *) {
            webView.isInspectable = true
        } else {
            webView.configuration.preferences.setValue(true, forKey: "developerExtrasEnabled")
        }

        container.addSubview(webView)

        NSLayoutConstraint.activate([
            backButton.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 4),
            backButton.topAnchor.constraint(equalTo: container.topAnchor, constant: 4),
            backButton.widthAnchor.constraint(equalToConstant: 28),
            backButton.heightAnchor.constraint(equalToConstant: 24),

            forwardButton.leadingAnchor.constraint(equalTo: backButton.trailingAnchor, constant: 2),
            forwardButton.topAnchor.constraint(equalTo: container.topAnchor, constant: 4),
            forwardButton.widthAnchor.constraint(equalToConstant: 28),
            forwardButton.heightAnchor.constraint(equalToConstant: 24),

            reloadButton.leadingAnchor.constraint(equalTo: forwardButton.trailingAnchor, constant: 2),
            reloadButton.topAnchor.constraint(equalTo: container.topAnchor, constant: 4),
            reloadButton.widthAnchor.constraint(equalToConstant: 28),
            reloadButton.heightAnchor.constraint(equalToConstant: 24),

            urlBar.leadingAnchor.constraint(equalTo: reloadButton.trailingAnchor, constant: 4),
            urlBar.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -4),
            urlBar.topAnchor.constraint(equalTo: container.topAnchor, constant: 4),
            urlBar.heightAnchor.constraint(equalToConstant: 24),

            webView.topAnchor.constraint(equalTo: urlBar.bottomAnchor, constant: 4),
            webView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            webView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])

        view = container
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        if preinstalledWebView != nil {
            // WebKit will load the target URL into this webView itself — do nothing.
        } else if initialURL.isEmpty {
            // Focus the URL bar so user can type
            DispatchQueue.main.async { [weak self] in
                self?.view.window?.makeFirstResponder(self?.urlBar)
            }
        } else {
            navigate(to: initialURL)
            startInitialLoadRetry()
        }
    }

    /// Retry the initial load every 3 seconds until it succeeds. Useful when the
    /// dev server is still booting when the browser tab is opened via `neetly visit`.
    private func startInitialLoadRetry() {
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + 3, repeating: 3.0)
        timer.setEventHandler { [weak self] in
            guard let self else { return }
            if self.hasCompletedInitialLoad {
                self.retryTimer?.cancel()
                self.retryTimer = nil
                return
            }
            NSLog("BrowserTab: retrying initial load for \(self.initialURL)")
            self.navigate(to: self.initialURL)
        }
        timer.resume()
        retryTimer = timer
    }

    @objc private func urlBarAction() {
        navigate(to: urlBar.stringValue)
    }

    @objc private func goBack() {
        webView.goBack()
    }

    @objc private func goForward() {
        webView.goForward()
    }

    @objc private func reload() {
        if webView.url != nil {
            webView.reloadFromOrigin()
        } else {
            // Initial load never succeeded — navigate fresh
            navigate(to: urlBar.stringValue.isEmpty ? initialURL : urlBar.stringValue)
        }
    }

    /// Force reload — same as clicking R. Skips if initial load hasn't completed.
    @objc func forceReload() {
        guard hasCompletedInitialLoad else { return }
        webView.reloadFromOrigin()
    }

    func navigate(to urlString: String) {
        var str = urlString.trimmingCharacters(in: .whitespaces)
        if !str.hasPrefix("http://") && !str.hasPrefix("https://") {
            str = "https://" + str
        }
        guard let url = URL(string: str) else { return }
        webView.load(URLRequest(url: url))
        urlBar.stringValue = str
    }

    // MARK: - WKNavigationDelegate

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        let nsError = error as NSError
        if nsError.code == NSURLErrorCancelled {
            // Reload was cancelled by a competing navigation — retry after a short delay
            NSLog("BrowserTab: reload cancelled, retrying in 1s")
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
                self?.webView.reloadFromOrigin()
            }
            return
        }
        NSLog("BrowserTab: provisional navigation failed: \(error)")
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        let nsError = error as NSError
        if nsError.code == NSURLErrorCancelled { return }  // handled above
        NSLog("BrowserTab: navigation failed: \(error)")
    }

    /// Handle target="_blank" links: WebKit sometimes sends them here with
    /// targetFrame == nil without calling createWebViewWith. We spawn a new tab.
    func webView(_ webView: WKWebView,
                 decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        if navigationAction.targetFrame == nil,
           let url = navigationAction.request.url {
            // Open in a new tab via the pane
            let newWebView = WKWebView(frame: .zero, configuration: webView.configuration)
            onRequestNewTab?(newWebView)
            newWebView.load(URLRequest(url: url))
            decisionHandler(.cancel)
            return
        }
        decisionHandler(.allow)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        hasCompletedInitialLoad = true
        if let url = webView.url?.absoluteString {
            urlBar.stringValue = url
        }
        currentTitle = shortTitle(from: webView.title, url: webView.url)
        fetchFavicon(for: webView.url)
        onTitleChanged?()
    }

    // MARK: - WKUIDelegate

    /// Called when a page wants to open a link in a new tab (target="_blank" or
    /// window.open). We create a new webview with the same configuration, hand it
    /// to the pane to wrap in a new BrowserTabViewController, and return it so
    /// WebKit loads the target URL into it automatically.
    func webView(_ webView: WKWebView,
                 createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction,
                 windowFeatures: WKWindowFeatures) -> WKWebView? {
        let newWebView = WKWebView(frame: .zero, configuration: configuration)
        onRequestNewTab?(newWebView)
        return newWebView
    }

    /// Build a short tab title: first two words of the page title, or the hostname.
    private func shortTitle(from title: String?, url: URL?) -> String {
        if let title = title, !title.isEmpty {
            let words = title.split(separator: " ").prefix(2)
            return words.joined(separator: " ")
        }
        return url?.host ?? "Browser"
    }

    /// Fetch /favicon.ico from the site's origin.
    private func fetchFavicon(for url: URL?) {
        guard let url = url,
              let scheme = url.scheme,
              let host = url.host,
              let faviconURL = URL(string: "\(scheme)://\(host)/favicon.ico") else { return }

        URLSession.shared.dataTask(with: faviconURL) { [weak self] data, response, _ in
            guard let data = data,
                  let http = response as? HTTPURLResponse,
                  http.statusCode == 200,
                  let image = NSImage(data: data) else { return }
            DispatchQueue.main.async {
                self?.favicon = image
                self?.onTitleChanged?()
            }
        }.resume()
    }

    // MARK: - KVO

    override func observeValue(
        forKeyPath keyPath: String?,
        of object: Any?,
        change: [NSKeyValueChangeKey : Any]?,
        context: UnsafeMutableRawPointer?
    ) {
        if keyPath == "URL", let url = webView.url?.absoluteString {
            urlBar.stringValue = url
        }
    }

    deinit {
        webView?.removeObserver(self, forKeyPath: "URL")
        retryTimer?.cancel()
    }
}
