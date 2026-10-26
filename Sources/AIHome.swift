import SwiftUI

struct AIHomeCardView: View {

    let chat: Chat

    var onSend: (String) -> Void

    var onCall: () -> Void

    var onBrowser: () -> Void

    var onDrop: () -> Void

    private var suggestions: [String] {
        let raw = UIConfig.text("aiHomeSuggestions",
            "上传照片 · 生成真实 3D 建模,帮我规划一个 App 的开发流程,调整动漫头像适配社交平台尺寸,设计含 5 个元素的简单创意标识")
        return raw.split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    private var acts: [(String, String)] {
        [("对话", "bubble.left.and.bubble.right.fill"),
         ("打电话", "phone.fill"),
         ("AI 创作", "wand.and.stars"),
         ("拍题答疑", "camera.viewfinder")]
    }

    var body: some View {
        PanelCard {
            VStack(spacing: 0) {
                Text(Tr("有什么我能帮你的吗？"))
                    .font(pf(19, .semibold))
                    .foregroundColor(C.label)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 16)
                    .padding(.top, 18)

                HStack {
                    Text(Tr("为你推荐")).font(pf(13)).foregroundColor(C.subLabel)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 2)

                VStack(spacing: 0) {
                    ForEach(Array(suggestions.enumerated()), id: \.offset) { i, s in
                        if i > 0 { HairLine(inset: 44) }
                        Button { onSend(s) } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "sparkles")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundColor(C.green)
                                    .frame(width: 22)
                                Text(s)
                                    .font(pf(15))
                                    .foregroundColor(C.label)
                                    .lineLimit(1)
                                Spacer(minLength: 0)
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundColor(C.subLabel)
                            }
                            .padding(.horizontal, 16)
                            .frame(height: 50)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }

                HairLine(inset: 0)

                HStack(spacing: 0) {
                    ForEach(Array(acts.enumerated()), id: \.offset) { _, a in
                        Button {
                            switch a.0 {
                            case "打电话": onCall()
                            case "对话":   onSend("")
                            case "AI 创作": onSend(Tr("帮我创作一张图片"))
                            default:        onSend(Tr("帮我解这道题"))
                            }
                        } label: {
                            VStack(spacing: 5) {
                                Image(systemName: a.1)
                                    .font(.system(size: 19))
                                    .foregroundColor(C.label)
                                Text(Tr(a.0))
                                    .font(pf(11.5))
                                    .foregroundColor(C.subLabel)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }

                HairLine(inset: 0)
                HStack(spacing: 0) {
                    Button(action: onBrowser) {
                        aiTool(icon: "safari", title: Tr("内置浏览器"),
                               sub: Tr("搜索和打开网页"))
                    }
                    .buttonStyle(.plain)
                    Rectangle().fill(C.hairline).frame(width: 0.5, height: 34)
                    Button(action: onDrop) {
                        aiTool(icon: "dot.radiowaves.left.and.right", title: Tr("文件快传"),
                               sub: Tr("面对面传文件"))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func aiTool(icon: String, title: String, sub: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 17, weight: .medium))
                .foregroundColor(C.green)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(pf(14.5, .medium)).foregroundColor(C.label)
                Text(sub).font(pf(10.8)).foregroundColor(C.subLabel)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .frame(maxWidth: .infinity)
        .frame(height: 54)
        .contentShape(Rectangle())
    }
}
