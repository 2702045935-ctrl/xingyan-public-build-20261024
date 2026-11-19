import SwiftUI

/// The bottom-bar video tab and the full-screen player opened from Works use
/// the same reel implementation. Embedded mode keeps the app tab bar visible;
/// presentation mode keeps the back affordance and hides the tab bar.
struct VideoTabView: View {
    var body: some View {
        ChannelsView(embedded: true)
    }
}
