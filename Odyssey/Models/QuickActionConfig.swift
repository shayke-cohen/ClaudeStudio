import Foundation

struct QuickActionConfig: Codable, Identifiable, Equatable {
    var id: UUID
    var name: String
    var prompt: String
    var symbolName: String

    init(id: UUID = UUID(), name: String, prompt: String, symbolName: String) {
        self.id = id
        self.name = name
        self.prompt = prompt
        self.symbolName = symbolName
    }
}

extension QuickActionConfig {
    static let usageThreshold = 10

    static let defaults: [QuickActionConfig] = [
        QuickActionConfig(id: UUID(uuidString: "A1000000-0000-0000-0000-000000000001")!, name: "Fix It",        prompt: "Fix the error above",                                                          symbolName: "wrench.and.screwdriver.fill"),
        QuickActionConfig(id: UUID(uuidString: "A1000000-0000-0000-0000-000000000002")!, name: "Continue",      prompt: "Continue where you left off",                                                  symbolName: "play.fill"),
        QuickActionConfig(id: UUID(uuidString: "A1000000-0000-0000-0000-000000000003")!, name: "Commit & Push", prompt: "Commit all changes and push to the remote",                                     symbolName: "paperplane.fill"),
        QuickActionConfig(id: UUID(uuidString: "A1000000-0000-0000-0000-000000000004")!, name: "Run Tests",     prompt: "Run the tests and show me the results",                                         symbolName: "flask.fill"),
        QuickActionConfig(id: UUID(uuidString: "A1000000-0000-0000-0000-000000000005")!, name: "Undo",          prompt: "Undo the last changes you made — revert them",                                  symbolName: "arrow.uturn.backward"),
        QuickActionConfig(id: UUID(uuidString: "A1000000-0000-0000-0000-000000000006")!, name: "TL;DR",         prompt: "Give me a TL;DR summary of what we've done and where we are",                  symbolName: "bolt.fill"),
        QuickActionConfig(id: UUID(uuidString: "A1000000-0000-0000-0000-000000000007")!, name: "Double Check",  prompt: "Double check your last response — verify it's correct and nothing is missing",  symbolName: "checkmark.seal.fill"),
        QuickActionConfig(id: UUID(uuidString: "A1000000-0000-0000-0000-000000000008")!, name: "Open It",       prompt: "Open it — launch, run, or preview what we just built",                          symbolName: "link"),
        QuickActionConfig(id: UUID(uuidString: "A1000000-0000-0000-0000-000000000009")!, name: "Visual Options",prompt: "Show me visual options for this — present alternatives I can choose from",      symbolName: "paintpalette.fill"),
        QuickActionConfig(id: UUID(uuidString: "A1000000-0000-0000-0000-000000000010")!, name: "Show Visual",   prompt: "Show me this in a visual way — diagram, mockup, or illustration",               symbolName: "eye.fill"),
    ]
}
