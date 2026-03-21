import SwiftUI
import SwiftData

struct AgentCommsView: View {
    @EnvironmentObject private var appState: AppState
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
        VStack(spacing: 0) {
            header
            Divider()

            if filteredEvents.isEmpty {
                emptyState
            } else {
                ScrollViewReader { proxy in
                    List(filteredEvents.reversed()) { event in
                        CommsTimelineEntry(event: event)
                            .listRowSeparator(.visible)
                    }
                    .listStyle(.plain)
                }
            }
        }
        .frame(minWidth: 400, minHeight: 300)
    }

    private var header: some View {
        VStack(spacing: 8) {
            HStack {
                Label("Agent Comms", systemImage: "antenna.radiowaves.left.and.right")
                    .font(.headline)
                Spacer()
                Text("\(filteredEvents.count) events")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Picker("Filter", selection: $filter) {
                ForEach(CommsFilter.allCases, id: \.self) { f in
                    Text(f.rawValue).tag(f)
                }
            }
            .pickerStyle(.segmented)
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

            VStack(alignment: .leading, spacing: 4) {
                eventHeader
                eventBody
            }

            Spacer()

            Text(event.timestamp, style: .time)
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 4)
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
