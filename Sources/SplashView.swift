import SwiftUI

struct SplashView: View {

    var remote: String = ""

    var body: some View {

        GeometryReader { geo in
            ZStack {
                Color.black

                if !remote.isEmpty {

                    RemoteImage(path: remote, mode: .fill, maxSide: 1600)
                        .frame(width: geo.size.width, height: geo.size.height)
                        .blur(radius: 26)
                        .clipped()

                    RemoteImage(path: remote, mode: .fill, maxSide: 2560)
                        .frame(width: geo.size.width, height: geo.size.height)
                        .clipped()
                } else if let img = UIImage(named: "splash") {
                    Image(uiImage: img)
                        .resizable()
                        .scaledToFill()
                        .frame(width: geo.size.width, height: geo.size.height)
                        .blur(radius: 26)
                        .clipped()
                    Image(uiImage: img)
                        .resizable()
                        .scaledToFill()
                        .frame(width: geo.size.width, height: geo.size.height)
                        .clipped()
                } else {
                    VStack(spacing: 10) {
                        Image(systemName: "message.fill")
                            .font(.system(size: 54))
                            .foregroundColor(.white)
                        Text("Luchat")
                            .font(.system(size: 22, weight: .semibold))
                            .foregroundColor(.white)
                    }
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .ignoresSafeArea(.all)
    }
}
