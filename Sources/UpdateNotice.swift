import SwiftUI

struct CenterCard: View {
    var title: String

    var text: String
    var primary: String
    var onPrimary: () -> Void
    var secondary: String? = nil
    var onSecondary: (() -> Void)? = nil

    var bodyText: String { text.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        ZStack {
            Color.black.opacity(0.35).ignoresSafeArea()
            VStack(alignment: .leading, spacing: 0) {
                if !title.isEmpty {
                    Text(title)
                        .font(pf(17, .semibold))
                        .foregroundColor(C.label)
                        .padding(.bottom, 10)
                }
                if !bodyText.isEmpty {
                    ScrollView {
                        Text(bodyText)
                            .font(pf(14.5))
                            .foregroundColor(C.label.opacity(0.85))
                            .lineSpacing(4)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(maxHeight: 300)
                }
                HStack(spacing: 10) {
                    if let sec = secondary, let act = onSecondary {
                        Button(action: act) {
                            Text(sec)
                                .font(pf(15))
                                .foregroundColor(C.subLabel)
                                .frame(maxWidth: .infinity).frame(height: 42)
                                .background(RoundedRectangle(cornerRadius: 10).fill(C.fieldBg))
                        }
                        .buttonStyle(.plain)
                    }
                    Button(action: onPrimary) {
                        Text(primary)
                            .font(pf(15, .medium))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity).frame(height: 42)
                            .background(RoundedRectangle(cornerRadius: 10).fill(C.green))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.top, 18)
            }
            .padding(20)
            .frame(maxWidth: 320)
            .background(C.cardBg)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .shadow(color: Color.black.opacity(0.18), radius: 24, x: 0, y: 10)
            .padding(.horizontal, 28)
        }
    }
}

struct ForceUpdateView: View {
    var info: AppUpdateInfo
    @EnvironmentObject var app: AppState

    var body: some View {
        ZStack {
            C.pageBg.ignoresSafeArea()
            VStack(spacing: 0) {
                Spacer(minLength: 40)
                if let img = AppIconImage.image {
                    Image(uiImage: img)
                        .resizable()
                        .frame(width: 76, height: 76)
                        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                }
                Text(Tr("需要更新后才能继续使用"))
                    .font(pf(18, .semibold))
                    .foregroundColor(C.label)
                    .padding(.top, 18)
                Text((info.version ?? "") + (info.version == nil ? "" : Tr(" 版本")))
                    .font(pf(13))
                    .foregroundColor(C.subLabel)
                    .padding(.top, 6)
                if let notes = info.notes, !notes.isEmpty {
                    ScrollView {
                        Text(notes)
                            .font(pf(14))
                            .foregroundColor(C.label.opacity(0.8))
                            .lineSpacing(4)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(14)
                            .background(C.cardBg)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    .frame(maxHeight: 260)
                    .padding(.top, 18)
                }
                Spacer(minLength: 20)
                Button {
                    app.openUpdate(info)
                } label: {
                    Text(Tr("立即更新"))
                        .font(pf(16, .medium))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity).frame(height: 48)
                        .background(RoundedRectangle(cornerRadius: 12).fill(C.green))
                }
                .buttonStyle(.plain)
                .padding(.bottom, 40)
            }
            .padding(.horizontal, 28)
        }
    }
}
