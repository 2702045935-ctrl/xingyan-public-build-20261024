import SwiftUI

/// B682 的「插件」入口直接就是 AI 工作台，不再先显示插件首页。
struct PluginsView: View {
    @EnvironmentObject var app: AppState

    var body: some View {
        AIWorkspaceView()
            .environmentObject(app)
    }
}
