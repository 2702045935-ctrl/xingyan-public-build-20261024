import SwiftUI
import SafariServices
import UIKit

struct ShopLinkPrice: Hashable {
    var price: String
    var off: String
    var tag: String
}

struct ShopLink: Hashable {
    var title: String
    var sub: String
    var url: String
    var scheme: String

    var image: String

    var meta: String
    var reviews: String
    var prices: [ShopLinkPrice]

    var rich: Bool { !meta.isEmpty || !prices.isEmpty }

    init?(json: String) {
        guard let d = json.data(using: .utf8),
              let o = try? JSONSerialization.jsonObject(with: d) as? [String: Any] else { return nil }
        title = (o["title"] as? String) ?? "打开"
        sub = (o["sub"] as? String) ?? ""
        url = (o["url"] as? String) ?? ""
        scheme = (o["scheme"] as? String) ?? ""
        image = (o["image"] as? String) ?? ""
        meta = (o["meta"] as? String) ?? ""
        reviews = (o["reviews"] as? String) ?? ""
        prices = ((o["prices"] as? [[String: Any]]) ?? []).prefix(3).map { p in
            ShopLinkPrice(price: String(describing: p["price"] ?? ""),
                          off: (p["off"] as? String) ?? "",
                          tag: (p["tag"] as? String) ?? "")
        }
        if url.isEmpty && scheme.isEmpty { return nil }
    }
}

enum ExternalLinkRouter {
    private static let systemHosts = [
        "meituan.com", "meituan.net", "dianping.com", "dpurl.cn",
        "taobao.com", "tmall.com", "tb.cn",
        "jd.com", "jingdong.com",
        "pinduoduo.com", "yangkeduo.com",
        "ele.me", "alipay.com", "xiaohongshu.com", "douyin.com"
    ]

    static func prefersSystem(_ url: URL) -> Bool {
        guard ["http", "https"].contains(url.scheme?.lowercased() ?? ""),
              let host = url.host?.lowercased(), !host.isEmpty else { return false }
        return systemHosts.contains { host == $0 || host.hasSuffix("." + $0) }
    }

    @MainActor
    static func openIfNeeded(_ url: URL) -> Bool {
        guard prefersSystem(url) else { return false }
        UIApplication.shared.open(url)
        return true
    }
}

@MainActor
enum ShopOpener {
    static func open(_ link: ShopLink, inApp: @escaping (URL) -> Void) {
        if !link.scheme.isEmpty, let u = URL(string: link.scheme), UIApplication.shared.canOpenURL(u) {
            UIApplication.shared.open(u)
            return
        }
        if let u = URL(string: link.url) {
            if !ExternalLinkRouter.openIfNeeded(u) { inApp(u) }
        }
    }
}

struct SafariSheet: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> SFSafariViewController {
        let cfg = SFSafariViewController.Configuration()
        cfg.entersReaderIfAvailable = false
        let vc = SFSafariViewController(url: url, configuration: cfg)
        vc.preferredControlTintColor = UIColor(red: 0.34, green: 0.42, blue: 0.58, alpha: 1)
        return vc
    }

    func updateUIViewController(_ uiViewController: SFSafariViewController, context: Context) { }
}

struct WebURL: Identifiable {
    let id = UUID()
    var url: URL
}

struct ShopLinkCard: View {
    let link: ShopLink
    var onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            if link.rich { richBody } else { simpleBody }
        }
        .buttonStyle(.plain)
    }

    private var richBody: some View {
        HStack(alignment: .top, spacing: 10) {
            RemoteImage(path: link.image, mode: .fill, maxSide: 360)
                .frame(width: 104, height: 104)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                Text(link.title)
                    .font(pf(15.5, .semibold))
                    .foregroundColor(C.bubbleText)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                if !link.meta.isEmpty {
                    Text(link.meta)
                        .font(pf(11.5))
                        .foregroundColor(C.subLabel)
                        .lineLimit(1)
                }
                if !link.reviews.isEmpty {
                    Text(link.reviews)
                        .font(pf(11.5))
                        .foregroundColor(C.subLabel)
                        .lineLimit(1)
                }
                ForEach(link.prices.indices, id: \.self) { i in
                    let p = link.prices[i]
                    HStack(spacing: 4) {
                        Text("团")
                            .font(pf(10, .semibold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 3)
                            .padding(.vertical, 1)
                            .background(RoundedRectangle(cornerRadius: 3, style: .continuous).fill(C.red))
                        Text("¥" + p.price)
                            .font(pf(15, .semibold))
                            .foregroundColor(C.red)
                        if !p.off.isEmpty {
                            Text(p.off).font(pf(11.5)).foregroundColor(C.subLabel)
                        }
                        if !p.tag.isEmpty {
                            Text(p.tag).font(pf(11.5)).foregroundColor(C.subLabel).lineLimit(1)
                        }
                    }
                }
                Spacer(minLength: 0)
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .frame(width: 268, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.dyn(0xFFFFFF, 0x2C2C2E)))
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
            .stroke(Color.dyn(0xE8E8E8, 0x3A3A3C), lineWidth: 0.5))
    }

    private var simpleBody: some View {
            HStack(spacing: 10) {

                if !link.image.isEmpty {
                    RemoteImage(path: link.image, mode: .fill, maxSide: 240)
                        .frame(width: 48, height: 48)
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                } else {
                    ZStack {
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(Color(hexString: "#FF5000"))
                        Text("淘")
                            .font(pf(16, .semibold))
                            .foregroundColor(.white)
                    }
                    .frame(width: 34, height: 34)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(link.title)
                        .font(pf(15, .medium))
                        .foregroundColor(C.bubbleText)
                        .lineLimit(1)
                    Text(link.sub)
                        .font(pf(12))
                        .foregroundColor(C.subLabel)
                        .lineLimit(2)
                }
                Spacer(minLength: 6)
                Text(Tr("打开"))
                    .font(pf(12, .medium))
                    .foregroundColor(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Capsule().fill(Color(hexString: "#FF5000")))
            }
            .padding(10)
            .frame(width: 232, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.dyn(0xFFFFFF, 0x2C2C2E)))
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.dyn(0xE8E8E8, 0x3A3A3C), lineWidth: 0.5))
    }
}
