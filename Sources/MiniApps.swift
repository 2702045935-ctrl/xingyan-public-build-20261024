import SwiftUI
import WebKit
import UIKit

/* ============================================================
   小程序 / 小游戏运行时（发现 → 小程序）

   · 小程序由**后台加**（后台「小程序 / 小游戏」页：名字 / 图标 / 说明 / 类型 / 入口地址）
     —— 加新的、改名字图标都不用重新出包。
   · App 这一页就是个**运行时**：内置浏览器（WKWebView）+ 一层 `wx.*` JS 桥
     （setNavigationBarTitle / showToast / showModal / 存储 / request / 震动 / 分享 / 退出…），
     所以按小程序 API 写的页面直接能跑。
   · 文件先下到本机再跑（App 默认连的是 IP，证书 App 自己放过、WKWebView 不认，
     直连必然加载失败；下到本地顺带离线也能用）。
   ⚠ 小游戏（kind = game）**不注入** wx 桥 —— 它们自己那份 adapter.js 在浏览器模式下走 canvas。
   ============================================================ */

/* Codable（不是只 Decodable）：会话页二楼要把小程序清单**存本机一份**，
   网络抖的时候用上次那份，二楼不会一会儿正常一会儿不正常。 */
struct MiniApp: Codable, Identifiable, Hashable {
    var id: String
    var name: String
    var desc: String?
    var icon: String?
    var kind: String?
    var url: String
    var color: String?
    /// 封面图（后台填，可空 —— 空就用图标那块渐变）
    var cover: String?
    /// 分组名（微信那边是「发现新游 / 动作对抗游戏」这种小标题）
    var group: String?
    /// 卡片上那颗按钮的文字（立即玩 / 预约 …）
    var action: String?
    /// 小程序能力类目（后台可填；没填时按名字/分组自动归类）
    var category: String? = nil
    /// 服务能力标签，例如「在线预约」「查件」「会员」
    var capabilities: [String]? = nil
    var provider: String? = nil
    var featured: Bool? = nil

    var isGame: Bool { (kind ?? "") == "game" }
    var iconText: String { (icon?.isEmpty == false) ? icon! : (isGame ? "🕹️" : "🧩") }
    var actionText: String { (action?.isEmpty == false) ? action! : "立即玩" }
    var groupText: String { (group?.isEmpty == false) ? group! : "推荐小游戏" }
}

struct MiniAppCapabilityCategory: Identifiable {
    let id: String
    let title: String
    let subtitle: String
    let symbol: String
    let tint: Color
    let examples: [String]

    static let all: [MiniAppCapabilityCategory] = [
        .init(id: "retail", title: "电商零售", subtitle: "商城与品牌", symbol: "bag.fill", tint: Color(hex: 0xFF6B4A),
              examples: ["综合商城", "品牌商城", "会员商城", "拼团", "二手交易"]),
        .init(id: "food", title: "餐饮服务", subtitle: "点餐外卖", symbol: "fork.knife", tint: Color(hex: 0xFF8A1F),
              examples: ["扫码点餐", "外卖", "排队取号", "订座", "团购套餐"]),
        .init(id: "life", title: "生活服务", subtitle: "到家与缴费", symbol: "house.fill", tint: Color(hex: 0x2E9E5B),
              examples: ["家政", "维修", "搬家", "洗衣", "水电燃气"]),
        .init(id: "beauty", title: "美容健康", subtitle: "到店与健身", symbol: "heart.fill", tint: Color(hex: 0xEC5B86),
              examples: ["美发", "美甲", "美容", "健身", "瑜伽"]),
        .init(id: "medical", title: "医疗医药", subtitle: "挂号问诊", symbol: "cross.case.fill", tint: Color(hex: 0xE5484D),
              examples: ["医院挂号", "在线问诊", "报告查询", "疫苗预约", "药品配送"]),
        .init(id: "travel", title: "旅游出行", subtitle: "酒店与交通", symbol: "airplane", tint: Color(hex: 0x2F73C9),
              examples: ["酒店", "民宿", "机票", "火车票", "打车"]),
        .init(id: "tickets", title: "文娱票务", subtitle: "电影与演出", symbol: "ticket.fill", tint: Color(hex: 0x8B5CF6),
              examples: ["电影票", "演出票", "展览", "KTV", "体育赛事"]),
        .init(id: "education", title: "教育培训", subtitle: "课程与校园", symbol: "graduationcap.fill", tint: Color(hex: 0x0EA5A4),
              examples: ["课程购买", "在线学习", "考试报名", "作业", "校园服务"]),
        .init(id: "property", title: "房产服务", subtitle: "租房与物业", symbol: "building.2.fill", tint: Color(hex: 0x7C8798),
              examples: ["新房", "二手房", "租房", "物业缴费", "社区报修"]),
        .init(id: "auto", title: "汽车服务", subtitle: "养车与出行", symbol: "car.fill", tint: Color(hex: 0x3978D4),
              examples: ["4S店", "洗车", "保养", "驾校", "停车"]),
        .init(id: "gov", title: "政务民生", subtitle: "办事与社保", symbol: "building.columns.fill", tint: Color(hex: 0xD64B45),
              examples: ["政务办事", "社保", "公积金", "税务", "社区登记"]),
        .init(id: "finance", title: "金融保险", subtitle: "银行与保险", symbol: "creditcard.fill", tint: Color(hex: 0xC58A21),
              examples: ["银行", "保险", "信用卡", "基金", "理财"]),
        .init(id: "delivery", title: "快递物流", subtitle: "寄件与查件", symbol: "shippingbox.fill", tint: Color(hex: 0xB27042),
              examples: ["寄件", "查件", "驿站", "同城配送", "货运"]),
        .init(id: "enterprise", title: "企业服务", subtitle: "办公与经营", symbol: "briefcase.fill", tint: Color(hex: 0x596579),
              examples: ["招聘", "打卡", "审批", "CRM", "进销存"]),
        .init(id: "content", title: "内容资讯", subtitle: "新闻与社区", symbol: "newspaper.fill", tint: Color(hex: 0x4D7CFE),
              examples: ["新闻", "视频", "社区", "论坛", "知识付费"]),
        .init(id: "tools", title: "工具效率", subtitle: "扫描与转换", symbol: "wrench.and.screwdriver.fill", tint: Color(hex: 0x64748B),
              examples: ["翻译", "OCR", "扫描", "PDF", "记账"]),
        .init(id: "social", title: "社交互动", subtitle: "报名与投票", symbol: "person.3.fill", tint: Color(hex: 0x14A38B),
              examples: ["投票", "报名", "问卷", "抽奖", "活动签到"]),
        .init(id: "games", title: "娱乐游戏", subtitle: "小游戏", symbol: "gamecontroller.fill", tint: Color(hex: 0x7A45D6),
              examples: ["休闲游戏", "答题", "互动游戏", "抽奖", "虚拟宠物"]),
        .init(id: "member", title: "会员营销", subtitle: "卡券与积分", symbol: "crown.fill", tint: Color(hex: 0xD9A326),
              examples: ["会员卡", "积分", "优惠券", "储值", "秒杀"]),
        .init(id: "local", title: "本地门店", subtitle: "到店与核销", symbol: "storefront.fill", tint: Color(hex: 0x0F9D75),
              examples: ["门店展示", "预约到店", "扫码点单", "员工核销", "附近门店"]),
        .init(id: "campus", title: "教育校园", subtitle: "校园生活", symbol: "book.closed.fill", tint: Color(hex: 0x3A7BD5),
              examples: ["校园卡", "课表", "成绩", "缴费", "社团活动"]),
        .init(id: "public", title: "公共服务", subtitle: "场馆与公告", symbol: "mappin.and.ellipse", tint: Color(hex: 0x4B7F8C),
              examples: ["停车缴费", "景区导览", "场馆预约", "图书馆", "社区公告"]),
        .init(id: "agriculture", title: "农业产业", subtitle: "农产品与供应链", symbol: "leaf.fill", tint: Color(hex: 0x4D9B43),
              examples: ["农产品商城", "认养", "溯源", "农资", "批发"]),
        .init(id: "live", title: "直播内容", subtitle: "直播与带货", symbol: "dot.radiowaves.left.and.right", tint: Color(hex: 0xE23D6D),
              examples: ["商品直播", "短视频", "内容种草", "课程直播", "互动直播"])
    ]
}

/* ---------------------------------------------------------- 分享出去的那张卡 */

/// 好友发来的「小游戏 / 小程序」卡片：body 就是这一段 JSON
struct MiniAppShare: Decodable {
    var id: String
    var name: String
    var desc: String?
    var icon: String?
    var kind: String?
    var url: String
    var cover: String?
    var action: String?

    var asApp: MiniApp {
        MiniApp(id: id, name: name, desc: desc, icon: icon, kind: kind, url: url,
                color: nil, cover: cover, group: nil, action: action)
    }
    var isGame: Bool { (kind ?? "") == "game" }

    /// 从聊天消息 body 里解析（解析不出来就返回 nil，界面上退回一行「[小游戏]」）
    init?(json: String) {
        guard let d = json.data(using: .utf8),
              let o = (try? JSONSerialization.jsonObject(with: d)) as? [String: Any] else { return nil }
        let name = (o["name"] as? String) ?? ""
        let url = (o["url"] as? String) ?? ""
        guard !name.isEmpty, !url.isEmpty else { return nil }
        self.id = (o["id"] as? String) ?? ""
        self.name = name
        self.desc = o["desc"] as? String
        self.icon = o["icon"] as? String
        self.kind = o["kind"] as? String
        self.url = url
        self.cover = o["cover"] as? String
        self.action = o["action"] as? String
    }
}

/// 聊天里那张小游戏卡片（微信里好友分享给你的小游戏就是这个样子）
struct MiniAppCardBubble: View {
    let info: MiniAppShare
    var onOpen: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(LinearGradient(colors: [Color(hex: 0x2B2F3A), Color(hex: 0x171B22)],
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
                Text(info.icon?.isEmpty == false ? info.icon! : (info.isGame ? "🕹️" : "🧩"))
                    .font(.system(size: 26))
                if let cv = info.cover, !cv.isEmpty {
                    RemoteImage(path: cv).frame(width: 52, height: 52)
                        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                }
            }
            .frame(width: 52, height: 52)

            VStack(alignment: .leading, spacing: 4) {
                Text(info.name).font(pf(15)).foregroundColor(C.label).lineLimit(1)
                Text(info.desc?.isEmpty == false ? info.desc! : Tr("点开就能玩"))
                    .font(pf(12)).foregroundColor(C.subLabel).lineLimit(2)
                Text(Tr("小游戏"))
                    .font(pf(10.5)).foregroundColor(C.subLabel)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .frame(width: 232, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(C.cardBg))
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
            .stroke(C.hairline, lineWidth: 0.5))
        .contentShape(Rectangle())
        .onTapGesture { onOpen() }
    }
}

/* ---------------------------------------------------------- 列表页（发现 → 小程序） */

struct MiniAppsView: View {
    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var items: [MiniApp] = []
    @State private var loading = true
    @State private var run: MiniApp?
    @State private var search = ""
    @State private var category = ""
    @State private var capability: MiniAppCapabilityCategory?
    @State private var favoriteIds: Set<String> = []
    @State private var recentIds: [String] = []

    private let cols = Array(repeating: GridItem(.flexible(), spacing: 14), count: 3)
    private let capabilityCols = Array(repeating: GridItem(.flexible(), spacing: 10), count: 2)
    private let favKey = "mini.favorites"
    private let recentKey = "mini.recent"

    private var filtered: [MiniApp] {
        let q = search.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        var rows = items
        if !q.isEmpty {
            rows = rows.filter {
                ($0.name + " " + ($0.desc ?? "") + " " + categoryTitle(for: $0)
                 + " " + (($0.capabilities ?? []).joined(separator: " "))).lowercased().contains(q)
            }
        } else if !category.isEmpty {
            rows = rows.filter { categoryId(for: $0) == category }
        }
        return rows.sorted {
            let f0 = $0.featured == true ? 1 : 0
            let f1 = $1.featured == true ? 1 : 0
            if f0 != f1 { return f0 > f1 }
            return $0.name.localizedCompare($1.name) == .orderedAscending
        }
    }

    private var favorites: [MiniApp] {
        let all = items.filter { favoriteIds.contains($0.id) }
        let order = items.map(\.id)
        return all.sorted {
            (order.firstIndex(of: $0.id) ?? 0) < (order.firstIndex(of: $1.id) ?? 0)
        }
    }

    private var recent: [MiniApp] {
        recentIds.compactMap { id in items.first { $0.id == id } }
    }

    var body: some View {
        VStack(spacing: 0) {
            NavBar(title: Tr("小程序"), back: { dismiss() })

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    hero
                    searchBar
                    categoryStrip

                    if loading {
                        HStack(spacing: 10) {
                            ProgressView()
                            Text(Tr("正在加载…")).font(pf(15)).foregroundColor(C.subLabel)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.top, 30)
                    } else {
                        if search.isEmpty && category.isEmpty && !recent.isEmpty {
                            sectionTitle(Tr("最近使用"))
                            horizontalApps(recent)
                        }

                        if search.isEmpty && category.isEmpty && !favorites.isEmpty {
                            sectionTitle(Tr("我的收藏"))
                            horizontalApps(favorites)
                        }

                        sectionTitle(categoryTitle)
                        if filtered.isEmpty {
                            emptyServiceCard
                        } else {
                            LazyVGrid(columns: cols, spacing: 18) {
                                ForEach(filtered) { it in
                                    appTile(it)
                                }
                            }
                        }

                        if search.isEmpty && category.isEmpty {
                            sectionTitle(Tr("能力类目"))
                            LazyVGrid(columns: capabilityCols, spacing: 10) {
                                ForEach(MiniAppCapabilityCategory.all) { c in
                                    capabilityTile(c)
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 10)
                .padding(.bottom, 28)
            }
            .background(C.pageBg)
        }
        .background(C.pageBg.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .swipeBack { dismiss() }
        .hidesTabBar()
        .task {
            items = await API.shared.miniApps()
            favoriteIds = Set(UserDefaults.standard.stringArray(forKey: favKey) ?? [])
            recentIds = UserDefaults.standard.stringArray(forKey: recentKey) ?? []
            loading = false
        }
        .fullScreenCover(item: $run) { it in
            MiniAppRuntimeView(app: it)
                .environmentObject(app)
        }
        .sheet(item: $capability) { c in
            MiniAppCapabilitySheet(category: c)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
    }

    private var hero: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 5) {
                Text(Tr("星言小程序"))
                    .font(pf(21, .bold))
                    .foregroundColor(.white)
                Text(Tr("生活服务、内容、工具与企业能力统一接入"))
                    .font(pf(12))
                    .foregroundColor(.white.opacity(0.82))
                    .lineLimit(2)
            }
            Spacer(minLength: 0)
            Image(systemName: "square.grid.2x2.fill")
                .font(.system(size: 34, weight: .medium))
                .foregroundColor(.white.opacity(0.9))
        }
        .padding(.horizontal, 16)
        .frame(height: 96)
        .background(LinearGradient(colors: [Color(hex: 0x2458D8), Color(hex: 0x4A9BFF)],
                                   startPoint: .topLeading, endPoint: .bottomTrailing))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var searchBar: some View {
        HStack(spacing: 7) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(C.subLabel)
            TextField(Tr("搜索小程序、服务或能力"), text: $search)
                .font(.system(size: 14))
            if !search.isEmpty {
                Button { search = "" } label: {
                    Image(systemName: "xmark.circle.fill").foregroundColor(C.subLabel)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 40)
        .background(C.cardBg)
        .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
    }

    private var categoryStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                categoryChip(id: "", title: Tr("全部"))
                ForEach(MiniAppCapabilityCategory.all) { c in
                    categoryChip(id: c.id, title: Tr(c.title))
                }
            }
        }
    }

    private func categoryChip(id: String, title: String) -> some View {
        Button {
            withAnimation(.easeOut(duration: 0.16)) {
                category = id
                search = ""
            }
        } label: {
            Text(title)
                .font(pf(12.5, category == id ? .semibold : .regular))
                .foregroundColor(category == id ? .white : C.label)
                .padding(.horizontal, 12)
                .frame(height: 30)
                .background(Capsule().fill(category == id ? C.green : C.cardBg))
        }
        .buttonStyle(.plain)
    }

    private var categoryTitle: String {
        if !category.isEmpty { return Tr(MiniAppCapabilityCategory.all.first { $0.id == category }?.title ?? "全部") }
        if !search.isEmpty { return Tr("搜索结果") }
        return Tr("全部服务")
    }

    private func sectionTitle(_ t: String) -> some View {
        HStack(spacing: 8) {
            Text(t).font(pf(17, .semibold)).foregroundColor(C.label)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func horizontalApps(_ rows: [MiniApp]) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 14) {
                ForEach(rows) { it in
                    appTile(it).frame(width: 76)
                }
            }
        }
    }

    private func appTile(_ it: MiniApp) -> some View {
        Button {
            runApp(it)
        } label: {
            tile(it)
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button {
                toggleFavorite(it)
            } label: {
                Label(favoriteIds.contains(it.id) ? Tr("取消收藏") : Tr("收藏"),
                      systemImage: favoriteIds.contains(it.id) ? "star.slash" : "star")
            }
        }
    }

    private func tile(_ it: MiniApp) -> some View {
        VStack(spacing: 8) {
            ZStack {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(LinearGradient(colors: [Color(hex: 0x2B2F3A), Color(hex: 0x1B1F27)],
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
                Text(it.iconText).font(.system(size: 30))
                /* ⚠ 有上传的图标图就**用图**（后台/App 管理里换了图标这里要跟着变）——
                   以前这里只画 emoji，所以用户换了图标，小程序页看着"怎么没换"。 */
                if let cv = it.cover, !cv.isEmpty {
                    RemoteImage(path: cv)
                        .frame(width: 62, height: 62)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
            }
            .frame(width: 62, height: 62)
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(C.hairline, lineWidth: 0.6))
            .overlay(alignment: .topTrailing) {
                if favoriteIds.contains(it.id) {
                    Image(systemName: "star.fill")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundColor(.white)
                        .frame(width: 17, height: 17)
                        .background(Circle().fill(Color(hex: 0xE3A126)))
                        .offset(x: 4, y: -4)
                }
            }

            Text(it.name)
                .font(pf(13))
                .foregroundColor(C.label)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
    }

    private var emptyServiceCard: some View {
        VStack(spacing: 9) {
            Image(systemName: "square.stack.3d.up.fill")
                .font(.system(size: 28))
                .foregroundColor(C.subLabel.opacity(0.7))
            Text(Tr("这个能力已经预留，具体服务还没有接入"))
                .font(pf(14, .medium))
                .foregroundColor(C.label)
            Text(Tr("后台添加小程序入口后会自动出现在这里，不用重新出包"))
                .font(pf(12))
                .foregroundColor(C.subLabel)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
        .background(C.cardBg)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func capabilityTile(_ c: MiniAppCapabilityCategory) -> some View {
        let count = items.filter { categoryId(for: $0) == c.id }.count
        return Button {
            capability = c
        } label: {
            HStack(spacing: 10) {
                Image(systemName: c.symbol)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(c.tint)
                    .frame(width: 38, height: 38)
                    .background(c.tint.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                VStack(alignment: .leading, spacing: 3) {
                    Text(Tr(c.title)).font(pf(13.5, .medium)).foregroundColor(C.label).lineLimit(1)
                    Text(count > 0 ? "\(count) " + Tr("项服务") : Tr("能力已预留"))
                        .font(pf(10.5)).foregroundColor(C.subLabel).lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 11)
            .frame(height: 58)
            .background(C.cardBg)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func runApp(_ it: MiniApp) {
        recentIds.removeAll { $0 == it.id }
        recentIds.insert(it.id, at: 0)
        recentIds = Array(recentIds.prefix(8))
        UserDefaults.standard.set(recentIds, forKey: recentKey)
        run = it
    }

    private func toggleFavorite(_ it: MiniApp) {
        if favoriteIds.contains(it.id) { favoriteIds.remove(it.id) }
        else { favoriteIds.insert(it.id) }
        UserDefaults.standard.set(Array(favoriteIds), forKey: favKey)
    }

    private func categoryId(for app: MiniApp) -> String {
        if let c = app.category, !c.isEmpty { return c }
        let raw = (app.name + " " + (app.group ?? "") + " " + (app.desc ?? "")).lowercased()
        for c in MiniAppCapabilityCategory.all {
            if raw.contains(c.title.lowercased()) { return c.id }
            for e in c.examples where raw.contains(e.lowercased()) { return c.id }
        }
        if app.isGame { return "games" }
        return "tools"
    }

    private func categoryTitle(for app: MiniApp) -> String {
        MiniAppCapabilityCategory.all.first { $0.id == categoryId(for: app) }?.title ?? "工具效率"
    }
}

struct MiniAppCapabilitySheet: View {
    let category: MiniAppCapabilityCategory
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(spacing: 13) {
                        Image(systemName: category.symbol)
                            .font(.system(size: 24, weight: .semibold))
                            .foregroundColor(category.tint)
                            .frame(width: 54, height: 54)
                            .background(category.tint.opacity(0.12))
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        VStack(alignment: .leading, spacing: 4) {
                            Text(Tr(category.title)).font(pf(20, .bold)).foregroundColor(C.label)
                            Text(Tr(category.subtitle)).font(pf(12)).foregroundColor(C.subLabel)
                        }
                    }

                    Text(Tr("已预留的服务能力"))
                        .font(pf(15, .semibold))
                        .foregroundColor(C.label)
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 8),
                                        GridItem(.flexible(), spacing: 8)], spacing: 8) {
                        ForEach(category.examples, id: \.self) { name in
                            Text(Tr(name))
                                .font(pf(12.5))
                                .foregroundColor(C.label)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 11)
                                .frame(height: 38)
                                .background(C.cardBg)
                                .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                        }
                    }

                    Text(Tr("这些能力由后台按类目配置具体服务入口；上线后会自动进入搜索、最近使用和收藏。"))
                        .font(pf(12))
                        .foregroundColor(C.subLabel)
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(C.fieldBg)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                .padding(16)
            }
            .background(C.pageBg.ignoresSafeArea())
            .navigationTitle(Tr("能力详情"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(Tr("完成")) { dismiss() }
                }
            }
        }
    }
}

/* ---------------------------------------------------------- 运行时页 */

struct MiniAppRuntimeView: View {
    let app: MiniApp
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var title = ""
    @State private var localIndex: URL?
    @State private var localDir: URL?
    @State private var loading = true
    @State private var errorText = ""
    /// 顶栏那颗 🏆 要用它往里打 JS（好友排名面板）
    @StateObject private var box = WebBox()
    /// 右上角胶囊里的「···」菜单
    @State private var capsuleMenu = false

    var body: some View {
        /* 微信小程序那样：**整屏都是小程序**，只有右上角一颗胶囊（··· / ⊙） */
        ZStack(alignment: .topTrailing) {
            if let localIndex {
                MiniAppWebView(index: localIndex, dir: localDir,
                               injectBridge: !app.isGame,
                               rankJs: chrisRankJs(game: app.id, token: API.shared.token, base: API.shared.base),
                               box: box,
                               onMessage: handle,
                               onScore: { g, s in Task { await API.shared.gameScore(g, s) } },
                               onRank: { g, done in Task { done(await API.shared.gameRankJSONWithAvatars(g)) } })
            } else if loading {
                VStack(spacing: 10) {
                    ProgressView().tint(.white)
                    Text(Tr("正在准备…")).font(pf(13.5)).foregroundColor(.white.opacity(0.7))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                VStack(spacing: 12) {
                    Text(errorText.isEmpty ? Tr("打不开") : errorText)
                        .font(pf(14)).foregroundColor(.white.opacity(0.8))
                        .multilineTextAlignment(.center).padding(.horizontal, 30)
                    Button { Task { await prepare(force: true) } } label: {
                        Text(Tr("重试")).font(pf(15, .medium)).foregroundColor(.white)
                            .padding(.horizontal, 22).frame(height: 40)
                            .background(Capsule().fill(C.green))
                    }
                    .buttonStyle(.plain)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            /* 右上角胶囊：[ ··· | ⊙ ] */
            HStack(spacing: 0) {
                Button { capsuleMenu = true } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(width: 48, height: 32)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                Rectangle().fill(Color.white.opacity(0.25)).frame(width: 0.5, height: 18)
                Button { dismiss() } label: {
                    ZStack {
                        Circle().stroke(Color.white, lineWidth: 1.6).frame(width: 15, height: 15)
                        Circle().fill(Color.white).frame(width: 5.5, height: 5.5)
                    }
                    .frame(width: 46, height: 32)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .background(Capsule().fill(Color.black.opacity(0.35)))
            .overlay(Capsule().stroke(Color.white.opacity(0.18), lineWidth: 0.5))
            .padding(.top, 8)
            .padding(.trailing, 10)
            /* 右下角 🏆：好友排名（和游戏页一样，独立一颗好点） */
            if localIndex != nil {
                VStack {
                    Spacer(minLength: 0)
                    HStack {
                        Spacer(minLength: 0)
                        Button {
                            box.web?.evaluateJavaScript("window.chrisRank && chrisRank.show()")
                        } label: {
                            Text("🏆")
                                .font(.system(size: 20))
                                .frame(width: 42, height: 42)
                                .background(Circle().fill(Color.black.opacity(0.35)))
                                .overlay(Circle().stroke(Color.white.opacity(0.18), lineWidth: 0.5))
                        }
                        .buttonStyle(.plain)
                        .padding(.trailing, 12)
                        .padding(.bottom, 18)
                    }
                }
            }
        }
        .background(Color(hex: 0x0B0E17).ignoresSafeArea())
        .statusBarHidden(true)
        .task { await prepare() }
        .confirmationDialog(title.isEmpty ? app.name : title, isPresented: $capsuleMenu, titleVisibility: .visible) {
            Button(Tr("好友排名")) { box.web?.evaluateJavaScript("window.chrisRank && chrisRank.show()") }
            Button(Tr("重新进入")) { Task { await prepare(force: true) } }
            Button(Tr("关闭"), role: .destructive) { dismiss() }
            Button(Tr("取消"), role: .cancel) { }
        }
    }

    /// 小程序/小游戏那一套文件（约定：入口同目录下的 index.html + js/*.js）
    private var files: [String] {
        ["index.html", "js/adapter.js", "js/engine.js", "js/sound.js", "js/main.js"]
    }

    private func prepare(force: Bool = false) async {
        loading = true
        errorText = ""
        guard let remote = API.shared.assetURL(app.url) else {
            loading = false
            errorText = Tr("这个入口地址不对（后台「小程序」里看看）")
            return
        }
        let remoteDir = remote.deletingLastPathComponent()
        let fm = FileManager.default
        guard let caches = fm.urls(for: .cachesDirectory, in: .userDomainMask).first else {
            loading = false
            return
        }
        let root = caches.appendingPathComponent("miniapps/\(app.id)", isDirectory: true)
        do {
            try fm.createDirectory(at: root, withIntermediateDirectories: true)
            /* 文件清单问服务器（files.json），没有才用默认那 5 个 */
            let list = await miniAppFileList(baseDir: remoteDir)
            for f in list {
                let dst = root.appendingPathComponent(f)
                if !force, let sz = try? dst.resourceValues(forKeys: [.fileSizeKey]).fileSize, sz > 0 { continue }
                try fm.createDirectory(at: dst.deletingLastPathComponent(), withIntermediateDirectories: true)
                let data = try await API.shared.assetData(remoteDir.appendingPathComponent(f))
                try data.write(to: dst, options: .atomic)
            }
            localDir = root
            localIndex = root.appendingPathComponent("index.html")
        } catch {
            errorText = Tr("下载失败：") + error.localizedDescription
        }
        loading = false
    }

    /// JS 桥回传的消息（wx.showToast / wx.setNavigationBarTitle / wx.vibrateShort / wx.exitMiniProgram…）
    private func handle(_ dict: [String: Any]) {
        let fn = (dict["fn"] as? String) ?? ""
        switch fn {
        case "title":
            title = (dict["title"] as? String) ?? ""
        case "toast":
            appState.show((dict["title"] as? String) ?? "")
        case "vibrate":
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        case "share":
            appState.show(Tr("已分享"))
        case "exit":
            dismiss()
        default:
            break
        }
    }
}

/// 内置浏览器 + （小程序才注入的）wx.* JS 桥
struct MiniAppWebView: UIViewRepresentable {
    let index: URL
    let dir: URL?
    let injectBridge: Bool
    /// 好友排名那一层（自动报分 + 🏆 面板）—— 游戏和小程序都注
    let rankJs: String
    let box: WebBox
    let onMessage: ([String: Any]) -> Void
    /// 报分 / 拉榜：由原生替网页发（本地 file:// 直连服务器会被证书拦掉）
    var onScore: ((String, Int) -> Void)? = nil
    var onRank: ((String, @escaping (String) -> Void) -> Void)? = nil

    func makeUIView(context: Context) -> WKWebView {
        let cfg = WKWebViewConfiguration()
        cfg.allowsInlineMediaPlayback = true
        cfg.mediaTypesRequiringUserActionForPlayback = []
        /* 安全区：小程序页面自己也吃安全区（微信就是这么做的）——
           页面顶部的文字不再钻到刘海底下，背景/画面仍然铺满。 */
        cfg.userContentController.addUserScript(
            WKUserScript(source: WebSafeArea.js, injectionTime: .atDocumentStart, forMainFrameOnly: true))
        if !rankJs.isEmpty {
            cfg.userContentController.addUserScript(
                WKUserScript(source: rankJs, injectionTime: .atDocumentStart, forMainFrameOnly: true))
            /* 好友排行那根线（报分 / 拉榜） */
            context.coordinator.rank.onScore = onScore
            context.coordinator.rank.onRank = onRank
            cfg.userContentController.add(context.coordinator.rank, name: "chrisRank")
        }
        if injectBridge {
            cfg.userContentController.add(context.coordinator, name: "wx")
            let js = miniAppWxBridge(token: API.shared.token, base: API.shared.base)
            cfg.userContentController.addUserScript(
                WKUserScript(source: js, injectionTime: .atDocumentStart, forMainFrameOnly: true))
        }
        let v = WKWebView(frame: .zero, configuration: cfg)
        v.isOpaque = false
        v.backgroundColor = UIColor(red: 0.043, green: 0.055, blue: 0.09, alpha: 1)
        v.scrollView.bounces = false
        v.scrollView.contentInsetAdjustmentBehavior = .never
        v.loadFileURL(index, allowingReadAccessTo: dir ?? index.deletingLastPathComponent())
        context.coordinator.web = v
        context.coordinator.rank.web = v
        box.web = v
        return v
    }

    func updateUIView(_ v: WKWebView, context: Context) { }

    func makeCoordinator() -> Coord { Coord(onMessage: onMessage) }

    final class Coord: NSObject, WKScriptMessageHandler {
        let onMessage: ([String: Any]) -> Void
        /// 好友排行（自己不是一个 handler 名，见 makeUIView 里的注册）
        let rank = RankBridge()
        weak var web: WKWebView?
        init(onMessage: @escaping ([String: Any]) -> Void) { self.onMessage = onMessage }
        func userContentController(_ uc: WKUserContentController, didReceive message: WKScriptMessage) {
            if let d = message.body as? [String: Any] { onMessage(d) }
            else if let s = message.body as? String { onMessage(["fn": s]) }
        }
    }
}

/* ---------------------------------------------------------- wx.* 桥（注入到小程序页面里） */

/// 一套小程序/小游戏要下哪些文件 —— **问服务器**：
/// 游戏目录里放一份 files.json（`{"files":["index.html","js/a.js",…]}`），
/// 没有就退回默认那 5 个文件。
/// 这样后台再加一款（哪怕 js 文件不一样多），App 不用改也不用出包。
func miniAppFileList(baseDir: URL) async -> [String] {
    let fallback = ["index.html", "js/adapter.js", "js/engine.js", "js/sound.js", "js/main.js"]
    guard let data = try? await API.shared.assetData(baseDir.appendingPathComponent("files.json")),
          let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let arr = obj["files"] as? [String], !arr.isEmpty else { return fallback }
    return arr
}

/// 一层很薄的 wx 兼容层：够大多数「小程序」页面直接跑。
/// 原生那边只接 4 件事（改标题 / toast / 震动 / 退出 / 分享），其余都在 JS 里自己搞定。
func miniAppWxBridge(token: String, base: String) -> String {
    let t = token.replacingOccurrences(of: "\"", with: "\\\"")
    let b = base.replacingOccurrences(of: "\"", with: "\\\"")
    return """
    (function () {
      if (window.wx && window.wx.__chris) return;
      var TOKEN = "\(t)", BASE = "\(b)";
      function post(o) { try { window.webkit.messageHandlers.wx.postMessage(o); } catch (e) { } }
      function abs(u) { return /^https?:/i.test(u) ? u : (BASE + (u.charAt(0) === '/' ? u : '/' + u)); }
      var api = {
        __chris: true,
        setNavigationBarTitle: function (o) { post({ fn: 'title', title: (o && o.title) || '' }); },
        setNavigationBarColor: function () { },
        showToast: function (o) { post({ fn: 'toast', title: (o && o.title) || '' }); },
        hideToast: function () { },
        showLoading: function (o) { post({ fn: 'toast', title: (o && o.title) || '加载中' }); },
        hideLoading: function () { },
        showModal: function (o) {
          o = o || {};
          var ok = window.confirm(((o.title || '') + '\\n' + (o.content || '')).trim());
          if (ok && o.success) o.success({ confirm: true, cancel: false });
          else if (!ok && o.fail) o.fail({ confirm: false, cancel: true });
        },
        vibrateShort: function () { post({ fn: 'vibrate' }); },
        vibrateLong: function () { post({ fn: 'vibrate' }); },
        setStorageSync: function (k, v) { try { localStorage.setItem('wx_' + k, JSON.stringify(v)); } catch (e) { } },
        getStorageSync: function (k) { try { var s = localStorage.getItem('wx_' + k); return s == null ? '' : JSON.parse(s); } catch (e) { return ''; } },
        removeStorageSync: function (k) { try { localStorage.removeItem('wx_' + k); } catch (e) { } },
        clearStorageSync: function () { try { Object.keys(localStorage).forEach(function (k) { if (k.indexOf('wx_') === 0) localStorage.removeItem(k); }); } catch (e) { } },
        request: function (o) {
          o = o || {};
          var h = {}; var hh = o.header || {};
          for (var k in hh) h[k] = hh[k];
          if (TOKEN) h['Authorization'] = 'Bearer ' + TOKEN;
          if (o.data && (o.method || 'GET').toUpperCase() !== 'GET') h['Content-Type'] = 'application/json';
          fetch(abs(o.url), { method: o.method || 'GET', headers: h,
            body: (o.data && (o.method || 'GET').toUpperCase() !== 'GET') ? JSON.stringify(o.data) : undefined })
            .then(function (r) { return r.json(); })
            .then(function (j) { if (o.success) o.success({ statusCode: 200, data: j }); })
            .catch(function (e) { if (o.fail) o.fail({ errMsg: String(e) }); });
        },
        getSystemInfoSync: function () {
          return { platform: 'ios', brand: 'Apple', model: 'iPhone', system: 'iOS',
                   windowWidth: window.innerWidth, windowHeight: window.innerHeight,
                   pixelRatio: window.devicePixelRatio || 2, statusBarHeight: 0,
                   screenWidth: window.innerWidth, screenHeight: window.innerHeight,
                   safeArea: { top: 0, bottom: 0, left: 0, right: 0 } };
        },
        getLaunchOptionsSync: function () { return { scene: 1001, query: {}, path: '' }; },
        showShareMenu: function () { }, hideShareMenu: function () { },
        onShareAppMessage: function () { }, onShow: function () { }, onHide: function () { },
        onError: function () { }, onUnhandledRejection: function () { },
        shareAppMessage: function () { post({ fn: 'share' }); },
        exitMiniProgram: function () { post({ fn: 'exit' }); },
        navigateBack: function () { post({ fn: 'exit' }); },
        navigateTo: function () { post({ fn: 'exit' }); }
      };
      window.wx = api;
    })();
    """
}
