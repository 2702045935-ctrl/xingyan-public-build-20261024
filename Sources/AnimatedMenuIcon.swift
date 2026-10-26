import SwiftUI

enum MenuIconKind: String {
    case service, favorites, moments, works, stickers, settings

    case channels, live, shake, nearby, starworld, game, scan, look, searchrow

    case shop, plugins

    var colors: (Color, Color) {
        switch self {
        case .service:   return (Color(hex: 0x5ED07F), Color(hex: 0x2FA85C))
        case .favorites: return (Color(hex: 0xFFC94B), Color(hex: 0xF0A020))
        case .moments:   return (Color(hex: 0x4EC3A6), Color(hex: 0x22997E))
        case .works:     return (Color(hex: 0x5AA0F2), Color(hex: 0x2C6FD1))
        case .stickers:  return (Color(hex: 0xFFD75E), Color(hex: 0xF5A623))
        case .settings:  return (Color(hex: 0x8E9AA8), Color(hex: 0x5B6673))
        case .channels:  return (Color(hex: 0xFF8A5C), Color(hex: 0xE0652A))
        case .live:      return (Color(hex: 0xFF6B6B), Color(hex: 0xD93A3A))
        case .shake:     return (Color(hex: 0x5AA0F2), Color(hex: 0x2C6FD1))
        case .nearby:    return (Color(hex: 0x4EC97A), Color(hex: 0x22995A))
        case .starworld: return (Color(hex: 0x6B7BFF), Color(hex: 0x3B4CE0))
        case .game:      return (Color(hex: 0xA96BF6), Color(hex: 0x7A3ED6))
        case .scan:      return (Color(hex: 0x5AA0F2), Color(hex: 0x2C6FD1))
        case .look:      return (Color(hex: 0xFFB74A), Color(hex: 0xE08A10))
        case .searchrow: return (Color(hex: 0x8E9AA8), Color(hex: 0x5B6673))
        case .shop:      return (Color(hex: 0xFFC24B), Color(hex: 0xE08A22))
        case .plugins:   return (Color(hex: 0x8E9AA8), Color(hex: 0x5B6673))
        }
    }

    var symbol: String {
        switch self {
        case .service:   return "wallet.pass"
        case .favorites: return "star"
        case .moments:   return "photo"
        case .works:     return "play.rectangle"
        case .stickers:  return "face.smiling"
        case .settings:  return "gearshape"

        case .channels:  return "play.rectangle"
        case .live:      return "dot.radiowaves.left.and.right"
        case .shake:     return "gyroscope"
        case .nearby:    return "location"
        case .starworld: return "globe"
        case .game:      return "gamecontroller"
        case .scan:      return "qrcode.viewfinder"
        case .look:      return "eye"
        case .searchrow: return "magnifyingglass"
        case .shop:      return "bag"
        case .plugins:   return "puzzlepiece"
        }
    }
}

struct AnimatedMenuIcon: View {
    let kind: MenuIconKind
    var size: CGFloat = 22

    @State private var breathe = false
    @State private var sweeping = false

    private var radius: CGFloat { size * 0.28 }

    var body: some View {

        ZStack {
            Image(systemName: kind.symbol)
                .font(.system(size: size * 0.86, weight: .regular))
                .foregroundColor(kind.colors.1)
            Image(systemName: kind.symbol)
                .font(.system(size: size * 0.86, weight: .regular))
                .foregroundColor(kind.colors.1)
                .offset(x: 0.35, y: 0.35)
                .opacity(0.55)
        }
        .frame(width: size, height: size)
    }
}
