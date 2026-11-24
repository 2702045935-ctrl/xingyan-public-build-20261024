import Contacts
import MessageUI
import SwiftUI
import UIKit

private enum PhoneContactLoadState {
    case idle, requesting, ready, denied
}

private struct LocalPhoneContact: Identifiable {
    let id: String
    let name: String
    let phone: String
}

private struct PhoneContactSection: Identifiable {
    var id: String { letter }
    let letter: String
    let contacts: [LocalPhoneContact]
}

private struct QRInvite: Identifiable {
    let id = UUID()
    let name: String
    let phone: String
    let image: UIImage
    let messageImage: UIImage
}

private struct PhoneContactMark: View {
    let accent: Color

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: AppDesign.Radius.mini, style: .continuous)
                .fill(accent)
            HStack(spacing: AppDesign.Spacing.xxs) {
                Capsule().fill(AppPalette.deepForest).frame(width: 2.8, height: 7)
                Capsule().fill(AppPalette.deepForest).frame(width: 2.8, height: 7)
            }
            .offset(y: 1)
        }
    }
}

private struct PhoneOrbitMotif: View {
    let accent: Color
    let ink: Color

    var body: some View {
        GeometryReader { geo in
            let side = min(geo.size.width, geo.size.height) * 0.95
            ZStack {
                Ellipse()
                    .trim(from: 0.04, to: 0.80)
                    .stroke(ink.opacity(0.16),
                            style: StrokeStyle(lineWidth: 0.8, dash: [3, 6]))
                    .frame(width: side, height: side * 0.40)
                    .rotationEffect(.degrees(-17))
                    .position(x: geo.size.width * 0.68, y: geo.size.height * 0.42)
                Ellipse()
                    .trim(from: 0.20, to: 0.92)
                    .stroke(accent.opacity(0.28),
                            style: StrokeStyle(lineWidth: 0.8, dash: [1, 5]))
                    .frame(width: side * 0.68, height: side * 0.26)
                    .rotationEffect(.degrees(15))
                    .position(x: geo.size.width * 0.70, y: geo.size.height * 0.44)
            }
        }
    }
}

struct PhoneContactsView: View {
    @EnvironmentObject private var app: AppState
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    var onOpenUser: (User) -> Void

    @State private var state: PhoneContactLoadState = .idle
    @State private var contacts: [LocalPhoneContact] = []
    @State private var keyword = ""
    @State private var searchingPhone = ""
    @State private var qrInvite: QRInvite?
    @State private var errorText = ""

    private var filteredContacts: [LocalPhoneContact] {
        let q = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return contacts }
        let digits = q.filter { $0 >= "0" && $0 <= "9" }
        return contacts.filter {
            $0.name.localizedCaseInsensitiveContains(q)
                || (!digits.isEmpty && $0.phone.contains(digits))
        }
    }

    private var groupedContacts: [PhoneContactSection] {
        var order: [String] = []
        var map: [String: [LocalPhoneContact]] = [:]
        for contact in filteredContacts {
            let letter = pinyinInitial(contact.name)
            if map[letter] == nil { order.append(letter) }
            map[letter, default: []].append(contact)
        }
        return order.sorted { a, b in
            if a == "#" { return false }
            if b == "#" { return true }
            return a < b
        }.map { PhoneContactSection(letter: $0, contacts: map[$0] ?? []) }
    }

    var body: some View {
        VStack(spacing: 0) {
            NavBar(title: Tr("手机联系人"), back: { dismiss() })

            ScrollView(showsIndicators: false) {
                LazyVStack(spacing: 0, pinnedViews: [.sectionHeaders]) {
                    contactsHero

                    switch state {
                    case .idle, .denied:
                        phonePermissionCard

                    case .requesting:
                        VStack(spacing: AppDesign.Spacing.sm) {
                            ProgressView()
                            Text(Tr("正在读取手机联系人…"))
                                .font(pf(14))
                                .foregroundStyle(C.subLabel)
                        }
                        .frame(maxWidth: .infinity, minHeight: 220)

                    case .ready:
                        phoneSearchBar

                        if contacts.isEmpty {
                            phoneEmptyState(icon: "person.crop.circle.badge.xmark",
                                            title: Tr("手机通讯录里没有可查询的号码"))
                        } else if filteredContacts.isEmpty {
                            phoneEmptyState(icon: "magnifyingglass",
                                            title: Tr("没有找到匹配的手机联系人"))
                        } else {
                            ForEach(groupedContacts) { section in
                                Section {
                                    ForEach(section.contacts) { contact in
                                        Button {
                                            Task { await lookUp(contact) }
                                        } label: {
                                            phoneContactRow(contact)
                                        }
                                        .buttonStyle(.plain)
                                        .disabled(!searchingPhone.isEmpty)
                                    }
                                } header: {
                                    HStack {
                                        Text(section.letter)
                                            .font(pfStyled(size: 12, weight: .semibold))
                                            .foregroundStyle(
                                                section.letter == "#"
                                                ? AppPalette.whatsApp
                                                : C.subLabel
                                            )
                                        Spacer()
                                    }
                                    .padding(.horizontal, 18)
                                    .frame(height: AppDesign.Control.statusHeight)
                                    .background(C.pageBg)
                                }
                            }
                        }
                    }

                    if !errorText.isEmpty {
                        Text(errorText)
                            .font(AppDesign.Typography.caption)
                            .foregroundColor(C.red)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, AppDesign.Spacing.xl)
                    }

                    if state == .ready {
                        Text(Tr("仅在你选择联系人后查询号码，不会批量上传通讯录。"))
                            .font(AppDesign.Typography.caption)
                            .foregroundStyle(C.subLabel)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 34)
                            .padding(.top, AppDesign.Spacing.xl)
                    }
                }
                .padding(.bottom, max(20, L.safeBottom))
            }
        }
        .background(phoneContactsBackdrop)
        .toolbar(.hidden, for: .navigationBar)
        .sheet(item: $qrInvite) { invite in
            PhoneInviteSheet(name: invite.name,
                             phone: invite.phone,
                             image: invite.image,
                             messageImage: invite.messageImage) {
                qrInvite = nil
            }
        }
    }

    private var phoneContactsBackdrop: some View {
        Color.dyn(0xFFFFFF, 0x000000).ignoresSafeArea()
    }

    private var phoneSearchBar: some View {
        HStack(spacing: AppDesign.Spacing.xs) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(C.subLabel)
            TextField(Tr("搜索姓名或号码"), text: $keyword)
                .font(pfStyled(size: 15.5, weight: .regular))
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            if !keyword.isEmpty {
                Button {
                    keyword = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(C.subLabel)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, AppDesign.Spacing.sm)
        .frame(height: AppDesign.Control.iconControlHeight)
        .background(C.fieldBg,
                    in: RoundedRectangle(cornerRadius: AppDesign.Radius.small, style: .continuous))
        .padding(.horizontal, 14)
        .padding(.vertical, AppDesign.Spacing.xs)
        .background(C.pageBg)
    }

    private var contactsHero: some View {
        HStack(alignment: .center, spacing: 13) {
            Image(systemName: "person.crop.circle.badge.plus")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 48, height: 48)
                .background(AppPalette.whatsApp, in: Circle())

            VStack(alignment: .leading, spacing: 4) {
                Text(Tr("从手机通讯录添加朋友"))
                    .font(pfStyled(size: 17, weight: .semibold))
                    .foregroundStyle(C.label)
                if state == .ready {
                    Text("\(contacts.count) " + Tr("位联系人"))
                        .font(pfStyled(size: 13, weight: .regular))
                        .foregroundStyle(C.subLabel)
                } else {
                    Text(Tr("安全地查找已经在使用星言的朋友"))
                        .font(pfStyled(size: 13, weight: .regular))
                        .foregroundStyle(C.subLabel)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .background(C.pageBg)
    }

    private func phoneContactRow(_ contact: LocalPhoneContact) -> some View {
        HStack(spacing: AppDesign.Spacing.sm) {
            Text(String(contact.name.prefix(1)))
                .font(pfStyled(size: 18, weight: .medium))
                .foregroundStyle(.white)
                .frame(width: 44, height: 44)
                .background(phoneAvatarColor(contact.name), in: Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text(contact.name)
                    .font(pfStyled(size: 16.5, weight: .regular))
                    .foregroundStyle(C.label)
                    .lineLimit(1)
                Text(contact.phone)
                    .font(pfStyled(size: 13.5, weight: .regular))
                    .foregroundStyle(C.subLabel)
                    .lineLimit(1)
            }

            Spacer(minLength: 6)
            if searchingPhone == contact.phone {
                ProgressView().tint(AppPalette.whatsApp)
            } else {
                Image(systemName: "person.crop.circle.badge.plus")
                    .font(.system(size: 19, weight: .medium))
                    .foregroundStyle(AppPalette.whatsApp)
            }
        }
        .padding(.horizontal, 18)
        .frame(height: AppDesign.Control.compactRowHeight)
        .background(C.pageBg)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(C.hairline)
                .frame(height: AppDesign.Control.hairline)
                .padding(.leading, 74)
        }
        .contentShape(Rectangle())
    }

    private var phonePermissionCard: some View {
        VStack(spacing: 14) {
            Image(systemName: "person.crop.circle.badge.questionmark")
                .font(.system(size: 42, weight: .light))
                .foregroundStyle(AppPalette.whatsApp)
            Text(Tr("读取手机联系人"))
                .font(pf(17, .semibold))
                .foregroundStyle(C.label)
            Text(Tr("仅在你选择联系人后查询号码，不会批量上传通讯录。"))
                .font(AppDesign.Typography.body)
                .foregroundStyle(C.subLabel)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 22)
            Button {
                Task { await loadContacts() }
            } label: {
                Text(state == .denied
                     ? Tr("去系统设置开启通讯录权限")
                     : Tr("读取手机联系人"))
                    .font(AppDesign.Typography.rowTitle)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 46)
                    .background(AppPalette.whatsApp,
                                in: RoundedRectangle(cornerRadius: AppDesign.Radius.compact,
                                                     style: .continuous))
            }
            .buttonStyle(.plain)
            .padding(.horizontal, AppDesign.Spacing.xl)
        }
        .frame(maxWidth: .infinity, minHeight: 260)
        .padding(.vertical, AppDesign.Spacing.lg)
    }

    private func phoneEmptyState(icon: String, title: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(C.subLabel)
            Text(title)
                .font(pf(14))
                .foregroundStyle(C.subLabel)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, minHeight: 220)
        .padding(.horizontal, 30)
    }

    private func phoneAvatarColor(_ name: String) -> Color {
        let palette = [
            Color(hex: 0x7A8B99),
            Color(hex: 0x9A7B8C),
            Color(hex: 0x708C7B),
            Color(hex: 0x8A8068),
            Color(hex: 0x7A7899),
            Color(hex: 0x698890)
        ]
        let scalar = name.unicodeScalars.reduce(0) { $0 + Int($1.value) }
        return palette[abs(scalar) % palette.count]
    }

    private func loadContacts() async {
        if state == .denied {
            if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
            return
        }

        state = .requesting
        errorText = ""
        let granted = await withCheckedContinuation { continuation in
            CNContactStore().requestAccess(for: .contacts) { allowed, _ in
                continuation.resume(returning: allowed)
            }
        }
        guard granted else {
            state = .denied
            errorText = Tr("没有通讯录权限。你可以去系统设置里开启，星言不会在后台读取。")
            return
        }

        do {
            contacts = try PhoneContactLoader.load()
            state = .ready
        } catch {
            state = .idle
            errorText = Tr("读取手机联系人失败，请稍后再试")
        }
    }

    private func lookUp(_ contact: LocalPhoneContact) async {
        guard searchingPhone.isEmpty else { return }
        searchingPhone = contact.phone
        errorText = ""
        defer { searchingPhone = "" }

        do {
            guard let user = try await API.shared.searchUsers(contact.phone).first else {
                errorText = Tr("这个手机联系人还没有注册星言，可以生成二维码邀请")
                prepareInvite(contact)
                return
            }
            onOpenUser(user)
            dismiss()
        } catch {
            errorText = (error as? LocalizedError)?.errorDescription ?? Tr("查找失败，请稍后再试")
        }
    }

    private func prepareInvite(_ contact: LocalPhoneContact) {
        guard let image = makeInviteQRCard(),
              let messageImage = makeMessageInviteQRCard() else {
            errorText = Tr("二维码生成失败，请稍后再试")
            return
        }
        qrInvite = QRInvite(name: contact.name,
                            phone: contact.phone,
                            image: image,
                            messageImage: messageImage)
    }

    private func makeInviteQRCard() -> UIImage? {
        guard let qr = qrImage("https://aa.x8iu.com/download.html", size: 720) else {
            return nil
        }
        let size = CGSize(width: 1080, height: 1380)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: size, format: format).image { renderer in
            let ctx = renderer.cgContext
            let colors = [
                UIColor(red: 0.035, green: 0.20, blue: 0.17, alpha: 1).cgColor,
                UIColor(red: 0.015, green: 0.075, blue: 0.065, alpha: 1).cgColor
            ] as CFArray
            if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                         colors: colors, locations: [0, 1]) {
                ctx.drawLinearGradient(gradient,
                                       start: CGPoint(x: 0, y: 0),
                                       end: CGPoint(x: size.width, y: size.height),
                                       options: [])
            }

            UIColor.white.withAlphaComponent(0.05).setStroke()
            ctx.setLineWidth(2)
            ctx.strokeEllipse(in: CGRect(x: -180, y: 80, width: 720, height: 720))
            ctx.strokeEllipse(in: CGRect(x: 670, y: 940, width: 520, height: 520))

            let card = CGRect(x: 80, y: 72, width: 920, height: 1236)
            let cardPath = UIBezierPath(roundedRect: card, cornerRadius: AppDesign.Radius.hero)
            UIColor.white.setFill()
            cardPath.fill()

            let titleStyle = NSMutableParagraphStyle()
            titleStyle.alignment = .center
            let title = "星言 Luchat" as NSString
            title.draw(in: CGRect(x: 130, y: 158, width: 820, height: 72),
                       withAttributes: [
                        .font: UIFont.systemFont(ofSize: 56, weight: .semibold),
                        .foregroundColor: UIColor(red: 0.035, green: 0.18, blue: 0.15, alpha: 1),
                        .paragraphStyle: titleStyle
                       ])

            let tagline = "安全、克制的即时通讯" as NSString
            tagline.draw(in: CGRect(x: 130, y: 238, width: 820, height: 48),
                         withAttributes: [
                            .font: UIFont.systemFont(ofSize: 26, weight: .regular),
                            .foregroundColor: UIColor(white: 0.38, alpha: 1),
                            .paragraphStyle: titleStyle
                         ])

            if let icon = UIImage(named: "AppIcon60x60@3x")
                ?? UIImage(named: "AppIcon60x60@2x") {
                let iconRect = CGRect(x: 480, y: 314, width: 120, height: 120)
                let iconPath = UIBezierPath(roundedRect: iconRect, cornerRadius: AppDesign.Radius.overlay)
                ctx.saveGState()
                iconPath.addClip()
                icon.draw(in: iconRect)
                ctx.restoreGState()
            }

            let qrFrame = CGRect(x: 170, y: 474, width: 740, height: 740)
            let qrPath = UIBezierPath(roundedRect: qrFrame.insetBy(dx: -22, dy: -22),
                                      cornerRadius: AppDesign.Radius.hero)
            UIColor(white: 0.96, alpha: 1).setFill()
            qrPath.fill()
            qr.draw(in: qrFrame)

            let foot = "请使用微信或系统相机扫码下载" as NSString
            foot.draw(in: CGRect(x: 120, y: 1242, width: 840, height: 46),
                      withAttributes: [
                        .font: UIFont.systemFont(ofSize: 25, weight: .medium),
                        .foregroundColor: UIColor(red: 0.035, green: 0.18, blue: 0.15, alpha: 1),
                        .paragraphStyle: titleStyle
                      ])
        }
    }

    /// Messages renders attachments at roughly their real aspect ratio. Keep the
    /// SMS version compact and square so it does not dominate the composer or
    /// arrive as a large poster-sized preview.
    private func makeMessageInviteQRCard() -> UIImage? {
        guard let qr = qrImage("https://aa.x8iu.com/download.html", size: 420) else {
            return nil
        }
        let size = CGSize(width: 640, height: 640)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: size, format: format).image { renderer in
            let ctx = renderer.cgContext
            let colors = [
                UIColor(red: 0.035, green: 0.20, blue: 0.17, alpha: 1).cgColor,
                UIColor(red: 0.015, green: 0.075, blue: 0.065, alpha: 1).cgColor
            ] as CFArray
            if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                         colors: colors, locations: [0, 1]) {
                ctx.drawLinearGradient(gradient,
                                       start: CGPoint(x: 0, y: 0),
                                       end: CGPoint(x: size.width, y: size.height),
                                       options: [])
            }

            let card = CGRect(x: 28, y: 28, width: 584, height: 584)
            let cardPath = UIBezierPath(roundedRect: card, cornerRadius: AppDesign.Radius.hero)
            UIColor.white.setFill()
            cardPath.fill()

            let center = NSMutableParagraphStyle()
            center.alignment = .center
            ("星言 Luchat" as NSString).draw(
                in: CGRect(x: 64, y: 64, width: 512, height: 44),
                withAttributes: [
                    .font: UIFont.systemFont(ofSize: 34, weight: .semibold),
                    .foregroundColor: UIColor(red: 0.035, green: 0.18, blue: 0.15, alpha: 1),
                    .paragraphStyle: center
                ]
            )

            let qrFrame = CGRect(x: 124, y: 128, width: 392, height: 392)
            UIColor(white: 0.985, alpha: 1).setFill()
            UIBezierPath(roundedRect: qrFrame.insetBy(dx: -12, dy: -12),
                         cornerRadius: AppDesign.Radius.panel).fill()
            qr.draw(in: qrFrame)

            ("扫码下载星言" as NSString).draw(
                in: CGRect(x: 96, y: 550, width: 448, height: 34),
                withAttributes: [
                    .font: UIFont.systemFont(ofSize: 22, weight: .medium),
                    .foregroundColor: UIColor(red: 0.035, green: 0.18, blue: 0.15, alpha: 1),
                    .paragraphStyle: center
                ]
            )
        }
    }
}

private struct PhoneInviteSheet: View {
    let name: String
    let phone: String
    let image: UIImage
    let messageImage: UIImage
    let onFinish: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var showShare = false
    @State private var showMessages = false
    @State private var saved = false

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(spacing: AppDesign.Spacing.md) {
                    VStack(spacing: 6) {
                        Text(Tr("邀请 ") + name)
                            .font(pf(18, .semibold))
                            .foregroundColor(C.label)
                        Text(phone)
                            .font(AppDesign.Typography.caption)
                            .foregroundColor(C.subLabel)
                        Text(Tr("这个号码还没有注册星言"))
                            .font(pf(13))
                            .foregroundColor(C.subLabel)
                    }

                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: 220, maxHeight: 282)
                        .clipShape(RoundedRectangle(cornerRadius: AppDesign.Radius.panel, style: .continuous))
                        .shadow(color: Color.black.opacity(0.12), radius: 14, y: 6)
                        .padding(.horizontal, 18)

                    VStack(spacing: 10) {
                        Button { showShare = true } label: {
                            inviteButton(Tr("分享二维码图片"), "square.and.arrow.up", filled: true)
                        }
                        .buttonStyle(.plain)

                        Button {
                            UIImageWriteToSavedPhotosAlbum(image, nil, nil, nil)
                            saved = true
                        } label: {
                            inviteButton(saved ? Tr("已提交保存到相册") : Tr("保存二维码到相册"),
                                         "square.and.arrow.down", filled: false)
                        }
                        .buttonStyle(.plain)

                        Button { showMessages = true } label: {
                            inviteButton(Tr("发短信"), "message", filled: false)
                        }
                        .buttonStyle(.plain)

                        Text(Tr("支持彩信或 iMessage 时会附带二维码；纯短信只能发送文字邀请。"))
                            .font(pf(12))
                            .foregroundColor(C.subLabel)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, AppDesign.Spacing.xs)
                    }
                }
                .padding(.horizontal, AppDesign.Spacing.md)
                .padding(.vertical, 14)
            }
            .background(C.pageBg.ignoresSafeArea())
            .navigationTitle(Tr("二维码邀请"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(Tr("完成")) {
                        dismiss()
                        onFinish()
                    }
                }
            }
        }
        .sheet(isPresented: $showShare) {
            ShareSheet(items: [image])
        }
        .sheet(isPresented: $showMessages) {
            SMSInviteComposer(phone: phone, image: messageImage) {
                showMessages = false
            }
        }
    }

    private func inviteButton(_ title: String, _ icon: String, filled: Bool) -> some View {
        HStack(spacing: 9) {
            Image(systemName: icon).font(.system(size: 17, weight: .medium))
            Text(title).font(pf(15, .medium))
        }
        .foregroundColor(filled ? .white : C.green)
        .frame(maxWidth: .infinity)
        .frame(height: 46)
        .background(
            RoundedRectangle(cornerRadius: AppDesign.Radius.control, style: .continuous)
                .fill(filled ? C.green : C.cardBg)
        )
        .overlay(
            RoundedRectangle(cornerRadius: AppDesign.Radius.control, style: .continuous)
                .stroke(filled ? Color.clear : C.green.opacity(0.35), lineWidth: 0.8)
        )
    }
}

private struct SMSInviteComposer: UIViewControllerRepresentable {
    let phone: String
    let image: UIImage
    let onFinish: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onFinish: onFinish)
    }

    func makeUIViewController(context: Context) -> MFMessageComposeViewController {
        let composer = MFMessageComposeViewController()
        composer.recipients = [phone]
        if MFMessageComposeViewController.canSendAttachments(),
           let data = image.pngData() {
            composer.body = Tr("我正在使用星言，扫描二维码即可下载：")
            composer.addAttachmentData(data, typeIdentifier: "public.png",
                                       filename: "xingyan-invite-qr.png")
        } else {
            composer.body = Tr("我正在使用星言，下载后可以通过手机号找到我。")
        }
        composer.messageComposeDelegate = context.coordinator
        return composer
    }

    func updateUIViewController(_ uiViewController: MFMessageComposeViewController,
                                context: Context) { }

    final class Coordinator: NSObject, MFMessageComposeViewControllerDelegate {
        private let onFinish: () -> Void

        init(onFinish: @escaping () -> Void) {
            self.onFinish = onFinish
        }

        func messageComposeViewController(
            _ controller: MFMessageComposeViewController,
            didFinishWith result: MessageComposeResult
        ) {
            controller.dismiss(animated: true) { self.onFinish() }
        }
    }
}

private enum PhoneContactLoader {
    static func load() throws -> [LocalPhoneContact] {
        let keys = [
            CNContactGivenNameKey, CNContactFamilyNameKey,
            CNContactOrganizationNameKey, CNContactPhoneNumbersKey
        ] as [CNKeyDescriptor]
        let contacts = try CNContactStore().unifiedContacts(
            matching: NSPredicate(value: true),
            keysToFetch: keys
        )

        var seen = Set<String>()
        var rows: [LocalPhoneContact] = []
        for contact in contacts {
            let baseName = [contact.familyName, contact.givenName]
                .filter { !$0.isEmpty }
                .joined()
            let name = baseName.isEmpty ? contact.organizationName : baseName
            for phone in contact.phoneNumbers {
                let normalized = normalize(phone.value.stringValue)
                guard normalized.count >= 7, normalized.count <= 15,
                      seen.insert(normalized).inserted else { continue }
                rows.append(LocalPhoneContact(
                    id: normalized,
                    name: name.isEmpty ? normalized : name,
                    phone: normalized
                ))
            }
        }
        return rows.sorted { $0.name.localizedCompare($1.name) == .orderedAscending }
    }

    private static func normalize(_ value: String) -> String {
        var digits = value.filter { $0 >= "0" && $0 <= "9" }
        if digits.hasPrefix("0086") { digits.removeFirst(4) }
        else if digits.hasPrefix("86"), digits.count == 13 { digits.removeFirst(2) }
        return digits
    }
}
