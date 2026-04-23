import SwiftUI
import SwiftData

// MARK: - Create GitHub Issue Sheet

struct CreateGHIssueSheet: View {
    let conversation: Conversation?
    let project: Project?

    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    @Query(sort: [SortDescriptor(\Agent.name)]) private var agents: [Agent]
    @Query(sort: [SortDescriptor(\AgentGroup.name)]) private var groups: [AgentGroup]

    @State private var title: String = ""
    @State private var issueBody: String = ""
    @State private var selectedRepo: String = ""
    @State private var routingType: RoutingType = .none
    @State private var selectedAgentName: String = ""
    @State private var selectedGroupName: String = ""
    @State private var isSubmitting = false
    @State private var submitError: String? = nil

    private var settings: GHPollerSettings { GHPollerSettings.shared }

    enum RoutingType: String, CaseIterable {
        case none = "None"
        case agent = "Agent"
        case group = "Group"
    }

    private var availableRepos: [String] {
        var repos: [String] = []
        if !settings.inboxRepo.isEmpty { repos.append(settings.inboxRepo) }
        if let projectRepo = project?.githubRepo, !projectRepo.isEmpty {
            repos.append(projectRepo)
        }
        return repos
    }

    private var isInboxSelected: Bool { selectedRepo == settings.inboxRepo }

    private var computedLabels: [String] {
        if let agent = conversation?.sessions?.first?.agent {
            return ["odyssey:agent:\(agent.name)"]
        }
        guard isInboxSelected else { return [] }
        switch routingType {
        case .none: return []
        case .agent where !selectedAgentName.isEmpty: return ["odyssey:agent:\(selectedAgentName)"]
        case .group where !selectedGroupName.isEmpty: return ["odyssey:group:\(selectedGroupName)"]
        default: return []
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            headerBar
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    titleSection
                    repoSection
                    if isInboxSelected && conversation?.sessions?.first?.agent == nil {
                        routingSection
                    }
                    bodySection
                    if !computedLabels.isEmpty {
                        labelsPreview
                    }
                    if let err = submitError {
                        Text(err)
                            .foregroundStyle(.red)
                            .font(.caption)
                            .stableXrayId("createGHIssue.errorLabel")
                    }
                }
                .padding(24)
            }
            Divider()
            footerBar
        }
        .frame(minWidth: 520, minHeight: 460)
        .onChange(of: appState.lastCreatedIssueUrl) { _, url in
            guard url != nil, isSubmitting else { return }
            isSubmitting = false
            dismiss()
        }
        .onAppear {
            title = conversation?.topic ?? ""
            selectedRepo = availableRepos.first ?? ""
            if let agent = conversation?.sessions?.first?.agent {
                routingType = .agent
                selectedAgentName = agent.name
            } else if let first = agents.filter(\.isEnabled).first {
                routingType = .agent
                selectedAgentName = first.name
            }
            if selectedGroupName.isEmpty, let first = groups.first {
                selectedGroupName = first.name
            }
        }
    }

    // MARK: - Subviews

    private var headerBar: some View {
        HStack {
            Image(systemName: "exclamationmark.circle")
                .foregroundStyle(.secondary)
            Text("Create GitHub Issue")
                .font(.headline)
            Spacer()
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .stableXrayId("createGHIssue.closeButton")
            .accessibilityLabel("Close")
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    private var titleSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Title")
                .font(.subheadline.weight(.medium))
            TextField("Issue title", text: $title)
                .textFieldStyle(.roundedBorder)
                .stableXrayId("createGHIssue.titleField")
        }
    }

    private var repoSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Repository")
                .font(.subheadline.weight(.medium))
            if availableRepos.isEmpty {
                Text("No repos configured. Connect a GitHub inbox repo in Settings → GitHub.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                Picker("Repository", selection: $selectedRepo) {
                    ForEach(availableRepos, id: \.self) { repo in
                        Text(repo).tag(repo)
                    }
                }
                .labelsHidden()
                .stableXrayId("createGHIssue.repoPicker")
            }
        }
    }

    private var routingSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Route To")
                .font(.subheadline.weight(.medium))
            Picker("Route to", selection: $routingType) {
                ForEach(RoutingType.allCases, id: \.self) { type in
                    Text(type.rawValue).tag(type)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .stableXrayId("createGHIssue.routingTypePicker")

            switch routingType {
            case .none:
                Text("Issue will be filed without a routing label. You can add one manually on GitHub.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            case .agent:
                let enabledAgents = agents.filter(\.isEnabled)
                if enabledAgents.isEmpty {
                    Text("No enabled agents found.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Picker("Agent", selection: $selectedAgentName) {
                        ForEach(enabledAgents, id: \.name) { agent in
                            Text(agent.name).tag(agent.name)
                        }
                    }
                    .stableXrayId("createGHIssue.agentPicker")
                }
            case .group:
                if groups.isEmpty {
                    Text("No groups found.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Picker("Group", selection: $selectedGroupName) {
                        ForEach(groups, id: \.name) { group in
                            Text(group.name).tag(group.name)
                        }
                    }
                    .stableXrayId("createGHIssue.groupPicker")
                }
            }
        }
    }

    private var labelsPreview: some View {
        HStack(spacing: 6) {
            Image(systemName: "tag")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(computedLabels.map { "'\($0)'" }.joined(separator: ", "))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .stableXrayId("createGHIssue.labelsPreview")
    }

    private var bodySection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Description (optional)")
                .font(.subheadline.weight(.medium))
            TextEditor(text: $issueBody)
                .font(.callout)
                .frame(minHeight: 120)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.2)))
                .stableXrayId("createGHIssue.bodyField")
        }
    }

    private var footerBar: some View {
        HStack {
            Spacer()
            Button("Cancel") { dismiss() }
                .buttonStyle(.plain)
                .stableXrayId("createGHIssue.cancelButton")
            Button {
                submit()
            } label: {
                if isSubmitting {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Text("Create Issue")
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty || selectedRepo.isEmpty || isSubmitting)
            .stableXrayId("createGHIssue.submitButton")
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    // MARK: - Actions

    private func submit() {
        let trimmedTitle = title.trimmingCharacters(in: .whitespaces)
        guard !trimmedTitle.isEmpty, !selectedRepo.isEmpty else { return }

        isSubmitting = true
        submitError = nil

        appState.sendToSidecar(.ghIssueCreate(
            repo: selectedRepo,
            title: trimmedTitle,
            body: issueBody.trimmingCharacters(in: .whitespacesAndNewlines),
            labels: computedLabels,
            conversationId: conversation?.id.uuidString
        ))

        // Wait briefly for gh.issue.created event; dismiss or surface error
        Task {
            try? await Task.sleep(for: .seconds(8))
            await MainActor.run {
                if isSubmitting {
                    isSubmitting = false
                    submitError = "Timed out — check that the sidecar is running and gh is authenticated."
                }
            }
        }
    }
}
