import SafariServices
import SwiftUI
import UIKit
import WebKit

struct ScannedWebBrowserView: UIViewControllerRepresentable {
    let url: URL
    let onClose: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onClose: onClose)
    }

    func makeUIViewController(context: Context) -> SFSafariViewController {
        let configuration = SFSafariViewController.Configuration()
        configuration.entersReaderIfAvailable = false
        configuration.barCollapsingEnabled = true

        let browser = SFSafariViewController(
            url: url,
            configuration: configuration
        )
        browser.delegate = context.coordinator
        browser.dismissButtonStyle = .close
        browser.preferredControlTintColor = UIColor(C.green)
        browser.modalPresentationStyle = .fullScreen
        return browser
    }

    func updateUIViewController(
        _ controller: SFSafariViewController,
        context: Context
    ) {}

    final class Coordinator: NSObject, SFSafariViewControllerDelegate {
        private let onClose: () -> Void

        init(onClose: @escaping () -> Void) {
            self.onClose = onClose
        }

        func safariViewControllerDidFinish(
            _ controller: SFSafariViewController
        ) {
            onClose()
        }
    }
}

private struct BrowserTab: Identifiable, Equatable {
    let id: UUID
    var url: URL?
    var title: String
    var isPrivate: Bool

    init(url: URL? = nil, title: String = Tr("新标签页"),
         isPrivate: Bool = false) {
        id = UUID()
        self.url = url
        self.title = title
        self.isPrivate = isPrivate
    }
}

private struct BrowserVisit: Codable, Identifiable, Hashable {
    let id: UUID
    let title: String
    let url: String
    let visitedAt: Date

    var link: URL? { URL(string: url) }
}

private struct BrowserBookmark: Codable, Identifiable, Hashable {
    let id: UUID
    let title: String
    let url: String
    let createdAt: Date

    var link: URL? { URL(string: url) }
}

private final class BrowserDataStore: ObservableObject {
    @Published private(set) var history: [BrowserVisit] = []
    @Published private(set) var bookmarks: [BrowserBookmark] = []

    private let historyKey = "xingyan.browser.history.v1"
    private let bookmarkKey = "xingyan.browser.bookmarks.v1"

    init() {
        if let data = UserDefaults.standard.data(forKey: historyKey),
           let values = try? JSONDecoder().decode(
               [BrowserVisit].self,
               from: data
           ) {
            history = values
        }
        if let data = UserDefaults.standard.data(forKey: bookmarkKey),
           let values = try? JSONDecoder().decode(
               [BrowserBookmark].self,
               from: data
           ) {
            bookmarks = values
        }
    }

    func record(url: URL, title: String) {
        guard ["http", "https"].contains(url.scheme?.lowercased() ?? "") else {
            return
        }
        let clean = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let value = clean.isEmpty ? (url.host ?? url.absoluteString) : clean
        history.removeAll { $0.url == url.absoluteString }
        history.insert(
            BrowserVisit(
                id: UUID(),
                title: value,
                url: url.absoluteString,
                visitedAt: Date()
            ),
            at: 0
        )
        history = Array(history.prefix(200))
        save(history, key: historyKey)
    }

    func toggleBookmark(url: URL, title: String) {
        if isBookmarked(url) {
            bookmarks.removeAll { $0.url == url.absoluteString }
        } else {
            let clean = title.trimmingCharacters(
                in: .whitespacesAndNewlines
            )
            bookmarks.insert(
                BrowserBookmark(
                    id: UUID(),
                    title: clean.isEmpty
                        ? (url.host ?? url.absoluteString) : clean,
                    url: url.absoluteString,
                    createdAt: Date()
                ),
                at: 0
            )
        }
        save(bookmarks, key: bookmarkKey)
    }

    func isBookmarked(_ url: URL?) -> Bool {
        guard let url else { return false }
        return bookmarks.contains { $0.url == url.absoluteString }
    }

    func clearHistory() {
        history = []
        UserDefaults.standard.removeObject(forKey: historyKey)
    }

    private func save<T: Encodable>(_ value: T, key: String) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }
}

struct InAppBrowserView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme

    let initialURL: String

    @StateObject private var dataStore = BrowserDataStore()
    @State private var tabs: [BrowserTab]
    @State private var activeTabID: UUID
    @State private var address: String
    @State private var title = Tr("浏览器")
    @State private var progress: Double = 0
    @State private var loading = false
    @State private var canBack = false
    @State private var canForward = false
    @State private var currentURL: URL?
    @State private var reloadTick = 0
    @State private var showShare = false
    @State private var showMenu = false
    @State private var showAddress = false
    @State private var showTabs = false
    @State private var showFind = false
    @State private var showHistory = false
    @State private var showBookmarks = false
    @State private var showReader = false
    @State private var readerTitle = ""
    @State private var readerText = ""
    @State private var findText = ""
    @State private var desktopMode = false
    @State private var loadError = ""
    @FocusState private var editingAddress: Bool
    @State private var addressEditing = false

    init(initialURL: String = "https://m.baidu.com/") {
        self.initialURL = initialURL
        let url = Self.normalizedURL(initialURL)
        let tab = BrowserTab(url: url, title: Tr("浏览器"))
        _tabs = State(initialValue: [tab])
        _activeTabID = State(initialValue: tab.id)
        _address = State(initialValue: url?.absoluteString ?? "")
        _currentURL = State(initialValue: url)
    }

    private var activeTab: BrowserTab {
        tabs.first(where: { $0.id == activeTabID }) ?? tabs[0]
    }

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .topTrailing) {
                BrowserWebView(
                    initialURL: activeTab.url,
                    reloadTick: reloadTick,
                    privateMode: activeTab.isPrivate,
                    title: $title,
                    progress: $progress,
                    loading: $loading,
                    canBack: $canBack,
                    canForward: $canForward,
                    currentURL: $currentURL,
                    address: $address,
                    addressEditing: $addressEditing,
                    loadError: $loadError,
                    onVisit: recordVisit,
                    onNewWindow: { url in
                        openTab(url: url, privateMode: activeTab.isPrivate)
                    }
                )
                .id(activeTabID)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .ignoresSafeArea()

                if loading {
                    ProgressView(value: progress)
                        .tint(C.green)
                        .frame(height: 2)
                        .frame(maxWidth: .infinity)
                        .padding(.top, geo.safeAreaInsets.top)
                        .allowsHitTesting(false)
                }

                if shouldShowStartPage {
                    BrowserStartPage(
                        history: dataStore.history,
                        bookmarks: dataStore.bookmarks,
                        onOpen: openURL,
                        onAddress: {
                            showAddress = true
                            addressEditing = true
                            editingAddress = true
                        },
                        onPrivate: { openTab(privateMode: true) }
                    )
                    .padding(.top, geo.safeAreaInsets.top)
                    .padding(.bottom, geo.safeAreaInsets.bottom + 76)
                }

                if showAddress {
                    addressOverlay(top: geo.safeAreaInsets.top)
                        .padding(.horizontal, AppDesign.Spacing.sm)
                } else {
                    floatingControls(top: geo.safeAreaInsets.top)
                        .padding(.trailing, 10)
                }

                if showFind {
                    findOverlay(top: geo.safeAreaInsets.top)
                        .padding(.horizontal, AppDesign.Spacing.sm)
                }

                VStack {
                    Spacer()
                    bottomToolbar(bottom: geo.safeAreaInsets.bottom)
                }

                if !loadError.isEmpty {
                    browserError
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
        .confirmationDialog(
            title,
            isPresented: $showMenu,
            titleVisibility: .visible
        ) {
            Button(Tr("新建标签页")) { openTab() }
            Button(Tr("新建无痕标签页")) { openTab(privateMode: true) }
            Button(Tr("输入网址")) { showAddress = true }
            Button(Tr("后退")) { BrowserCommands.shared.back() }
                .disabled(!canBack)
            Button(Tr("前进")) { BrowserCommands.shared.forward() }
                .disabled(!canForward)
            Button(Tr("刷新")) { BrowserCommands.shared.reload() }
            Button(Tr("页内查找")) { showFind = true }
            Button(Tr("阅读模式")) { openReader() }
            Button(desktopMode ? Tr("关闭桌面网页") : Tr("请求桌面网页")) {
                desktopMode.toggle()
                BrowserCommands.shared.setDesktopMode(desktopMode)
            }
            if let currentURL {
                Button(dataStore.isBookmarked(currentURL)
                       ? Tr("取消收藏") : Tr("收藏此页")) {
                    dataStore.toggleBookmark(url: currentURL, title: title)
                }
                Button(Tr("复制链接")) {
                    UIPasteboard.general.url = currentURL
                }
                Button(Tr("分享")) {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
                        showShare = true
                    }
                }
                Button(Tr("用 Safari 打开")) {
                    UIApplication.shared.open(currentURL)
                }
            }
            Button(Tr("历史记录")) { showHistory = true }
            Button(Tr("书签")) { showBookmarks = true }
            Button(Tr("关闭浏览器"), role: .destructive) { dismiss() }
            Button(Tr("取消"), role: .cancel) { }
        }
        .sheet(isPresented: $showShare) {
            if let currentURL {
                ShareSheet(items: [currentURL])
            }
        }
        .sheet(isPresented: $showTabs) {
            BrowserTabsSheet(
                tabs: $tabs,
                active: $activeTabID,
                onSelect: selectTab,
                onClose: closeTab,
                onNew: { openTab() },
                onPrivate: { openTab(privateMode: true) }
            )
        }
        .sheet(isPresented: $showHistory) {
            BrowserHistorySheet(store: dataStore, onOpen: openURL)
        }
        .sheet(isPresented: $showBookmarks) {
            BrowserBookmarksSheet(store: dataStore, onOpen: openURL)
        }
        .sheet(isPresented: $showReader) {
            BrowserReaderSheet(title: readerTitle, text: readerText)
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
        .onChange(of: title) { value in
            updateActiveTab { tab in
                tab.title = value
            }
        }
        .onChange(of: currentURL) { url in
            updateActiveTab { tab in
                tab.url = url
                if let host = url?.host { tab.title = host }
            }
        }
    }

    private var shouldShowStartPage: Bool {
        currentURL == nil && !loading && loadError.isEmpty
    }

    private func floatingControls(top: CGFloat) -> some View {
        GameWindowCapsule(
            onMenu: { showMenu = true },
            onClose: { dismiss() }
        )
        .padding(.top, max(6, top + 6))
    }

    private var browserError: some View {
        VStack(spacing: AppDesign.Spacing.sm) {
            Image(systemName: "wifi.exclamationmark")
                .font(.system(size: 30))
                .foregroundColor(C.subLabel)
            Text(Tr("网页暂时没准备好"))
                .font(pf(17, .semibold))
                .foregroundColor(C.label)
            Text(loadError)
                .font(AppDesign.Typography.caption)
                .foregroundColor(C.subLabel)
                .multilineTextAlignment(.center)
                .lineLimit(3)
            HStack(spacing: 10) {
                Button(Tr("重试")) {
                    loadError = ""
                    reloadTick += 1
                }
                .buttonStyle(.plain)
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .frame(height: AppDesign.Control.searchHeight)
                .background(Capsule().fill(C.green))

                if let currentURL {
                    Button(Tr("用 Safari 打开")) {
                        UIApplication.shared.open(currentURL)
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(C.label)
                    .frame(maxWidth: .infinity)
                    .frame(height: AppDesign.Control.searchHeight)
                    .background(Capsule().fill(C.cardBg))
                }
            }
        }
        .padding(18)
        .frame(maxWidth: 320)
        .background { CardGlassBox(radius: 18) }
        .padding(.horizontal, AppDesign.Spacing.xl)
    }

    private func addressOverlay(top: CGFloat) -> some View {
        HStack(spacing: AppDesign.Spacing.xs) {
            Image(systemName: currentURL?.scheme == "https"
                  ? "lock.fill" : "globe")
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
            Button(Tr("关闭")) { showAddress = false }
                .font(AppDesign.Typography.bodyMedium)
                .foregroundColor(.secondary)
                .buttonStyle(.plain)
        }
        .padding(.horizontal, 13)
        .frame(height: AppDesign.Control.searchHeight)
        .background(.ultraThinMaterial, in: Capsule(style: .continuous))
        .overlay(
            Capsule(style: .continuous)
                .stroke(Color.white.opacity(0.3), lineWidth: 0.6)
        )
        .shadow(color: .black.opacity(0.18), radius: 10, y: 4)
        .padding(.top, max(6, top + 6))
    }

    private func findOverlay(top: CGFloat) -> some View {
        HStack(spacing: AppDesign.Spacing.xs) {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.secondary)
            TextField(Tr("在页面中查找"), text: $findText)
                .font(pf(14))
                .submitLabel(.search)
                .onSubmit {
                    BrowserCommands.shared.find(findText)
                }
            Button {
                BrowserCommands.shared.find(findText)
            } label: {
                Image(systemName: "chevron.down")
            }
            .buttonStyle(.plain)
            .disabled(findText.isEmpty)
            Button(Tr("关闭")) {
                showFind = false
                findText = ""
            }
            .font(AppDesign.Typography.compactButtonMedium)
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 13)
        .frame(height: AppDesign.Control.searchHeight)
        .background(.regularMaterial, in: Capsule())
        .padding(.top, max(58, top + 56))
    }

    private func bottomToolbar(bottom: CGFloat) -> some View {
        HStack(spacing: 14) {
            Button {
                BrowserCommands.shared.back()
            } label: {
                Image(systemName: "chevron.left")
            }
            .disabled(!canBack)

            Button {
                BrowserCommands.shared.forward()
            } label: {
                Image(systemName: "chevron.right")
            }
            .disabled(!canForward)

            Spacer(minLength: 0)

            Button {
                showAddress = true
            } label: {
                HStack(spacing: 6) {
                    if activeTab.isPrivate {
                        Image(systemName: "eye.slash.fill")
                            .font(.system(size: 10.5, weight: .semibold))
                    }
                    Text(displayAddress)
                        .lineLimit(1)
                }
                .font(AppDesign.Typography.captionMedium)
                .foregroundStyle(.primary)
                .padding(.horizontal, AppDesign.Spacing.sm)
                .frame(maxWidth: 220)
                .frame(height: 34)
                .background(Color.primary.opacity(0.06), in: Capsule())
            }
            .buttonStyle(.plain)

            Spacer(minLength: 0)

            Button {
                showTabs = true
            } label: {
                ZStack {
                    Image(systemName: "square.on.square")
                    Text("\(tabs.count)")
                        .font(.system(size: 8, weight: .bold))
                        .offset(y: 1)
                }
            }
            .accessibilityLabel(Tr("标签页"))

            Button {
                showMenu = true
            } label: {
                Image(systemName: "ellipsis")
            }
            .accessibilityLabel(Tr("浏览器菜单"))
        }
        .font(.system(size: 17, weight: .semibold))
        .foregroundStyle(.primary)
        .padding(.horizontal, 18)
        .frame(height: AppDesign.Control.menuRowHeight)
        .background(.regularMaterial, in: Capsule())
        .overlay {
            Capsule().stroke(
                Color.white.opacity(scheme == .dark ? 0.13 : 0.45),
                lineWidth: 0.6
            )
        }
        .shadow(color: .black.opacity(0.18), radius: 16, y: 7)
        .padding(.horizontal, AppDesign.Spacing.sm)
        .padding(.bottom, max(8, bottom + 4))
    }

    private var displayAddress: String {
        if activeTab.isPrivate {
            return currentURL?.host ?? Tr("无痕浏览")
        }
        return currentURL?.host ?? title
    }

    private func submitAddress() {
        guard let url = Self.normalizedURL(address) else { return }
        addressEditing = false
        editingAddress = false
        showAddress = false
        updateActiveTab { tab in tab.url = url }
        currentURL = url
        address = url.absoluteString
        reloadTick += 1
    }

    private func openURL(_ url: URL) {
        updateActiveTab { tab in tab.url = url }
        currentURL = url
        address = url.absoluteString
        reloadTick += 1
    }

    private func openTab(url: URL? = nil, privateMode: Bool = false) {
        let tab = BrowserTab(
            url: url,
            title: url?.host ?? (privateMode
                ? Tr("无痕标签页") : Tr("新标签页")),
            isPrivate: privateMode
        )
        tabs.append(tab)
        activeTabID = tab.id
        title = tab.title
        currentURL = tab.url
        address = tab.url?.absoluteString ?? ""
        canBack = false
        canForward = false
        reloadTick += 1
    }

    private func selectTab(_ id: UUID) {
        guard let tab = tabs.first(where: { $0.id == id }) else { return }
        activeTabID = id
        title = tab.title
        currentURL = tab.url
        address = tab.url?.absoluteString ?? ""
        canBack = false
        canForward = false
        showTabs = false
        reloadTick += 1
    }

    private func closeTab(_ id: UUID) {
        guard let index = tabs.firstIndex(where: { $0.id == id }) else {
            return
        }
        tabs.remove(at: index)
        if tabs.isEmpty {
            let tab = BrowserTab()
            tabs = [tab]
            activeTabID = tab.id
        } else if activeTabID == id {
            activeTabID = tabs[max(0, min(index - 1, tabs.count - 1))].id
        }
        title = activeTab.title
        currentURL = activeTab.url
        address = activeTab.url?.absoluteString ?? ""
        reloadTick += 1
    }

    private func updateActiveTab(_ change: (inout BrowserTab) -> Void) {
        guard let index = tabs.firstIndex(where: { $0.id == activeTabID }) else {
            return
        }
        change(&tabs[index])
    }

    private func recordVisit(url: URL, title: String) {
        dataStore.record(url: url, title: title)
        updateActiveTab { tab in
            tab.url = url
            if !title.isEmpty { tab.title = title }
        }
    }

    private func openReader() {
        BrowserCommands.shared.reader { title, text in
            readerTitle = title.isEmpty ? self.title : title
            readerText = text
            showReader = !text.isEmpty
        }
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
        let q = text.addingPercentEncoding(
            withAllowedCharacters: .urlQueryAllowed
        ) ?? text
        return URL(string: "https://m.baidu.com/s?word=" + q)
    }

}

final class BrowserCommands {
    static let shared = BrowserCommands()
    weak var web: WKWebView?

    func back() { web?.goBack() }
    func forward() { web?.goForward() }
    func reload() { web?.reload() }

    func find(_ text: String) {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty, let web else { return }
        let configuration = WKFindConfiguration()
        configuration.backwards = false
        configuration.wraps = true
        web.find(value, configuration: configuration) { _ in }
    }

    func setDesktopMode(_ enabled: Bool) {
        web?.customUserAgent = enabled
            ? "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Safari/605.1.15"
            : nil
        web?.reload()
    }

    func reader(_ completion: @escaping (String, String) -> Void) {
        let script = """
        (() => {
          const nodes = [
            document.querySelector('article'),
            document.querySelector('main'),
            document.querySelector('[role="main"]'),
            document.body
          ].filter(Boolean);
          let node = nodes.find(n => (n.innerText || '').trim().length > 500)
            || nodes[0];
          if (!node) return '';
          const text = (node.innerText || '')
            .replace(/\\n{3,}/g, '\\n\\n')
            .trim();
          return JSON.stringify({
            title: document.title || '',
            text: text.slice(0, 60000)
          });
        })();
        """
        web?.evaluateJavaScript(script) { result, _ in
            guard let raw = result as? String,
                  let data = raw.data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(
                    with: data
                  ) as? [String: Any] else {
                return
            }
            let title = object["title"] as? String ?? ""
            let text = object["text"] as? String ?? ""
            DispatchQueue.main.async {
                completion(title, text)
            }
        }
    }
}

private struct BrowserWebView: UIViewRepresentable {
    let initialURL: URL?
    let reloadTick: Int
    let privateMode: Bool
    @Binding var title: String
    @Binding var progress: Double
    @Binding var loading: Bool
    @Binding var canBack: Bool
    @Binding var canForward: Bool
    @Binding var currentURL: URL?
    @Binding var address: String
    @Binding var addressEditing: Bool
    @Binding var loadError: String
    let onVisit: (URL, String) -> Void
    let onNewWindow: (URL) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []
        config.defaultWebpagePreferences.allowsContentJavaScript = true
        config.websiteDataStore = privateMode ? .nonPersistent() : .default()

        let web = WKWebView(frame: .zero, configuration: config)
        web.navigationDelegate = context.coordinator
        web.uiDelegate = context.coordinator
        web.allowsBackForwardNavigationGestures = true
        web.isOpaque = true
        web.backgroundColor = .white
        web.scrollView.backgroundColor = .white
        web.scrollView.isOpaque = true
        web.underPageBackgroundColor = .white
        web.scrollView.contentInsetAdjustmentBehavior = .never
        web.scrollView.keyboardDismissMode = .interactive
        web.scrollView.contentInset.bottom = 82
        web.scrollView.verticalScrollIndicatorInsets.bottom = 82
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

    static func dismantleUIView(_ uiView: WKWebView,
                                coordinator: Coordinator) {
        if BrowserCommands.shared.web === uiView {
            BrowserCommands.shared.web = nil
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
            observations.append(
                web.observe(\.estimatedProgress, options: [.new]) {
                    [weak self] view, _ in
                    DispatchQueue.main.async {
                        self?.parent.progress = view.estimatedProgress
                    }
                }
            )
            observations.append(
                web.observe(\.canGoBack, options: [.new]) {
                    [weak self] view, _ in
                    DispatchQueue.main.async {
                        self?.parent.canBack = view.canGoBack
                    }
                }
            )
            observations.append(
                web.observe(\.canGoForward, options: [.new]) {
                    [weak self] view, _ in
                    DispatchQueue.main.async {
                        self?.parent.canForward = view.canGoForward
                    }
                }
            )
            observations.append(
                web.observe(\.url, options: [.new]) { [weak self] view, _ in
                    DispatchQueue.main.async {
                        guard let url = view.url else { return }
                        self?.parent.currentURL = url
                        if self?.parent.addressEditing != true {
                            self?.parent.address = url.absoluteString
                        }
                    }
                }
            )
            observations.append(
                web.observe(\.title, options: [.new]) {
                    [weak self] view, _ in
                    DispatchQueue.main.async {
                        let value = (view.title ?? "")
                            .trimmingCharacters(in: .whitespacesAndNewlines)
                        self?.parent.title = value.isEmpty
                            ? Tr("浏览器") : value
                    }
                }
            )
        }

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
        ) {
            guard let url = navigationAction.request.url else {
                decisionHandler(.allow)
                return
            }
            let scheme = url.scheme?.lowercased() ?? ""
            if scheme != "http", scheme != "https" {
                // Keep shopping/social links inside the WebKit session. Custom
                // schemes are cancelled instead of launching another app.
                decisionHandler(.cancel)
                return
            }
            decisionHandler(.allow)
        }

        func webView(
            _ webView: WKWebView,
            didStartProvisionalNavigation navigation: WKNavigation!
        ) {
            parent.loading = true
            parent.progress = max(0.02, parent.progress)
            parent.loadError = ""
        }

        func webView(
            _ webView: WKWebView,
            didFinish navigation: WKNavigation!
        ) {
            parent.loading = false
            parent.progress = 1
            parent.canBack = webView.canGoBack
            parent.canForward = webView.canGoForward
            if !parent.privateMode, let url = webView.url {
                parent.onVisit(url, webView.title ?? "")
            }
        }

        func webView(
            _ webView: WKWebView,
            didFail navigation: WKNavigation!,
            withError error: Error
        ) {
            parent.loading = false
            if (error as NSError).code != NSURLErrorCancelled {
                parent.loadError = error.localizedDescription
            }
        }

        func webView(
            _ webView: WKWebView,
            didFailProvisionalNavigation navigation: WKNavigation!,
            withError error: Error
        ) {
            parent.loading = false
            if (error as NSError).code != NSURLErrorCancelled {
                parent.loadError = error.localizedDescription
            }
        }

        func webView(
            _ webView: WKWebView,
            didReceive challenge: URLAuthenticationChallenge,
            completionHandler: @escaping (
                URLSession.AuthChallengeDisposition,
                URLCredential?
            ) -> Void
        ) {
            completionHandler(.performDefaultHandling, nil)
        }

        func webView(
            _ webView: WKWebView,
            createWebViewWith configuration: WKWebViewConfiguration,
            for navigationAction: WKNavigationAction,
            windowFeatures: WKWindowFeatures
        ) -> WKWebView? {
            if navigationAction.targetFrame == nil,
               let url = navigationAction.request.url {
                parent.onNewWindow(url)
            }
            return nil
        }

        func webView(
            _ webView: WKWebView,
            runJavaScriptAlertPanelWithMessage message: String,
            initiatedByFrame frame: WKFrameInfo,
            completionHandler: @escaping () -> Void
        ) {
            let alert = UIAlertController(
                title: webView.url?.host,
                message: message,
                preferredStyle: .alert
            )
            alert.addAction(
                UIAlertAction(title: Tr("知道了"), style: .default) { _ in
                    completionHandler()
                }
            )
            topController()?.present(alert, animated: true)
        }

        func webView(
            _ webView: WKWebView,
            runJavaScriptConfirmPanelWithMessage message: String,
            initiatedByFrame frame: WKFrameInfo,
            completionHandler: @escaping (Bool) -> Void
        ) {
            let alert = UIAlertController(
                title: webView.url?.host,
                message: message,
                preferredStyle: .alert
            )
            alert.addAction(
                UIAlertAction(title: Tr("取消"), style: .cancel) { _ in
                    completionHandler(false)
                }
            )
            alert.addAction(
                UIAlertAction(title: Tr("确定"), style: .default) { _ in
                    completionHandler(true)
                }
            )
            topController()?.present(alert, animated: true)
        }

        func webView(
            _ webView: WKWebView,
            runJavaScriptTextInputPanelWithPrompt prompt: String,
            defaultText: String?,
            initiatedByFrame frame: WKFrameInfo,
            completionHandler: @escaping (String?) -> Void
        ) {
            let alert = UIAlertController(
                title: webView.url?.host,
                message: prompt,
                preferredStyle: .alert
            )
            alert.addTextField { field in
                field.text = defaultText
            }
            alert.addAction(
                UIAlertAction(title: Tr("取消"), style: .cancel) { _ in
                    completionHandler(nil)
                }
            )
            alert.addAction(
                UIAlertAction(title: Tr("确定"), style: .default) { _ in
                    completionHandler(alert.textFields?.first?.text)
                }
            )
            topController()?.present(alert, animated: true)
        }

        private func topController() -> UIViewController? {
            var controller = UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .flatMap { $0.windows }
                .first(where: { $0.isKeyWindow })?
                .rootViewController
            while let presented = controller?.presentedViewController {
                controller = presented
            }
            return controller
        }
    }
}

private struct BrowserStartPage: View {
    let history: [BrowserVisit]
    let bookmarks: [BrowserBookmark]
    let onOpen: (URL) -> Void
    let onAddress: () -> Void
    let onPrivate: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(Tr("星言浏览器"))
                        .font(pf(30, .bold))
                    Text(Tr("快速、安静，同时守住你的隐私"))
                        .font(pf(14))
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: 11) {
                    Button(action: onAddress) {
                        HStack(spacing: 9) {
                            Image(systemName: "magnifyingglass")
                            Text(Tr("搜索或输入网站"))
                            Spacer()
                        }
                        .font(pf(15, .medium))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, AppDesign.Spacing.md)
                        .frame(height: AppDesign.Control.mediumControlHeight)
                        .background(
                            Color.primary.opacity(0.055),
                            in: Capsule()
                        )
                    }
                    .buttonStyle(.plain)

                    Button(action: onPrivate) {
                        Image(systemName: "eye.slash.fill")
                            .font(.system(size: 16, weight: .semibold))
                            .frame(width: 48, height: 48)
                            .background(
                                Color.primary.opacity(0.055),
                                in: Circle()
                            )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Tr("无痕浏览"))
                }

                if !bookmarks.isEmpty {
                    BrowserStartSection(
                        title: Tr("书签"),
                        rows: bookmarks.prefix(4).map {
                            BrowserStartRow(
                                title: $0.title,
                                subtitle: $0.link?.host ?? "",
                                icon: "bookmark.fill",
                                url: $0.link
                            )
                        },
                        onOpen: onOpen
                    )
                }

                if !history.isEmpty {
                    BrowserStartSection(
                        title: Tr("最近访问"),
                        rows: history.prefix(8).map {
                            BrowserStartRow(
                                title: $0.title,
                                subtitle: $0.link?.host ?? "",
                                icon: "clock",
                                url: $0.link
                            )
                        },
                        onOpen: onOpen
                    )
                }
            }
            .padding(.horizontal, 22)
            .padding(.top, 74)
            .padding(.bottom, 36)
        }
        .background(C.pageBg)
    }
}

private struct BrowserStartRow: Identifiable {
    let id = UUID()
    let title: String
    let subtitle: String
    let icon: String
    let url: URL?
}

private struct BrowserStartSection: View {
    let title: String
    let rows: [BrowserStartRow]
    let onOpen: (URL) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(title)
                .font(pf(14, .semibold))
            VStack(spacing: 0) {
                ForEach(Array(rows.enumerated()), id: \.element.id) {
                    index, row in
                    Button {
                        if let url = row.url { onOpen(url) }
                    } label: {
                        HStack(spacing: AppDesign.Spacing.sm) {
                            Image(systemName: row.icon)
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(C.green)
                                .frame(width: 32, height: 32)
                                .background(
                                    C.green.opacity(0.10),
                                    in: Circle()
                                )
                            VStack(alignment: .leading, spacing: 2) {
                                Text(row.title)
                                    .font(pf(14, .medium))
                                    .foregroundStyle(C.label)
                                    .lineLimit(1)
                                Text(row.subtitle)
                                    .font(pf(11))
                                    .foregroundStyle(C.subLabel)
                                    .lineLimit(1)
                            }
                            Spacer()
                        }
                        .frame(height: AppDesign.Control.largeControlHeight)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    if index < rows.count - 1 {
                        Divider().padding(.leading, 44)
                    }
                }
            }
            .padding(.horizontal, 13)
            .background(C.cardBg, in: RoundedRectangle(
                cornerRadius: AppDesign.Radius.panel,
                style: .continuous
            ))
        }
    }
}

private struct BrowserTabsSheet: View {
    @Binding var tabs: [BrowserTab]
    @Binding var active: UUID
    let onSelect: (UUID) -> Void
    let onClose: (UUID) -> Void
    let onNew: () -> Void
    let onPrivate: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                ForEach(tabs) { tab in
                    Button {
                        onSelect(tab.id)
                        dismiss()
                    } label: {
                        HStack(spacing: AppDesign.Spacing.sm) {
                            Image(systemName: tab.isPrivate
                                  ? "eye.slash.fill" : "globe")
                                .foregroundStyle(tab.id == active
                                                 ? C.green : C.subLabel)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(tab.title)
                                    .font(pf(15, .medium))
                                    .foregroundStyle(C.label)
                                    .lineLimit(1)
                                Text(tab.url?.host ?? Tr("空白标签页"))
                                    .font(pf(11.5))
                                    .foregroundStyle(C.subLabel)
                                    .lineLimit(1)
                            }
                            Spacer()
                            if tab.id == active {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(C.green)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .swipeActions {
                        Button(role: .destructive) {
                            onClose(tab.id)
                        } label: {
                            Label(Tr("关闭"), systemImage: "xmark")
                        }
                    }
                }
            }
            .navigationTitle(Tr("标签页"))
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(action: onPrivate) {
                        Image(systemName: "eye.slash")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: onNew) {
                        Image(systemName: "plus")
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

private struct BrowserHistorySheet: View {
    @ObservedObject var store: BrowserDataStore
    let onOpen: (URL) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List(store.history) { item in
                Button {
                    if let url = item.link { onOpen(url) }
                    dismiss()
                } label: {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(item.title)
                            .font(pf(14.5, .medium))
                            .foregroundStyle(C.label)
                            .lineLimit(1)
                        Text(item.link?.host ?? item.url)
                            .font(pf(11.5))
                            .foregroundStyle(C.subLabel)
                            .lineLimit(1)
                    }
                }
                .buttonStyle(.plain)
            }
            .overlay {
                if store.history.isEmpty {
                    BrowserEmptyState(
                        icon: "clock",
                        title: Tr("还没有浏览记录")
                    )
                }
            }
            .navigationTitle(Tr("历史记录"))
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(Tr("清空")) { store.clearHistory() }
                        .disabled(store.history.isEmpty)
                }
            }
        }
    }
}

private struct BrowserEmptyState: View {
    let icon: String
    let title: String

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 27, weight: .regular))
                .foregroundStyle(C.subLabel)
            Text(title)
                .font(pf(14, .medium))
                .foregroundStyle(C.subLabel)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct BrowserBookmarksSheet: View {
    @ObservedObject var store: BrowserDataStore
    let onOpen: (URL) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List(store.bookmarks) { item in
                Button {
                    if let url = item.link { onOpen(url) }
                    dismiss()
                } label: {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(item.title)
                            .font(pf(14.5, .medium))
                            .foregroundStyle(C.label)
                            .lineLimit(1)
                        Text(item.link?.host ?? item.url)
                            .font(pf(11.5))
                            .foregroundStyle(C.subLabel)
                            .lineLimit(1)
                    }
                }
                .buttonStyle(.plain)
            }
            .overlay {
                if store.bookmarks.isEmpty {
                    BrowserEmptyState(
                        icon: "bookmark",
                        title: Tr("还没有书签")
                    )
                }
            }
            .navigationTitle(Tr("书签"))
        }
    }
}

private struct BrowserReaderSheet: View {
    let title: String
    let text: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text(title)
                        .font(pf(28, .bold))
                    Text(text)
                        .font(pf(18))
                        .lineSpacing(8)
                        .textSelection(.enabled)
                }
                .padding(22)
            }
            .background(C.pageBg)
            .navigationTitle(Tr("阅读模式"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(Tr("完成")) { dismiss() }
                }
            }
        }
    }
}
