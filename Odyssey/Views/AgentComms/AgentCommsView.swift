import SwiftUI
import SwiftData

struct AgentCommsView: View {
    @Environment(AppState.self) private var appState
    @State private var filter: CommsFilter = .all

    enum CommsFilter: String, CaseIterable {
        case all = "All"
        case chats = "Chats"
        case delegations = "Delegations"
        case blackboard = "Blackboard"
    }

    var filteredEvents: [AppState.CommsEvent] {
        switch filter {
        case .all:
            return appState.commsEvents
        case .chats:
            return appState.commsEvents.filter {
                if case .chat = $0.kind { return true }
                return false
            }
        case .delegations:
            return appState.commsEvents.filter {
                if case .delegation = $0.kind { return true }
                return false
            }
        case .blackboard:
            return appState.commsEvents.filter {
                if case .blackboardUpdate = $0.kind { return true }
                return false
            }
        }
    }

    var body: some View {
        // Compute the filtered events once per body run instead of three times
        // (header count, empty check, list source). With the cap at 1000 the
        // per-call cost is small but the dedupe is free.
        let events = filteredEvents
        return VStack(spacing: 0) {
            header(eventCount: events.count)
            Divider()

            if events.isEmpty {
                emptyState
                    .xrayId("agentComms.emptyState")
            } else {
                ScrollViewReader { proxy in
                    List(events.reversed()) { event in
                        CommsTimelineEntry(event: event)
                            .listRowSeparator(.visible)
                            .xrayId("agentComms.event.\(event.id.uuidString)")
                    }
                    .listStyle(.plain)
                    .xrayId("agentComms.eventList")
                }
            }
        }
        .frame(minWidth: 400, minHeight: 300)
    }

    private func header(eventCount: Int) -> some View {
        VStack(spacing: 8) {
            HStack {
                Label("Agent Comms", systemImage: "antenna.radiowaves.left.and.right")
                    .font(.headline)
                    .xrayId("agentComms.title")
                Spacer()
                Text("\(eventCount) events")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .xrayId("agentComms.eventCount")
            }

            Picker("Filter", selection: $filter) {
                ForEach(CommsFilter.allCases, id: \.self) { f in
                    Text(f.rawValue).tag(f)
                }
            }
            .pickerStyle(.segmented)
            .xrayId("agentComms.filterPicker")
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("No Agent Communication", systemImage: "bubble.left.and.bubble.right")
        } description: {
            Text("Inter-agent messages, delegations, and blackboard updates will appear here as agents collaborate.")
        }
    }
}

struct CommsTimelineEntry: View {
    let event: AppState.CommsEvent

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            eventIcon
                .frame(width: 24)
                .xrayId("agentComms.eventIcon.\(event.id.uuidString)")
                .accessibilityLabel(eventKindLabel)

            VStack(alignment: .leading, spacing: 4) {
                eventHeader
                eventBody
            }

            Spacer()

            Text(event.timestamp, style: .time)
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .xrayId("agentComms.eventTimestamp.\(event.id.uuidString)")
        }
        .padding(.vertical, 4)
    }

    private var eventKindLabel: String {
        switch event.kind {
        case .chat: return "Chat"
        case .delegation: return "Delegation"
        case .blackboardUpdate: return "Blackboard update"
        }
    }

    @ViewBuilder
    private var eventIcon: some View {
        switch event.kind {
        case .chat:
            Image(systemName: "bubble.left.and.bubble.right.fill")
                .foregroundStyle(.blue)
        case .delegation:
            Image(systemName: "arrow.triangle.branch")
                .foregroundStyle(.orange)
        case .blackboardUpdate:
            Image(systemName: "square.and.pencil")
                .foregroundStyle(.green)
        }
    }

    @ViewBuilder
    private var eventHeader: some View {
        switch event.kind {
        case .chat(_, let from, _):
            Text(from)
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(.primary)
        case .delegation(let from, let to, _):
            HStack(spacing: 4) {
                Text(from)
                    .font(.caption)
                    .fontWeight(.semibold)
                Image(systemName: "arrow.right")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text(to)
                    .font(.caption)
                    .fontWeight(.semibold)
            }
        case .blackboardUpdate(let key, _, let writtenBy):
            HStack(spacing: 4) {
                Text(writtenBy)
                    .font(.caption)
                    .fontWeight(.semibold)
                Image(systemName: "arrow.right")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text(key)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var eventBody: some View {
        switch event.kind {
        case .chat(_, _, let message):
            Text(message)
                .font(.callout)
                .lineLimit(3)
        case .delegation(_, _, let task):
            Text(task)
                .font(.callout)
                .lineLimit(3)
                .foregroundStyle(.secondary)
        case .blackboardUpdate(_, let value, _):
            Text(value)
                .font(.caption)
                .lineLimit(2)
                .foregroundStyle(.secondary)
                .padding(4)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 4))
        }
    }
}
