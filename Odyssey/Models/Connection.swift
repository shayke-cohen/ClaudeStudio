import Foundation
import SwiftData

enum ConnectionProvider: String, Codable, CaseIterable, Sendable, Identifiable {
    case slack
    case linkedin
    case x
    case facebook
    case whatsapp

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .slack: return "Slack"
        case .linkedin: return "LinkedIn"
        case .x: return "X"
        case .facebook: return "Facebook"
        case .whatsapp: return "WhatsApp"
        }
    }

    var iconName: String {
        switch self {
        case .slack: return "bubble.left.and.bubble.right.fill"
        case .linkedin: return "person.text.rectangle"
        case .x: return "text.bubble.fill"
        case .facebook: return "person.2.fill"
        case .whatsapp: return "phone.fill"
        }
    }
}

enum ConnectionInstallScope: String, Codable, CaseIterable, Sendable {
    case system
}

enum ConnectionAuthMode: String, Codable, CaseIterable, Sendable {
    case pkceNative = "pkce-native"
    case brokered

    var displayName: String {
        switch self {
        case .pkceNative: return "PKCE (Native)"
        case .brokered: return "Brokered"
        }
    }
}

enum ConnectionWritePolicy: String, Codable, CaseIterable, Sendable {
    case requireApproval = "require-approval"
    case autonomous
    case readOnly = "read-only"

    var displayName: String {
        switch self {
        case .requireApproval: return "Require Approval"
        case .autonomous: return "Autonomous Writes"
        case .readOnly: return "Read Only"
        }
    }
}

enum ConnectionStatus: String, Codable, CaseIterable, Sendable {
    case disconnected
    case authorizing
    case connected
    case needsAttention = "needs-attention"
    case revoked
    case failed

    var displayName: String {
        switch self {
        case .disconnected: return "Disconnected"
        case .authorizing: return "Authorizing"
        case .connected: return "Connected"
        case .needsAttention: return "Needs Attention"
        case .revoked: return "Revoked"
        case .failed: return "Failed"
        }
    }
}

struct ConnectionCredentialPayload: Codable, Sendable {
    var accessToken: String?
    var refreshToken: String?
    var tokenType: String?
    var expiresAt: Date?
    var brokerReference: String?
    var authorizationCode: String?
    var codeVerifier: String?

    var hasRuntimeCredential: Bool {
        accessToken?.isEmpty == false || brokerReference?.isEmpty == false
    }
}

@Model
final class Connection {
    var id: UUID = UUID()
    var providerRaw: String = ConnectionProvider.slack.rawValue
    var installScopeRaw: String = ConnectionInstallScope.system.rawValue
    var displayName: String = ""
    var accountId: String?
    var accountHandle: String?
    var accountMetadataJSON: String?
    var grantedScopes: [String] = []
    var authModeRaw: String = ConnectionAuthMode.brokered.rawValue
    var writePolicyRaw: String = ConnectionWritePolicy.requireApproval.rawValue
    var statusRaw: String = ConnectionStatus.disconnected.rawValue
    var statusMessage: String?
    var brokerReference: String?
    var auditSummary: String?
    var lastAuthenticatedAt: Date?
    var lastCheckedAt: Date?
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    init(
        provider: ConnectionProvider,
        installScope: ConnectionInstallScope = .system,
        displayName: String? = nil,
        authMode: ConnectionAuthMode,
        writePolicy: ConnectionWritePolicy = .requireApproval
    ) {
        let now = Date()
        self.id = UUID()
        self.providerRaw = provider.rawValue
        self.installScopeRaw = installScope.rawValue
        self.displayName = displayName ?? provider.displayName
        self.grantedScopes = []
        self.authModeRaw = authMode.rawValue
        self.writePolicyRaw = writePolicy.rawValue
        self.statusRaw = ConnectionStatus.disconnected.rawValue
        self.createdAt = now
        self.updatedAt = now
    }

    var provider: ConnectionProvider {
        get { ConnectionProvider(rawValue: providerRaw) ?? .slack }
        set { providerRaw = newValue.rawValue }
    }

    var installScope: ConnectionInstallScope {
        get { ConnectionInstallScope(rawValue: installScopeRaw) ?? .system }
        set { installScopeRaw = newValue.rawValue }
    }

    var authMode: ConnectionAuthMode {
        get { ConnectionAuthMode(rawValue: authModeRaw) ?? .brokered }
        set { authModeRaw = newValue.rawValue }
    }

    var writePolicy: ConnectionWritePolicy {
        get { ConnectionWritePolicy(rawValue: writePolicyRaw) ?? .requireApproval }
        set { writePolicyRaw = newValue.rawValue }
    }

    var status: ConnectionStatus {
        get { ConnectionStatus(rawValue: statusRaw) ?? .disconnected }
        set { statusRaw = newValue.rawValue }
    }
}
