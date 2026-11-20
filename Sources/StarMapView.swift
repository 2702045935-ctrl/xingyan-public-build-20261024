import AVFoundation
import CoreLocation
import MapKit
import SwiftUI
import UIKit

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

    func coordinate(at distance: Double) -> CLLocationCoordinate2D? {
        guard coordinates.count >= 2, cumulative.count == coordinates.count else {
            return coordinates.first
        }
        let target = max(0, min(total, distance))
        guard let upper = cumulative.firstIndex(where: { $0 >= target }) else {
            return coordinates.last
        }
        if upper == 0 { return coordinates[0] }
        let lower = upper - 1
        let span = cumulative[upper] - cumulative[lower]
        let fraction = span > 0
            ? (target - cumulative[lower]) / span
            : 0
        let a = coordinates[lower]
        let b = coordinates[upper]
        return CLLocationCoordinate2D(
            latitude: a.latitude + (b.latitude - a.latitude) * fraction,
            longitude: a.longitude + (b.longitude - a.longitude) * fraction
        )
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
    @Published var followingInstruction = ""
    @Published var followingDistance: Double = 0
    @Published var navigationCenter: CLLocationCoordinate2D?
    @Published var currentSpeed: Double = 0
    @Published var voiceGuidanceEnabled = true
    @Published var showingRouteOverview = false
    @Published var cameraRevision = 0
    @Published var authorizationDenied = false

    private let manager = CLLocationManager()
    private let geocoder = CLGeocoder()
    private let speech = AVSpeechSynthesizer()
    private var geometry: StarRouteGeometry?
    private var offRouteSamples = 0
    private var lastRerouteAt = Date.distantPast
    private var routeRequest: MKDirections?
    private var didReverseGeocode = false
    private var lastAcceptedAt = Date.distantPast
    private var lastSpokenInstruction = ""

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
        followingInstruction = ""
        followingDistance = 0
        navigationCenter = nil
        currentSpeed = 0
        showingRouteOverview = false
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
        showingRouteOverview = false
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
        showingRouteOverview = false
        offRouteSamples = 0
        lastSpokenInstruction = ""
        manager.activityType = travelMode == .walking
            ? .fitness : .automotiveNavigation
        manager.startUpdatingLocation()
        speakCurrentInstruction()
        cameraRevision += 1
    }

    func endNavigation() {
        navigating = false
        showingRouteOverview = false
        navigationCenter = nil
        speech.stopSpeaking(at: .immediate)
        cameraRevision += 1
    }

    func recenter() {
        showingRouteOverview = false
        cameraRevision += 1
    }

    func toggleRouteOverview() {
        showingRouteOverview.toggle()
        cameraRevision += 1
    }

    func toggleVoiceGuidance() {
        voiceGuidanceEnabled.toggle()
        if !voiceGuidanceEnabled {
            speech.stopSpeaking(at: .immediate)
            return
        }
        speakCurrentInstruction()
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
        currentSpeed = max(0, next.speed) * 3.6
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
        let lookAhead = travelMode == .walking ? 45.0 : 105.0
        navigationCenter = geometry.coordinate(
            at: min(geometry.total, match.along + lookAhead)
        )
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
            showingRouteOverview = false
            navigationCenter = nil
            nextInstruction = Tr("已到达目的地")
            nextDistance = 0
            followingInstruction = ""
            followingDistance = 0
            speech.stopSpeaking(at: .immediate)
        }
    }

    private func updateInstruction(along: Double) {
        guard let geometry else { return }
        var activeStep: StarRouteGeometry.Step?
        if let step = geometry.nextStep(after: along),
           !step.instruction.isEmpty {
            activeStep = step
            nextInstruction = step.instruction
            nextDistance = max(0, step.start - along)
        } else if let last = geometry.steps.last,
                  !last.instruction.isEmpty {
            activeStep = last
            nextInstruction = last.instruction
            nextDistance = max(0, geometry.total - along)
        } else {
            nextInstruction = Tr("沿当前道路继续行驶")
            nextDistance = max(0, geometry.total - along)
        }

        if let activeStep,
           let following = geometry.steps.first(
               where: { $0.start > activeStep.start + 12 }
           ),
           !following.instruction.isEmpty {
            followingInstruction = following.instruction
            followingDistance = max(0, following.start - along)
        } else {
            followingInstruction = ""
            followingDistance = 0
        }
        if navigating {
            speakIfNeeded()
        }
    }

    private func speakCurrentInstruction() {
        guard navigating,
              voiceGuidanceEnabled,
              !nextInstruction.isEmpty else { return }
        lastSpokenInstruction = ""
        speakIfNeeded()
    }

    private func speakIfNeeded() {
        guard voiceGuidanceEnabled,
              nextInstruction != lastSpokenInstruction else { return }
        lastSpokenInstruction = nextInstruction
        let lead = nextDistance < 30
            ? Tr("现在")
            : "\(max(10, Int(nextDistance.rounded(.toNearestOrAwayFromZero))))"
                + Tr("米后")
        let utterance = AVSpeechUtterance(
            string: lead + nextInstruction
        )
        utterance.voice = AVSpeechSynthesisVoice(language: "zh-CN")
        utterance.rate = 0.48
        utterance.pitchMultiplier = 1.0
        utterance.volume = 0.92
        speech.stopSpeaking(at: .immediate)
        speech.speak(utterance)
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

            Group {
                if model.navigating {
                    navigationChrome
                        .transition(.opacity.combined(with: .move(edge: .top)))
                } else {
                    browseChrome
                        .transition(.opacity)
                }
            }
            .padding(.horizontal, 14)
            .padding(.top, max(10, L.safeTop + 8))
            .padding(.bottom, max(12, L.safeBottom + 8))
            .animation(
                .spring(response: 0.42, dampingFraction: 0.88),
                value: model.navigating
            )

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

            if !model.error.isEmpty,
               !model.searching,
               !model.routing {
                Text(model.error)
                    .font(pf(12.5, .medium))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(.regularMaterial, in: Capsule())
                    .shadow(color: .black.opacity(0.14), radius: 12, y: 5)
                    .padding(.horizontal, 28)
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

    private var browseChrome: some View {
        VStack(spacing: 10) {
            searchHeader

            if !model.results.isEmpty {
                searchResults
            }

            Spacer(minLength: 0)

            if let route = model.route {
                routeCapsule(route)
            } else {
                exploreCapsule
            }
        }
    }

    private var navigationChrome: some View {
        VStack(spacing: 9) {
            navigationInstructionCard

            if !model.followingInstruction.isEmpty {
                followingInstructionStrip
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }

            Spacer(minLength: 0)
            navigationTripCard
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
            mapControl(kind: model.use3D ? .cubeOn : .cube,
                       active: model.use3D) {
                model.toggle3D()
            }
            mapControl(kind: model.mapStyle == .satellite ? .satellite : .layers,
                       active: model.mapStyle != .standard) {
                model.cycleMapStyle()
            }
            mapControl(kind: .locate, active: false) {
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
        VStack(spacing: 13) {
            HStack(spacing: 12) {
                StarMapControlIcon(kind: .route, size: 44)
                VStack(alignment: .leading, spacing: 4) {
                    Text(model.destination?.name ?? Tr("目的地"))
                        .font(pf(18, .semibold))
                        .lineLimit(1)
                    Text(model.destination?.placemark.title ?? Tr("准备出发"))
                        .font(pf(12))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 6)
                Button {
                    model.clearDestination()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.secondary)
                        .frame(width: 34, height: 34)
                        .background(Color.primary.opacity(0.055), in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Tr("关闭路线"))
            }

            HStack(spacing: 7) {
                ForEach(StarTravelMode.allCases) { mode in
                    Button {
                        model.setTravelMode(mode)
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: mode.symbol)
                                .font(.system(size: 13, weight: .semibold))
                            Text(mode.title)
                                .font(pf(13, .semibold))
                        }
                        .foregroundStyle(model.travelMode == mode
                                         ? Color(hex: 0x0A6ED1) : Color.primary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 36)
                        .background(model.travelMode == mode
                                    ? Color(hex: 0x0A84FF).opacity(0.13)
                                    : Color.primary.opacity(0.055),
                                    in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }

            if model.routes.count > 1 {
                routeOptions
            }

            HStack(alignment: .center, spacing: 13) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(routeClock(route.expectedTravelTime))
                        .font(pf(25, .bold))
                        .monospacedDigit()
                    Text(routeDistance(route.distance)
                         + " · " + arrivalClock(route.expectedTravelTime))
                        .font(pf(12.5, .medium))
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                Button {
                    model.startNavigation()
                } label: {
                    HStack(spacing: 7) {
                        Image(systemName: "location.north.fill")
                            .font(.system(size: 13, weight: .bold))
                        Text(Tr("开始导航"))
                            .font(pf(15, .semibold))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 18)
                    .frame(height: 46)
                    .background(
                        LinearGradient(
                            colors: [
                                Color(hex: 0x189BFF),
                                Color(hex: 0x006EDC)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        in: Capsule()
                    )
                    .shadow(color: Color(hex: 0x007AFF).opacity(0.25),
                            radius: 9, y: 4)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(16)
        .background(.regularMaterial,
                    in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .stroke(Color.white.opacity(scheme == .dark ? 0.12 : 0.44),
                        lineWidth: 0.6)
        }
        .shadow(color: .black.opacity(0.22), radius: 24, y: 11)
    }

    private var routeOptions: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(Array(model.routes.prefix(3).enumerated()),
                        id: \.offset) { index, value in
                    let selected = model.route.map {
                        ObjectIdentifier($0)
                    } == ObjectIdentifier(value)
                    Button {
                        model.selectRoute(value)
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 5) {
                                Text(index == 0 ? Tr("推荐") : Tr("方案")
                                     + " \(index + 1)")
                                    .font(pf(11.5, .semibold))
                                    .foregroundStyle(
                                        selected ? Color(hex: 0x0A6ED1)
                                                 : Color.secondary
                                    )
                                Spacer(minLength: 0)
                                if selected {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 10, weight: .bold))
                                        .foregroundStyle(Color(hex: 0x0A84FF))
                                }
                            }
                            Text(routeClock(value.expectedTravelTime))
                                .font(pf(16, .semibold))
                                .monospacedDigit()
                            Text(routeDistance(value.distance))
                                .font(pf(11.5, .medium))
                                .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 12)
                        .frame(width: 118, height: 70, alignment: .leading)
                        .background(
                            selected
                                ? Color(hex: 0x0A84FF).opacity(0.12)
                                : Color.primary.opacity(0.045),
                            in: RoundedRectangle(
                                cornerRadius: 15,
                                style: .continuous
                            )
                        )
                        .overlay {
                            RoundedRectangle(
                                cornerRadius: 15,
                                style: .continuous
                            )
                            .stroke(
                                selected
                                    ? Color(hex: 0x0A84FF).opacity(0.35)
                                    : Color.primary.opacity(0.04),
                                lineWidth: 0.7
                            )
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var navigationInstructionCard: some View {
        HStack(alignment: .center, spacing: 14) {
            StarManeuverIcon(kind: maneuverKind, size: 62)
            VStack(alignment: .leading, spacing: 5) {
                Text(routeDistance(model.nextDistance))
                    .font(pf(14, .bold))
                    .foregroundStyle(Color(hex: 0x0A84FF))
                    .monospacedDigit()
                Text(model.nextInstruction)
                    .font(pf(21, .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .minimumScaleFactor(0.80)
            }
            Spacer(minLength: 0)
            Button {
                model.toggleVoiceGuidance()
            } label: {
                Image(systemName: model.voiceGuidanceEnabled
                      ? "speaker.wave.2.fill" : "speaker.slash.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.primary)
                    .frame(width: 36, height: 36)
                    .background(Color.primary.opacity(0.06), in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(
                model.voiceGuidanceEnabled ? Tr("关闭语音") : Tr("开启语音")
            )
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(.regularMaterial,
                    in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .stroke(Color.white.opacity(scheme == .dark ? 0.13 : 0.46),
                        lineWidth: 0.6)
        }
        .shadow(color: .black.opacity(0.23), radius: 24, y: 10)
    }

    private var followingInstructionStrip: some View {
        HStack(spacing: 9) {
            StarManeuverIcon(kind: followingManeuverKind, size: 28)
            Text(model.followingInstruction)
                .font(pf(13, .medium))
                .foregroundStyle(.primary)
                .lineLimit(1)
            Spacer(minLength: 6)
            if model.followingDistance > 0 {
                Text(routeDistance(model.followingDistance))
                    .font(pf(11.5, .semibold))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
        .padding(.horizontal, 11)
        .frame(height: 48)
        .background(.thinMaterial,
                    in: RoundedRectangle(cornerRadius: 17, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 17, style: .continuous)
                .stroke(Color.white.opacity(scheme == .dark ? 0.11 : 0.42),
                        lineWidth: 0.6)
        }
        .shadow(color: .black.opacity(0.15), radius: 14, y: 6)
    }

    private var navigationTripCard: some View {
        VStack(spacing: 13) {
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.primary.opacity(0.08))
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color(hex: 0x46B4FF),
                                    Color(hex: 0x007AFF)
                                ],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(
                            width: max(5,
                                       geometry.size.width
                                       * max(0.015, model.progress))
                        )
                }
            }
            .frame(height: 4)

            HStack(alignment: .center, spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(Tr("预计到达")
                         + " " + arrivalClock(model.timeRemaining))
                        .font(pf(17, .semibold))
                    Text(routeClock(model.timeRemaining)
                         + " · " + routeDistance(model.distanceRemaining)
                         + " " + Tr("剩余"))
                        .font(pf(12, .medium))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                Spacer(minLength: 6)
                mapControl(kind: model.showingRouteOverview
                           ? .overviewOn : .overview,
                           active: model.showingRouteOverview) {
                    model.toggleRouteOverview()
                }
                mapControl(kind: model.use3D ? .cubeOn : .cube,
                           active: model.use3D) {
                    model.toggle3D()
                }
                Button {
                    model.endNavigation()
                } label: {
                    Text(Tr("结束"))
                        .font(pf(13.5, .semibold))
                        .foregroundStyle(.red)
                        .padding(.horizontal, 13)
                        .frame(height: 36)
                        .background(Color.red.opacity(0.10), in: Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Tr("结束导航"))
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 13)
        .padding(.bottom, 14)
        .background(.regularMaterial,
                    in: RoundedRectangle(cornerRadius: 25, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 25, style: .continuous)
                .stroke(Color.white.opacity(scheme == .dark ? 0.13 : 0.46),
                        lineWidth: 0.6)
        }
        .shadow(color: .black.opacity(0.23), radius: 24, y: 10)
    }

    private func mapControl(kind: StarMapControlKind,
                            active: Bool,
                            action: @escaping () -> Void) -> some View {
        Button(action: action) {
            StarMapControlIcon(kind: kind, size: 36, active: active)
        }
        .buttonStyle(.plain)
    }

    private var maneuverKind: StarManeuverKind {
        maneuverKind(for: model.nextInstruction)
    }

    private var followingManeuverKind: StarManeuverKind {
        maneuverKind(for: model.followingInstruction)
    }

    private func maneuverKind(for text: String) -> StarManeuverKind {
        if text.contains("到达") { return .arrive }
        if text.contains("向右前方") || text.contains("稍向右") {
            return .slightRight
        }
        if text.contains("向左前方") || text.contains("稍向左") {
            return .slightLeft
        }
        if text.contains("掉头") { return .uTurn }
        if text.contains("环岛") { return .roundabout }
        if text.contains("左") { return .left }
        if text.contains("右") { return .right }
        return .straight
    }

    private func arrivalClock(_ seconds: TimeInterval) -> String {
        let formatter = DateFormatter()
        formatter.locale = .current
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        return formatter.string(
            from: Date().addingTimeInterval(max(0, seconds))
        )
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

private enum StarManeuverKind {
    case straight, left, right, slightLeft, slightRight, uTurn, roundabout, arrive
}

private struct StarManeuverIcon: View {
    let kind: StarManeuverKind
    let size: CGFloat

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.28,
                             style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(hex: 0x2F86FF),
                            Color(hex: 0x0B5ED7)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            RoundedRectangle(cornerRadius: size * 0.28,
                             style: .continuous)
                .stroke(Color.white.opacity(0.32), lineWidth: 0.8)
            Canvas { context, canvas in
                var path = Path()
                let p: (CGFloat, CGFloat) -> CGPoint = {
                    CGPoint(x: $0 * canvas.width, y: $1 * canvas.height)
                }
                let width = max(3.8, size * 0.095)
                switch kind {
                case .straight:
                    path.move(to: p(0.50, 0.88))
                    path.addLine(to: p(0.50, 0.18))
                    path.move(to: p(0.36, 0.32))
                    path.addLine(to: p(0.50, 0.16))
                    path.addLine(to: p(0.64, 0.32))
                case .left:
                    path.move(to: p(0.53, 0.88))
                    path.addLine(to: p(0.53, 0.48))
                    path.addQuadCurve(to: p(0.28, 0.29),
                                      control: p(0.53, 0.29))
                    path.addLine(to: p(0.17, 0.29))
                    path.move(to: p(0.31, 0.15))
                    path.addLine(to: p(0.15, 0.29))
                    path.addLine(to: p(0.31, 0.43))
                case .right:
                    path.move(to: p(0.47, 0.88))
                    path.addLine(to: p(0.47, 0.48))
                    path.addQuadCurve(to: p(0.72, 0.29),
                                      control: p(0.47, 0.29))
                    path.addLine(to: p(0.83, 0.29))
                    path.move(to: p(0.69, 0.15))
                    path.addLine(to: p(0.85, 0.29))
                    path.addLine(to: p(0.69, 0.43))
                case .slightLeft:
                    path.move(to: p(0.62, 0.88))
                    path.addLine(to: p(0.62, 0.55))
                    path.addLine(to: p(0.35, 0.22))
                    path.move(to: p(0.34, 0.41))
                    path.addLine(to: p(0.34, 0.20))
                    path.addLine(to: p(0.55, 0.20))
                case .slightRight:
                    path.move(to: p(0.38, 0.88))
                    path.addLine(to: p(0.38, 0.55))
                    path.addLine(to: p(0.65, 0.22))
                    path.move(to: p(0.45, 0.20))
                    path.addLine(to: p(0.66, 0.20))
                    path.addLine(to: p(0.66, 0.41))
                case .uTurn:
                    path.move(to: p(0.64, 0.88))
                    path.addLine(to: p(0.64, 0.42))
                    path.addQuadCurve(to: p(0.36, 0.42),
                                      control: p(0.50, 0.15))
                    path.addLine(to: p(0.36, 0.64))
                    path.move(to: p(0.22, 0.50))
                    path.addLine(to: p(0.36, 0.66))
                    path.addLine(to: p(0.50, 0.50))
                case .roundabout:
                    path.addEllipse(in: CGRect(x: canvas.width * 0.22,
                                               y: canvas.height * 0.20,
                                               width: canvas.width * 0.50,
                                               height: canvas.height * 0.50))
                    path.move(to: p(0.66, 0.25))
                    path.addLine(to: p(0.84, 0.16))
                    path.move(to: p(0.70, 0.13))
                    path.addLine(to: p(0.86, 0.15))
                    path.addLine(to: p(0.84, 0.31))
                case .arrive:
                    path.move(to: p(0.31, 0.86))
                    path.addLine(to: p(0.31, 0.15))
                    path.move(to: p(0.31, 0.18))
                    path.addLine(to: p(0.78, 0.31))
                    path.addLine(to: p(0.31, 0.45))
                }
                context.stroke(
                    path,
                    with: .color(.white),
                    style: StrokeStyle(
                        lineWidth: width,
                        lineCap: .round,
                        lineJoin: .round
                    )
                )
            }
            .padding(size * 0.13)
        }
        .frame(width: size, height: size)
        .shadow(color: Color(hex: 0x0B5ED7).opacity(0.24),
                radius: 8, y: 4)
        .accessibilityHidden(true)
    }
}

private enum StarMapControlKind {
    case cube, cubeOn, layers, satellite, locate, route, overview, overviewOn
}

private struct StarMapControlIcon: View {
    let kind: StarMapControlKind
    let size: CGFloat
    var active = false

    var body: some View {
        ZStack {
            Circle()
                .fill(active ? Color(hex: 0x1A73E8)
                             : Color.primary.opacity(0.055))
            Circle()
                .stroke(Color.white.opacity(active ? 0.30 : 0.16),
                        lineWidth: 0.7)
            Canvas { context, canvas in
                let color = active ? Color.white : Color.primary
                let c = CGPoint(x: canvas.width / 2, y: canvas.height / 2)
                let p: (CGFloat, CGFloat) -> CGPoint = {
                    CGPoint(x: $0 * canvas.width, y: $1 * canvas.height)
                }
                var path = Path()
                switch kind {
                case .cube, .cubeOn:
                    path.move(to: p(0.50, 0.14))
                    path.addLine(to: p(0.80, 0.31))
                    path.addLine(to: p(0.80, 0.68))
                    path.addLine(to: p(0.50, 0.86))
                    path.addLine(to: p(0.20, 0.68))
                    path.addLine(to: p(0.20, 0.31))
                    path.closeSubpath()
                    path.move(to: p(0.20, 0.31))
                    path.addLine(to: c)
                    path.addLine(to: p(0.80, 0.31))
                    path.move(to: c)
                    path.addLine(to: p(0.50, 0.86))
                case .layers:
                    for y in [0.30, 0.50, 0.70] {
                        path.move(to: p(0.50, y - 0.13))
                        path.addLine(to: p(0.78, y))
                        path.addLine(to: p(0.50, y + 0.13))
                        path.addLine(to: p(0.22, y))
                        path.closeSubpath()
                    }
                case .satellite:
                    path.addEllipse(in: CGRect(x: canvas.width * 0.20,
                                               y: canvas.height * 0.20,
                                               width: canvas.width * 0.60,
                                               height: canvas.height * 0.60))
                    path.move(to: p(0.16, 0.50))
                    path.addLine(to: p(0.84, 0.50))
                    path.move(to: p(0.50, 0.16))
                    path.addQuadCurve(to: p(0.50, 0.84),
                                      control: p(0.10, 0.50))
                    path.move(to: p(0.50, 0.16))
                    path.addQuadCurve(to: p(0.50, 0.84),
                                      control: p(0.90, 0.50))
                case .locate:
                    path.addEllipse(in: CGRect(x: canvas.width * 0.34,
                                               y: canvas.height * 0.34,
                                               width: canvas.width * 0.32,
                                               height: canvas.width * 0.32))
                    path.move(to: p(0.50, 0.10))
                    path.addLine(to: p(0.50, 0.90))
                    path.move(to: p(0.10, 0.50))
                    path.addLine(to: p(0.90, 0.50))
                case .route:
                    path.move(to: p(0.22, 0.72))
                    path.addCurve(to: p(0.78, 0.28),
                                  control1: p(0.50, 0.76),
                                  control2: p(0.50, 0.24))
                    path.addEllipse(in: CGRect(x: canvas.width * 0.14,
                                               y: canvas.height * 0.64,
                                               width: canvas.width * 0.16,
                                               height: canvas.width * 0.16))
                    path.addEllipse(in: CGRect(x: canvas.width * 0.70,
                                               y: canvas.height * 0.20,
                                               width: canvas.width * 0.16,
                                               height: canvas.width * 0.16))
                case .overview, .overviewOn:
                    path.move(to: p(0.14, 0.28))
                    path.addLine(to: p(0.39, 0.20))
                    path.addLine(to: p(0.61, 0.31))
                    path.addLine(to: p(0.86, 0.22))
                    path.addLine(to: p(0.86, 0.73))
                    path.addLine(to: p(0.61, 0.81))
                    path.addLine(to: p(0.39, 0.70))
                    path.addLine(to: p(0.14, 0.79))
                    path.closeSubpath()
                    path.move(to: p(0.39, 0.20))
                    path.addLine(to: p(0.39, 0.70))
                    path.move(to: p(0.61, 0.31))
                    path.addLine(to: p(0.61, 0.81))
                }
                context.stroke(
                    path,
                    with: .color(color),
                    style: StrokeStyle(
                        lineWidth: max(1.7, size * 0.055),
                        lineCap: .round,
                        lineJoin: .round
                    )
                )
            }
            .padding(size * 0.20)
        }
        .frame(width: size, height: size)
        .shadow(color: .black.opacity(active ? 0.18 : 0.06),
                radius: active ? 7 : 3, y: active ? 3 : 1)
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
        map.pointOfInterestFilter = model.navigating
            ? .excludingAll : .includingAll
        map.showsCompass = !model.navigating
        context.coordinator.sync(map: map, model: model)
    }

    final class Coordinator: NSObject, MKMapViewDelegate {
        weak var map: MKMapView?
        private var glow: MKPolyline?
        private var casing: MKPolyline?
        private var core: MKPolyline?
        private var routeID: ObjectIdentifier?
        private var annotations: [MKPointAnnotation] = []
        private var lastCameraRevision = -1
        private var lastNavigationTimestamp = Date.distantPast
        private var smoothedHeading: Double?
        private var travelMode = StarTravelMode.driving

        func sync(map: MKMapView, model: StarMapModel) {
            syncRoute(map: map, model: model)
            syncAnnotations(map: map, model: model)
            syncCamera(map: map, model: model)
        }

        private func syncRoute(map: MKMapView, model: StarMapModel) {
            guard let route = model.route else {
                if let glow { map.removeOverlay(glow) }
                if let casing { map.removeOverlay(casing) }
                if let core { map.removeOverlay(core) }
                glow = nil
                casing = nil
                core = nil
                routeID = nil
                return
            }
            let id = ObjectIdentifier(route)
            guard routeID != id else { return }
            if let glow { map.removeOverlay(glow) }
            if let casing { map.removeOverlay(casing) }
            if let core { map.removeOverlay(core) }
            let count = route.polyline.pointCount
            var points = Array(repeating: CLLocationCoordinate2D(),
                               count: count)
            route.polyline.getCoordinates(
                &points,
                range: NSRange(location: 0, length: count)
            )
            let wide = MKPolyline(coordinates: points, count: points.count)
            let border = MKPolyline(coordinates: points, count: points.count)
            let line = MKPolyline(coordinates: points, count: points.count)
            glow = wide
            casing = border
            core = line
            routeID = id
            travelMode = model.travelMode
            map.addOverlay(wide, level: .aboveRoads)
            map.addOverlay(border, level: .aboveRoads)
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
            if model.navigating,
               !model.showingRouteOverview,
               let location = model.location {
                guard location.timestamp.timeIntervalSince(lastNavigationTimestamp)
                        >= 0.8 || model.cameraRevision != lastCameraRevision else {
                    return
                }
                lastNavigationTimestamp = location.timestamp
                lastCameraRevision = model.cameraRevision
                let targetHeading = location.course >= 0
                    ? location.course
                    : map.camera.heading
                let heading = smoothedCourse(
                    target: targetHeading,
                    previous: smoothedHeading ?? map.camera.heading
                )
                smoothedHeading = heading
                let camera = MKMapCamera(
                    lookingAtCenter: model.navigationCenter
                        ?? location.coordinate,
                    fromDistance: model.use3D
                        ? (model.travelMode == .walking ? 410 : 520)
                        : (model.travelMode == .walking ? 620 : 760),
                    pitch: model.use3D
                        ? (model.travelMode == .walking ? 38 : 62)
                        : 32,
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
                                                  bottom: 220, right: 50),
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

        private func smoothedCourse(target: Double,
                                    previous: Double) -> Double {
            let delta = ((target - previous + 540).truncatingRemainder(
                dividingBy: 360
            )) - 180
            return (previous + delta * 0.22 + 360)
                .truncatingRemainder(dividingBy: 360)
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
                renderer.strokeColor = UIColor(red: 0.04, green: 0.49,
                                               blue: 1.0, alpha: 0.18)
                renderer.lineWidth = 24
            } else if line === casing {
                renderer.strokeColor = UIColor { traits in
                    traits.userInterfaceStyle == .dark
                        ? UIColor(red: 0.02, green: 0.22,
                                  blue: 0.42, alpha: 0.98)
                        : UIColor(red: 0.00, green: 0.28,
                                  blue: 0.60, alpha: 0.94)
                }
                renderer.lineWidth = 10
            } else {
                renderer.strokeColor = UIColor { traits in
                    traits.userInterfaceStyle == .dark
                        ? UIColor(red: 0.16, green: 0.66,
                                  blue: 1.0, alpha: 1.0)
                        : UIColor(red: 0.00, green: 0.48,
                                  blue: 1.0, alpha: 1.0)
                }
                renderer.lineWidth = 6.2
                if travelMode == .walking {
                    renderer.lineDashPattern = [0.1, 7]
                }
            }
            return renderer
        }

        func mapView(_ mapView: MKMapView,
                     viewFor annotation: MKAnnotation)
            -> MKAnnotationView? {
            guard annotation is MKPointAnnotation else { return nil }
            let identifier = "star-destination"
            let marker = mapView.dequeueReusableAnnotationView(
                withIdentifier: identifier
            ) as? MKMarkerAnnotationView
                ?? MKMarkerAnnotationView(
                    annotation: annotation,
                    reuseIdentifier: identifier
                )
            marker.annotation = annotation
            marker.canShowCallout = true
            marker.markerTintColor = UIColor(
                red: 0.00, green: 0.48, blue: 1.0, alpha: 1.0
            )
            marker.glyphTintColor = .white
            marker.glyphImage = UIImage(systemName: "sparkle")
            marker.displayPriority = .required
            return marker
        }
    }
}
