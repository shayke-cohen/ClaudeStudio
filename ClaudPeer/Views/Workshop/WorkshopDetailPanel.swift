import SwiftUI
import SwiftData

struct WorkshopDetailPanel: View {
    let entityContext: String?

    @Query(sort: \Agent.name) private var agents: [Agent]
    @Query(sort: \AgentGroup.name) private var groups: [AgentGroup]
    @Query(sort: \Skill.name) private var skills: [Skill]
    @Query(sort: \MCPServer.name) private var mcps: [MCPServer]
    @Query(sort: \PermissionSet.name) private var permissions: [PermissionSet]

    var body: some View {
        Group {
            if let context = entityContext, let parsed = parseContext(context) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text(parsed.name)
                                .font(.title3)
                                .fontWeight(.semibold)
                            Spacer()
                            Text(parsed.type)
                                .font(.caption)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(.quaternary)
                                .clipShape(Capsule())
                        }
                        .xrayId("workshop.detail.header")

                        Divider()

                        ForEach(parsed.fields, id: \.key) { field in
                            HStack(alignment: .top, spacing: 8) {
                                Text(field.key)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .frame(width: 80, alignment: .trailing)
                                Text(field.value)
                                    .font(.caption)
                                    .textSelection(.enabled)
                            }
                        }
                    }
                    .padding()
                }
                .xrayId("workshop.detailPanel")
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "hand.point.up.left")
                        .font(.title2)
                        .foregroundStyle(.tertiary)
                    Text("Select an entity to inspect")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .xrayId("workshop.detailPanel.empty")
            }
        }
    }

    private struct ParsedEntity {
        let type: String
        let name: String
        let fields: [(key: String, value: String)]
    }

    private func parseContext(_ context: String) -> ParsedEntity? {
        let lines = context.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        guard let firstLine = lines.first else { return nil }

        let typePattern = /User selected (\w[\w ]*) "([^"]+)"/
        guard let match = firstLine.firstMatch(of: typePattern) else { return nil }
        let type = String(match.1)
        let name = String(match.2)

        var fields: [(key: String, value: String)] = []
        for line in lines.dropFirst() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }
            if let colonIdx = trimmed.firstIndex(of: ":") {
                let key = String(trimmed[trimmed.startIndex..<colonIdx]).trimmingCharacters(in: .whitespaces)
                let value = String(trimmed[trimmed.index(after: colonIdx)...]).trimmingCharacters(in: .whitespaces)
                fields.append((key: key, value: value))
            }
        }

        return ParsedEntity(type: type, name: name, fields: fields)
    }
}
