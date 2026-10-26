import SwiftUI

enum MusicLRC {

    static func parse(_ raw: String?, duration: Double = 0) -> [(t: Double, text: String)] {
        guard let raw = raw, !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return [] }
        var out: [(Double, String)] = []
        let re = try? NSRegularExpression(pattern: "\\[(\\d{1,2}):(\\d{1,2})(?:[.:](\\d{1,3}))?\\]", options: [])
        for line in raw.components(separatedBy: .newlines) {
            let s = line.trimmingCharacters(in: .whitespaces)
            guard !s.isEmpty else { continue }
            if let re = re {
                let ns = s as NSString
                let ms = re.matches(in: s, options: [], range: NSRange(location: 0, length: ns.length))
                if !ms.isEmpty {
                    let text = ns.replacingCharacters(in: ms.first!.range, with: "")
                        .trimmingCharacters(in: .whitespaces)
                    for m in ms {
                        let mi = Int(ns.substring(with: m.range(at: 1))) ?? 0
                        let se = Int(ns.substring(with: m.range(at: 2))) ?? 0
                        var frac = 0.0
                        if m.range(at: 3).location != NSNotFound {
                            let f = ns.substring(with: m.range(at: 3))
                            frac = (Double(f) ?? 0) / pow(10.0, Double(f.count))
                        }
                        out.append((Double(mi) * 60 + Double(se) + frac, text))
                    }
                    continue
                }
            }

            if s.hasPrefix("[ti:") || s.hasPrefix("[ar:") || s.hasPrefix("[al:") || s.hasPrefix("[by:") { continue }
            out.append((-1, s))
        }
        var list = out.sorted { $0.0 < $1.0 }

        if list.allSatisfy({ $0.0 < 0 }) {
            let d = duration > 1 ? duration : Double(list.count) * 4
            let step = d / Double(max(1, list.count))
            list = list.enumerated().map { (Double($0.offset) * step, $0.element.1) }
        }
        return list.map { (t: max(0, $0.0), text: $0.1) }
    }

    static func index(at seconds: Double, in lines: [(t: Double, text: String)]) -> Int {
        var idx = -1
        for (i, l) in lines.enumerated() where l.t <= seconds + 0.15 { idx = i }
        return idx
    }
}

struct LyricsView: View {
    let raw: String?

    let seconds: Double

    var duration: Double = 0

    var onSeek: (Double) -> Void

    private var lines: [(t: Double, text: String)] { MusicLRC.parse(raw, duration: duration) }

    var body: some View {
        let ls = lines
        if ls.isEmpty {
            VStack(spacing: 6) {
                Image(systemName: "music.note.list")
                    .font(.system(size: 30, weight: .light)).foregroundColor(C.subLabel.opacity(0.7))
                Text(Tr("暂无歌词")).font(pf(13.5)).foregroundColor(C.subLabel)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollViewReader { proxy in
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 14) {
                        Spacer().frame(height: 26)
                        ForEach(ls.indices, id: \.self) { i in
                            let cur = MusicLRC.index(at: seconds, in: ls)
                            Text(ls[i].text.isEmpty ? "♪" : ls[i].text)
                                .font(pf(i == cur ? 16.5 : 15, i == cur ? .semibold : .regular))
                                .foregroundColor(i == cur ? C.label : C.subLabel)
                                .multilineTextAlignment(.center)
                                .frame(maxWidth: .infinity)
                                .id(i)
                                .contentShape(Rectangle())

                                .highPriorityGesture(TapGesture().onEnded { onSeek(ls[i].t) })
                        }
                        Spacer().frame(height: 90)
                    }
                    .padding(.horizontal, 22)
                }
                .onChange(of: MusicLRC.index(at: seconds, in: ls)) { i in
                    guard i >= 0 else { return }
                    withAnimation(.easeInOut(duration: 0.28)) { proxy.scrollTo(i, anchor: .center) }
                }
            }
        }
    }
}
