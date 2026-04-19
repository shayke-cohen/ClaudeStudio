import SwiftUI

// MARK: - Page data

private struct FTEPage {
    let title: String
    let body: String
}

private let ftePages: [FTEPage] = [
    FTEPage(title: "Welcome to Odyssey",
            body: "Your multi-agent AI workspace — where specialized agents collaborate, skills extend their capabilities, and schedules keep them running around the clock."),
    FTEPage(title: "Meet Your Agents",
            body: "Pre-built AI specialists with their own persona, model, skills, and permissions. Pick one for a focused task or combine them into teams."),
    FTEPage(title: "Agent Groups",
            body: "Assemble specialists into named teams. Send one message — they coordinate automatically. Dev Squad, Security Audit, Full Stack Team and more."),
    FTEPage(title: "Skills & Schedules",
            body: "Skills are reusable prompt modules that give agents new superpowers. Schedules run them automatically — daily, hourly, weekly — no manual trigger needed."),
    FTEPage(title: "You're All Set",
            body: "Your agents and groups are ready. Open a chat, pick an agent, or kick off a group session. Everything is configured and waiting."),
]

// MARK: - Root view

struct FTEView: View {
    @Environment(\.dismiss) private var dismissAction
    @AppStorage(AppSettings.fteShownKey, store: AppSettings.store)
    private var fteShown = false

    @State private var page = 0
    @State private var slideForward = true

    private var isFirst: Bool { page == 0 }
    private var isLast: Bool  { page == ftePages.count - 1 }

    var body: some View {
        VStack(spacing: 0) {
            topBar
            pageCarousel
            bottomBar
        }
        .frame(width: 600, height: 540)
        .background(Color(nsColor: .controlBackgroundColor))
    }

    // MARK: Top bar

    private var topBar: some View {
        HStack {
            Button { markAndDismiss() } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title2).foregroundStyle(.tertiary)
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.escape, modifiers: [])
            .accessibilityLabel("Close")
            .accessibilityIdentifier("fte.closeButton")

            Spacer()

            HStack(spacing: 6) {
                ForEach(0..<ftePages.count, id: \.self) { i in
                    Circle()
                        .fill(i == page ? Color.primary.opacity(0.7) : Color.primary.opacity(0.15))
                        .frame(width: 6, height: 6)
                        .animation(.easeInOut(duration: 0.2), value: page)
                }
            }
            .accessibilityIdentifier("fte.pageIndicator")

            Spacer()
            Image(systemName: "xmark.circle.fill").font(.title2).hidden()
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
        .padding(.bottom, 4)
    }

    // MARK: Carousel

    private var pageCarousel: some View {
        ZStack {
            ForEach(0..<ftePages.count, id: \.self) { i in
                if i == page {
                    PageContentView(pageIndex: i, page: ftePages[i])
                        .transition(
                            .asymmetric(
                                insertion: .move(edge: slideForward ? .trailing : .leading).combined(with: .opacity),
                                removal:   .move(edge: slideForward ? .leading  : .trailing).combined(with: .opacity)
                            )
                        )
                        .id(i)
                        .accessibilityIdentifier("fte.pageContent.\(i)")
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
    }

    // MARK: Bottom bar

    private var bottomBar: some View {
        VStack(spacing: 8) {
            HStack(spacing: 12) {
                Button("← Back") { navigate(forward: false) }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .font(.callout)
                    .opacity(isFirst ? 0 : 1)
                    .disabled(isFirst)
                    .accessibilityIdentifier("fte.backButton")

                Spacer()

                if isLast {
                    Button("Get Started") { markAndDismiss() }
                        .buttonStyle(.borderedProminent)
                        .keyboardShortcut(.return, modifiers: [])
                        .accessibilityIdentifier("fte.getStartedButton")
                } else {
                    Button("Next →") { navigate(forward: true) }
                        .buttonStyle(.borderedProminent)
                        .keyboardShortcut(.return, modifiers: [])
                        .accessibilityIdentifier("fte.nextButton")
                }
            }
            .padding(.horizontal, 28)

            Text("Dismissing won't show this again")
                .font(.caption2).foregroundStyle(.quaternary)
        }
        .padding(.bottom, 20)
        .padding(.top, 4)
    }

    // MARK: Actions

    private func navigate(forward: Bool) {
        slideForward = forward
        withAnimation(.easeInOut(duration: 0.22)) {
            page = forward ? min(page + 1, ftePages.count - 1) : max(page - 1, 0)
        }
    }

    private func markAndDismiss() {
        fteShown = true
        dismissAction()
    }
}

// MARK: - Page wrapper

private struct PageContentView: View {
    let pageIndex: Int
    let page: FTEPage

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)

            illustrationView
                .frame(maxWidth: .infinity)
                .frame(height: 240)

            Spacer(minLength: 12)

            VStack(spacing: 8) {
                Text(page.title)
                    .font(.title2).fontWeight(.bold)
                Text(page.body)
                    .font(.callout).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 460)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 40)

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private var illustrationView: some View {
        switch pageIndex {
        case 0: WelcomeIllustration()
        case 1: AgentsIllustration()
        case 2: GroupChatIllustration()
        case 3: SkillsSchedulesIllustration()
        default: AllSetIllustration()
        }
    }
}

// MARK: - Page 0: Welcome constellation

private struct WelcomeIllustration: View {
    private struct SatelliteNode {
        /// Fractional position within the illustration frame (0…1)
        let fx: CGFloat; let fy: CGFloat
        let label: String; let color: Color; let emoji: String
    }

    private let nodes: [SatelliteNode] = [
        SatelliteNode(fx: 0.17, fy: 0.24, label: "CODER",    color: .orange, emoji: "🤖"),
        SatelliteNode(fx: 0.83, fy: 0.24, label: "REVIEWER",  color: .teal,   emoji: "🔍"),
        SatelliteNode(fx: 0.50, fy: 0.11, label: "PLANNER",   color: .indigo, emoji: "✦"),
        SatelliteNode(fx: 0.14, fy: 0.80, label: "TESTER",    color: .green,  emoji: "🧪"),
        SatelliteNode(fx: 0.86, fy: 0.80, label: "DEVOPS",    color: .blue,   emoji: "⚙"),
    ]

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let cx = w * 0.50
            let cy = h * 0.52

            ZStack {
                // Lines + glow via Canvas
                Canvas { ctx, size in
                    // Glow
                    ctx.drawLayer { inner in
                        inner.addFilter(.blur(radius: 26))
                        inner.fill(
                            Path(ellipseIn: CGRect(x: cx-50, y: cy-50, width: 100, height: 100)),
                            with: .color(Color.indigo.opacity(0.4))
                        )
                    }
                    // Spokes
                    for node in nodes {
                        var path = Path()
                        path.move(to: CGPoint(x: cx, y: cy))
                        path.addLine(to: CGPoint(x: node.fx * w, y: node.fy * h))
                        ctx.stroke(path, with: .color(node.color.opacity(0.22)), lineWidth: 1)
                    }
                    // Outer ring
                    let r1: CGFloat = 36
                    ctx.stroke(
                        Path(ellipseIn: CGRect(x: cx-r1, y: cy-r1, width: r1*2, height: r1*2)),
                        with: .color(Color.indigo.opacity(0.38)), lineWidth: 1.5
                    )
                    // Inner fill
                    let r2: CGFloat = 26
                    ctx.fill(
                        Path(ellipseIn: CGRect(x: cx-r2, y: cy-r2, width: r2*2, height: r2*2)),
                        with: .color(Color.indigo.opacity(0.2))
                    )
                }
                .frame(width: w, height: h)

                // Center label
                VStack(spacing: 2) {
                    Text("✦").font(.system(size: 20)).foregroundStyle(.indigo)
                    Text("ODYSSEY").font(.system(size: 7.5, weight: .bold))
                        .foregroundStyle(Color.white.opacity(0.6))
                }
                .position(x: cx, y: cy)

                // Satellite nodes
                ForEach(Array(nodes.enumerated()), id: \.offset) { _, node in
                    satelliteView(node, in: geo.size)
                }
            }
        }
    }

    @ViewBuilder
    private func satelliteView(_ node: SatelliteNode, in size: CGSize) -> some View {
        VStack(spacing: 2) {
            ZStack {
                Circle()
                    .fill(node.color.opacity(0.13))
                    .overlay(Circle().stroke(node.color.opacity(0.32), lineWidth: 1.5))
                    .frame(width: 40, height: 40)
                Text(node.emoji).font(.system(size: 18))
            }
            Text(node.label)
                .font(.system(size: 7.5, weight: .bold))
                .foregroundStyle(node.color.opacity(0.9))
        }
        .position(x: node.fx * size.width, y: node.fy * size.height)
    }
}

// MARK: - Page 1: Agent cards

private struct AgentsIllustration: View {
    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            AgentCard(emoji: "🤖", name: "CODER",    color: .orange,
                      tags: ["Swift", "Python"],          model: "Sonnet", perm: "Bypass",     elevated: false)
            AgentCard(emoji: "🔍", name: "REVIEWER", color: .teal,
                      tags: ["Code Review", "Security"],  model: "Opus",   perm: "Permissive", elevated: true)
            AgentCard(emoji: "🎨", name: "DESIGNER", color: Color(red:0.65,green:0.55,blue:0.98),
                      tags: ["UI/UX", "Figma"],           model: "Sonnet", perm: "Focused",    elevated: false)
        }
        .padding(.horizontal, 32)
        .frame(maxHeight: .infinity)
    }
}

private struct AgentCard: View {
    let emoji: String
    let name: String
    let color: Color
    let tags: [String]
    let model: String
    let perm: String
    let elevated: Bool

    private var avatarSize: CGFloat { elevated ? 54 : 46 }

    var body: some View {
        VStack(spacing: 0) {
            // Avatar
            ZStack {
                Circle()
                    .fill(color.opacity(0.15))
                    .overlay(Circle().stroke(color.opacity(0.38), lineWidth: 1.5))
                    .frame(width: avatarSize, height: avatarSize)
                Text(emoji).font(.system(size: elevated ? 28 : 24))
            }
            .padding(.top, elevated ? 16 : 20)

            Text(name)
                .font(.system(size: elevated ? 10 : 9, weight: .bold))
                .foregroundStyle(color)
                .padding(.top, 7)

            Divider().opacity(0.25).padding(.horizontal, 12).padding(.vertical, 9)

            VStack(spacing: 5) {
                ForEach(tags, id: \.self) { tag in
                    Text(tag)
                        .font(.system(size: 8))
                        .foregroundStyle(color.opacity(0.9))
                        .padding(.horizontal, 10).padding(.vertical, 3)
                        .background(color.opacity(0.13))
                        .clipShape(Capsule())
                }
            }
            .padding(.horizontal, 10)

            Spacer(minLength: 0)

            Text(model)
                .font(.system(size: 7.5))
                .foregroundStyle(.quaternary)
                .padding(.horizontal, 8).padding(.vertical, 3)
                .background(Color.white.opacity(0.05))
                .clipShape(Capsule())

            HStack(spacing: 4) {
                Circle().fill(Color.green.opacity(0.8)).frame(width: 5, height: 5)
                Text(perm).font(.system(size: 7.5)).foregroundStyle(.quaternary)
            }
            .padding(.top, 6)
            .padding(.bottom, 14)
        }
        .frame(maxWidth: .infinity, maxHeight: elevated ? .infinity : 190)
        .background(color.opacity(0.07))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(color.opacity(elevated ? 0.28 : 0.18), lineWidth: elevated ? 1.5 : 1))
        .shadow(color: elevated ? color.opacity(0.12) : .clear, radius: 12, y: 4)
        .padding(.vertical, elevated ? 0 : 16)
    }
}

// MARK: - Page 2: Group chat

private struct GroupChatIllustration: View {
    // Agent positions as fractions of (width, height)
    private let coderPos    = CGPoint(x: 0.50, y: 0.19)
    private let reviewerPos = CGPoint(x: 0.76, y: 0.70)
    private let testerPos   = CGPoint(x: 0.24, y: 0.70)

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height

            ZStack {
                // Dashed ring + triangle lines
                Canvas { ctx, size in
                    let cx = size.width * 0.50
                    let cy = size.height * 0.50
                    let r  = min(size.width, size.height) * 0.36

                    // Dashed ring
                    var ring = Path()
                    ring.addEllipse(in: CGRect(x: cx-r, y: cy-r, width: r*2, height: r*2))
                    ctx.stroke(ring, with: .color(Color.indigo.opacity(0.13)),
                               style: StrokeStyle(lineWidth: 1, dash: [4, 4]))

                    // Triangle
                    let pts = [coderPos, reviewerPos, testerPos]
                    for i in 0..<pts.count {
                        let j = (i+1) % pts.count
                        var p = Path()
                        p.move(to:    CGPoint(x: pts[i].x * size.width, y: pts[i].y * size.height))
                        p.addLine(to: CGPoint(x: pts[j].x * size.width, y: pts[j].y * size.height))
                        ctx.stroke(p, with: .color(Color.indigo.opacity(0.14)), lineWidth: 1)
                    }
                }

                // Agent nodes
                agentNode(emoji: "🤖", name: "CODER",    color: .orange,  at: coderPos,    in: geo.size)
                agentNode(emoji: "🔍", name: "REVIEWER", color: .teal,    at: reviewerPos, in: geo.size)
                agentNode(emoji: "🧪", name: "TESTER",   color: .green,   at: testerPos,   in: geo.size)

                // Chat bubbles — placed away from agent circles
                // Coder → upper-right quadrant
                bubble("Auth module done.\nReady for review.", color: .orange)
                    .position(x: w * 0.80, y: h * 0.14)

                // Reviewer → lower-right outside
                bubble("2 issues found.\nFlagging now…", color: .teal)
                    .position(x: w * 0.87, y: h * 0.55)

                // Tester → lower-left outside
                bubble("Coverage 87% ✓", color: .green)
                    .position(x: w * 0.13, y: h * 0.55)

                // Group badge — center
                Text("⚙ DEV SQUAD")
                    .font(.system(size: 9.5, weight: .bold))
                    .foregroundStyle(Color.indigo.opacity(0.9))
                    .padding(.horizontal, 14).padding(.vertical, 6)
                    .background(Color.indigo.opacity(0.18))
                    .clipShape(Capsule())
                    .overlay(Capsule().stroke(Color.indigo.opacity(0.35), lineWidth: 1))
                    .position(x: w * 0.50, y: h * 0.47)

                // User prompt bar at bottom
                HStack(spacing: 6) {
                    Text("\"Build the auth service\"")
                        .font(.system(size: 9))
                        .foregroundStyle(.tertiary)
                    Text("→ all agents")
                        .font(.system(size: 8.5, weight: .semibold))
                        .foregroundStyle(Color.indigo.opacity(0.7))
                }
                .padding(.horizontal, 14).padding(.vertical, 6)
                .background(Color.white.opacity(0.04))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.08), lineWidth: 1))
                .position(x: w * 0.50, y: h * 0.90)
            }
        }
        .padding(.horizontal, 16)
    }

    @ViewBuilder
    private func agentNode(emoji: String, name: String, color: Color,
                           at pos: CGPoint, in size: CGSize) -> some View {
        VStack(spacing: 3) {
            ZStack {
                Circle()
                    .fill(color.opacity(0.13))
                    .overlay(Circle().stroke(color.opacity(0.32), lineWidth: 1.5))
                    .frame(width: 48, height: 48)
                Text(emoji).font(.system(size: 24))
            }
            Text(name).font(.system(size: 8, weight: .bold)).foregroundStyle(color.opacity(0.9))
        }
        .position(x: pos.x * size.width, y: pos.y * size.height)
    }

    @ViewBuilder
    private func bubble(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.system(size: 8.5))
            .foregroundStyle(Color.white.opacity(0.7))
            .multilineTextAlignment(.center)
            .lineSpacing(2)
            .padding(.horizontal, 11).padding(.vertical, 7)
            .background(color.opacity(0.11))
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(color.opacity(0.25), lineWidth: 1))
            .frame(width: 114)
    }
}

// MARK: - Page 3: Skills & Schedules

private struct SkillsSchedulesIllustration: View {
    private let skills: [(icon: String, name: String, opacity: Double)] = [
        ("⚡", "blackboard_read", 1.0),
        ("⚡", "delegation",      0.68),
        ("⚡", "git_aware",       0.42),
    ]

    private let schedules: [(title: String, sub: String, opacity: Double)] = [
        ("Daily standup",  "Every day 9:00 AM", 1.0),
        ("Inbox triage",   "Every hour",         0.68),
        ("Weekly audit",   "Mondays 8:00 AM",    0.42),
    ]

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            skillsColumn
            Divider().padding(.vertical, 20)
            schedulesColumn
        }
        .padding(.horizontal, 36)
        .padding(.top, 8)
    }

    private var skillsColumn: some View {
        VStack(spacing: 0) {
            Text("SKILLS")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(Color.purple.opacity(0.55))
                .tracking(0.8)

            Spacer(minLength: 10)

            ZStack {
                Circle()
                    .fill(Color.purple.opacity(0.12))
                    .overlay(Circle().stroke(Color.purple.opacity(0.32), lineWidth: 1.5))
                    .frame(width: 52, height: 52)
                Text("🤖").font(.system(size: 28))
            }

            // Connector
            Rectangle()
                .fill(Color.purple.opacity(0.25))
                .frame(width: 1, height: 14)
                .padding(.vertical, 3)

            VStack(spacing: 7) {
                ForEach(skills, id: \.name) { skill in
                    HStack(spacing: 6) {
                        Text(skill.icon).font(.system(size: 11))
                        Text(skill.name)
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(Color.purple.opacity(skill.opacity))
                    }
                    .padding(.horizontal, 13).padding(.vertical, 6)
                    .background(Color.purple.opacity(0.09 * skill.opacity))
                    .clipShape(Capsule())
                    .overlay(Capsule().stroke(Color.purple.opacity(0.28 * skill.opacity), lineWidth: 1))
                    .opacity(skill.opacity)
                }
            }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity)
    }

    private var schedulesColumn: some View {
        VStack(spacing: 0) {
            Text("SCHEDULES")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(Color.green.opacity(0.55))
                .tracking(0.8)

            Spacer(minLength: 10)

            ZStack {
                Circle()
                    .fill(Color.green.opacity(0.1))
                    .overlay(Circle().stroke(Color.green.opacity(0.28), lineWidth: 1.5))
                    .frame(width: 52, height: 52)
                Image(systemName: "clock.fill")
                    .font(.system(size: 24))
                    .foregroundStyle(Color.green.opacity(0.75))
            }

            Rectangle()
                .fill(Color.green.opacity(0.25))
                .frame(width: 1, height: 14)
                .padding(.vertical, 3)

            VStack(spacing: 7) {
                ForEach(schedules, id: \.title) { sched in
                    HStack(spacing: 8) {
                        Circle().fill(Color.green.opacity(sched.opacity * 0.8)).frame(width: 6, height: 6)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(sched.title)
                                .font(.system(size: 9, weight: .medium))
                                .foregroundStyle(Color.white.opacity(sched.opacity * 0.85))
                            Text(sched.sub)
                                .font(.system(size: 7.5))
                                .foregroundStyle(Color.green.opacity(sched.opacity * 0.8))
                        }
                        Spacer()
                        Image(systemName: "checkmark")
                            .font(.system(size: 8, weight: .semibold))
                            .foregroundStyle(Color.green.opacity(sched.opacity))
                    }
                    .padding(.horizontal, 12).padding(.vertical, 7)
                    .background(Color.green.opacity(0.07 * sched.opacity))
                    .clipShape(RoundedRectangle(cornerRadius: 9))
                    .overlay(RoundedRectangle(cornerRadius: 9).stroke(Color.green.opacity(0.2 * sched.opacity), lineWidth: 1))
                    .opacity(sched.opacity)
                }
            }
            .frame(maxWidth: .infinity)

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity)
        .padding(.leading, 22)
    }
}

// MARK: - Page 4: Chat mockup

private struct AllSetIllustration: View {
    var body: some View {
        VStack(spacing: 0) {
            // Chrome bar
            HStack(spacing: 0) {
                HStack(spacing: 6) {
                    Circle().fill(Color(red:1,green:0.37,blue:0.34)).frame(width: 10, height: 10)
                    Circle().fill(Color(red:0.99,green:0.74,blue:0.18)).frame(width: 10, height: 10)
                    Circle().fill(Color(red:0.16,green:0.78,blue:0.25)).frame(width: 10, height: 10)
                }
                .padding(.leading, 12)

                Spacer()

                HStack(spacing: 8) {
                    Circle()
                        .fill(Color.orange.opacity(0.22))
                        .overlay(Circle().stroke(Color.orange.opacity(0.38), lineWidth: 1))
                        .frame(width: 24, height: 24)
                        .overlay(Text("🤖").font(.system(size: 13)))
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Coder")
                            .font(.system(size: 11, weight: .semibold))
                        Text("Claude Sonnet  ·  ~/my-app")
                            .font(.system(size: 8.5)).foregroundStyle(.quaternary)
                    }
                }

                Spacer()
                Image(systemName: "sidebar.right")
                    .font(.system(size: 12)).foregroundStyle(.quaternary)
                    .padding(.trailing, 12)
            }
            .frame(height: 44)
            .background(Color.white.opacity(0.04))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

            Spacer(minLength: 10)

            // User message
            HStack {
                Spacer()
                Text("Add tests for the auth service")
                    .font(.system(size: 11))
                    .padding(.horizontal, 16).padding(.vertical, 9)
                    .background(Color.indigo.opacity(0.26))
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                    .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.indigo.opacity(0.35), lineWidth: 1))
            }

            Spacer(minLength: 10)

            // Agent reply
            HStack(alignment: .top, spacing: 10) {
                Circle()
                    .fill(Color.orange.opacity(0.2))
                    .overlay(Circle().stroke(Color.orange.opacity(0.3), lineWidth: 1))
                    .frame(width: 28, height: 28)
                    .overlay(Text("🤖").font(.system(size: 14)))

                VStack(alignment: .leading, spacing: 7) {
                    Text("Sure! Writing tests now…")
                        .font(.system(size: 11))

                    VStack(alignment: .leading, spacing: 4) {
                        Capsule().fill(Color.white.opacity(0.09)).frame(width: 180, height: 7)
                        Capsule().fill(Color.white.opacity(0.06)).frame(width: 140, height: 7)
                        Capsule().fill(Color.white.opacity(0.04)).frame(width: 100, height: 7)
                    }

                    HStack(spacing: 6) {
                        Image(systemName: "gearshape.fill")
                            .font(.system(size: 9)).foregroundStyle(Color.orange.opacity(0.7))
                        Text("write_file · auth.test.ts")
                            .font(.system(size: 9)).foregroundStyle(Color.orange.opacity(0.7))
                    }
                    .padding(.horizontal, 11).padding(.vertical, 5)
                    .background(Color.orange.opacity(0.08))
                    .clipShape(Capsule())
                    .overlay(Capsule().stroke(Color.orange.opacity(0.22), lineWidth: 1))
                }
                .padding(.horizontal, 14).padding(.vertical, 12)
                .background(Color.white.opacity(0.045))
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.white.opacity(0.07), lineWidth: 1))

                Spacer()
            }

            Spacer(minLength: 10)

            // Input bar
            HStack(spacing: 10) {
                RoundedRectangle(cornerRadius: 11)
                    .fill(Color.white.opacity(0.05))
                    .overlay(RoundedRectangle(cornerRadius: 11).stroke(Color.white.opacity(0.09), lineWidth: 1))
                    .overlay(
                        Text("Message Coder…")
                            .font(.system(size: 11)).foregroundStyle(.quaternary)
                            .padding(.leading, 14),
                        alignment: .leading
                    )
                    .frame(height: 36)

                Circle()
                    .fill(Color.indigo.opacity(0.55))
                    .frame(width: 32, height: 32)
                    .overlay(
                        Image(systemName: "arrow.up")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.white)
                    )
            }
        }
        .padding(.horizontal, 40)
        .padding(.vertical, 4)
    }
}
