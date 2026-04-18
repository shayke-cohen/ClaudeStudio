import SwiftUI

/// Standalone debug window that displays a unified, filterable, real-time
/// log stream from both the Swift app (OSLog) and the TypeScript sidecar.
struct DebugLogView: View {
    @Environment(AppState.self) private var appState
    @StateObject private var aggregator = LogAggregator()
    @State private var autoScroll = true
    @State private var copyFlash = false

    var body: some View {
        VStack(spacing: 0) {
            filterBar
            Divider()
            logTable
            Divider()
            statusBar
        }
        .frame(minWidth: 600, minHeight: 400)
        .xrayId("debugLog.root")
        .onAppear {
            aggregator.startStreaming(logDirectory: InstanceConfig.logDirectory)
        }
        .onDisappear {
            aggregator.stopStreaming()
        }
    }

    // MARK: - Filter Bar

    private var filterBar: some View {
        HStack(spacing: 12) {
            Picker("Level", selection: $aggregator.filterLevel) {
                ForEach(LogLevel.allCases) { level in
                    Text(level.label).tag(level)
                }
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 280)
            .xrayId("debugLog.levelPicker")

            Picker("Source", selection: $aggregator.filterSource) {
                Text("All").tag(nil as UnifiedLogEntry.LogSource?)
                ForEach(UnifiedLogEntry.LogSource.allCases) { src in
                    Text(src.rawValue).tag(src as UnifiedLogEntry.LogSource?)
                }
            }
            .frame(width: 100)
            .xrayId("debugLog.sourcePicker")

            Picker("Category", selection: $aggregator.filterCategory) {
                Text("All").tag(nil as String?)
                ForEach(aggregator.availableCategories, id: \.self) { cat in
                    Text(cat).tag(cat as String?)
                }
            }
            .frame(width: 130)
            .xrayId("debugLog.categoryPicker")

            TextField("Search...", text: $aggregator.searchText)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 200)
                .xrayId("debugLog.searchField")

            Spacer()

            Button {
                aggregator.copyFilteredToClipboard()
                withAnimation { copyFlash = true }
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                    withAnimation { copyFlash = false }
                }
            } label: {
                Label(copyFlash ? "Copied!" : "Copy", systemImage: copyFlash ? "checkmark" : "doc.on.doc")
            }
            .controlSize(.small)
            .xrayId("debugLog.copyButton")

            Button {
                aggregator.clear()
            } label: {
                Label("Clear", systemImage: "trash")
            }
            .controlSize(.small)
            .xrayId("debugLog.clearButton")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    // MARK: - Log Table

    private var logTable: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(aggregator.visibleEntries) { entry in
                        logRow(entry)
                            .id(entry.id)
                            .padding(.vertical, 2)
                            .padding(.horizontal, 8)
                    }
                    // Invisible anchor at the bottom for auto-scroll
                    Color.clear
                        .frame(height: 1)
                        .id("bottom")
                }
            }
            .font(.system(.caption, design: .monospaced))
            .xrayId("debugLog.entryList")
            .onChange(of: aggregator.scrollToken) {
                if autoScroll {
                    proxy.scrollTo("bottom", anchor: .bottom)
                }
            }
        }
    }

    @ViewBuilder
    private func logRow(_ entry: UnifiedLogEntry) -> some View {
        HStack(spacing: 6) {
            Text(Self.timeFormatter.string(from: entry.timestamp))
                .foregroundStyle(.secondary)
                .frame(width: 85, alignment: .leading)

            Text(entry.level.rawValue.uppercased())
                .font(.system(.caption2, design: .monospaced, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 4)
                .padding(.vertical, 1)
                .background(levelColor(entry.level), in: RoundedRectangle(cornerRadius: 3))
                .frame(width: 48, alignment: .center)

            Text(entry.category)
                .foregroundStyle(.secondary)
                .frame(width: 80, alignment: .leading)
                .lineLimit(1)

            Text(entry.source.rawValue)
                .foregroundStyle(.tertiary)
                .frame(width: 55, alignment: .leading)

            Text(entry.message)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - Status Bar

    private var statusBar: some View {
        HStack {
            let showing = aggregator.visibleEntries.count
            let filtered = aggregator.filteredCount
            let total = aggregator.totalCount

            if filtered > showing {
                Text("Showing last \(showing) of \(filtered) filtered")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text("\(filtered) entries")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if filtered != total {
                Text("(\(total) total)")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            Spacer()
            Toggle("Auto-scroll", isOn: $autoScroll)
                .toggleStyle(.switch)
                .controlSize(.mini)
                .xrayId("debugLog.autoScrollToggle")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
    }

    // MARK: - Helpers

    private func levelColor(_ level: LogLevel) -> Color {
        switch level {
        case .debug: .gray
        case .info: .blue
        case .warn: .orange
        case .error: .red
        }
    }

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss.SSS"
        return f
    }()
}
