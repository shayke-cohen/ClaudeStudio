import Foundation

/// The mode of a launch intent — what kind of session to create.
enum LaunchMode: Sendable, Equatable {
    case chat
    case agent(name: String)
    case group(name: String)
    case schedule(id: UUID)
    case roomJoin(payload: SharedRoomService.JoinPayload)
    case connectInvite(payload: String)
}

/// A parsed launch intent from CLI args or an app URL.
///
/// Parsed eagerly (no SwiftData dependency). Execution is deferred until
/// `AppState.executeLaunchIntent(_:modelContext:)` is called.
struct LaunchIntent: Sendable {
    let mode: LaunchMode
    let prompt: String?
    let workingDirectory: String?
    let autonomous: Bool
    let occurrence: Date?

    // MARK: - CLI Parsing

    /// Parses `CommandLine.arguments` for launch flags.
    ///
    /// Recognized flags:
    /// - `--chat` — freeform chat
    /// - `--agent <name>` — session with a named agent
    /// - `--group <name>` — group chat with a named group
    /// - `--prompt <text>` — initial message to auto-send
    /// - `--workdir <path>` — override working directory
    /// - `--autonomous` — start in autonomous mode
    /// - `--connect-invite <base64url>` — handle a device invite from `odyssey://connect?invite=...`
    ///
    /// Returns `nil` when no launch-mode flag is present.
    static func fromCommandLine() -> LaunchIntent? {
        fromArguments(CommandLine.arguments)
    }

    static func fromArguments(_ args: [String]) -> LaunchIntent? {

        var mode: LaunchMode?
        var prompt: String?
        var workingDirectory: String?
        var autonomous = false
        var scheduleId: UUID?
        var occurrence: Date?

        var i = 1 // skip argv[0]
        while i < args.count {
            switch args[i] {
            case "--chat":
                mode = .chat

            case "--agent":
                i += 1
                guard i < args.count else { break }
                mode = .agent(name: args[i])

            case "--group":
                i += 1
                guard i < args.count else { break }
                mode = .group(name: args[i])

            case "--prompt":
                i += 1
                guard i < args.count else { break }
                prompt = args[i]

            case "--workdir":
                i += 1
                guard i < args.count else { break }
                workingDirectory = args[i]

            case "--autonomous":
                autonomous = true

            case "--schedule":
                i += 1
                guard i < args.count else { break }
                scheduleId = UUID(uuidString: args[i])

            case "--room-join":
                i += 1
                guard i < args.count else { break }
                let parts = args[i].split(separator: ":", maxSplits: 2).map(String.init)
                guard parts.count >= 2 else { break }
                mode = .roomJoin(payload: .init(
                    roomId: parts[0],
                    inviteId: parts[1],
                    inviteToken: parts.count > 2 ? parts[2] : nil
                ))

            case "--connect-invite":
                i += 1
                guard i < args.count else { break }
                mode = .connectInvite(payload: args[i])

            case "--occurrence":
                i += 1
                guard i < args.count else { break }
                occurrence = ISO8601DateFormatter().date(from: args[i])

            default:
                break
            }
            i += 1
        }

        let resolvedMode: LaunchMode
        if let scheduleId {
            resolvedMode = .schedule(id: scheduleId)
        } else if let mode {
            resolvedMode = mode
        } else {
            return nil
        }
        return LaunchIntent(
            mode: resolvedMode,
            prompt: prompt,
            workingDirectory: workingDirectory,
            autonomous: autonomous,
            occurrence: occurrence
        )
    }

    // MARK: - URL Scheme Parsing

    /// Parses an app URL into a launch intent.
    ///
    /// Supported formats:
    /// - `odyssey://chat?prompt=...`
    /// - `odyssey://agent/Coder?prompt=...&workdir=/path&autonomous=true`
    /// - `odyssey://group/Dev%20Team?autonomous=true`
    /// - `odyssey://schedule/2F0D95B8-1D90-49B4-9C7B-6DAB4F9386A8?occurrence=2026-03-27T06:00:00Z`
    /// - `odyssey://connect?invite=<base64url>` — device invite from QR code or link
    ///
    /// Also accepts legacy `claudestudio://` and `claudpeer://` links.
    ///
    /// Returns `nil` when the URL is not a valid app intent.
    static func fromURL(_ url: URL) -> LaunchIntent? {
        let supportedSchemes = ["odyssey", "claudestudio", "claudpeer"]
        guard let scheme = url.scheme?.lowercased(), supportedSchemes.contains(scheme) else { return nil }

        let host = url.host(percentEncoded: false) ?? ""
        let pathName = url.pathComponents.count > 1 ? url.pathComponents[1] : ""
        let queryItems = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []

        func queryValue(_ name: String) -> String? {
            queryItems.first(where: { $0.name == name })?.value
        }

        let mode: LaunchMode
        switch host {
        case "chat":
            mode = .chat
        case "agent":
            guard !pathName.isEmpty else { return nil }
            mode = .agent(name: pathName)
        case "group":
            guard !pathName.isEmpty else { return nil }
            mode = .group(name: pathName)
        case "schedule":
            guard let id = UUID(uuidString: pathName) else { return nil }
            mode = .schedule(id: id)
        case "room":
            guard pathName == "join",
                  let roomId = queryValue("roomId"),
                  let inviteId = queryValue("inviteId"),
                  !roomId.isEmpty,
                  !inviteId.isEmpty else { return nil }
            mode = .roomJoin(payload: .init(
                roomId: roomId,
                inviteId: inviteId,
                inviteToken: queryValue("token")
            ))
        case "connect":
            guard let invite = queryValue("invite"), !invite.isEmpty else { return nil }
            mode = .connectInvite(payload: invite)
        default:
            return nil
        }

        return LaunchIntent(
            mode: mode,
            prompt: queryValue("prompt"),
            workingDirectory: queryValue("workdir"),
            autonomous: queryValue("autonomous") == "true",
            occurrence: queryValue("occurrence").flatMap { ISO8601DateFormatter().date(from: $0) }
        )
    }
}
