import SwiftUI
import UIKit
import WebKit

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
    @State private var showMenu = false
    @State private var showAddress = false
    @FocusState private var editingAddress: Bool
    @State private var addressEditing = false

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .topTrailing) {
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
                .ignoresSafeArea()

                if loading {
                    ProgressView(value: progress)
                        .tint(C.green)
                        .frame(height: 2)
                        .frame(maxWidth: .infinity)
                        .padding(.top, geo.safeAreaInsets.top)
                        .allowsHitTesting(false)
                }

                if showAddress {
                    addressOverlay(top: geo.safeAreaInsets.top)
                        .padding(.horizontal, 12)
                } else {
                    floatingControls(top: geo.safeAreaInsets.top)
                        .padding(.trailing, 10)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.white)
        }
        .background(Color.white.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .statusBarHidden(true)
        .persistentSystemOverlays(.hidden)
        .swipeBack { dismiss() }
        .hidesTabBar()
        .confirmationDialog(title.isEmpty ? Tr("浏览器") : title,
                            isPresented: $showMenu,
                            titleVisibility: .visible) {
            Button(Tr("输入网址")) { showAddress = true }
            Button(Tr("后退")) { BrowserCommands.shared.back() }
                .disabled(!canBack)
            Button(Tr("前进")) { BrowserCommands.shared.forward() }
                .disabled(!canForward)
            Button(Tr("刷新")) { BrowserCommands.shared.reload() }
            if currentURL != nil {
                Button(Tr("复制链接")) {
                    if let url = currentURL { UIPasteboard.general.url = url }
                }
                Button(Tr("分享")) {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
                        showShare = true
                    }
                }
                Button(Tr("用 Safari 打开")) {
                    if let url = currentURL { UIApplication.shared.open(url) }
                }
            }
            Button(Tr("关闭浏览器"), role: .destructive) { dismiss() }
            Button(Tr("取消"), role: .cancel) { }
        }
        .sheet(isPresented: $showShare) {
            if let u = currentURL {
                ShareSheet(items: [u])
            }
        }
        .onChange(of: showAddress) { visible in
            if visible {
                showMenu = false
                addressEditing = true
                editingAddress = true
            } else {
                addressEditing = false
                editingAddress = false
            }
        }
    }

    private func floatingControls(top: CGFloat) -> some View {
        GameWindowCapsule(
            onMenu: { showMenu = true },
            onClose: { dismiss() }
        )
        .padding(.top, max(6, top + 6))
    }

    private func addressOverlay(top: CGFloat) -> some View {
        HStack(spacing: 8) {
            Image(systemName: currentURL?.scheme == "https" ? "lock.fill" : "globe")
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundColor(.secondary)
            TextField(Tr("输入网址或搜索内容"), text: $address)
                .font(pf(14.5))
                .foregroundColor(.primary)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .keyboardType(.URL)
                .submitLabel(.go)
                .focused($editingAddress)
                .onSubmit { submitAddress() }
            if !address.isEmpty {
                Button {
                    address = ""
                    editingAddress = true
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 15))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            Button(Tr("关闭")) {
                showAddress = false
            }
            .font(pf(13.5, .medium))
            .foregroundColor(.secondary)
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 13)
        .frame(height: 42)
        .background(.ultraThinMaterial, in: Capsule(style: .continuous))
        .overlay(Capsule(style: .continuous).stroke(Color.white.opacity(0.3), lineWidth: 0.6))
        .shadow(color: .black.opacity(0.18), radius: 10, y: 4)
        .padding(.top, max(6, top + 6))
    }

    private func submitAddress() {
        addressEditing = false
        editingAddress = false
        showAddress = false
        reloadTick += 1
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

final class BrowserCommands {
    static let shared = BrowserCommands()
    weak var web: WKWebView?

    func back() { web?.goBack() }
    func forward() { web?.goForward() }
    func reload() { web?.reload() }
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
        web.allowsBackForwardNavigationGestures = false
        web.isOpaque = true
        web.backgroundColor = .white
        web.scrollView.backgroundColor = .white
        web.scrollView.isOpaque = true
        web.underPageBackgroundColor = .white
        web.scrollView.contentInsetAdjustmentBehavior = .never
        web.scrollView.keyboardDismissMode = .interactive
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

        func webView(_ webView: WKWebView,
                     decidePolicyFor navigationAction: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            if navigationAction.navigationType == .linkActivated,
               let url = navigationAction.request.url,
               ExternalLinkRouter.openIfNeeded(url) {
                decisionHandler(.cancel)
                return
            }
            decisionHandler(.allow)
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
                  let trust = challenge.protectionSpace.serverTrust else {
                completionHandler(.performDefaultHandling, nil)
                return
            }
            if ServerTrustPolicy.canAccept(trust, host: challenge.protectionSpace.host) {
                completionHandler(.useCredential, URLCredential(trust: trust))
            } else {
                completionHandler(.cancelAuthenticationChallenge, nil)
            }
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
