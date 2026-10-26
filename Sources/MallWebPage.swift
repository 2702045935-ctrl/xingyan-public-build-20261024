import SwiftUI
import WebKit

struct MallWebPage: View {
    @Environment(\.dismiss) private var dismiss

    var path: String = "/mall/index.html"
    var title: String = "拼多多商城"

    @State private var reloadTick = 0
    @State private var loading = true

    private var url: URL? {
        URL(string: API.shared.base + path + (path.contains("?") ? "&" : "?") + "v=\(reloadTick)")
    }

    var body: some View {
        VStack(spacing: 0) {
            NavBar(title: Tr(title), back: { dismiss() }) {
                Button {
                    reloadTick += 1
                    loading = true
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(C.label)
                        .frame(width: 40, height: 32)
                }
                .buttonStyle(.plain)
            }
            ZStack(alignment: .top) {
                if let u = url {
                    MallWebView(url: u, tick: reloadTick, loading: $loading)
                        .ignoresSafeArea(edges: .bottom)
                } else {
                    Text(Tr("商城地址不对")).font(pf(14)).foregroundColor(C.subLabel)
                }
                if loading {
                    ProgressView().padding(.top, 24)
                }
            }
        }
        .background(C.pageBg.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .swipeBack { dismiss() }
    }
}

struct MallWebView: UIViewRepresentable {
    let url: URL

    let tick: Int
    @Binding var loading: Bool

    func makeUIView(context: Context) -> WKWebView {
        let cfg = WKWebViewConfiguration()
        cfg.allowsInlineMediaPlayback = true
        cfg.mediaTypesRequiringUserActionForPlayback = []
        let v = WKWebView(frame: .zero, configuration: cfg)
        v.navigationDelegate = context.coordinator
        v.isOpaque = false
        v.backgroundColor = .clear
        v.scrollView.bounces = false
        v.scrollView.contentInsetAdjustmentBehavior = .never
        v.load(URLRequest(url: url))
        context.coordinator.lastTick = tick
        return v
    }

    func updateUIView(_ v: WKWebView, context: Context) {

        if context.coordinator.lastTick != tick {
            context.coordinator.lastTick = tick
            v.load(URLRequest(url: url))
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(loading: $loading) }

    final class Coordinator: NSObject, WKNavigationDelegate {
        var lastTick = 0
        let loading: Binding<Bool>
        init(loading: Binding<Bool>) { self.loading = loading }

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
                completionHandler(.performDefaultHandling, nil)
            }
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            DispatchQueue.main.async { self.loading.wrappedValue = false }
        }
        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            DispatchQueue.main.async { self.loading.wrappedValue = false }
        }
        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!,
                     withError error: Error) {
            DispatchQueue.main.async { self.loading.wrappedValue = false }
        }
    }
}
