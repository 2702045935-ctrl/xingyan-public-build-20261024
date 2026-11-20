import CoreLocation
import MapKit
import SwiftUI

private enum StarMapStyle: String, CaseIterable, Identifiable {
    case standard
    case hybrid
    case satellite

    var id: String { rawValue }

    var title: String {
        switch self {
        case .standard: return Tr("地图")
        case .hybrid: return Tr("混合")
        case .satellite: return Tr("卫星")
        }
    }

    var mapType: MKMapType {
        switch self {
        case .standard: return .standard
        case .hybrid: return .hybrid
        case .satellite: return .satellite
        }
    }
}

private enum StarTravelMode: String, CaseIterable, Identifiable {
    case driving
    case walking
    case transit

    var id: String { rawValue }

    var title: String {
        switch self {
        case .driving: return Tr("驾车")
        case .walking: return Tr("步行")
        case .transit: return Tr("公交")
        }
    }

    var symbol: String {
        switch self {
        case .driving: return "car.fill"
        case .walking: return "figure.walk"
        case .transit: return "tram.fill"
        }
    }

    var directionsType: MKDirectionsTransportType {
        switch self {
        case .driving: return .automobile
        case .walking: return .walking
        case .transit: return .transit
        }
    }
}

private struct StarRouteGeometry {
    struct Match {
        let crossTrack: Double
        let along: Double
    }

    struct Step {
        let start: Double
        let end: Double
        let instruction: String
    }

    let coordinates: [CLLocationCoordinate2D]
    let cumulative: [Double]
    let total: Double
    let steps: [Step]

    init(route: MKRoute) {
        let count = route.polyline.pointCount
        var points = Array(repeating: CLLocationCoordinate2D(),
                           count: count)
        route.polyline.getCoordinates(
            &points,
            range: NSRange(location: 0, length: count)
        )
        coordinates = points
        var distances: [Double] = []
        var running: Double = 0
        if points.count > 1 {
            for index in 1..<points.count {
                running += Self.meters(points[index - 1], points[index])
                distances.append(running)
            }
        }
        cumulative = distances.isEmpty ? [0] : [0] + distances
        total = max(0, cumulative.last ?? 0)

        var start: Double = 0
        steps = route.steps.compactMap { step in
            let distance = max(0, step.distance)
            guard distance > 0 else { return nil }
            let row = Step(start: start,
                           end: start + distance,
                           instruction: step.instructions)
            start += distance
            return row
        }
    }

    func match(_ coordinate: CLLocationCoordinate2D) -> Match {
        guard coordinates.count >= 2 else {
            return Match(crossTrack: .greatestFiniteMagnitude, along: 0)
        }
        let latitudeScale = 111_320.0
        let longitudeScale = latitudeScale
            * max(0.15, cos(coordinate.latitude * .pi / 180))
        var best = Match(crossTrack: .greatestFiniteMagnitude, along: 0)

        for index in 1..<coordinates.count {
            let start = coordinates[index - 1]
            let end = coordinates[index]
            let ax = (start.longitude - coordinate.longitude) * longitudeScale
            let ay = (start.latitude - coordinate.latitude) * latitudeScale
            let bx = (end.longitude - coordinate.longitude) * longitudeScale
            let by = (end.latitude - coordinate.latitude) * latitudeScale
            let dx = bx - ax
            let dy = by - ay
            let lengthSquared = dx * dx + dy * dy
            let t = lengthSquared > 0
                ? max(0, min(1, -(ax * dx + ay * dy) / lengthSquared))
                : 0
            let px = ax + dx * t
            let py = ay + dy * t
            let distance = sqrt(px * px + py * py)
            if distance < best.crossTrack {
                let segmentStart = cumulative[index - 1]
                let segmentLength = cumulative[index] - segmentStart
                best = Match(crossTrack: distance,
                             along: segmentStart + segmentLength * t)
            }
        }
        return best
    }

    func nextStep(after along: Double) -> Step? {
        steps.first { $0.start > along + 8 }
    }

    private static func meters(_ left: CLLocationCoordinate2D,
                               _ right: CLLocationCoordinate2D) -> Double {
        CLLocation(latitude: left.latitude, longitude: left.longitude)
            .distance(from: CLLocation(latitude: right.latitude,
                                       longitude: right.longitude))
    }
}

@MainActor
private final class StarMapModel: NSObject, ObservableObject,
                                  CLLocationManagerDelegate {
    @Published var location: CLLocation?
    @Published var locationName = Tr("正在定位…")
    @Published var results: [MKMapItem] = []
    @Published var destination: MKMapItem?
    @Published var routes: [MKRoute] = []
    @Published var route: MKRoute?
    @Published var searching = false
    @Published var routing = false
    @Published var navigating = false
    @Published var error = ""
    @Published var travelMode: StarTravelMode = .driving
    @Published var mapStyle: StarMapStyle = .standard
    @Published var use3D = true
    @Published var progress: Double = 0
    @Published var distanceRemaining: Double = 0
    @Published var timeRemaining: TimeInterval = 0
    @Published var nextInstruction = Tr("选择目的地")
    @Published var nextDistance: Double = 0
    @Published var cameraRevision = 0
    @Published var authorizationDenied = false

    private let manager = CLLocationManager()
    private let geocoder = CLGeocoder()
    private var geometry: StarRouteGeometry?
    private var offRouteSamples = 0
    private var lastRerouteAt = Date.distantPast
    private var routeRequest: MKDirections?
    private var didReverseGeocode = false
    private var lastAcceptedAt = Date.distantPast

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
        manager.distanceFilter = 5
        manager.activityType = .automotiveNavigation
        manager.pausesLocationUpdatesAutomatically = false
    }

    func start() {
        switch manager.authorizationStatus {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        case .authorizedAlways, .authorizedWhenInUse:
            manager.startUpdatingLocation()
        case .denied, .restricted:
            authorizationDenied = true
        @unknown default:
            authorizationDenied = true
        }
    }

    func stop() {
        manager.stopUpdatingLocation()
        routeRequest?.cancel()
        routeRequest = nil
    }

    nonisolated func locationManagerDidChangeAuthorization(
        _ manager: CLLocationManager
    ) {
        let status = manager.authorizationStatus
        Task { @MainActor [weak self] in
            guard let self else { return }
            switch status {
            case .authorizedAlways, .authorizedWhenInUse:
                self.authorizationDenied = false
                manager.startUpdatingLocation()
            case .denied, .restricted:
                self.authorizationDenied = true
            default:
                break
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager,
                                     didUpdateLocations locations: [CLLocation]) {
        guard let latest = locations.last else { return }
        Task { @MainActor [weak self] in
            self?.accept(latest)
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager,
                                     didFailWithError error: Error) {
        Task { @MainActor [weak self] in
            self?.error = error.localizedDescription
        }
    }

    func search(_ query: String) {
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !searching else { return }
        searching = true
        error = ""
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = text
        request.region = MKCoordinateRegion(
            center: location?.coordinate
                ?? CLLocationCoordinate2D(latitude: 31.2304,
                                          longitude: 121.4737),
            span: MKCoordinateSpan(latitudeDelta: 0.08,
                                   longitudeDelta: 0.08)
        )
        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let response = try await MKLocalSearch(request: request).start()
                self.results = Array(response.mapItems.prefix(12))
            } catch {
                self.results = []
                self.error = Tr("没有找到这个地点")
            }
            self.searching = false
        }
    }

    func select(_ item: MKMapItem) {
        destination = item
        results = []
        routes = []
        route = nil
        geometry = nil
        planRoute()
    }

    func clearDestination() {
        destination = nil
        routes = []
        route = nil
        geometry = nil
        navigating = false
        progress = 0
        nextInstruction = Tr("选择目的地")
        nextDistance = 0
        distanceRemaining = 0
        timeRemaining = 0
        cameraRevision += 1
    }

    func setTravelMode(_ mode: StarTravelMode) {
        guard mode != travelMode else { return }
        travelMode = mode
        if destination != nil {
            planRoute(preserveNavigation: false)
        }
    }

    func selectRoute(_ value: MKRoute) {
        route = value
        geometry = StarRouteGeometry(route: value)
        distanceRemaining = value.distance
        timeRemaining = value.expectedTravelTime
        updateInstruction(along: 0)
        cameraRevision += 1
    }

    func planRoute(preserveNavigation: Bool = false) {
        guard let destination else { return }
        guard location != nil else {
            error = Tr("正在等待定位，请稍后再试")
            return
        }
        routeRequest?.cancel()
        routing = true
        error = ""
        let request = MKDirections.Request()
        request.source = .forCurrentLocation()
        request.destination = destination
        request.transportType = travelMode.directionsType
        request.requestsAlternateRoutes = true
        let directions = MKDirections(request: request)
        routeRequest = directions
        directions.calculate { [weak self] response, error in
            Task { @MainActor in
                guard let self else { return }
                self.routing = false
                guard let response, !response.routes.isEmpty else {
                    self.error = error?.localizedDescription
                        ?? Tr("暂时无法规划这条路线")
                    return
                }
                self.routes = response.routes
                self.selectRoute(response.routes[0])
                if preserveNavigation {
                    self.navigating = true
                    self.offRouteSamples = 0
                }
            }
        }
    }

    func startNavigation() {
        guard route != nil else { return }
        navigating = true
        use3D = true
        offRouteSamples = 0
        manager.activityType = travelMode == .walking
            ? .fitness : .automotiveNavigation
        manager.startUpdatingLocation()
        cameraRevision += 1
    }

    func endNavigation() {
        navigating = false
        cameraRevision += 1
    }

    func recenter() {
        cameraRevision += 1
    }

    func cycleMapStyle() {
        let all = StarMapStyle.allCases
        let index = all.firstIndex(of: mapStyle) ?? 0
        mapStyle = all[(index + 1) % all.count]
        cameraRevision += 1
    }

    func toggle3D() {
        use3D.toggle()
        cameraRevision += 1
    }

    private func accept(_ raw: CLLocation) {
        guard raw.horizontalAccuracy >= 0,
              raw.horizontalAccuracy <= 120,
              abs(raw.timestamp.timeIntervalSinceNow) < 20 else { return }
        let now = Date()
        guard now.timeIntervalSince(lastAcceptedAt) >= 0.45 else { return }
        lastAcceptedAt = now

        let next: CLLocation
        if let previous = location {
            let alpha = max(0.16,
                            min(0.55, max(0, raw.speed) / 28.0 + 0.16))
            let latitude = previous.coordinate.latitude
                + (raw.coordinate.latitude - previous.coordinate.latitude) * alpha
            let longitude = previous.coordinate.longitude
                + (raw.coordinate.longitude - previous.coordinate.longitude) * alpha
            next = CLLocation(
                coordinate: CLLocationCoordinate2D(latitude: latitude,
                                                   longitude: longitude),
                altitude: raw.altitude,
                horizontalAccuracy: raw.horizontalAccuracy,
                verticalAccuracy: raw.verticalAccuracy,
                course: raw.course,
                speed: raw.speed,
                timestamp: raw.timestamp
            )
        } else {
            next = raw
        }
        location = next
        cameraRevision += 1
        reverseGeocodeIfNeeded(next)
        updateNavigation(next)
    }

    private func reverseGeocodeIfNeeded(_ value: CLLocation) {
        guard !didReverseGeocode else { return }
        didReverseGeocode = true
        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let marks = try await self.geocoder.reverseGeocodeLocation(value)
                if let mark = marks.first {
                    self.locationName = mark.name
                        ?? mark.locality
                        ?? mark.administrativeArea
                        ?? Tr("当前位置")
                }
            } catch {
                self.locationName = Tr("当前位置")
            }
        }
    }

    private func updateNavigation(_ value: CLLocation) {
        guard navigating, let geometry, let route else { return }
        let match = geometry.match(value.coordinate)
        progress = geometry.total > 1
            ? max(0, min(1, match.along / geometry.total))
            : 0
        distanceRemaining = max(0, geometry.total - match.along)
        timeRemaining = route.expectedTravelTime
            * (1 - progress)
        updateInstruction(along: match.along)

        if match.crossTrack > 68 {
            offRouteSamples += 1
        } else {
            offRouteSamples = 0
        }
        if offRouteSamples >= 3,
           Date().timeIntervalSince(lastRerouteAt) > 8 {
            lastRerouteAt = Date()
            nextInstruction = Tr("已偏离路线，正在重新规划")
            planRoute(preserveNavigation: true)
        }
        if distanceRemaining < 18 {
            navigating = false
            nextInstruction = Tr("已到达目的地")
            nextDistance = 0
        }
    }

    private func updateInstruction(along: Double) {
        guard let geometry else { return }
        if let step = geometry.nextStep(after: along),
           !step.instruction.isEmpty {
            nextInstruction = step.instruction
            nextDistance = max(0, step.start - along)
        } else if let last = geometry.steps.last,
                  !last.instruction.isEmpty {
            nextInstruction = last.instruction
            nextDistance = max(0, geometry.total - along)
        } else {
            nextInstruction = Tr("沿当前道路继续行驶")
            nextDistance = max(0, geometry.total - along)
        }
    }
}

struct StarMapView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme
    @StateObject private var model = StarMapModel()
    @State private var query = ""

    var body: some View {
        ZStack(alignment: .top) {
            StarMapSurface(model: model, dark: scheme == .dark)
                .ignoresSafeArea()

            VStack(spacing: 10) {
                searchHeader

                if !model.results.isEmpty {
                    searchResults
                }

                Spacer(minLength: 0)

                if model.navigating {
                    VStack(spacing: 10) {
                        navigationBanner
                        navigationCapsule
                    }
                } else if let route = model.route {
                    routeCapsule(route)
                } else {
                    exploreCapsule
                }
            }
            .padding(.horizontal, 14)
            .padding(.top, max(8, L.safeTop + 6))
            .padding(.bottom, max(12, L.safeBottom + 8))

            if model.searching || model.routing {
                HStack(spacing: 9) {
                    ProgressView()
                    Text(model.searching ? Tr("正在搜索…") : Tr("正在规划星轨…"))
                        .font(pf(13, .medium))
                        .foregroundStyle(.primary)
                }
                .padding(.horizontal, 15)
                .frame(height: 40)
                .background(.regularMaterial, in: Capsule())
                .shadow(color: .black.opacity(0.15), radius: 12, y: 5)
                .padding(.top, max(72, L.safeTop + 62))
            }
        }
        .background(Color.black.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .statusBarHidden(false)
        .task {
            model.start()
        }
        .onDisappear {
            model.stop()
        }
    }

    private var searchHeader: some View {
        HStack(spacing: 9) {
            Button {
                dismiss()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.primary)
                    .frame(width: 40, height: 40)
                    .background(.regularMaterial, in: Circle())
            }
            .buttonStyle(.plain)

            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.secondary)
                TextField(Tr("搜索地点、商场、车站"), text: $query)
                    .font(pf(15))
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.search)
                    .onSubmit { model.search(query) }
                if !query.isEmpty {
                    Button {
                        query = ""
                        model.results = []
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 13)
            .frame(height: 40)
            .background(.regularMaterial,
                        in: RoundedRectangle(cornerRadius: 14,
                                             style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Color.white.opacity(scheme == .dark ? 0.12 : 0.36),
                            lineWidth: 0.6)
            }
        }
        .shadow(color: .black.opacity(0.14), radius: 10, y: 4)
    }

    private var searchResults: some View {
        VStack(spacing: 0) {
            ForEach(Array(model.results.enumerated()), id: \.offset) { index, item in
                Button {
                    query = item.name ?? ""
                    model.select(item)
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "mappin.and.ellipse")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(Color(hex: 0x33C7A1))
                            .frame(width: 34, height: 34)
                            .background(Color(hex: 0x33C7A1).opacity(0.12),
                                        in: Circle())
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.name ?? Tr("未命名地点"))
                                .font(pf(15, .semibold))
                                .foregroundStyle(.primary)
                                .lineLimit(1)
                            Text(item.placemark.title ?? "")
                                .font(pf(12))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        Spacer(minLength: 6)
                        Image(systemName: "plus")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 13)
                    .frame(height: 58)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                if index < model.results.count - 1 {
                    HairLine(inset: 59)
                }
            }
        }
        .background(.regularMaterial,
                    in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.white.opacity(scheme == .dark ? 0.11 : 0.40),
                        lineWidth: 0.6)
        }
        .shadow(color: .black.opacity(0.15), radius: 16, y: 7)
    }

    private var exploreCapsule: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(Tr("星轨地图"))
                    .font(pf(16, .semibold))
                Text(model.authorizationDenied
                     ? Tr("定位权限关闭，可搜索地点后继续")
                     : model.locationName)
                    .font(pf(12))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            mapControl(icon: model.use3D ? "cube.fill" : "cube",
                       active: model.use3D) {
                model.toggle3D()
            }
            mapControl(icon: model.mapStyle == .satellite
                       ? "globe.americas.fill" : "map.fill",
                       active: model.mapStyle != .standard) {
                model.cycleMapStyle()
            }
            mapControl(icon: "location.fill", active: false) {
                model.recenter()
            }
        }
        .padding(.leading, 16)
        .padding(.trailing, 10)
        .frame(minHeight: 66)
        .background(.regularMaterial,
                    in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Color.white.opacity(scheme == .dark ? 0.10 : 0.42),
                        lineWidth: 0.6)
        }
        .shadow(color: .black.opacity(0.18), radius: 18, y: 8)
    }

    private func routeCapsule(_ route: MKRoute) -> some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: "arrow.triangle.swap")
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(Color(hex: 0x33C7A1))
                    .frame(width: 42, height: 42)
                    .background(Color(hex: 0x33C7A1).opacity(0.12),
                                in: Circle())
                VStack(alignment: .leading, spacing: 3) {
                    Text(model.destination?.name ?? Tr("目的地"))
                        .font(pf(16, .semibold))
                        .lineLimit(1)
                    Text(routeClock(route.expectedTravelTime)
                         + " · " + routeDistance(route.distance))
                        .font(pf(12.5, .medium))
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 6)
                Button {
                    model.clearDestination()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.secondary)
                        .frame(width: 30, height: 30)
                }
                .buttonStyle(.plain)
            }

            HStack(spacing: 8) {
                ForEach(StarTravelMode.allCases) { mode in
                    Button {
                        model.setTravelMode(mode)
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: mode.symbol)
                                .font(.system(size: 12, weight: .semibold))
                            Text(mode.title)
                                .font(pf(12.5, .semibold))
                        }
                        .foregroundStyle(model.travelMode == mode
                                         ? Color.white : Color.primary)
                        .padding(.horizontal, 10)
                        .frame(height: 32)
                        .background(model.travelMode == mode
                                    ? Color(hex: 0x1D8C72)
                                    : Color.primary.opacity(0.065),
                                    in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
                Spacer(minLength: 4)
                Button {
                    model.startNavigation()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "location.north.fill")
                            .font(.system(size: 12, weight: .bold))
                        Text(Tr("开始导航"))
                            .font(pf(14, .semibold))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 13)
                    .frame(height: 36)
                    .background(Color(hex: 0x167E68),
                                in: Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(14)
        .background(.regularMaterial,
                    in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(Color.white.opacity(scheme == .dark ? 0.11 : 0.42),
                        lineWidth: 0.6)
        }
        .shadow(color: .black.opacity(0.20), radius: 20, y: 9)
    }

    private var navigationBanner: some View {
        HStack(spacing: 13) {
            Image(systemName: maneuverSymbol)
                .font(.system(size: 25, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 50, height: 50)
                .background(Color(hex: 0x167E68),
                            in: RoundedRectangle(cornerRadius: 15,
                                                 style: .continuous))
            VStack(alignment: .leading, spacing: 3) {
                Text(model.nextInstruction)
                    .font(pf(16, .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                Text(routeDistance(model.nextDistance))
                    .font(pf(12.5, .semibold))
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 6)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .background(.regularMaterial,
                    in: RoundedRectangle(cornerRadius: 19, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 19, style: .continuous)
                .stroke(Color.white.opacity(scheme == .dark ? 0.12 : 0.42),
                        lineWidth: 0.6)
        }
        .shadow(color: .black.opacity(0.20), radius: 18, y: 7)
    }

    private var navigationCapsule: some View {
        VStack(spacing: 9) {
            ProgressView(value: model.progress)
                .tint(Color(hex: 0x33C7A1))
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(routeClock(model.timeRemaining))
                        .font(pf(20, .bold))
                    Text(routeDistance(model.distanceRemaining)
                         + " · " + Tr("剩余"))
                        .font(pf(11.5))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                mapControl(icon: model.use3D ? "cube.fill" : "cube",
                           active: model.use3D) {
                    model.toggle3D()
                }
                Button {
                    model.endNavigation()
                } label: {
                    Text(Tr("结束"))
                        .font(pf(13.5, .semibold))
                        .foregroundStyle(.red)
                        .padding(.horizontal, 12)
                        .frame(height: 34)
                        .background(Color.red.opacity(0.10), in: Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(14)
        .background(.regularMaterial,
                    in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Color.white.opacity(scheme == .dark ? 0.11 : 0.42),
                        lineWidth: 0.6)
        }
        .shadow(color: .black.opacity(0.20), radius: 20, y: 9)
    }

    private func mapControl(icon: String,
                            active: Bool,
                            action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(active ? Color.white : Color.primary)
                .frame(width: 36, height: 36)
                .background(active ? Color(hex: 0x167E68)
                                   : Color.primary.opacity(0.06),
                            in: Circle())
        }
        .buttonStyle(.plain)
    }

    private var maneuverSymbol: String {
        let text = model.nextInstruction
        if text.contains("到达") { return "flag.checkered" }
        if text.contains("掉头") { return "arrow.uturn.backward" }
        if text.contains("左") { return "arrow.turn.up.left" }
        if text.contains("右") { return "arrow.turn.up.right" }
        if text.contains("环岛") { return "arrow.triangle.2.circlepath" }
        return "arrow.up"
    }

    private func routeClock(_ seconds: TimeInterval) -> String {
        let value = max(0, Int(seconds.rounded()))
        if value >= 3600 {
            return "\(value / 3600) " + Tr("小时")
                + " \(value % 3600 / 60) " + Tr("分钟")
        }
        return "\(max(1, value / 60)) " + Tr("分钟")
    }

    private func routeDistance(_ meters: Double) -> String {
        if meters >= 1000 {
            return String(format: "%.1f km", meters / 1000)
        }
        return "\(max(0, Int(meters.rounded()))) m"
    }
}

private struct StarMapSurface: UIViewRepresentable {
    @ObservedObject var model: StarMapModel
    let dark: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> MKMapView {
        let map = MKMapView(frame: .zero)
        map.delegate = context.coordinator
        map.showsUserLocation = true
        map.showsBuildings = true
        map.showsTraffic = true
        map.showsCompass = true
        map.isPitchEnabled = true
        map.isRotateEnabled = true
        map.isZoomEnabled = true
        map.pointOfInterestFilter = .includingAll
        map.overrideUserInterfaceStyle = dark ? .dark : .light
        map.setRegion(
            MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: 31.2304,
                                               longitude: 121.4737),
                span: MKCoordinateSpan(latitudeDelta: 0.06,
                                       longitudeDelta: 0.06)
            ),
            animated: false
        )
        context.coordinator.map = map
        return map
    }

    func updateUIView(_ map: MKMapView, context: Context) {
        map.overrideUserInterfaceStyle = dark ? .dark : .light
        map.mapType = model.mapStyle.mapType
        context.coordinator.sync(map: map, model: model)
    }

    final class Coordinator: NSObject, MKMapViewDelegate {
        weak var map: MKMapView?
        private var glow: MKPolyline?
        private var core: MKPolyline?
        private var routeID: ObjectIdentifier?
        private var annotations: [MKPointAnnotation] = []
        private var lastCameraRevision = -1
        private var lastNavigationTimestamp = Date.distantPast

        func sync(map: MKMapView, model: StarMapModel) {
            syncRoute(map: map, model: model)
            syncAnnotations(map: map, model: model)
            syncCamera(map: map, model: model)
        }

        private func syncRoute(map: MKMapView, model: StarMapModel) {
            guard let route = model.route else {
                if let glow { map.removeOverlay(glow) }
                if let core { map.removeOverlay(core) }
                glow = nil
                core = nil
                routeID = nil
                return
            }
            let id = ObjectIdentifier(route)
            guard routeID != id else { return }
            if let glow { map.removeOverlay(glow) }
            if let core { map.removeOverlay(core) }
            let count = route.polyline.pointCount
            var points = Array(repeating: CLLocationCoordinate2D(),
                               count: count)
            route.polyline.getCoordinates(
                &points,
                range: NSRange(location: 0, length: count)
            )
            let wide = MKPolyline(coordinates: points, count: points.count)
            let line = MKPolyline(coordinates: points, count: points.count)
            glow = wide
            core = line
            routeID = id
            map.addOverlay(wide, level: .aboveRoads)
            map.addOverlay(line, level: .aboveRoads)
        }

        private func syncAnnotations(map: MKMapView, model: StarMapModel) {
            map.removeAnnotations(annotations)
            annotations.removeAll(keepingCapacity: true)
            if let destination = model.destination {
                let annotation = MKPointAnnotation()
                annotation.coordinate = destination.placemark.coordinate
                annotation.title = destination.name
                annotation.subtitle = destination.placemark.title
                annotations.append(annotation)
            } else {
                for item in model.results.prefix(10) {
                    let annotation = MKPointAnnotation()
                    annotation.coordinate = item.placemark.coordinate
                    annotation.title = item.name
                    annotation.subtitle = item.placemark.title
                    annotations.append(annotation)
                }
            }
            if !annotations.isEmpty {
                map.addAnnotations(annotations)
            }
        }

        private func syncCamera(map: MKMapView, model: StarMapModel) {
            if model.navigating, let location = model.location {
                guard location.timestamp.timeIntervalSince(lastNavigationTimestamp)
                        >= 0.8 || model.cameraRevision != lastCameraRevision else {
                    return
                }
                lastNavigationTimestamp = location.timestamp
                lastCameraRevision = model.cameraRevision
                let heading = location.course >= 0
                    ? location.course
                    : map.camera.heading
                let camera = MKMapCamera(
                    lookingAtCenter: location.coordinate,
                    fromDistance: model.use3D ? 560 : 760,
                    pitch: model.use3D ? 58 : 36,
                    heading: heading
                )
                map.setCamera(camera, animated: true)
                return
            }
            if model.cameraRevision != lastCameraRevision {
                lastCameraRevision = model.cameraRevision
                if let route = model.route {
                    map.setVisibleMapRect(
                        route.polyline.boundingMapRect,
                        edgePadding: UIEdgeInsets(top: 150, left: 50,
                                                  bottom: 190, right: 50),
                        animated: true
                    )
                } else if let location = model.location {
                    let camera = MKMapCamera(
                        lookingAtCenter: location.coordinate,
                        fromDistance: model.use3D ? 1_500 : 2_400,
                        pitch: model.use3D ? 46 : 20,
                        heading: 0
                    )
                    map.setCamera(camera, animated: true)
                }
            }
        }

        func mapView(_ mapView: MKMapView,
                     rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            guard let line = overlay as? MKPolyline else {
                return MKOverlayRenderer(overlay: overlay)
            }
            let renderer = MKPolylineRenderer(polyline: line)
            renderer.lineJoin = .round
            renderer.lineCap = .round
            if line === glow {
                renderer.strokeColor = UIColor(red: 0.20, green: 0.86,
                                               blue: 0.70, alpha: 0.18)
                renderer.lineWidth = 18
            } else {
                renderer.strokeColor = UIColor(red: 0.08, green: 0.62,
                                               blue: 0.49, alpha: 0.96)
                renderer.lineWidth = 6
            }
            return renderer
        }
    }
}
