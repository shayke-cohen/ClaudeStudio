import SwiftUI
import SwiftData
import Foundation

enum WindowInspectorTab: String, CaseIterable, Identifiable {
    case info = "Info"
    case files = "Files"
    case blackboard = "Blackboard"
    case group = "Group"

    var id: String { rawValue }
}

enum WindowContentRoute: String {
    case workspace
    case settings
}

struct InspectorFileSelectionRequest: Equatable {
    let id: UUID
    let url: URL

    init(id: UUID = UUID(), url: URL) {
        self.id = id
        self.url = url
    }
}

enum ProjectRecords {
    private static let workspaceMarkerPaths = [
        "project.yml",
        "sidecar/src/index.ts",
        "Odyssey.xcodeproj",
    ]

    static func canonicalPath(for path: String) -> String {
        URL(fileURLWithPath: path)
            .standardizedFileURL
            .resolvingSymlinksInPath()
            .path
    }

    static func displayName(for path: String) -> String {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "Project" }
        return (trimmed as NSString).lastPathComponent
    }

    @discardableResult
    static func repairMissingProjects(
        in modelContext: ModelContext,
        currentDirectoryPath: String = FileManager.default.currentDirectoryPath,
        recentDirectories: [String] = RecentDirectories.load(),
        projectRootOverride: String? = InstanceConfig.userDefaults.string(forKey: AppSettings.sidecarPathKey)
    ) -> Bool {
        let descriptor = FetchDescriptor<Project>()
        let projects = (try? modelContext.fetch(descriptor)) ?? []
        var changed = false

        for project in projects {
            changed = repairProjectIfNeeded(
                project,
                currentDirectoryPath: currentDirectoryPath,
                recentDirectories: recentDirectories,
                projectRootOverride: projectRootOverride
            ) || changed
        }

        if changed {
            try? modelContext.save()
        }
        return changed
    }

    @discardableResult
    static func repairProjectIfNeeded(
        _ project: Project,
        currentDirectoryPath: String = FileManager.default.currentDirectoryPath,
        recentDirectories: [String] = RecentDirectories.load(),
        projectRootOverride: String? = InstanceConfig.userDefaults.string(forKey: AppSettings.sidecarPathKey)
    ) -> Bool {
        let currentPath = canonicalPath(for: project.canonicalRootPath.isEmpty ? project.rootPath : project.canonicalRootPath)
        let defaultName = displayName(for: currentPath)
        let fileManager = FileManager.default

        if fileManager.fileExists(atPath: currentPath) {
            var changed = false
            if project.rootPath != currentPath {
                project.rootPath = currentPath
                changed = true
            }
            if project.canonicalRootPath != currentPath {
                project.canonicalRootPath = currentPath
                changed = true
            }
            if project.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                project.name = defaultName
                changed = true
            }
            return changed
        }

        guard let relocatedPath = relocatedProjectPath(
            forMissingPath: currentPath,
            currentDirectoryPath: currentDirectoryPath,
            recentDirectories: recentDirectories,
            projectRootOverride: projectRootOverride
        ) else {
            return false
        }

        let relocatedName = displayName(for: relocatedPath)
        let shouldRename = project.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || project.name == defaultName

        project.rootPath = relocatedPath
        project.canonicalRootPath = relocatedPath
        project.lastOpenedAt = Date()
        if shouldRename {
            project.name = relocatedName
        }
        return true
    }

    @discardableResult
    static func upsertProject(
        at path: String,
        in modelContext: ModelContext,
        currentDirectoryPath: String = FileManager.default.currentDirectoryPath,
        recentDirectories: [String] = RecentDirectories.load(),
        projectRootOverride: String? = InstanceConfig.userDefaults.string(forKey: AppSettings.sidecarPathKey)
    ) -> Project {
        let requestedCanonical = canonicalPath(for: path)
        let canonical = relocatedProjectPath(
            forMissingPath: requestedCanonical,
            currentDirectoryPath: currentDirectoryPath,
            recentDirectories: recentDirectories,
            projectRootOverride: projectRootOverride
        ) ?? requestedCanonical
        let defaultName = displayName(for: canonical)
        let descriptor = FetchDescriptor<Project>()
        let existing = (try? modelContext.fetch(descriptor))?.first {
            $0.canonicalRootPath == canonical || $0.canonicalRootPath == requestedCanonical
        }

        let project = existing ?? Project(
            name: defaultName,
            rootPath: canonical,
            canonicalRootPath: canonical
        )
        let requestedName = displayName(for: requestedCanonical)
        if project.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || project.name == requestedName {
            project.name = defaultName
        }
        project.rootPath = canonical
        project.canonicalRootPath = canonical
        project.lastOpenedAt = Date()

        if existing == nil {
            modelContext.insert(project)
        }
        try? modelContext.save()
        return project
    }

    private static func relocatedProjectPath(
        forMissingPath path: String,
        currentDirectoryPath: String,
        recentDirectories: [String],
        projectRootOverride: String?
    ) -> String? {
        let canonical = canonicalPath(for: path)
        let fileManager = FileManager.default
        guard !fileManager.fileExists(atPath: canonical) else { return canonical }

        let parentPath = URL(fileURLWithPath: canonical).deletingLastPathComponent().path
        var candidates = [currentDirectoryPath]
        if let projectRootOverride, !projectRootOverride.isEmpty {
            candidates.append(projectRootOverride)
        }
        candidates.append(contentsOf: recentDirectories)

        if fileManager.fileExists(atPath: parentPath),
           let siblingURLs = try? fileManager.contentsOfDirectory(
                at: URL(fileURLWithPath: parentPath),
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
           ) {
            candidates.append(contentsOf: siblingURLs.map(\.path))
        }

        let normalizedCandidates = Array(
            Set(
                candidates
                    .map(canonicalPath(for:))
                    .filter { candidate in
                        var isDirectory: ObjCBool = false
                        return fileManager.fileExists(atPath: candidate, isDirectory: &isDirectory) && isDirectory.boolValue
                    }
            )
        )

        let sameParentWorkspaceCandidates = normalizedCandidates.filter {
            URL(fileURLWithPath: $0).deletingLastPathComponent().path == parentPath
                && looksLikeWorkspaceRoot($0)
        }
        if sameParentWorkspaceCandidates.count == 1 {
            return sameParentWorkspaceCandidates[0]
        }

        let workspaceCandidates = normalizedCandidates.filter(looksLikeWorkspaceRoot)
        if workspaceCandidates.count == 1 {
            return workspaceCandidates[0]
        }

        return nil
    }

    private static func looksLikeWorkspaceRoot(_ path: String) -> Bool {
        let fileManager = FileManager.default
        return workspaceMarkerPaths.allSatisfy { marker in
            fileManager.fileExists(atPath: URL(fileURLWithPath: path).appendingPathComponent(marker).path)
        }
    }
}

struct PendingTemplatePrompt: Equatable {
    let conversationId: UUID
    let text: String
}

/// Per-window state for the project-first shell.
@MainActor @Observable
final class WindowState {
    /// Reference to the shared AppState for cross-window coordination.
    weak var appState: AppState?

    private(set) var selectedProjectId: UUID?
    private var chatScrollAnchorIds: [UUID: UUID] = [:]

    private var currentProjectDirectory: String
    private var currentProjectDisplayName: String

    var selectedConversationId: UUID? {
        didSet {
            if selectedConversationId != nil { selectedGroupId = nil }
            if selectedConversationId == nil { chatTitle = nil }
            // Update AppState's visible set for notification gating
            if let old = oldValue { appState?.visibleConversationIds.remove(old) }
            if let new = selectedConversationId {
                appState?.visibleConversationIds.insert(new)
                markConversationRead(id: new)
            }
        }
    }
    var selectedGroupId: UUID? {
        didSet {
            if selectedGroupId != nil { selectedConversationId = nil }
            if selectedGroupId == nil { chatTitle = nil }
        }
    }
    /// Set by ChatView when the active conversation's agent/group name is known.
    /// Used by WindowTitleSetter to build the breadcrumb title.
    var chatTitle: String? = nil

    var isDefaultProject: Bool {
        projectName == "Playground" || projectName == "No Project"
    }
    /// Fire-and-forget signal: SidebarView observes this via onChange, expands the owning
    /// agent/group tree, then nils it out. Note: if the same UUID is set twice in a row
    /// without the sidebar consuming and clearing it first, the second onChange won't fire.
    var sidebarRevealConversationId: UUID? = nil

    var inspectorVisible = false
    var selectedInspectorTab: WindowInspectorTab = .info
    var inspectorFileSelectionRequest: InspectorFileSelectionRequest?

    var showAgentPicker: Bool = false
    var showGroupPicker: Bool = false
    var showNewSessionSheet = false
    var showNewGroupThreadSheet = false
    var showScheduleLibrary = false
    var showAllSchedules = false
    var showPeerNetwork = false
    var showAgentComms = false
    var showSharedRoomInviteSheet = false
    var showSharedRoomInbox = false
    var showFTE = false
    var activeRoute: WindowContentRoute = .workspace
    var pendingConfigSection: ConfigSection? = nil
    var pendingConfigSlug: String? = nil
    var sharedRoomInviteConversationId: UUID?

    var launchError: String?
    var autoSendText: String?
    /// Set by the sidebar project template context menu; consumed by ChatView to auto-send
    /// the prompt when the new conversation appears. The consumer should only act when
    /// `pendingTemplatePrompt.conversationId` matches the currently displayed conversation ID.
    var pendingTemplatePrompt: PendingTemplatePrompt?

    init(project: Project) {
        self.selectedProjectId = project.id
        self.currentProjectDirectory = project.rootPath
        self.currentProjectDisplayName = project.name
    }

    var projectName: String {
        currentProjectDisplayName
    }

    var projectDirectory: String {
        currentProjectDirectory
    }

    func selectProject(_ project: Project, preserveSelection: Bool = false) {
        apply(project: project, preserveSelection: preserveSelection)
    }

    func selectProject(id: UUID, preserveSelection: Bool = false) {
        guard let ctx = appState?.modelContext else { return }
        let descriptor = FetchDescriptor<Project>(predicate: #Predicate { project in
            project.id == id
        })
        guard let project = try? ctx.fetch(descriptor).first else { return }
        apply(project: project, preserveSelection: preserveSelection)
    }

    private func apply(project: Project, preserveSelection: Bool) {
        selectedProjectId = project.id
        currentProjectDirectory = project.rootPath
        currentProjectDisplayName = project.name
        project.lastOpenedAt = Date()
        try? appState?.modelContext?.save()

        if !preserveSelection {
            selectedConversationId = nil
            selectedGroupId = nil
        }
        inspectorFileSelectionRequest = nil
    }

    private func markConversationRead(id: UUID) {
        guard let ctx = appState?.modelContext else { return }
        let descriptor = FetchDescriptor<Conversation>(predicate: #Predicate { c in c.id == id })
        guard let convo = try? ctx.fetch(descriptor).first, convo.isUnread else { return }
        convo.isUnread = false
        try? ctx.save()
    }

    func openSettings() {
        activeRoute = .settings
    }

    func openConfiguration(section: ConfigSection, slug: String? = nil) {
        pendingConfigSection = section
        pendingConfigSlug = slug
        activeRoute = .settings
    }

    func closeSettings() {
        pendingConfigSection = nil
        pendingConfigSlug = nil
        activeRoute = .workspace
    }

    func navigateToConversation(_ conversationId: UUID, projectId: UUID?) {
        if let projectId { selectProject(id: projectId, preserveSelection: true) }
        selectedConversationId = conversationId
        sidebarRevealConversationId = nil  // ensure onChange fires even if same UUID repeated
        sidebarRevealConversationId = conversationId
        showScheduleLibrary = false
    }

    func openInspector(tab: WindowInspectorTab? = nil) {
        if let tab {
            selectedInspectorTab = tab
        }
        inspectorVisible = true
    }

    func openInspectorFile(at url: URL) {
        inspectorFileSelectionRequest = InspectorFileSelectionRequest(
            url: url.standardizedFileURL.resolvingSymlinksInPath()
        )
        selectedInspectorTab = .files
        inspectorVisible = true
    }

    func consumeInspectorFileSelectionRequest(id: UUID) {
        guard inspectorFileSelectionRequest?.id == id else { return }
        inspectorFileSelectionRequest = nil
    }

    func chatScrollAnchor(for conversationId: UUID) -> UUID? {
        chatScrollAnchorIds[conversationId]
    }

    func setChatScrollAnchor(_ messageId: UUID?, for conversationId: UUID) {
        if let messageId {
            chatScrollAnchorIds[conversationId] = messageId
        } else {
            chatScrollAnchorIds.removeValue(forKey: conversationId)
        }
    }

    func clearProjectSelection() {
        selectedProjectId = nil
        currentProjectDirectory = ""
        currentProjectDisplayName = "No Project"
        selectedConversationId = nil
        selectedGroupId = nil
        selectedInspectorTab = .info
        inspectorFileSelectionRequest = nil
        activeRoute = .workspace
    }
}
