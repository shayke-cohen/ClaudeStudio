import SwiftUI

/// Diamond-mesh icon used for every AgentGroup throughout the app.
/// Four Claude icons at N/E/S/W positions, fully connected by white lines,
/// on the standard terracotta orange background.
struct GroupIconView: View {
    var size: CGFloat = 36

    private var radius: CGFloat   { size * 0.343 }
    private var nodeSize: CGFloat { size * 0.286 }
    private var lineWidth: CGFloat { max(1, size * 0.018) }
    private var dotRadius: CGFloat { size * 0.022 }

    private var nodes: [CGPoint] {
        let c = size / 2
        return [
            CGPoint(x: c,          y: c - radius),
            CGPoint(x: c + radius, y: c),
            CGPoint(x: c,          y: c + radius),
            CGPoint(x: c - radius, y: c),
        ]
    }

    private static let pairs: [(Int, Int)] =
        [(0,1),(0,2),(0,3),(1,2),(1,3),(2,3)]

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.229, style: .continuous)
                .fill(Color(red: 192/255, green: 112/255, blue: 72/255))

            Canvas { ctx, _ in
                let pts = self.nodes
                let lw  = self.lineWidth
                let dr  = self.dotRadius
                for (i, j) in Self.pairs {
                    var path = Path()
                    path.move(to: pts[i])
                    path.addLine(to: pts[j])
                    ctx.stroke(path, with: .color(.white.opacity(0.65)), lineWidth: lw)
                }
                for pt in pts {
                    ctx.fill(
                        Path(ellipseIn: CGRect(
                            x: pt.x - dr, y: pt.y - dr,
                            width: dr * 2, height: dr * 2
                        )),
                        with: .color(.white.opacity(0.8))
                    )
                }
            }

            ForEach(0..<4, id: \.self) { i in
                Image("ClaudeIcon")
                    .resizable()
                    .frame(width: nodeSize, height: nodeSize)
                    .position(nodes[i])
            }
        }
        .frame(width: size, height: size)
    }
}

#Preview {
    HStack(spacing: 16) {
        GroupIconView(size: 24)
        GroupIconView(size: 28)
        GroupIconView(size: 36)
        GroupIconView(size: 40)
        GroupIconView(size: 48)
        GroupIconView(size: 64)
    }
    .padding()
}
