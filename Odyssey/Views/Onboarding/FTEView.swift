import SwiftUI

private struct FTEPage {
    let icon: String
    let iconColor: Color
    let title: String
    let body: String
    let detail: String?
}

private let ftePages: [FTEPage] = [
    FTEPage(
        icon: "sparkles.rectangle.stack.fill",
        iconColor: .indigo,
        title: "Welcome to Odyssey",
        body: "Your multi-agent AI workspace — where specialized agents collaborate, skills extend their capabilities, and schedules keep them running around the clock.",
        detail: nil
    ),
    FTEPage(
        icon: "cpu",
        iconColor: .orange,
        title: "Agents & Groups",
        body: "Odyssey ships with pre-built AI specialists: Coder, Reviewer, Tester, Designer, and more. Each has its own persona, model, and permissions.",
        detail: "Assemble agents into Groups for complex workflows. Dev Squad, Full Stack Team, Security Audit — start one with a single prompt."
    ),
    FTEPage(
        icon: "bolt.fill",
        iconColor: .purple,
        title: "Skills & Schedules",
        body: "Skills are reusable prompt modules that extend what agents know — blackboard patterns, delegation strategies, and more.",
        detail: "Schedules run agent missions on a cron — daily standups, hourly inbox checks, weekly audits. Set it and let it run."
    ),
    FTEPage(
        icon: "checkmark.seal.fill",
        iconColor: .green,
        title: "You're All Set",
        body: "Your default agents and groups are ready to go. Open a conversation, pick an agent from the library, or kick off a group session.",
        detail: nil
    ),
]

struct FTEView: View {
    @Environment(\.dismiss) private var dismissAction
    @AppStorage(AppSettings.fteShownKey, store: AppSettings.store)
    private var fteShown = false

    @State private var page = 0
    @State private var slideDirection: Edge = .trailing

    private var isLastPage: Bool { page == ftePages.count - 1 }
    private var isFirstPage: Bool { page == 0 }

    var body: some View {
        VStack(spacing: 0) {
            topBar
            pageContent
            bottomBar
        }
        .frame(width: 560, height: 480)
        .background(Color(nsColor: .controlBackgroundColor))
    }

    // MARK: - Top bar

    private var topBar: some View {
        HStack {
            Button {
                markShownAndDismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title2)
                    .foregroundStyle(.tertiary)
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.escape, modifiers: [])
            .accessibilityLabel("Close")
            .accessibilityIdentifier("fte.closeButton")

            Spacer()

            HStack(spacing: 6) {
                ForEach(0..<ftePages.count, id: \.self) { i in
                    Circle()
                        .fill(i == page ? Color.primary.opacity(0.7) : Color.primary.opacity(0.18))
                        .frame(width: 6, height: 6)
                        .animation(.easeInOut(duration: 0.2), value: page)
                }
            }
            .accessibilityIdentifier("fte.pageIndicator")

            Spacer()

            // Balancing spacer so dots stay centered
            Image(systemName: "xmark.circle.fill")
                .font(.title2)
                .hidden()
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
        .padding(.bottom, 8)
    }

    // MARK: - Page content

    private var pageContent: some View {
        ZStack {
            ForEach(0..<ftePages.count, id: \.self) { i in
                if i == page {
                    PageView(ftePage: ftePages[i], pageIndex: i)
                        .transition(
                            .asymmetric(
                                insertion: .move(edge: slideDirection),
                                removal: .move(edge: slideDirection == .trailing ? .leading : .trailing)
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

    // MARK: - Bottom bar

    private var bottomBar: some View {
        VStack(spacing: 10) {
            HStack(spacing: 12) {
                Button("← Back") {
                    navigate(forward: false)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .font(.callout)
                .opacity(isFirstPage ? 0 : 1)
                .disabled(isFirstPage)
                .accessibilityIdentifier("fte.backButton")

                Spacer()

                if isLastPage {
                    Button("Get Started") {
                        markShownAndDismiss()
                    }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.return, modifiers: [])
                    .accessibilityIdentifier("fte.getStartedButton")
                } else {
                    Button("Next →") {
                        navigate(forward: true)
                    }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.return, modifiers: [])
                    .accessibilityIdentifier("fte.nextButton")
                }
            }
            .padding(.horizontal, 28)

            Text("Dismissing won't show this again")
                .font(.caption2)
                .foregroundStyle(.quaternary)
        }
        .padding(.bottom, 20)
        .padding(.top, 4)
    }

    // MARK: - Actions

    private func navigate(forward: Bool) {
        slideDirection = forward ? .trailing : .leading
        withAnimation(.easeInOut(duration: 0.22)) {
            page = forward ? min(page + 1, ftePages.count - 1) : max(page - 1, 0)
        }
    }

    private func markShownAndDismiss() {
        fteShown = true
        dismissAction()
    }
}

// MARK: - PageView

private struct PageView: View {
    let ftePage: FTEPage
    let pageIndex: Int

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            Image(systemName: ftePage.icon)
                .font(.system(size: 52, weight: .medium))
                .foregroundStyle(ftePage.iconColor)
                .padding(.bottom, 20)

            Text(ftePage.title)
                .font(.title)
                .fontWeight(.bold)
                .padding(.bottom, 12)

            Text(ftePage.body)
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)

            if let detail = ftePage.detail {
                Text(detail)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 420)
                    .padding(.top, 10)
            }

            Spacer()
        }
        .padding(.horizontal, 48)
    }
}
