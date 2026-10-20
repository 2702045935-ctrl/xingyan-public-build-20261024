import SwiftUI
import UIKit
import WebKit

/* ============================================================
   星言内置浏览器

   和微信内置浏览器一样，网页一直在 App 里打开，不把用户甩到 Safari。
   支持地址/搜索、前进后退、刷新、分享，以及网页里的 alert / confirm / prompt。
   只有我们自己的服务器放行自签证书；其他网站仍走系统 TLS 校验。
   ============================================================ */

struct InAppBrowserView: View {
    @Environment(\.dismiss) private var dismiss

    var initialURL: String = "https://m.baidu.com/"

    @State private var address = ""
    @State private var title = "浏览器"
    @State private var progress: Double = 0
    @State private var loading = false
    @State private var canBack = false
    @State private var canForward = false
    @State private var currentURL: URL?
    @State private var reloadTick = 0
    @State private var showShare = false
    @FocusState private var editingAddress: Bool
    @State private var addressEditing = false

    var body: some View {
        VStack(spacing: 0) {
            NavBar(title: title.isEmpty ? Tr("浏览器") : title, back: { dismiss() }) {
                Button { reloadTick += 1 } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(C.label)
                        .frame(width: 42, height: 42)
                }
                .buttonStyle(.plain)
            }

            addressBar

            if loading {
                ProgressView(value: progress)
                    .tint(C.green)
                    .frame(height: 2)
            } else {
                Rectangle().fill(C.hairline).frame(height: 0.5)
            }

            BrowserWebView(
                initialURL: InAppBrowserView.normalizedURL(initialURL),
                reloadTick: reloadTick,
                title: $title,
                progress: $progress,
                loading: $loading,
                canBack: $canBack,
                canForward: $canForward,
                currentURL: $currentURL,
                address: $address,
                addressEditing: $addressEditing
            )

            toolbar
        }
        .background(C.pageBg.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .swipeBack { dismiss() }
        .hidesTabBar()
        .sheet(isPresented: $showShare) {
            if let u = currentURL {
                ShareSheet(items: [u])
            }
        }
    }

    private var addressBar: some View {
        HStack(spacing: 8) {
            Image(systemName: currentURL?.scheme == "https" ? "lock.fill" : "globe")
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundColor(C.subLabel)
            TextField(Tr("输入网址或搜索内容"), text: $address)
                .font(pf(14.5))
                .foregroundColor(C.label)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .keyboardType(.URL)
                .submitLabel(.go)
                .focused($editingAddress)
                .onChange(of: editingAddress) { focused in
                    addressEditing = focused
                }
                .onSubmit { reloadTick += 1 }
            if !address.isEmpty {
                Button {
                    address = ""
                    editingAddress = true
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 15))
                        .foregroundColor(C.searchIcon)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 11)
        .frame(height: 38)
        .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(C.searchBg))
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(C.pageBg)
    }

    private var toolbar: some View {
        HStack {
            toolbarButton("chevron.left", enabled: canBack) {
                BrowserCommands.shared.back()
            }
            Spacer()
            toolbarButton("chevron.right", enabled: canForward) {
                BrowserCommands.shared.forward()
            }
            Spacer()
            toolbarButton("house", enabled: true) {
                address = "https://m.baidu.com/"
                reloadTick += 1
            }
            Spacer()
            toolbarButton("square.and.arrow.up", enabled: currentURL != nil) {
                showShare = true
            }
        }
        .padding(.horizontal, 24)
        .frame(height: 50)
        .background(C.cardBg)
        .overlay(alignment: .top) {
            Rectangle().fill(C.hairline).frame(height: 0.5)
        }
    }

    private func toolbarButton(_ icon: String, enabled: Bool,
                               action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .medium))
                .foregroundColor(enabled ? C.label : C.time)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }

    static func normalizedURL(_ raw: String) -> URL? {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        if let direct = URL(string: text),
           let scheme = direct.scheme?.lowercased(),
           scheme == "http" || scheme == "https" {
            return direct
        }
        let looksLikeHost = text.contains(".") && !text.contains(" ")
        if looksLikeHost, let direct = URL(string: "https://" + text) {
            return direct
        }
        let q = text.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? text
        return URL(string: "https://m.baidu.com/s?word=" + q)
    }
}

/// 工具栏操作打到当前 WebView；页面只保留一个，所以单例足够。
final class BrowserCommands {
    static let shared = BrowserCommands()
    weak var web: WKWebView?

    func back() { web?.goBack() }
    func forward() { web?.goForward() }
}

private struct BrowserWebView: UIViewRepresentable {
    let initialURL: URL?
    let reloadTick: Int
    @Binding var title: String
    @Binding var progress: Double
    @Binding var loading: Bool
    @Binding var canBack: Bool
    @Binding var canForward: Bool
    @Binding var currentURL: URL?
    @Binding var address: String
    @Binding var addressEditing: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []
        config.defaultWebpagePreferences.allowsContentJavaScript = true

        let web = WKWebView(frame: .zero, configuration: config)
        web.navigationDelegate = context.coordinator
        web.uiDelegate = context.coordinator
        web.allowsBackForwardNavigationGestures = true
        web.isOpaque = false
        web.backgroundColor = .clear
        web.scrollView.backgroundColor = .clear
        web.scrollView.contentInsetAdjustmentBehavior = .automatic
        context.coordinator.web = web
        BrowserCommands.shared.web = web
        context.coordinator.observe(web)
        if let initialURL {
            web.load(URLRequest(url: initialURL))
        }
        return web
    }

    func updateUIView(_ web: WKWebView, context: Context) {
        guard context.coordinator.lastTick != reloadTick else { return }
        context.coordinator.lastTick = reloadTick
        guard let url = InAppBrowserView.normalizedURL(address) else { return }
        if web.url?.absoluteString == url.absoluteString {
            web.reload()
        } else {
            web.load(URLRequest(url: url))
        }
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
        private let parent: BrowserWebView
        weak var web: WKWebView?
        var lastTick = 0
        private var observations: [NSKeyValueObservation] = []

        init(_ parent: BrowserWebView) {
            self.parent = parent
        }

        func observe(_ web: WKWebView) {
            observations.append(web.observe(\.estimatedProgress, options: [.new]) { [weak self] view, _ in
                DispatchQueue.main.async {
                    self?.parent.progress = view.estimatedProgress
                }
            })
            observations.append(web.observe(\.canGoBack, options: [.new]) { [weak self] view, _ in
                DispatchQueue.main.async { self?.parent.canBack = view.canGoBack }
            })
            observations.append(web.observe(\.canGoForward, options: [.new]) { [weak self] view, _ in
                DispatchQueue.main.async { self?.parent.canForward = view.canGoForward }
            })
            observations.append(web.observe(\.url, options: [.new]) { [weak self] view, _ in
                DispatchQueue.main.async {
                    guard let url = view.url else { return }
                    self?.parent.currentURL = url
                    if self?.parent.addressEditing != true { self?.parent.address = url.absoluteString }
                }
            })
            observations.append(web.observe(\.title, options: [.new]) { [weak self] view, _ in
                DispatchQueue.main.async {
                    let t = (view.title ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                    self?.parent.title = t.isEmpty ? Tr("浏览器") : t
                }
            })
        }

        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            parent.loading = true
            parent.progress = max(0.02, parent.progress)
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            parent.loading = false
            parent.progress = 1
            parent.canBack = webView.canGoBack
            parent.canForward = webView.canGoForward
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            parent.loading = false
        }

        func webView(_ webView: WKWebView,
                     didFailProvisionalNavigation navigation: WKNavigation!,
                     withError error: Error) {
            parent.loading = false
        }

        func webView(_ webView: WKWebView,
                     didReceive challenge: URLAuthenticationChallenge,
                     completionHandler: @escaping (URLSession.AuthChallengeDisposition,
                                                   URLCredential?) -> Void) {
            guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
                  API.trustedHost(challenge.protectionSpace.host),
                  let trust = challenge.protectionSpace.serverTrust else {
                completionHandler(.performDefaultHandling, nil)
                return
            }
            completionHandler(.useCredential, URLCredential(trust: trust))
        }

        func webView(_ webView: WKWebView,
                     createWebViewWith configuration: WKWebViewConfiguration,
                     for navigationAction: WKNavigationAction,
                     windowFeatures: WKWindowFeatures) -> WKWebView? {
            if navigationAction.targetFrame == nil {
                webView.load(navigationAction.request)
            }
            return nil
        }

        func webView(_ webView: WKWebView,
                     runJavaScriptAlertPanelWithMessage message: String,
                     initiatedByFrame frame: WKFrameInfo,
                     completionHandler: @escaping () -> Void) {
            let alert = UIAlertController(title: webView.url?.host, message: message,
                                          preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: Tr("知道了"), style: .default) { _ in
                completionHandler()
            })
            topController()?.present(alert, animated: true)
        }

        func webView(_ webView: WKWebView,
                     runJavaScriptConfirmPanelWithMessage message: String,
                     initiatedByFrame frame: WKFrameInfo,
                     completionHandler: @escaping (Bool) -> Void) {
            let alert = UIAlertController(title: webView.url?.host, message: message,
                                          preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: Tr("取消"), style: .cancel) { _ in
                completionHandler(false)
            })
            alert.addAction(UIAlertAction(title: Tr("确定"), style: .default) { _ in
                completionHandler(true)
            })
            topController()?.present(alert, animated: true)
        }

        func webView(_ webView: WKWebView,
                     runJavaScriptTextInputPanelWithPrompt prompt: String,
                     defaultText: String?,
                     initiatedByFrame frame: WKFrameInfo,
                     completionHandler: @escaping (String?) -> Void) {
            let alert = UIAlertController(title: webView.url?.host, message: prompt,
                                          preferredStyle: .alert)
            alert.addTextField { field in field.text = defaultText }
            alert.addAction(UIAlertAction(title: Tr("取消"), style: .cancel) { _ in
                completionHandler(nil)
            })
            alert.addAction(UIAlertAction(title: Tr("确定"), style: .default) { _ in
                completionHandler(alert.textFields?.first?.text)
            })
            topController()?.present(alert, animated: true)
        }

        private func topController() -> UIViewController? {
            var controller = UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .flatMap { $0.windows }
                .first(where: { $0.isKeyWindow })?.rootViewController
            while let presented = controller?.presentedViewController {
                controller = presented
            }
            return controller
        }
    }
}
