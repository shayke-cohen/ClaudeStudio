import SwiftUI

/// Shown on launch when no working directory is configured for this instance.
/// Lets the user pick from recent directories or browse for a new one.
struct WorkingDirectoryPicker: View {
    var onSelect: (String) -> Void

    @State private var recentDirs: [String] = []
    @State private var customPath = ""

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
            Divider()
            footer
        }
        .frame(width: 520, height: 440)
        .interactiveDismissDisabled()
        .onAppear { recentDirs = RecentDirectories.load() }
    }

    // MARK: - Header

    private var header: some View {
        VStack(spacing: 4) {
            Image(systemName: "folder.badge.gearshape")
                .font(.system(size: 36))
                .foregroundStyle(.blue)
                .padding(.bottom, 4)

            Text("Choose Working Directory")
                .font(.title2)
                .fontWeight(.semibold)

            if !InstanceConfig.isDefault {
                Text("Instance: \(InstanceConfig.name)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.top, 1)
            }

            Text("This folder will be the default working directory for all chats in this window.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
                .padding(.top, 2)
        }
        .padding(.vertical, 20)
    }

    // MARK: - Content

    private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if !recentDirs.isEmpty {
                    recentSection
                }

                manualSection
            }
            .padding(20)
        }
    }

    private var recentSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Recent")
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundStyle(.secondary)

            ForEach(Array(recentDirs.enumerated()), id: \.offset) { index, dir in
                Button { onSelect(dir) } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "folder.fill")
                            .foregroundStyle(.blue.opacity(0.7))
                            .frame(width: 20)

                        VStack(alignment: .leading, spacing: 1) {
                            Text(displayName(for: dir))
                                .font(.callout)
                                .fontWeight(.medium)
                                .lineLimit(1)
                            Text(abbreviatePath(dir))
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }

                        Spacer()

                        Image(systemName: "arrow.right")
                            .font(.caption)
                            .foregroundStyle(.quaternary)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("directoryPicker.recent.\(index)")
            }
        }
    }

    private var manualSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Custom Path")
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundStyle(.secondary)

            HStack(spacing: 8) {
                TextField("~/projects/my-app", text: $customPath)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityIdentifier("directoryPicker.customPathField")
                    .onSubmit {
                        let expanded = expandPath(customPath)
                        if !expanded.isEmpty { onSelect(expanded) }
                    }

                Button("Browse...") { browse() }
                    .accessibilityIdentifier("directoryPicker.browseButton")
            }
        }
    }

    // MARK: - Footer

    private var footer: some View {
        HStack {
            Button("Use Home Directory") {
                onSelect(NSHomeDirectory())
            }
            .accessibilityIdentifier("directoryPicker.useHomeButton")

            Spacer()

            if !customPath.isEmpty {
                Button("Use Custom Path") {
                    let expanded = expandPath(customPath)
                    if !expanded.isEmpty { onSelect(expanded) }
                }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("directoryPicker.useCustomButton")
            }
        }
        .padding(16)
    }

    // MARK: - Actions

    private func browse() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.message = "Choose the working directory for this instance"
        panel.begin { response in
            if response == .OK, let url = panel.url {
                DispatchQueue.main.async {
                    onSelect(url.path(percentEncoded: false))
                }
            }
        }
    }

    // MARK: - Helpers

    private func displayName(for path: String) -> String {
        (path as NSString).lastPathComponent
    }

    private func abbreviatePath(_ path: String) -> String {
        let home = NSHomeDirectory()
        if path.hasPrefix(home) {
            return "~" + path.dropFirst(home.count)
        }
        return path
    }

    private func expandPath(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("~") {
            return NSHomeDirectory() + trimmed.dropFirst()
        }
        return trimmed
    }
}
