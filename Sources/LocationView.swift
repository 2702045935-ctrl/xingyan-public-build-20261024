import SwiftUI
import MapKit
import UIKit

struct LocationPoint: Identifiable, Equatable {
    var lat: Double
    var lng: Double
    var name: String
    var addr: String

    var id: String { String(format: "%.6f,%.6f", lat, lng) }
    var coord: CLLocationCoordinate2D { CLLocationCoordinate2D(latitude: lat, longitude: lng) }
    var title: String { name.isEmpty ? "位置" : name }

    static func parse(_ json: String) -> LocationPoint? {
        guard let data = json.data(using: .utf8),
              let o = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        let lat = (o["lat"] as? Double) ?? Double(o["lat"] as? String ?? "") ?? 0
        let lng = (o["lng"] as? Double) ?? Double(o["lng"] as? String ?? "") ?? 0
        guard lat != 0 || lng != 0 else { return nil }
        return LocationPoint(lat: lat, lng: lng,
                             name: (o["name"] as? String) ?? "",
                             addr: (o["addr"] as? String) ?? "")
    }

    var navigateURL: URL? {
        let q = title.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        return URL(string: "http://maps.apple.com/?daddr=\(lat),\(lng)&q=\(q)&dirflg=d")
    }
}

struct MapSnapshotView: View {
    let point: LocationPoint
    var width: CGFloat = 216
    var height: CGFloat = 136

    var drawPin: Bool = true

    @State private var image: UIImage?

    private static let cache = NSCache<NSString, UIImage>()

    var body: some View {
        ZStack {
            Color(hex: 0xE8E8E8)
            if let image = image {
                Image(uiImage: image).resizable().aspectRatio(contentMode: .fill)
            } else {
                Image(systemName: "map")
                    .font(.system(size: 22))
                    .foregroundColor(Color(hex: 0xB0B0B0))
            }
        }
        .frame(width: width, height: height)
        .clipped()
        .task(id: point.id + "\(Int(width))x\(Int(height))") { await load() }
    }

    private func load() async {
        let key = "\(point.id)@\(Int(width))x\(Int(height))\(drawPin ? "p" : "")" as NSString
        if let hit = MapSnapshotView.cache.object(forKey: key) { image = hit; return }

        let scale = await MainActor.run { UIScreen.main.scale }
        let opts = MKMapSnapshotter.Options()
        opts.region = MKCoordinateRegion(center: point.coord,
                                         span: MKCoordinateSpan(latitudeDelta: 0.004, longitudeDelta: 0.004))
        opts.size = CGSize(width: width, height: height)
        opts.scale = scale
        opts.mapType = .standard
        let snap = MKMapSnapshotter(options: opts)
        let shot = try? await snap.start()
        guard let shot = shot else { return }
        guard drawPin else { image = shot.image; MapSnapshotView.cache.setObject(shot.image, forKey: key); return }

        let size = CGSize(width: width, height: height)
        let renderer = UIGraphicsImageRenderer(size: size)
        let out = renderer.image { _ in
            shot.image.draw(in: CGRect(origin: .zero, size: size))
            let cx = size.width / 2, cy = size.height / 2
            let r: CGFloat = 7
            let pin = UIBezierPath()
            pin.move(to: CGPoint(x: cx, y: cy + 14))
            pin.addLine(to: CGPoint(x: cx - r, y: cy))
            pin.addArc(withCenter: CGPoint(x: cx, y: cy - 2), radius: r,
                       startAngle: .pi, endAngle: 0, clockwise: true)
            pin.close()
            UIColor.white.setStroke()
            pin.lineWidth = 2
            UIColor(red: 0.98, green: 0.32, blue: 0.32, alpha: 1).setFill()
            pin.fill()
            pin.stroke()
            let dot = UIBezierPath(ovalIn: CGRect(x: cx - 2.4, y: cy - 4.4, width: 4.8, height: 4.8))
            UIColor.white.setFill()
            dot.fill()
        }
        image = out
        MapSnapshotView.cache.setObject(out, forKey: key)
    }
}

struct LocationDetailView: View {
    let point: LocationPoint

    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var copied = false

    @State private var pickMap = false

    var body: some View {
        VStack(spacing: 0) {
            NavBar(title: point.title, back: { dismiss() })
            MapBigView(point: point)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            VStack(alignment: .leading, spacing: 10) {
                Text(point.title)
                    .font(pf(17, .medium))
                    .foregroundColor(C.label)
                if !point.addr.isEmpty {
                    Text(point.addr)
                        .font(pf(13))
                        .foregroundColor(C.subLabel)
                }
                HStack(spacing: 10) {
                    Button {

                        pickMap = true
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "arrow.triangle.turn.up.right.circle.fill")
                            Text(Tr("导航"))
                        }
                        .font(pf(15, .medium))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 42)
                        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(C.green))
                    }
                    .buttonStyle(.plain)
                    Button {
                        UIPasteboard.general.string = ([point.title, point.addr].filter { !$0.isEmpty }).joined(separator: " ")
                        copied = true
                        app.show(Tr("地址已复制"))
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "doc.on.doc")
                            Text(copied ? Tr("已复制") : Tr("复制地址"))
                        }
                        .font(pf(15, .medium))
                        .foregroundColor(C.label)
                        .frame(maxWidth: .infinity)
                        .frame(height: 42)
                        .background { CardGlassBox(radius: 8) }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(C.cardBg)
        }
        .confirmationDialog(Tr("用哪个地图打开"), isPresented: $pickMap, titleVisibility: .visible) {
            ForEach(MapApp.allCases) { m in
                Button(m.rawValue) { MapLink.open(m, point: point) }
            }
            Button(Tr("取消"), role: .cancel) { }
        }
        .background(C.pageBg.ignoresSafeArea(edges: .top))
        .toolbar(.hidden, for: .navigationBar)
        .swipeBack { dismiss() }
    }
}

struct MapBigView: UIViewRepresentable {
    let point: LocationPoint

    func makeUIView(context: Context) -> MKMapView {
        let v = MKMapView()
        v.isRotateEnabled = false
        v.isPitchEnabled = false
        v.showsCompass = false
        v.pointOfInterestFilter = .includingAll
        let ann = MKPointAnnotation()
        ann.coordinate = point.coord
        ann.title = point.title
        if !point.addr.isEmpty { ann.subtitle = point.addr }
        v.addAnnotation(ann)
        v.setRegion(MKCoordinateRegion(center: point.coord,
                                       span: MKCoordinateSpan(latitudeDelta: 0.006, longitudeDelta: 0.006)),
                    animated: false)
        v.selectAnnotation(ann, animated: false)
        return v
    }

    func updateUIView(_ v: MKMapView, context: Context) { }
}
