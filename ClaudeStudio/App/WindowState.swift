import SwiftUI
import SwiftData
import Foundation

enum LibrarySection: String, CaseIterable, Identifiable {
    case run
    case build
    case discover

    var id: String { rawValue }

    var title: String {
        switch self {
        case .run: "Run"
        case .build: "Build"
        case .discover: "Discover"
        }
    }
}

enum LibraryBuildSection: String, CaseIterable, Identifiable {
    case agents
    case groups

    var id: String { rawValue }

    var title: String {
        switch self {
        case .agents: "Agents"
        case .groups: "Groups"
        }
    }
}

enum LibraryDiscoverSection: String, CaseIterable, Identifiable {
    case agentTemplates
    case skills
    case integrations

    var id: String { rawValue }

    var title: String {
        switch self {
        case .agentTemplates: "Agent Templates"
        case .skills: "Skills"
        case .integrations: "Integrations"
        }
    }
}

enum WindowInspectorTab: String, CaseIterable, Identifiable {
    case info = "Info"
    case files = "Files"
    case blackboard = "Blackboard"
    case group = "Group"

    var id: String { rawValue }
}

enum ProjectRecords {
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
    static func upsertProject(at path: String, in modelContext: ModelContext) -> Project {
        let canonical = canonicalPath(for: path)
        let defaultName = displayName(for: canonical)
        let descriptor = FetchDescriptor<Project>()
        let existing = (try? modelContext.fetch(descriptor))?.first {
            $0.canonicalRootPath == canonical
        }

        let project = existing ?? Project(
            name: defaultName,
            rootPath: canonical,
            canonicalRootPath: canonical
        )
        if project.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
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
            // Update AppState's visible set for notification gating
            if let old = oldValue { appState?.visibleConversationIds.remove(old) }
            if let new = selectedConversationId {
                appState?.visibleConversationIds.insert(new)
                markConversationRead(id: new)
            }
        }
    }
    var selectedGroupId: UUID? {
        didSet { if selectedGroupId != nil { selectedConversationId = nil } }
    }

    var inspectorVisible = true
    var selectedInspectorTab: WindowInspectorTab = .info

    var showNewSessionSheet = false
    var showNewGroupThreadSheet = false
    var showLibraryHub = false
    var selectedLibrarySection: LibrarySection = .run
    var selectedLibraryBuildSection: LibraryBuildSection = .agents
    var selectedLibraryDiscoverSection: LibraryDiscoverSection = .agentTemplates
    var showScheduleLibrary = false
    var showPeerNetwork = false
    var showAgentComms = false
    var showWorkshop = false

    var launchError: String?
    var autoSendText: String?

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
    }

    private func markConversationRead(id: UUID) {
        guard let ctx = appState?.modelContext else { return }
        let descriptor = FetchDescriptor<Conversation>(predicate: #Predicate { c in c.id == id })
        guard let convo = try? ctx.fetch(descriptor).first, convo.isUnread else { return }
        convo.isUnread = false
        try? ctx.save()
    }

    func openLibrary(
        _ section: LibrarySection = .run,
        buildSection: LibraryBuildSection? = nil,
        discoverSection: LibraryDiscoverSection? = nil
    ) {
        selectedLibrarySection = section
        if let buildSection {
            selectedLibraryBuildSection = buildSection
        }
        if let discoverSection {
            selectedLibraryDiscoverSection = discoverSection
        }
        showLibraryHub = true
    }

    func openInspector(tab: WindowInspectorTab? = nil) {
        if let tab {
            selectedInspectorTab = tab
        }
        inspectorVisible = true
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
    }
}
