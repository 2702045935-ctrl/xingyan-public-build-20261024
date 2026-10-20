import SwiftUI

struct PickContactView: View {
    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) private var dismiss

    var onPick: (User) -> Void

    @State private var keyword = ""

    private var list: [User] {
        let me = app.me?.id ?? ""
        let base = app.contacts.filter { $0.id != me }
        let k = keyword.trimmingCharacters(in: .whitespaces)
        guard !k.isEmpty else { return base }
        return base.filter {
            $0.name.contains(k) || (($0.username ?? "").contains(k))
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                SearchBoxCenter(text: $keyword)
                    .padding(.horizontal, 8)
                    .padding(.top, 8)
                    .padding(.bottom, 6)

                List(list) { u in
                    Button {
                        onPick(u)
                        dismiss()
                    } label: {
                        HStack(spacing: 10) {
                            Avatar(path: u.avatarPath, size: 40, radius: 4)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(u.name)
                                    .font(pf(16))
                                    .foregroundColor(C.label)
                                if let un = u.username, !un.isEmpty {
                                    Text(un)
                                        .font(pf(12.5))
                                        .foregroundColor(C.subLabel)
                                }
                            }
                            Spacer(minLength: 0)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .listRowBackground(C.cardBg)
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .background(C.pageBg)

                if list.isEmpty {
                    Text(Tr("没有找到联系人"))
                        .font(pf(14))
                        .foregroundColor(C.subLabel)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 24)
                }
            }
            .background(C.pageBg.ignoresSafeArea())
            .navigationTitle(Tr("选择联系人"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(Tr("取消")) { dismiss() }
                }
            }
        }
    }
}
