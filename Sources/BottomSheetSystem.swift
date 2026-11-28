import SwiftUI

struct BottomChoiceItem: Identifiable {
    let id: String
    let title: String
    var detail: String = ""
    let symbol: String
    var tint: Color = C.green
}

struct BottomChoiceSheet: View {
    let title: String
    let headerSymbol: String
    let items: [BottomChoiceItem]
    let onSelect: (String) -> Void

    @Environment(\.dismiss) private var dismiss

    static func preferredHeight(itemCount: Int) -> CGFloat {
        CGFloat(154 + max(1, itemCount) * 58)
    }

    var body: some View {
        VStack(spacing: 10) {
            Capsule()
                .fill(C.subLabel.opacity(0.24))
                .frame(width: 36, height: 4)
                .padding(.top, 10)

            HStack(spacing: 10) {
                Image(systemName: headerSymbol)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 38, height: 38)
                    .background(C.green,
                                in: RoundedRectangle(cornerRadius: 11,
                                                     style: .continuous))
                Text(title)
                    .font(pf(18, .semibold))
                    .foregroundColor(C.label)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 18)
            .padding(.top, 2)

            ForEach(items) { item in
                choiceRow(item)
            }

            Button {
                dismiss()
            } label: {
                Text(Tr("取消"))
                    .font(pf(16, .medium))
                    .foregroundColor(C.label)
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .background(C.controlSurface,
                                in: RoundedRectangle(cornerRadius: 15,
                                                     style: .continuous))
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 18)

            Spacer(minLength: 8)
        }
        .background(C.pageBg.ignoresSafeArea())
    }

    private func choiceRow(_ item: BottomChoiceItem) -> some View {
        Button {
            dismiss()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) {
                onSelect(item.id)
            }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: item.symbol)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(item.tint)
                    .frame(width: 36, height: 36)
                    .background(item.tint.opacity(0.11),
                                in: RoundedRectangle(cornerRadius: 10,
                                                     style: .continuous))

                VStack(alignment: .leading, spacing: 2) {
                    Text(item.title)
                        .font(pf(15.5, .medium))
                        .foregroundColor(C.label)
                    if !item.detail.isEmpty {
                        Text(item.detail)
                            .font(pf(11.5))
                            .foregroundColor(C.subLabel)
                    }
                }

                Spacer(minLength: 0)

                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(C.subLabel.opacity(0.7))
            }
            .padding(.horizontal, 13)
            .frame(height: 58)
            .background(C.cardBg,
                        in: RoundedRectangle(cornerRadius: 15,
                                             style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 18)
    }
}
