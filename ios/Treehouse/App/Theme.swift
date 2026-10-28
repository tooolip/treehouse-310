import SwiftUI

enum TreeTheme {
    static let green = Color(light: 0x477A37, dark: 0x9FD27F)
    static let background = Color(light: 0xF6EFDC, dark: 0x18211B)
    static let paper = Color(light: 0xFFFAF0, dark: 0x222D25)
    static let ink = Color(light: 0x4A3523, dark: 0xF2E8D5)
    static let muted = Color(light: 0x8A7258, dark: 0xB3A68D)
    static let border = Color(light: 0xE3D2B0, dark: 0x3A4A3E)
    static let softGreen = Color(light: 0xE2EFCF, dark: 0x2F4430)
    static let berry = Color(light: 0xB6436B, dark: 0xF09AB6)
    static let sky = Color(light: 0x386F9F, dark: 0x9CC5EC)
}

extension Color {
    init(light: UInt32, dark: UInt32) {
        self.init(uiColor: UIColor { trait in
            let value = trait.userInterfaceStyle == .dark ? dark : light
            return UIColor(red: CGFloat((value >> 16) & 255) / 255,
                           green: CGFloat((value >> 8) & 255) / 255, blue: CGFloat(value & 255) / 255, alpha: 1)
        })
    }
}

struct PaperBackground: View {
    var body: some View {
        TreeTheme.background.overlay {
            Canvas { context, size in
                for x in stride(from: 12.0, to: size.width, by: 22) {
                    for y in stride(from: 12.0, to: size.height, by: 22) {
                        context.fill(Path(ellipseIn: CGRect(x: x, y: y, width: 2, height: 2)), with: .color(TreeTheme.border.opacity(0.5)))
                    }
                }
            }
        }.ignoresSafeArea()
    }
}

struct TreehouseArt: View {
    var body: some View {
        // Matches the treehouse artwork already used by the web client.
        Canvas { context, size in
            let scale = min(size.width / 120, size.height / 132)
            context.scaleBy(x: scale, y: scale)
            func fill(_ rect: CGRect, _ color: UInt32, ellipse: Bool = false, radius: CGFloat = 0) {
                let path = ellipse ? Path(ellipseIn: rect) : Path(roundedRect: rect, cornerRadius: radius)
                context.fill(path, with: .color(Color(light: color, dark: color)))
            }
            func line(_ points: [CGPoint], _ color: UInt32, width: CGFloat) {
                var p = Path(); p.addLines(points)
                context.stroke(p, with: .color(Color(light: color, dark: color)), style: StrokeStyle(lineWidth: width, lineCap: .round))
            }
            fill(CGRect(x: 12, y: 122, width: 96, height: 10), 0x8CC06B, ellipse: true)
            fill(CGRect(x: 10, y: 24, width: 48, height: 48), 0x6FAE57, ellipse: true)
            fill(CGRect(x: 62, y: 24, width: 48, height: 48), 0x6FAE57, ellipse: true)
            fill(CGRect(x: 30, y: 4, width: 60, height: 60), 0x7FBF63, ellipse: true)
            fill(CGRect(x: 53, y: 62, width: 14, height: 66), 0x8A5A32, radius: 3)
            line([CGPoint(x: 48, y: 90), CGPoint(x: 60, y: 100), CGPoint(x: 60, y: 92), CGPoint(x: 71, y: 83)], 0x8A5A32, width: 5)
            var roof = Path(); roof.addLines([CGPoint(x: 28, y: 50), CGPoint(x: 60, y: 24), CGPoint(x: 92, y: 50)]); roof.closeSubpath()
            context.fill(roof, with: .color(Color(light: 0xD0688A, dark: 0xD0688A)))
            fill(CGRect(x: 34, y: 48, width: 52, height: 26), 0xC48A52, radius: 3)
            fill(CGRect(x: 47, y: 54, width: 13, height: 11), 0xFFD66B, radius: 2)
            line([CGPoint(x: 53.5, y: 54), CGPoint(x: 53.5, y: 65)], 0xA8713F, width: 1.5)
            line([CGPoint(x: 47, y: 59.5), CGPoint(x: 60, y: 59.5)], 0xA8713F, width: 1.5)
            fill(CGRect(x: 67, y: 57, width: 11, height: 17), 0x7C4F2A, radius: 5)
            fill(CGRect(x: 24, y: 73, width: 72, height: 6), 0x7C4F2A, radius: 3)
            for x in [30.0, 40.0] { line([CGPoint(x: x, y: 79), CGPoint(x: x, y: 125)], 0xA8713F, width: 2.5) }
            for y in [88.0, 98, 108, 118] { line([CGPoint(x: 30, y: y), CGPoint(x: 40, y: y)], 0xA8713F, width: 2.5) }
        }.accessibilityHidden(true)
    }
}

struct ErrorBanner: View {
    let message: String
    var body: some View {
        Label(message, systemImage: "exclamationmark.circle")
            .font(.footnote).foregroundStyle(.red).padding(12)
            .frame(maxWidth: .infinity, alignment: .leading).background(TreeTheme.paper)
            .accessibilityIdentifier("errorBanner")
    }
}

struct EmptyTree: View {
    let title: String
    let subtitle: String
    var symbol = "leaf"
    var body: some View {
        ContentUnavailableView(title, systemImage: symbol, description: Text(subtitle))
            .foregroundStyle(TreeTheme.muted)
    }
}

extension View {
    func paperCard() -> some View {
        self.padding(16).background(TreeTheme.paper, in: RoundedRectangle(cornerRadius: 20))
            .overlay(RoundedRectangle(cornerRadius: 20).stroke(TreeTheme.border, lineWidth: 1))
    }
    func treeList() -> some View {
        self.scrollContentBackground(.hidden).background(PaperBackground())
    }
}
