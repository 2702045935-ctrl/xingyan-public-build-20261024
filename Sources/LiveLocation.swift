import SwiftUI
import MapKit
import CoreLocation

final class LiveLocationStore: ObservableObject {
    static let shared = LiveLocationStore()

    struct Peer: Identifiable {
        var id: String
        var name: String
        var avatar: String
        var lat: Double
        var lng: Double
    }

    @Published var sessionId = ""
    @Published var chatId = ""
    @Published var active = false
    @Published var peers: [Peer] = []

    func reset() {
        sessionId = ""
        chatId = ""
        active = false
        peers = []
    }

    func apply(sessionId: String, members: [API.LiveMember]) {
        self.sessionId = sessionId
        active = true
        var list: [Peer] = []
        for m in members {
            guard let lat = m.lat, let lng = m.lng else { continue }
            list.append(Peer(id: m.userId, name: m.name ?? "",
                             avatar: m.avatar ?? "", lat: lat, lng: lng))
        }
        peers = list
    }

    func upsert(userId: String, name: String, avatar: String, lat: Double, lng: Double) {
        if let i = peers.firstIndex(where: { $0.id == userId }) {
            peers[i].lat = lat
            peers[i].lng = lng
            if !name.isEmpty { peers[i].name = name }
        } else {
            peers.append(Peer(id: userId, name: name, avatar: avatar, lat: lat, lng: lng))
        }
    }
}

struct SendLocationView: View {
    var onSend: (String) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var region = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 31.2304, longitude: 121.4737),
        span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01))
    @State private var myLat = 0.0
    @State private var myLng = 0.0
    @State private var places: [(String, String, Double, Double)] = []
    @State private var loading = true
    @State private var picked = 0
    @State private var denied = false

    @State private var homePlaces: [(String, String, Double, Double)] = []

    @State private var centerPlace: (String, String, Double, Double)? = nil

    @State private var query = ""
    @State private var searchTask: Task<Void, Never>? = nil
    @State private var centerTask: Task<Void, Never>? = nil
    @State private var searching = false

    @State private var suppressCenter = false

    var body: some View {
        ZStack {
            Map(coordinateRegion: $region, showsUserLocation: true,
                annotationItems: places.enumerated().map { IndexedPlace(index: $0.offset, name: $0.element.0,
                                                                       lat: $0.element.2, lng: $0.element.3) }) { p in
                MapMarker(coordinate: CLLocationCoordinate2D(latitude: p.lat, longitude: p.lng),
                          tint: p.index == picked ? C.green : .red)
            }
            .ignoresSafeArea()
            .onChange(of: region.center.latitude) { _ in centerMoved() }
            .onChange(of: region.center.longitude) { _ in centerMoved() }

            LinearGradient(
                colors: [C.pageBg.opacity(0.54), .clear],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 180)
            .frame(maxHeight: .infinity, alignment: .top)
            .ignoresSafeArea(edges: .top)
            .allowsHitTesting(false)

            VStack(spacing: 9) {
                topControls
                searchBar
                Spacer(minLength: 0)
            }
            .padding(.top, 8)

            VStack(spacing: 9) {
                Spacer(minLength: 0)
                HStack {
                    Spacer(minLength: 0)
                    Button(action: recenter) {
                        Image(systemName: "location.fill")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(C.green)
                            .frame(width: 44, height: 44)
                            .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .background {
                        Circle()
                            .fill(C.floatingSurface)
                            .overlay(Circle().stroke(C.hairline, lineWidth: 0.6))
                            .shadow(color: Color.black.opacity(0.14), radius: 8, y: 3)
                    }
                    .accessibilityLabel(Tr("回到当前位置"))
                }
                .padding(.horizontal, 20)
                .padding(.bottom, locationPanelHeight + 12)

                mapStatus
                locationPanel
            }
        }
        .background(C.pageBg.ignoresSafeArea(edges: .bottom))
        .background(C.pageBg.ignoresSafeArea(edges: .top))
        .toolbar(.hidden, for: .navigationBar)
        .swipeBack { dismiss() }
        .hidesTabBar()
        .task { await locate() }
    }

    private var locationPanelHeight: CGFloat {
        min(330, max(238, L.height * 0.34))
    }

    private var topControls: some View {
        HStack(spacing: 10) {
            Button { dismiss() } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(C.label)
                    .frame(width: 42, height: 42)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .background {
                Circle()
                    .fill(C.floatingSurface)
                    .overlay(Circle().stroke(C.hairline, lineWidth: 0.6))
                    .shadow(color: Color.black.opacity(0.14), radius: 8, y: 3)
            }
            .accessibilityLabel(Tr("返回"))

            Spacer(minLength: 0)

            Text(Tr("发送位置"))
                .font(pf(15, .semibold))
                .foregroundColor(C.label)
                .padding(.horizontal, 14)
                .frame(height: 36)
                .background(Capsule(style: .continuous).fill(C.controlSurface))
                .overlay(Capsule(style: .continuous).stroke(C.hairline, lineWidth: 0.6))

            Spacer(minLength: 0)

            Button(action: send) {
                Text(Tr("发送"))
                    .font(pf(14, .semibold))
                    .foregroundColor(places.isEmpty ? C.subLabel : .white)
                    .padding(.horizontal, 15)
                    .frame(height: 42)
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .background {
                Capsule(style: .continuous)
                    .fill(
                        places.isEmpty
                            ? AnyShapeStyle(C.controlSurface)
                            : AnyShapeStyle(LinearGradient(
                                colors: [Color(hex: 0x45C892), C.green],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ))
                    )
                    .overlay(Capsule(style: .continuous)
                        .stroke(Color.white.opacity(places.isEmpty ? 0 : 0.16),
                                lineWidth: 0.7))
                    .shadow(color: places.isEmpty ? .clear : C.green.opacity(0.20),
                            radius: 8, y: 3)
            }
            .disabled(places.isEmpty)
            .accessibilityLabel(Tr("发送位置"))
        }
        .padding(.horizontal, 14)
    }

    @ViewBuilder
    private var mapStatus: some View {
        if loading {
            statusPill(Tr("正在定位…"), symbol: "location")
        } else if denied {
            Button {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            } label: {
                statusPill(Tr("定位没开：点这里去设置里打开「位置」"), symbol: "location.slash")
            }
            .buttonStyle(.plain)
        } else if searching {
            statusPill(Tr("正在找这个地方…"), symbol: "magnifyingglass")
        }
    }

    private func statusPill(_ title: String, symbol: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .semibold))
            Text(title)
                .font(pf(12.5, .medium))
                .lineLimit(1)
        }
        .foregroundColor(C.label)
        .padding(.horizontal, 12)
        .frame(height: 34)
        .background(Capsule(style: .continuous).fill(C.floatingSurface))
        .overlay(Capsule(style: .continuous).stroke(C.hairline, lineWidth: 0.6))
        .shadow(color: Color.black.opacity(0.12), radius: 7, y: 3)
    }

    private var locationPanel: some View {
        VStack(spacing: 0) {
            Capsule()
                .fill(Color.secondary.opacity(0.26))
                .frame(width: 34, height: 4)
                .padding(.top, 8)
                .padding(.bottom, 7)

            HStack(spacing: 8) {
                Image(systemName: trimmed.isEmpty ? "mappin.and.ellipse" : "magnifyingglass")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(C.green)
                Text(trimmed.isEmpty ? Tr("附近地点") : Tr("搜索结果"))
                    .font(pf(15, .semibold))
                    .foregroundColor(C.label)
                Spacer(minLength: 0)
                Text("\(places.count)")
                    .font(pf(11.5, .medium))
                    .foregroundColor(C.subLabel)
                    .padding(.horizontal, 8)
                    .frame(height: 22)
                    .background(Capsule().fill(C.label.opacity(0.06)))
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 8)

            HairLine()

            ScrollView(showsIndicators: false) {
                LazyVStack(spacing: 0) {
                    if places.isEmpty {
                        VStack(spacing: 10) {
                            Image(systemName: "mappin.slash")
                                .font(.system(size: 26, weight: .light))
                                .foregroundColor(C.subLabel)
                            Text(emptyText)
                                .font(pf(13.5))
                                .foregroundColor(C.subLabel)
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.horizontal, 30)
                        .padding(.top, 34)
                    } else {
                        ForEach(places.indices, id: \.self) { i in
                            placeRow(i)
                            HairLine(inset: 48)
                        }
                    }
                }
            }
        }
        .frame(height: locationPanelHeight)
        .background {
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(C.cardBg)
                .overlay {
                    RoundedRectangle(cornerRadius: 26, style: .continuous)
                        .stroke(
                            LinearGradient(
                                colors: [Color.white.opacity(0.13), C.hairline],
                                startPoint: .top,
                                endPoint: .bottom
                            ),
                            lineWidth: 0.7
                        )
                }
                .shadow(color: Color.black.opacity(0.18), radius: 20, y: 8)
        }
        .padding(.horizontal, 10)
        .padding(.bottom, 7)
    }

    private struct IndexedPlace: Identifiable {
        var id: Int { index }
        var index: Int
        var name: String
        var lat: Double
        var lng: Double
    }

    private var trimmed: String { query.trimmingCharacters(in: .whitespaces) }

    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 14.5, weight: .medium))
                .foregroundColor(C.searchIcon)
            TextField(Tr("搜索地点：大厦 / 小区 / 商铺名"), text: $query)
                .font(pf(15))
                .foregroundColor(C.label)
                .submitLabel(.search)
                .onSubmit { searchNow() }
                .onChange(of: query) { _ in queryChanged() }
            if !query.isEmpty {
                Button { query = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 15))
                        .foregroundColor(C.searchIcon2)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 42)
        .background(Capsule(style: .continuous).fill(C.floatingSurface))
        .overlay(Capsule(style: .continuous).stroke(C.hairline, lineWidth: 0.6))
        .shadow(color: Color.black.opacity(0.12), radius: 8, y: 3)
        .padding(.horizontal, 14)
    }

    private func placeRow(_ i: Int) -> some View {
        let p = places[i]
        return Button {
            picked = i

            suppressCenter = true
            withAnimation(.easeOut(duration: 0.22)) {
                region.center = CLLocationCoordinate2D(latitude: p.2, longitude: p.3)
                region.span = MKCoordinateSpan(latitudeDelta: 0.005, longitudeDelta: 0.005)
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { suppressCenter = false }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: i == picked ? "mappin.circle.fill" : "mappin.circle")
                    .font(.system(size: 17))
                    .foregroundColor(i == picked ? C.green : C.subLabel)
                VStack(alignment: .leading, spacing: 2) {
                    Text(p.0).font(pf(16)).foregroundColor(C.label).lineLimit(1)
                    if !p.1.isEmpty {
                        Text(p.1).font(pf(12.5)).foregroundColor(C.subLabel).lineLimit(1)
                    }
                }
                Spacer(minLength: 8)
                if i == picked {
                    Image(systemName: "checkmark").foregroundColor(C.green)
                }
            }
            .padding(.horizontal, 16)
            .frame(height: 58)
            .background(i == picked ? C.green.opacity(0.10) : Color.clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var emptyText: String {
        if !trimmed.isEmpty { return Tr("没找到") + "「\(trimmed)」\n" + Tr("换个说法试试（路名 / 楼名 / 小区名）") }
        if denied { return Tr("定位没开。可以在上面搜地点，也可以拖动地图选点") }
        return Tr("拖一下地图换个位置，或者在上面搜地点")
    }

    private func queryChanged() {
        searchTask?.cancel()
        let q = trimmed
        if q.isEmpty {
            searchTask = nil
            searching = false
            places = centerPlace.map { [$0] + homePlaces } ?? homePlaces
            picked = 0
            return
        }
        searchTask = Task {
            try? await Task.sleep(nanoseconds: 400_000_000)
            if Task.isCancelled { return }
            await runSearch(q)
        }
    }

    private func searchNow() {
        searchTask?.cancel()
        let q = trimmed
        guard !q.isEmpty else { queryChanged(); return }
        Task { await runSearch(q) }
    }

    private func runSearch(_ q: String) async {
        searching = true
        let res = await searchPlaces(q)

        guard trimmed == q else { return }
        places = res
        picked = 0
        searching = false
    }

    private func searchPlaces(_ q: String) async -> [(String, String, Double, Double)] {

        if !q.isEmpty,
           let rows = try? await API.shared.geoSearch(q: q,
                                                      lat: region.center.latitude,
                                                      lng: region.center.longitude),
           !rows.isEmpty {
            return rows.compactMap { p in
                guard let n = p.name, !n.isEmpty, let la = p.lat, let ln = p.lng else { return nil }
                return (n, p.addr ?? "", la, ln)
            }
        }
        return await systemSearchPlaces(q)
    }

    private func systemSearchPlaces(_ q: String) async -> [(String, String, Double, Double)] {
        await withCheckedContinuation { cont in
            let req = MKLocalSearch.Request()
            req.naturalLanguageQuery = q

            req.region = MKCoordinateRegion(center: region.center,
                                            span: MKCoordinateSpan(latitudeDelta: 0.6, longitudeDelta: 0.6))
            MKLocalSearch(request: req).start { resp, _ in
                var out: [(String, String, Double, Double)] = []
                for item in resp?.mapItems ?? [] {
                    let pm = item.placemark
                    let name = item.name ?? pm.name ?? Tr("位置")
                    let addr = [pm.locality, pm.subLocality, pm.thoroughfare, pm.subThoroughfare]
                        .compactMap { $0 }.joined(separator: " ")
                    let c = pm.coordinate
                    out.append((name, addr, c.latitude, c.longitude))
                }
                cont.resume(returning: out)
            }
        }
    }

    private func centerMoved() {
        guard !suppressCenter, !loading else { return }
        centerTask?.cancel()
        let lat = region.center.latitude
        let lng = region.center.longitude
        centerTask = Task {
            try? await Task.sleep(nanoseconds: 600_000_000)
            if Task.isCancelled { return }
            var name = Tr("地图上的这个点")
            var addr = ""
            if let marks = try? await CLGeocoder()
                .reverseGeocodeLocation(CLLocation(latitude: lat, longitude: lng)),
               let m = marks.first {
                name = m.name ?? m.locality ?? name
                addr = [m.locality, m.subLocality, m.thoroughfare, m.subThoroughfare]
                    .compactMap { $0 }.joined(separator: " ")
            }
            let place = (name, addr, lat, lng)
            centerPlace = place

            if trimmed.isEmpty {
                places = [place] + homePlaces
                picked = 0
            }
        }
    }

    private func locate() async {
        guard let loc = await OneShotLocation.shared.current() else {

            places = []
            denied = true
            loading = false
            return
        }
        myLat = loc.coordinate.latitude
        myLng = loc.coordinate.longitude

        suppressCenter = true
        region.center = loc.coordinate
        var list: [(String, String, Double, Double)] = []
        if let marks = try? await CLGeocoder().reverseGeocodeLocation(loc) {
            for m in marks.prefix(6) {
                let name = m.name ?? m.locality ?? Tr("我的位置")
                let addr = [m.locality, m.subLocality, m.thoroughfare, m.subThoroughfare]
                    .compactMap { $0 }.joined(separator: " ")
                list.append((name, addr, loc.coordinate.latitude, loc.coordinate.longitude))
            }
        }
        if list.isEmpty { list.append((Tr("我的位置"), "", myLat, myLng)) }
        homePlaces = list
        places = list
        picked = 0
        loading = false
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { suppressCenter = false }
    }

    private func recenter() {
        guard myLat != 0, myLng != 0 else {
            Task { await locate() }
            return
        }
        suppressCenter = true
        withAnimation(.easeOut(duration: 0.22)) {
            region.center = CLLocationCoordinate2D(latitude: myLat, longitude: myLng)
            region.span = MKCoordinateSpan(latitudeDelta: 0.008, longitudeDelta: 0.008)
        }
        if !homePlaces.isEmpty {
            places = homePlaces
            picked = 0
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { suppressCenter = false }
    }

    private func send() {
        guard places.indices.contains(picked) else { return }
        let p = places[picked]

        let obj: [String: Any] = ["lat": p.2, "lng": p.3, "name": p.0, "addr": p.1]
        guard let data = try? JSONSerialization.data(withJSONObject: obj),
              let payload = String(data: data, encoding: .utf8) else { return }
        onSend(payload)
        dismiss()
    }
}

struct LiveLocationView: View {
    let chat: Chat
    var onStop: (() -> Void)? = nil

    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var store = LiveLocationStore.shared

    @State private var region = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 31.2304, longitude: 121.4737),
        span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01))
    @State private var timer: Task<Void, Never>?
    @State private var hint = ""

    private var peers: [LiveLocationStore.Peer] { store.peers }

    var body: some View {
        ZStack {
            Map(coordinateRegion: $region, showsUserLocation: true,
                annotationItems: peers) { p in
                MapAnnotation(coordinate: CLLocationCoordinate2D(latitude: p.lat,
                                                                 longitude: p.lng)) {
                    VStack(spacing: 4) {
                        Avatar(path: p.avatar, size: 38, radius: 19, circle: true)
                            .overlay {
                                Circle().stroke(
                                    p.id == app.me?.id ? OrbitTheme.jade : Color.white,
                                    lineWidth: 2
                                )
                            }
                            .shadow(color: Color.black.opacity(0.24),
                                    radius: 7, y: 3)
                        Text(p.name.isEmpty ? Tr("成员") : p.name)
                            .font(pf(10.5, .semibold))
                            .foregroundColor(C.label)
                            .lineLimit(1)
                            .padding(.horizontal, 7)
                            .frame(height: 21)
                            .background(Capsule().fill(C.floatingSurface))
                            .overlay(Capsule().stroke(C.hairline, lineWidth: 0.5))
                    }
                }
            }
            .ignoresSafeArea()

            LinearGradient(
                stops: [
                    .init(color: C.pageBg.opacity(0.70), location: 0),
                    .init(color: .clear, location: 0.22),
                    .init(color: .clear, location: 0.64),
                    .init(color: C.pageBg.opacity(0.28), location: 1)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
            .allowsHitTesting(false)

            VStack(spacing: 0) {
                floatingHeader
                Spacer(minLength: 0)
                floatingPanel
            }
        }
        .background(C.pageBg.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .hidesTabBar()
        .swipeBack { stopAndClose() }
        .task { await start() }
        .onDisappear { timer?.cancel() }
    }

    private var floatingHeader: some View {
        HStack(spacing: 12) {
            Button { stopAndClose() } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(C.label)
                    .frame(width: 42, height: 42)
                    .background(Circle().fill(C.floatingSurface))
                    .overlay(Circle().stroke(C.hairline, lineWidth: 0.6))
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 2) {
                Text(Tr("共享实时位置"))
                    .font(pf(16, .semibold))
                    .foregroundColor(C.label)
                HStack(spacing: 5) {
                    Circle()
                        .fill(store.active ? OrbitTheme.jade : C.subLabel)
                        .frame(width: 6, height: 6)
                    Text(store.active ? Tr("实时更新中") : Tr("共享已结束"))
                        .font(pf(11.5, .medium))
                        .foregroundColor(C.subLabel)
                }
            }
            Spacer(minLength: 0)
            Button(action: recenter) {
                Image(systemName: "location.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(OrbitTheme.jade)
                    .frame(width: 42, height: 42)
                    .background(Circle().fill(C.floatingSurface))
                    .overlay(Circle().stroke(C.hairline, lineWidth: 0.6))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Tr("回到我的位置"))
        }
        .padding(.horizontal, 14)
        .padding(.top, 8)
    }

    private var floatingPanel: some View {
        VStack(spacing: 13) {
            Capsule()
                .fill(C.subLabel.opacity(0.26))
                .frame(width: 34, height: 4)

            HStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(OrbitTheme.jadeSoft)
                    Image(systemName: "location.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(OrbitTheme.jade)
                }
                .frame(width: 34, height: 34)
                VStack(alignment: .leading, spacing: 2) {
                    Text(Tr("一起看位置"))
                        .font(pf(15, .semibold))
                        .foregroundColor(C.label)
                    Text("\(peers.count) " + Tr("个人正在共享"))
                        .font(pf(11.5))
                        .foregroundColor(C.subLabel)
                }
                Spacer(minLength: 0)
                Text(store.active ? Tr("进行中") : Tr("已结束"))
                    .font(pf(11.5, .semibold))
                    .foregroundColor(store.active ? OrbitTheme.jade : C.subLabel)
                    .padding(.horizontal, 9)
                    .frame(height: 25)
                    .background(Capsule().fill(
                        store.active ? OrbitTheme.jadeSoft : C.controlSurface
                    ))
            }

            if !peers.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 9) {
                        ForEach(peers) { p in
                            HStack(spacing: 7) {
                                Avatar(path: p.avatar, size: 28, radius: 14, circle: true)
                                Text(p.name.isEmpty ? Tr("成员") : p.name)
                                    .font(pf(12.5, .medium))
                                    .foregroundColor(C.label)
                                    .lineLimit(1)
                            }
                            .padding(.leading, 4)
                            .padding(.trailing, 10)
                            .frame(height: 38)
                            .background(Capsule().fill(C.controlSurface))
                            .overlay(Capsule().stroke(C.hairline, lineWidth: 0.5))
                        }
                    }
                }
            }

            if !hint.isEmpty {
                Button {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                } label: {
                    HStack(spacing: 7) {
                        Image(systemName: "location.slash")
                        Text(hint).font(pf(12.5))
                        Text(Tr("去设置")).font(pf(12.5, .semibold)).foregroundColor(C.link)
                        Spacer(minLength: 0)
                    }
                    .foregroundColor(C.subLabel)
                    .padding(.horizontal, 11)
                    .frame(height: 36)
                    .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(C.controlSurface))
                }
                .buttonStyle(.plain)
            }

            Button { stopAndClose() } label: {
                HStack(spacing: 7) {
                    Image(systemName: "stop.fill")
                        .font(.system(size: 13, weight: .semibold))
                    Text(Tr("停止共享"))
                        .font(pf(15.5, .semibold))
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 46)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color(hex: 0xE34F4A))
                )
                .shadow(color: Color(hex: 0xE34F4A).opacity(0.22),
                        radius: 8, y: 3)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 15)
        .padding(.top, 9)
        .padding(.bottom, max(14, L.safeBottom + 8))
        .background(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(C.cardBg)
                .overlay {
                    RoundedRectangle(cornerRadius: 26, style: .continuous)
                        .stroke(C.hairline, lineWidth: 0.7)
                }
                .shadow(color: Color.black.opacity(0.20), radius: 22, y: 9)
        )
        .padding(.horizontal, 10)
        .padding(.bottom, 7)
    }

    private func start() async {
        guard let loc = await OneShotLocation.shared.current() else {
            hint = Tr("没给定位权限，先去 设置 → Luchat → 位置 打开")
            return
        }
        let lat = loc.coordinate.latitude
        let lng = loc.coordinate.longitude
        region.center = loc.coordinate
        if let r = await API.shared.liveStart(chatId: chat.id, lat: lat, lng: lng) {
            store.sessionId = r.sessionId
            store.chatId = chat.id
            store.active = true
            if !r.joined { onStop?() }
        }
        await pushState()

        timer?.cancel()
        timer = Task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 5_000_000_000)
                if Task.isCancelled { break }
                await reportMyPosition()
                await pushState()
            }
        }
    }

    private func pushState() async {
        guard !store.sessionId.isEmpty else { return }
        if let s = await API.shared.liveState(sessionId: store.sessionId) {
            store.apply(sessionId: s.sessionId, members: s.members)
            if let me = s.members.first(where: { $0.userId == app.me?.id }),
               let lat = me.lat, let lng = me.lng {
                region.center = CLLocationCoordinate2D(latitude: lat, longitude: lng)
            }
        }
    }

    private func reportMyPosition() async {
        guard store.active, !store.sessionId.isEmpty else { return }
        guard let loc = await OneShotLocation.shared.current() else { return }
        await API.shared.livePos(sessionId: store.sessionId,
                                 lat: loc.coordinate.latitude, lng: loc.coordinate.longitude)
        store.upsert(userId: app.me?.id ?? "", name: app.me?.name ?? "",
                     avatar: app.me?.avatarPath ?? "",
                     lat: loc.coordinate.latitude, lng: loc.coordinate.longitude)
    }

    private func recenter() {
        guard let mine = peers.first(where: { $0.id == app.me?.id }) else { return }
        withAnimation(.easeOut(duration: 0.24)) {
            region.center = CLLocationCoordinate2D(latitude: mine.lat, longitude: mine.lng)
            region.span = MKCoordinateSpan(latitudeDelta: 0.008, longitudeDelta: 0.008)
        }
    }

    private func stopAndClose() {
        timer?.cancel()
        Task {
            if !store.sessionId.isEmpty {
                await API.shared.liveStop(sessionId: store.sessionId)
            }
            store.reset()
        }
        dismiss()
    }
}
