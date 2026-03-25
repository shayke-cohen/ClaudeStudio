import SwiftData
import SwiftUI

enum CatalogItem {
    case agent(CatalogAgent)
    case skill(CatalogSkill)
    case mcp(CatalogMCP)
}

struct CatalogDetailView: View {
    let item: CatalogItem
    let onInstallChanged: () -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @State private var showSystemPrompt = false

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    tagsRow
                    descriptionSection
                    detailContent
                }
                .padding()
            }
            .xrayId("catalogDetail.scrollView")
            Divider()
            footer
        }
        .frame(minWidth: 480, idealWidth: 520, minHeight: 400, idealHeight: 500)
    }

    // MARK: - Header

    @ViewBuilder
    private var header: some View {
        HStack(spacing: 12) {
            iconView
            VStack(alignment: .leading, spacing: 2) {
                Text(itemName)
                    .font(.title3)
                    .fontWeight(.semibold)
                metadataChips
            }
            Spacer()
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)
            .xrayId("catalogDetail.closeButton")
            .accessibilityLabel("Close")
        }
        .padding()
    }

    @ViewBuilder
    private var iconView: some View {
        switch item {
        case .agent(let agent):
            Image(systemName: agent.icon)
                .font(.largeTitle)
                .foregroundStyle(Color.fromAgentColor(agent.color))
                .frame(width: 44, height: 44)
        case .skill(let skill):
            Image(systemName: skill.icon)
                .font(.largeTitle)
                .foregroundStyle(Color.accentColor)
                .frame(width: 44, height: 44)
        case .mcp(let mcp):
            Image(systemName: mcp.icon)
                .font(.largeTitle)
                .foregroundStyle(.secondary)
                .frame(width: 44, height: 44)
        }
    }

    @ViewBuilder
    private var metadataChips: some View {
        HStack(spacing: 6) {
            switch item {
            case .agent(let agent):
                chip(agent.category, color: .purple)
                chip(agent.model, color: .blue)
            case .skill(let skill):
                chip(skill.category, color: .blue)
            case .mcp(let mcp):
                chip(mcp.category, color: .blue)
                chip(mcp.transport.kind, color: .orange)
            }
        }
    }

    private func chip(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.caption2)
            .fontWeight(.medium)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .foregroundStyle(color)
            .background(color.opacity(0.12))
            .clipShape(Capsule())
    }

    // MARK: - Tags

    @ViewBuilder
    private var tagsRow: some View {
        let tags = itemTags
        if !tags.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(tags, id: \.self) { tag in
                        Text(tag)
                            .font(.caption2)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.secondary.opacity(0.1))
                            .clipShape(Capsule())
                    }
                }
            }
        }
    }

    // MARK: - Description

    private var descriptionSection: some View {
        Text(itemDescription)
            .font(.body)
            .foregroundStyle(.secondary)
    }

    // MARK: - Type-Specific Content

    @ViewBuilder
    private var detailContent: some View {
        switch item {
        case .agent(let agent):
            agentDetail(agent)
        case .skill(let skill):
            skillDetail(skill)
        case .mcp(let mcp):
            mcpDetail(mcp)
        }
    }

    @ViewBuilder
    private func agentDetail(_ agent: CatalogAgent) -> some View {
        if !agent.requiredSkills.isEmpty {
            detailSection("Required Skills") {
                ForEach(agent.requiredSkills, id: \.self) { skillId in
                    let skillName = CatalogService.shared.findSkill(skillId)?.name ?? skillId
                    Label(skillName, systemImage: "book.fill")
                        .font(.callout)
                }
            }
        }

        if !agent.extraMCPs.isEmpty {
            detailSection("Extra MCPs") {
                ForEach(agent.extraMCPs, id: \.self) { mcpId in
                    let mcpName = CatalogService.shared.findMCP(mcpId)?.name ?? mcpId
                    Label(mcpName, systemImage: "server.rack")
                        .font(.callout)
                }
            }
        }

        if !agent.systemPrompt.isEmpty {
            detailSection("System Prompt") {
                DisclosureGroup(isExpanded: $showSystemPrompt) {

                    Text(agent.systemPrompt)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.secondary.opacity(0.06))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                } label: {
                    Text("\(agent.systemPrompt.count) characters")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .xrayId("catalogDetail.systemPromptDisclosure")
            }
        }
    }

    @ViewBuilder
    private func skillDetail(_ skill: CatalogSkill) -> some View {
        if !skill.requiredMCPs.isEmpty {
            detailSection("Required MCPs") {
                ForEach(skill.requiredMCPs, id: \.self) { mcpId in
                    let mcpName = CatalogService.shared.findMCP(mcpId)?.name ?? mcpId
                    Label(mcpName, systemImage: "server.rack")
                        .font(.callout)
                }
            }
        }

        if !skill.triggers.isEmpty {
            detailSection("Triggers") {
                FlowLayout(spacing: 6) {
                    ForEach(skill.triggers, id: \.self) { trigger in
                        Text(trigger)
                            .font(.caption)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.accentColor.opacity(0.1))
                            .clipShape(Capsule())
                    }
                }
            }
        }

        if !skill.content.isEmpty {
            detailSection("Content") {
                Text(skill.content)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.secondary.opacity(0.06))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            }
        }
    }

    @ViewBuilder
    private func mcpDetail(_ mcp: CatalogMCP) -> some View {
        detailSection("Transport") {
            if mcp.transport.kind == "stdio" {
                if let command = mcp.transport.command {
                    detailRow("Command", value: command)
                }
                if let args = mcp.transport.args, !args.isEmpty {
                    detailRow("Args", value: args.joined(separator: " "))
                }
                if let envKeys = mcp.transport.envKeys, !envKeys.isEmpty {
                    detailRow("Env Keys", value: envKeys.joined(separator: ", "))
                }
            } else {
                if let url = mcp.transport.url {
                    detailRow("URL", value: url)
                }
                if let headerKeys = mcp.transport.headerKeys, !headerKeys.isEmpty {
                    detailRow("Header Keys", value: headerKeys.joined(separator: ", "))
                }
            }
        }

        detailSection("Info") {
            detailRow("Popularity", value: formatPopularity(mcp.popularity))
            if !mcp.homepage.isEmpty {
                HStack {
                    Text("Homepage")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Link(mcp.homepage, destination: URL(string: mcp.homepage) ?? URL(string: "https://example.com")!)
                        .font(.callout)
                        .lineLimit(1)
                        .xrayId("catalogDetail.homepageLink")
                }
            }
        }
    }

    // MARK: - Footer

    private var footer: some View {
        HStack {
            installStatus
            Spacer()
            installAction
        }
        .padding()
    }

    @ViewBuilder
    private var installStatus: some View {
        if isInstalled {
            Label("Installed", systemImage: "checkmark.circle.fill")
                .font(.callout)
                .foregroundStyle(.green)
        }
    }

    @ViewBuilder
    private var installAction: some View {
        if isInstalled {
            Button(role: .destructive) {
                uninstall()
                onInstallChanged()
            } label: {
                Text("Uninstall")
            }
            .controlSize(.regular)
            .xrayId("catalogDetail.uninstallButton")
        } else {
            Button {
                install()
                onInstallChanged()
            } label: {
                Label("Install", systemImage: "arrow.down.circle")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.regular)
            .xrayId("catalogDetail.installButton")
        }
    }

    // MARK: - Helpers

    private var itemName: String {
        switch item {
        case .agent(let a): a.name
        case .skill(let s): s.name
        case .mcp(let m): m.name
        }
    }

    private var itemDescription: String {
        switch item {
        case .agent(let a): a.description
        case .skill(let s): s.description
        case .mcp(let m): m.description
        }
    }

    private var itemTags: [String] {
        switch item {
        case .agent(let a): a.tags
        case .skill(let s): s.tags
        case .mcp(let m): m.tags
        }
    }

    private var isInstalled: Bool {
        switch item {
        case .agent(let a): CatalogService.shared.isAgentInstalled(a.catalogId, context: modelContext)
        case .skill(let s): CatalogService.shared.isSkillInstalled(s.catalogId, context: modelContext)
        case .mcp(let m): CatalogService.shared.isMCPInstalled(m.catalogId, context: modelContext)
        }
    }

    private func install() {
        switch item {
        case .agent(let a):
            CatalogService.shared.installAgent(a.catalogId, into: modelContext)
        case .skill(let s):
            CatalogService.shared.installSkill(s.catalogId, into: modelContext)
        case .mcp(let m):
            CatalogService.shared.installMCP(m.catalogId, into: modelContext)
        }
        try? modelContext.save()
    }

    private func uninstall() {
        switch item {
        case .agent(let a):
            CatalogService.shared.uninstallAgent(catalogId: a.catalogId, context: modelContext)
        case .skill(let s):
            CatalogService.shared.uninstallSkill(catalogId: s.catalogId, context: modelContext)
        case .mcp(let m):
            CatalogService.shared.uninstallMCP(catalogId: m.catalogId, context: modelContext)
        }
        try? modelContext.save()
    }

    private func detailSection<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.subheadline)
                .fontWeight(.semibold)
            content()
        }
    }

    private func detailRow(_ label: String, value: String) -> some View {
        HStack(alignment: .top) {
            Text(label)
                .font(.callout)
                .foregroundStyle(.secondary)
                .frame(width: 90, alignment: .leading)
            Text(value)
                .font(.callout)
                .textSelection(.enabled)
        }
    }

    private func formatPopularity(_ value: Int) -> String {
        if value >= 1_000_000 {
            return String(format: "%.1fM", Double(value) / 1_000_000)
        } else if value >= 1_000 {
            return String(format: "%.0fK", Double(value) / 1_000)
        }
        return "\(value)"
    }
}

// Uses FlowLayout from AgentPreviewCard.swift
