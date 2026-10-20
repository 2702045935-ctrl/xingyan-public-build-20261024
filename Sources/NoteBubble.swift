import SwiftUI

struct NoteCardBubble: View {

    let text: String
    var mine: Bool
    var showTail: Bool
    var seed: Double

    @State private var open = false

    private var title: String {
        let first = text.split(separator: "\n").first.map(String.init) ?? text
        let t = first.hasPrefix("[图]") ? "图片" : first
        return String(t.prefix(24))
    }
    private var preview: String {
        var lines: [String] = []
        for line in text.components(separatedBy: "\n") {
            if line.hasPrefix("[图]") { lines.append("［图片］"); continue }
            if !line.trimmingCharacters(in: .whitespaces).isEmpty { lines.append(line) }
            if lines.count >= 4 { break }
        }
        return lines.joined(separator: "\n")
    }

    var body: some View {
        Button { open = true } label: {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Image(systemName: "doc.text.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(C.green)
                    Text(Tr("笔记"))
                        .font(pf(12.5, .medium))
                        .foregroundColor(C.green)
                    Spacer(minLength: 0)
                }
                Text(title.isEmpty ? Tr("笔记") : title)
                    .font(pf(15, .medium))
                    .foregroundColor(C.label)
                    .lineLimit(1)
                Text(preview)
                    .font(pf(13))
                    .foregroundColor(C.subLabel)
                    .lineLimit(3)
                    .multilineTextAlignment(.leading)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(width: 232, alignment: .leading)
            .background(Color.dyn(0xFFFFFF, 0x1F1F22))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(C.hairline, lineWidth: 0.6))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $open) {
            NoteViewerSheet(text: text)
        }
    }
}

struct NoteViewerSheet: View {
    @Environment(\.dismiss) private var dismiss
    let text: String
    @State private var copied = false

    @State private var viewerPath: String?

    var body: some View {
        VStack(spacing: 0) {
            NavBar(title: Tr("笔记"), back: { dismiss() }) {
                Button {
                    UIPasteboard.general.string = text
                    copied = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) { copied = false }
                } label: {
                    Text(copied ? Tr("已复制") : Tr("复制"))
                        .font(pf(15, .medium)).foregroundColor(C.green)
                        .padding(.horizontal, 14).frame(height: 32)
                }
                .buttonStyle(.plain)
            }
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(Array(text.components(separatedBy: "\n").enumerated()), id: \.offset) { _, line in
                        if line.hasPrefix("[图]") {

                            NoteImageBlock(path: String(line.dropFirst(3))) { p in viewerPath = p }
                        } else if !line.isEmpty {
                            Text(line)
                                .font(pf(16))
                                .foregroundColor(C.label)
                                .textSelection(.enabled)
                                .fixedSize(horizontal: false, vertical: true)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
                .padding(14)
                .background(C.cardBg)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .padding(.horizontal, 12)
                .padding(.top, 12)
                Spacer().frame(height: 30)
            }
            .background(C.pageBg)
        }
        .background(C.pageBg.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .swipeBack { dismiss() }
        .overlay {
            if let p = viewerPath, !p.isEmpty {
                PhotoPager(paths: [p], startIndex: 0, showActions: true) { viewerPath = nil }
            }
        }
    }
}

struct NoteImageBlock: View {
    let path: String

    var onTap: ((String) -> Void)? = nil

    @State private var height: CGFloat = 210

    var body: some View {
        RemoteImage(path: path, mode: .fill, maxSide: 1400) { img in

            let w = max(120, L.width - 52)
            let ratio = img.size.height / max(1, img.size.width)
            height = min(360, max(120, w * ratio))
        }
        .frame(maxWidth: .infinity)
        .frame(height: height)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .contentShape(Rectangle())
        .onTapGesture { onTap?(path) }
    }
}
