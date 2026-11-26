import SwiftUI
import UIKit

struct FeedbackView: View {
    @EnvironmentObject private var app: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var category = "功能异常"
    @State private var content = ""
    @State private var contact = ""
    @State private var picked: [UIImage] = []
    @State private var busy = false
    @State private var done = false
    @State private var showPhoto = false
    @State private var showCamera = false
    @State private var showHistory = false

    private let categories = ["功能异常", "产品建议", "界面样式", "其他"]
    private let maxLength = 200

    var body: some View {
        VStack(spacing: 0) {
            NavBar(
                title: done ? Tr("反馈已提交") : Tr("意见反馈"),
                back: { dismiss() }
            ) {
                if !done {
                    Button {
                        send()
                    } label: {
                        Text(busy ? Tr("提交中…") : Tr("提交"))
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(canSubmit
                                             ? Color.accentColor
                                             : Color.secondary)
                            .padding(.trailing, 16)
                    }
                    .buttonStyle(.plain)
                    .disabled(!canSubmit)
                }
            }

            if done {
                successList
            } else {
                feedbackForm
            }
        }
        .background(Color(uiColor: .systemGroupedBackground).ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .swipeBack { dismiss() }
        .hidesTabBar()
        .sheet(isPresented: $showPhoto) {
            PhotosPicker(limit: 3 - picked.count) { images in
                picked.append(contentsOf: images.prefix(3 - picked.count))
            }
        }
        .sheet(isPresented: $showCamera) {
            CameraPicker { image in
                if picked.count < 3 {
                    picked.append(image)
                }
            }
        }
        .sheet(isPresented: $showHistory) {
            FeedbackHistoryView()
                .environmentObject(app)
        }
    }

    private var canSubmit: Bool {
        !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !busy
    }

    private var feedbackForm: some View {
        Form {
            Section {
                Picker(Tr("问题类型"), selection: $category) {
                    ForEach(categories, id: \.self) { item in
                        Text(Tr(item)).tag(item)
                    }
                }
            } footer: {
                Text(Tr("选择最接近的类型，方便我们更快分派。"))
            }

            Section {
                ZStack(alignment: .topLeading) {
                    if content.isEmpty {
                        Text(Tr("说说遇到的问题，或者你希望加什么功能…"))
                            .font(.body)
                            .foregroundStyle(.tertiary)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 9)
                            .allowsHitTesting(false)
                    }

                    TextEditor(text: $content)
                        .font(.body)
                        .scrollContentBackground(.hidden)
                        .frame(minHeight: 132)
                        .onChange(of: content) { value in
                            if value.count > maxLength {
                                content = String(value.prefix(maxLength))
                            }
                        }
                }
            } header: {
                Text(Tr("问题描述"))
            } footer: {
                HStack {
                    Text(Tr("请勿填写密码、验证码或支付密码。"))
                    Spacer()
                    Text("\(content.count)/\(maxLength)")
                        .monospacedDigit()
                        .foregroundStyle(content.count > maxLength - 20
                                         ? Color.orange
                                         : Color.secondary)
                }
            }

            Section {
                if !picked.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            ForEach(Array(picked.enumerated()), id: \.offset) { _, image in
                                ZStack(alignment: .topTrailing) {
                                    Image(uiImage: image)
                                        .resizable()
                                        .scaledToFill()
                                        .frame(width: 68, height: 68)
                                        .clipShape(
                                            RoundedRectangle(cornerRadius: 10,
                                                             style: .continuous)
                                        )

                                    Button {
                                        if let index = picked.firstIndex(where: {
                                            $0 === image
                                        }) {
                                            picked.remove(at: index)
                                        }
                                    } label: {
                                        Image(systemName: "xmark")
                                            .font(.system(size: 8, weight: .bold))
                                            .foregroundStyle(.white)
                                            .frame(width: 18, height: 18)
                                            .background(.black.opacity(0.66), in: Circle())
                                    }
                                    .buttonStyle(.plain)
                                    .offset(x: 6, y: -6)
                                }
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }

                if picked.count < 3 {
                    Menu {
                        Button {
                            showPhoto = true
                        } label: {
                            Label(Tr("从相册选择"), systemImage: "photo.on.rectangle")
                        }
                        Button {
                            showCamera = true
                        } label: {
                            Label(Tr("拍照"), systemImage: "camera.fill")
                        }
                    } label: {
                        Label(Tr("添加截图"), systemImage: "plus.circle.fill")
                    }
                }
            } header: {
                Text(Tr("截图"))
            } footer: {
                Text(Tr("最多 3 张。截图能帮助我们更快定位问题。"))
            }

            Section {
                TextField(Tr("手机号或邮箱（选填）"), text: $contact)
                    .textContentType(.emailAddress)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
            } header: {
                Text(Tr("联系方式"))
            } footer: {
                Text(Tr("需要进一步确认时，我们可能通过这里联系你。"))
            }

            Section {
                Button {
                    showHistory = true
                } label: {
                    HStack {
                        Label(Tr("我的反馈"), systemImage: "tray.full.fill")
                        Spacer()
                        Text(Tr("查看处理进度和官方回复"))
                            .foregroundStyle(.secondary)
                        Image(systemName: "chevron.right")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.tertiary)
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .scrollDismissesKeyboard(.interactively)
    }

    private var successList: some View {
        List {
            Section {
                VStack(spacing: 12) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 54, weight: .regular))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(.green)
                    Text(Tr("感谢你的反馈"))
                        .font(.title3.weight(.semibold))
                    Text(Tr("我们会尽快处理，处理结果可以在「我的反馈」里查看。"))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 22)
            }

            Section {
                Button {
                    showHistory = true
                } label: {
                    Label(Tr("查看我的反馈"), systemImage: "tray.full.fill")
                }
                Button {
                    dismiss()
                } label: {
                    Text(Tr("完成"))
                        .frame(maxWidth: .infinity)
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    private func send() {
        let text = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            app.show(Tr("先写点内容"))
            return
        }
        busy = true
        Task {
            var urls: [String] = []
            for image in picked {
                if let url = try? await API.shared.upload(image: image) {
                    urls.append(url)
                }
            }
            if let error = await API.shared.sendFeedback(
                content: text,
                contact: contact,
                category: category,
                images: urls
            ) {
                app.show(error)
            } else {
                content = ""
                contact = ""
                picked = []
                done = true
            }
            busy = false
        }
    }
}

struct FeedbackHistoryView: View {
    @EnvironmentObject private var app: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var rows: [API.MyFeedback] = []
    @State private var loading = true

    var body: some View {
        VStack(spacing: 0) {
            NavBar(title: Tr("我的反馈"), back: { dismiss() })

            List {
                if loading {
                    Section {
                        HStack {
                            Spacer()
                            ProgressView()
                            Spacer()
                        }
                        .padding(.vertical, 36)
                    }
                } else if rows.isEmpty {
                    Section {
                        VStack(spacing: 10) {
                            Image(systemName: "tray")
                                .font(.system(size: 32, weight: .regular))
                                .foregroundStyle(.secondary)
                            Text(Tr("还没有提交过反馈"))
                                .font(.body)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 28)
                    }
                } else {
                    ForEach(rows) { row in
                        feedbackRow(row)
                    }
                }
            }
            .listStyle(.insetGrouped)
            .refreshable {
                rows = await API.shared.myFeedback()
            }
        }
        .background(Color(uiColor: .systemGroupedBackground).ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .swipeBack { dismiss() }
        .hidesTabBar()
        .task {
            rows = await API.shared.myFeedback()
            loading = false
        }
    }

    private func feedbackRow(_ row: API.MyFeedback) -> some View {
        Section {
            HStack {
                Text(Tr(row.category ?? "功能异常"))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text((row.status ?? "pending") == "replied"
                     ? Tr("已回复")
                     : Tr("处理中"))
                    .font(.caption.weight(.medium))
                    .foregroundStyle((row.status ?? "pending") == "replied"
                                     ? Color.green
                                     : Color.secondary)
            }

            Text(row.content ?? "")
                .font(.body)
                .textSelection(.enabled)
                .padding(.vertical, 3)

            if let images = row.images, !images.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(Array(images.prefix(3).enumerated()),
                                id: \.offset) { _, path in
                            RemoteImage(path: path, mode: .fill, maxSide: 320)
                                .frame(width: 64, height: 64)
                                .clipShape(
                                    RoundedRectangle(cornerRadius: 9,
                                                     style: .continuous)
                                )
                        }
                    }
                }
            }

            if let reply = row.reply, !reply.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Label(Tr("官方回复"), systemImage: "checkmark.bubble.fill")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Color.accentColor)
                    Text(reply)
                        .font(.body)
                        .textSelection(.enabled)
                }
                .padding(.vertical, 4)
            }

            if let created = row.createdAt {
                LabeledContent(Tr("提交时间"), value: formatDate(created))
            }
        }
    }

    private func formatDate(_ value: String) -> String {
        guard value.count >= 16 else { return value }
        return String(value.prefix(16)).replacingOccurrences(of: "T", with: " ")
    }
}
