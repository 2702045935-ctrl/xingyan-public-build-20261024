import SwiftUI

struct MomentCommentBar: View {
    @Binding var text: String

    var replyTo: String = ""
    let onSend: () -> Void
    let onCancel: () -> Void

    @FocusState private var focused: Bool

    private var canSend: Bool { !text.trimmingCharacters(in: .whitespaces).isEmpty }

    var body: some View {
        HStack(spacing: 10) {
            TextField(replyTo.isEmpty ? Tr("评论") : (Tr("回复 ") + replyTo + "："),
                      text: $text, axis: .vertical)
                .font(pf(15.5))
                .lineLimit(1...4)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(C.fieldBg))
                .focused($focused)
                .submitLabel(.send)
                .onSubmit { if canSend { onSend() } }

            Button { onSend() } label: {
                Text(Tr("发送"))
                    .font(pf(15.5, .medium))
                    .foregroundColor(canSend ? C.green : C.subLabel)
                    .frame(height: 36)
                    .padding(.horizontal, 4)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(!canSend)

            Button { onCancel() } label: {
                Text(Tr("取消"))
                    .font(pf(15.5))
                    .foregroundColor(C.subLabel)
                    .frame(height: 36)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(C.cardBg)
        .overlay(alignment: .top) { HairLine() }
        .task {

            try? await Task.sleep(nanoseconds: 150_000_000)
            focused = true
        }
    }
}
