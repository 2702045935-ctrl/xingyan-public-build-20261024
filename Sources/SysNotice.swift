import SwiftUI

struct SysNoticeInfo {
    var title = ""
    var text = ""

    init?(json: String) {
        guard let d = json.data(using: .utf8),
              let o = (try? JSONSerialization.jsonObject(with: d)) as? [String: Any] else { return nil }
        let t = (o["title"] as? String) ?? ""
        let b = (o["text"] as? String) ?? ""
        guard !t.isEmpty || !b.isEmpty else { return nil }
        title = t.isEmpty ? Tr("通知") : t
        text = b
    }

    var fullText: String {
        text.isEmpty ? title : (title + "\n\n" + text)
    }

    var preview: String { text.isEmpty ? title : text }
}

struct SysNoticeBubble: View {
    let info: SysNoticeInfo
    var onOpen: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {

            Text(info.title)
                .font(pf(16, .medium))
                .foregroundColor(C.label)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 13).padding(.vertical, 11)

            HairLine(inset: 0)

            if !info.text.isEmpty {
                Text(info.text)
                    .font(pf(15))
                    .foregroundColor(C.label.opacity(0.9))
                    .lineLimit(6)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 13).padding(.vertical, 11)

                HairLine(inset: 0)
            }

            HStack(spacing: 4) {
                Text(Tr("查看详情")).font(pf(15))
                Image(systemName: "chevron.right").font(.system(size: 11, weight: .semibold))
                Spacer(minLength: 0)
            }
            .foregroundColor(Color(hex: 0x576B95))
            .padding(.horizontal, 13).padding(.vertical, 10)
        }
        .frame(width: 252, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(C.cardBg))
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
            .stroke(C.hairline, lineWidth: 0.5))
        .contentShape(Rectangle())
        .onTapGesture { onOpen() }
    }
}
