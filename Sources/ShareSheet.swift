import SwiftUI
import UIKit

enum ShareBrand: String, CaseIterable, Identifiable {
    case wechat
    case qq
    case xiaohongshu
    case douyin

    var id: String { rawValue }

    var label: String {
        switch self {
        case .wechat: return "微信"
        case .qq: return "QQ"
        case .xiaohongshu: return "小红书"
        case .douyin: return "抖音"
        }
    }

    var scheme: String {
        switch self {
        case .wechat: return "weixin://"
        case .qq: return "mqq://"
        case .xiaohongshu: return "xhsdiscover://"
        case .douyin: return "snssdk1128://"
        }
    }
}

enum ShareBrandAction {
    @discardableResult
    static func open(_ brand: ShareBrand, text: String?, image: UIImage? = nil) -> Bool {
        if let image {
            UIPasteboard.general.image = image
        } else if let text, !text.isEmpty {
            UIPasteboard.general.string = text
        }
        guard let url = URL(string: brand.scheme),
              UIApplication.shared.canOpenURL(url) else {
            return false
        }
        UIApplication.shared.open(url)
        return true
    }
}

struct ShareBrandIcon: View {
    let brand: ShareBrand
    var size: CGFloat = 54

    var body: some View {
        ZStack {
            switch brand {
            case .wechat:
                RoundedRectangle(cornerRadius: size * 0.23, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [Color(hex: 0x29D268), Color(hex: 0x07B84D)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                SVGIcon(
                    markup: ShareBrandArtwork.wechat,
                    size: size * 0.64,
                    color: .white,
                    direct: true
                )
            case .qq:
                RoundedRectangle(cornerRadius: size * 0.23, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [Color(hex: 0x26C9FF), Color(hex: 0x0798E9)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                SVGIcon(
                    markup: ShareBrandArtwork.qq,
                    size: size * 0.62,
                    color: .white,
                    direct: true
                )
            case .xiaohongshu:
                RoundedRectangle(cornerRadius: size * 0.23, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [Color(hex: 0xFF334E), Color(hex: 0xFF1838)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                SVGIcon(
                    markup: ShareBrandArtwork.xiaohongshu,
                    size: size * 0.70,
                    color: .white,
                    direct: true
                )
            case .douyin:
                RoundedRectangle(cornerRadius: size * 0.23, style: .continuous)
                    .fill(Color(hex: 0x101014))
                SVGIcon(
                    markup: ShareBrandArtwork.douyin,
                    size: size * 0.58,
                    color: Color(hex: 0x25F4EE),
                    direct: true
                )
                .offset(x: -size * 0.018, y: size * 0.014)
                SVGIcon(
                    markup: ShareBrandArtwork.douyin,
                    size: size * 0.58,
                    color: Color(hex: 0xFE2C55),
                    direct: true
                )
                .offset(x: size * 0.018, y: -size * 0.014)
                SVGIcon(
                    markup: ShareBrandArtwork.douyin,
                    size: size * 0.58,
                    color: .white,
                    direct: true
                )
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.23, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: size * 0.23, style: .continuous)
                .stroke(Color.white.opacity(0.14), lineWidth: 0.7)
        }
        .accessibilityHidden(true)
    }
}

struct ShareBrandRail: View {
    @Environment(\.colorScheme) private var scheme
    let onTap: (ShareBrand) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(Tr("发送给好友"))
                .font(pf(12, .semibold))
                .foregroundStyle(ShareSheetTheme.secondaryInk(scheme))

            HStack(alignment: .top, spacing: 0) {
                ForEach(ShareBrand.allCases) { brand in
                    Button {
                        UISelectionFeedbackGenerator().selectionChanged()
                        onTap(brand)
                    } label: {
                        VStack(spacing: 7) {
                            ShareBrandIcon(brand: brand, size: 50)
                                .shadow(color: Color.black.opacity(scheme == .dark ? 0.28 : 0.10),
                                        radius: 8, y: 4)
                            Text(Tr(brand.label))
                                .font(pf(11.5, .medium))
                                .foregroundStyle(ShareSheetTheme.ink(scheme))
                                .lineLimit(1)
                        }
                        .frame(maxWidth: .infinity)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(ShareBrandPressStyle())
                    .accessibilityLabel(Tr("分享到") + Tr(brand.label))
                }
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 12)
            .background {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(C.floatingSurface)
            }
        }
    }
}

private struct ShareBrandPressStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(reduceMotion ? 1 : (configuration.isPressed ? 0.93 : 1))
            .opacity(configuration.isPressed ? 0.78 : 1)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.10),
                       value: configuration.isPressed)
    }
}

struct ShareFile: Identifiable {
    let id = UUID()
    let url: URL
}

/// Shared visual language for every outbound share surface in the app.
/// The hierarchy follows QQ: compact content preview, app grid, utility
/// icon grid, then one explicit cancel action.
enum ShareSheetTheme {
    static var accent: Color { Color.dyn(0x0099FF, 0x4CB8FF) }
    static var secondaryAccent: Color { Color.dyn(0x5B6EF5, 0x8B9AFF) }

    static func page(_ scheme: ColorScheme) -> Color {
        C.pageBg
    }

    @ViewBuilder
    static func pageBackdrop(_ scheme: ColorScheme) -> some View {
        ZStack {
            Rectangle()
                .fill(C.floatingSurface)
            Rectangle()
                .fill(page(scheme).opacity(scheme == .dark ? 0.42 : 0.46))
        }
    }

    static func card(_ scheme: ColorScheme) -> Color {
        C.cardBg
    }

    static func ink(_ scheme: ColorScheme) -> Color {
        C.label
    }

    static func secondaryInk(_ scheme: ColorScheme) -> Color {
        C.subLabel
    }
}

extension View {
    @ViewBuilder
    func shareSheetTranslucentBackground() -> some View {
        if #available(iOS 16.4, *) {
            presentationBackground(.clear)
                .presentationCornerRadius(30)
        } else {
            self
        }
    }
}

struct SharePreviewCard<Content: View>: View {
    @Environment(\.colorScheme) private var scheme
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .padding(12)
            .background {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(C.floatingSurface)
            }
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(Color.primary.opacity(scheme == .dark ? 0.08 : 0.05),
                            lineWidth: 0.7)
            }
            .shadow(color: Color.black.opacity(scheme == .dark ? 0.18 : 0.035),
                    radius: 12, y: 5)
    }
}

struct ShareActionTile: View {
    @Environment(\.colorScheme) private var scheme
    let title: String
    let subtitle: String?
    let symbol: String
    let tint: Color
    let action: () -> Void

    init(title: String,
         subtitle: String? = nil,
         symbol: String,
         tint: Color,
         action: @escaping () -> Void) {
        self.title = title
        self.subtitle = subtitle
        self.symbol = symbol
        self.tint = tint
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                ZStack {
                    RoundedRectangle(cornerRadius: 15, style: .continuous)
                        .fill(C.floatingSurface)
                        .frame(width: 54, height: 54)
                        .overlay {
                            RoundedRectangle(cornerRadius: 15, style: .continuous)
                                .stroke(tint.opacity(scheme == .dark ? 0.24 : 0.14),
                                        lineWidth: 0.8)
                        }
                    Image(systemName: symbol)
                        .font(.system(size: 21, weight: .semibold))
                        .foregroundStyle(tint)
                }
                Text(Tr(title))
                    .font(pf(11, .medium))
                    .foregroundStyle(ShareSheetTheme.ink(scheme))
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

struct ShareSheet: View {
    let items: [Any]

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme
    @State private var copied = false
    @State private var saved = false
    @State private var fetchedLinkTitle: String?

    private var image: UIImage? {
        for item in items {
            if let value = item as? UIImage { return value }
            if let data = item as? Data, let value = UIImage(data: data) { return value }
            if let url = item as? URL,
               url.isFileURL,
               let value = UIImage(contentsOfFile: url.path) {
                return value
            }
        }
        return nil
    }

    private var remoteImageURL: URL? {
        for item in items {
            guard let url = item as? URL, !url.isFileURL else { continue }
            let ext = url.pathExtension.lowercased()
            if ["jpg", "jpeg", "png", "heic", "webp", "gif"].contains(ext) {
                return url
            }
        }
        return nil
    }

    private var shareURL: URL? {
        for item in items {
            if let url = item as? URL { return url }
            if let text = item as? String,
               let url = URL(string: text.trimmingCharacters(in: .whitespacesAndNewlines)),
               ["http", "https"].contains(url.scheme?.lowercased() ?? "") {
                return url
            }
        }
        return nil
    }

    private var primaryText: String {
        for item in items {
            if let text = item as? String,
               !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return readableShareText(text)
            }
            if let url = item as? URL {
                if ["http", "https"].contains(url.scheme?.lowercased() ?? "") {
                    return fetchedLinkTitle ?? Tr("网页内容")
                }
                return url.lastPathComponent
            }
        }
        return Tr("来自星言的内容")
    }

    private func readableShareText(_ raw: String) -> String {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: text),
              ["http", "https"].contains(url.scheme?.lowercased() ?? "") else {
            return text
        }
        return fetchedLinkTitle ?? Tr("网页内容")
    }

    private func readableHost(_ url: URL) -> String? {
        guard let host = url.host, !host.isEmpty else { return nil }
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }

    private var previewTitle: String {
        if image != nil || remoteImageURL != nil { return Tr("图片") }
        guard let url = shareURL else { return Tr("文字内容") }
        let ext = url.pathExtension.lowercased()
        if ["mp4", "mov", "m4v", "webm"].contains(ext) { return Tr("视频") }
        if !ext.isEmpty { return Tr("文件") }
        return Tr("链接")
    }

    private var previewSymbol: String {
        if image != nil || remoteImageURL != nil { return "photo.on.rectangle.angled" }
        if previewTitle == Tr("视频") { return "play.rectangle.fill" }
        if previewTitle == Tr("文件") { return "doc.fill" }
        if shareURL != nil { return "link" }
        return "text.quote"
    }

    private var copyText: String? {
        if let shareURL { return shareURL.absoluteString }
        return items.compactMap { $0 as? String }.first
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView(showsIndicators: false) {
                VStack(spacing: 18) {
                    preview
                    brandRail
                    actionGrid
                    privacyNote
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
            }
            cancelButton
        }
        .background(ShareSheetTheme.pageBackdrop(scheme).ignoresSafeArea())
        .shareSheetTranslucentBackground()
        .presentationDragIndicator(.visible)
        .presentationDetents([.fraction(0.76), .large])
        .task(id: shareURL?.absoluteString) {
            await loadLinkMetadata()
        }
    }

    private var header: some View {
        ZStack {
            Text(Tr("分享到"))
                .font(pf(17, .semibold))
                .foregroundStyle(ShareSheetTheme.ink(scheme))
                .frame(maxWidth: .infinity)

            HStack {
                Spacer(minLength: 0)
                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(ShareSheetTheme.secondaryInk(scheme))
                        .frame(width: 34, height: 34)
                        .background(ShareSheetTheme.card(scheme), in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Tr("关闭"))
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 10)
        .padding(.bottom, 12)
    }

    private var preview: some View {
        SharePreviewCard {
            HStack(spacing: 13) {
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 78, height: 92)
                        .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
                } else if let remoteImageURL {
                    AsyncImage(url: remoteImageURL) { phase in
                        if let value = phase.image {
                            value.resizable().scaledToFill()
                        } else {
                            previewPlaceholder
                        }
                    }
                    .frame(width: 78, height: 92)
                    .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
                } else {
                    previewPlaceholder
                        .frame(width: 78, height: 92)
                }

                VStack(alignment: .leading, spacing: 7) {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(ShareSheetTheme.accent)
                            .frame(width: 6, height: 6)
                        Text(previewTitle.uppercased())
                            .font(pfStyled(size: 9, weight: .bold))
                            .tracking(1.15)
                            .foregroundStyle(ShareSheetTheme.accent)
                    }
                    Text(primaryText)
                        .font(pf(14.5, .semibold))
                        .foregroundStyle(ShareSheetTheme.ink(scheme))
                        .lineLimit(3)
                    Text(shareURL.flatMap(readableHost) ?? Tr("来自星言"))
                        .font(pf(10.5))
                        .foregroundStyle(ShareSheetTheme.secondaryInk(scheme))
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
        }
    }

    private var previewPlaceholder: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            ShareSheetTheme.accent.opacity(0.16),
                            ShareSheetTheme.secondaryAccent.opacity(0.13)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            Image(systemName: previewSymbol)
                .font(.system(size: 29, weight: .medium))
                .foregroundStyle(ShareSheetTheme.accent)
        }
    }

    private var actionGrid: some View {
        VStack(alignment: .leading, spacing: 10) {
            shareSectionTitle(Tr("更多操作"))

            LazyVGrid(
                columns: Array(
                    repeating: GridItem(.flexible(), spacing: 8),
                    count: 4
                ),
                spacing: 12
            ) {
                if copyText != nil {
                    ShareActionTile(
                        title: copied ? "已复制" : "复制链接",
                        subtitle: copied ? nil : "发送给朋友",
                        symbol: copied ? "checkmark" : "link",
                        tint: ShareSheetTheme.accent
                    ) {
                        UIPasteboard.general.string = copyText
                        withAnimation(.easeOut(duration: 0.16)) { copied = true }
                        UINotificationFeedbackGenerator().notificationOccurred(.success)
                    }
                }

                if image != nil {
                    ShareActionTile(
                        title: saved ? "已保存" : "保存图片",
                        subtitle: saved ? nil : "存入相册",
                        symbol: saved ? "checkmark" : "arrow.down.to.line.compact",
                        tint: ShareSheetTheme.secondaryAccent
                    ) {
                        guard let image else { return }
                        UIImageWriteToSavedPhotosAlbum(image, nil, nil, nil)
                        withAnimation(.easeOut(duration: 0.16)) { saved = true }
                        UINotificationFeedbackGenerator().notificationOccurred(.success)
                    }
                }

                ShareActionTile(
                    title: "系统分享",
                    subtitle: "更多应用",
                    symbol: "square.and.arrow.up",
                    tint: ShareSheetTheme.secondaryAccent
                ) {
                    presentSystemShare()
                }

                if copyText != nil {
                    ShareActionTile(
                        title: "复制内容",
                        subtitle: "复制原始内容",
                        symbol: "doc.on.doc",
                        tint: ShareSheetTheme.accent
                    ) {
                        UIPasteboard.general.string = copyText
                        withAnimation(.easeOut(duration: 0.16)) { copied = true }
                        UINotificationFeedbackGenerator().notificationOccurred(.success)
                    }
                }
            }
        }
    }

    private var brandRail: some View {
        ShareBrandRail { brand in
            let text = copyText ?? primaryText
            if ShareBrandAction.open(brand, text: text, image: image) {
                dismiss()
            } else {
                dismiss()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.28) {
                    presentSystemShare()
                }
            }
        }
    }

    private func shareSectionTitle(_ title: String) -> some View {
        Text(title)
            .font(pf(12, .semibold))
            .foregroundStyle(ShareSheetTheme.secondaryInk(scheme))
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var privacyNote: some View {
        HStack(spacing: 6) {
            Image(systemName: "lock.shield.fill")
            Text(Tr("仅复制本次要分享的内容，不会读取其他信息"))
        }
        .font(pf(10.5))
        .foregroundStyle(ShareSheetTheme.secondaryInk(scheme))
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var cancelButton: some View {
        Button { dismiss() } label: {
            Text(Tr("取消"))
                .font(pf(16, .semibold))
                .foregroundStyle(ShareSheetTheme.ink(scheme))
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .background(
                    ShareSheetTheme.card(scheme),
                    in: RoundedRectangle(cornerRadius: 16, style: .continuous)
                )
        }
        .buttonStyle(MenuPressStyle())
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    private func presentSystemShare() {
        guard let scene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive }),
              let root = scene.windows.first(where: \.isKeyWindow)?.rootViewController else {
            return
        }
        var presenter = root
        while let next = presenter.presentedViewController {
            presenter = next
        }
        let controller = UIActivityViewController(activityItems: items,
                                                  applicationActivities: nil)
        if let popover = controller.popoverPresentationController {
            popover.sourceView = presenter.view
            popover.sourceRect = CGRect(x: presenter.view.bounds.midX,
                                        y: presenter.view.bounds.maxY - 80,
                                        width: 1, height: 1)
        }
        presenter.present(controller, animated: true)
    }

    @MainActor
    private func loadLinkMetadata() async {
        fetchedLinkTitle = nil
        guard let url = shareURL,
              ["http", "https"].contains(url.scheme?.lowercased() ?? "") else {
            return
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 4
        request.setValue(
            "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15",
            forHTTPHeaderField: "User-Agent"
        )
        request.setValue("text/html,application/xhtml+xml", forHTTPHeaderField: "Accept")

        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse,
              (200..<400).contains(http.statusCode),
              let html = String(
                data: data.prefix(768_000),
                encoding: .utf8
              ),
              !Task.isCancelled,
              let title = linkTitle(from: html) else {
            return
        }
        withAnimation(.easeOut(duration: 0.16)) {
            fetchedLinkTitle = title
        }
    }

    private func linkTitle(from html: String) -> String? {
        let patterns = [
            #"<meta[^>]+(?:property|name)\s*=\s*[\"']og:title[\"'][^>]+content\s*=\s*[\"']([^\"']+)[\"']"#,
            #"<meta[^>]+content\s*=\s*[\"']([^\"']+)[\"'][^>]+(?:property|name)\s*=\s*[\"']og:title[\"']"#,
            #"<title[^>]*>(.*?)</title>"#,
        ]
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(
                pattern: pattern,
                options: [.caseInsensitive, .dotMatchesLineSeparators]
            ) else { continue }
            let source = html as NSString
            guard let match = regex.firstMatch(
                in: html,
                range: NSRange(location: 0, length: source.length)
            ),
                  match.numberOfRanges > 1 else { continue }
            let raw = source.substring(with: match.range(at: 1))
                .replacingOccurrences(of: "<[^>]+>", with: " ",
                                      options: .regularExpression)
                .replacingOccurrences(of: "&amp;", with: "&")
                .replacingOccurrences(of: "&quot;", with: "\"")
                .replacingOccurrences(of: "&#39;", with: "'")
                .replacingOccurrences(of: "&lt;", with: "<")
                .replacingOccurrences(of: "&gt;", with: ">")
                .replacingOccurrences(of: "&nbsp;", with: " ")
                .replacingOccurrences(of: #"\s+"#, with: " ",
                                      options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !raw.isEmpty,
                  !raw.lowercased().hasPrefix("http"),
                  raw.count <= 160 else { continue }
            return raw
        }
        return nil
    }
}

func writeTempFile(name: String, text: String) -> URL? {
    let dir = FileManager.default.temporaryDirectory
    let url = dir.appendingPathComponent(name)
    do {
        try text.write(to: url, atomically: true, encoding: .utf8)
        return url
    } catch {
        return nil
    }
}
