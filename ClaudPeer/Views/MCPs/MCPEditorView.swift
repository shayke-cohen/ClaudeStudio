import SwiftUI
import SwiftData

struct KeyValuePair: Identifiable {
    let id = UUID()
    var key: String
    var value: String
}

struct MCPEditorView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    let mcp: MCPServer?
    let onSave: (MCPServer) -> Void

    @State private var name: String
    @State private var serverDescription: String
    @State private var transportType: Int
    @State private var command: String
    @State private var argsText: String
    @State private var envPairs: [KeyValuePair]
    @State private var httpUrl: String
    @State private var headerPairs: [KeyValuePair]

    init(mcp: MCPServer?, onSave: @escaping (MCPServer) -> Void) {
        self.mcp = mcp
        self.onSave = onSave

        _name = State(initialValue: mcp?.name ?? "")
        _serverDescription = State(initialValue: mcp?.serverDescription ?? "")

        let kind = mcp?.transportKind ?? "stdio"
        _transportType = State(initialValue: kind == "stdio" ? 0 : 1)

        switch mcp?.transport {
        case .stdio(let cmd, let args, let env):
            _command = State(initialValue: cmd)
            _argsText = State(initialValue: args.joined(separator: ", "))
            _envPairs = State(initialValue: env.map { KeyValuePair(key: $0.key, value: $0.value) }.sorted { $0.key < $1.key })
            _httpUrl = State(initialValue: "")
            _headerPairs = State(initialValue: [])
        case .http(let url, let headers):
            _command = State(initialValue: "")
            _argsText = State(initialValue: "")
            _envPairs = State(initialValue: [])
            _httpUrl = State(initialValue: url)
            _headerPairs = State(initialValue: headers.map { KeyValuePair(key: $0.key, value: $0.value) }.sorted { $0.key < $1.key })
        case .none:
            _command = State(initialValue: "")
            _argsText = State(initialValue: "")
            _envPairs = State(initialValue: [])
            _httpUrl = State(initialValue: "")
            _headerPairs = State(initialValue: [])
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(mcp == nil ? "Create MCP Server" : "Edit MCP Server")
                    .font(.title3)
                    .fontWeight(.semibold)
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
                .help("Close")
            }
            .padding()

            Form {
                Section("Basic Info") {
                    TextField("Name", text: $name)
                    TextField("Description", text: $serverDescription, axis: .vertical)
                        .lineLimit(3...8)
                }

                Section("Transport") {
                    Picker("Kind", selection: $transportType) {
                        Text("stdio").tag(0)
                        Text("http").tag(1)
                    }
                    .pickerStyle(.segmented)
                }

                if transportType == 0 {
                    Section("stdio Configuration") {
                        TextField("Command", text: $command)
                        TextField("Arguments (comma-separated)", text: $argsText)
                    }
                    Section("Environment Variables") {
                        ForEach($envPairs) { $pair in
                            HStack(alignment: .firstTextBaseline) {
                                TextField("Key", text: $pair.key)
                                TextField("Value", text: $pair.value)
                                Button {
                                    envPairs.removeAll { $0.id == pair.id }
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundStyle(.secondary)
                                }
                                .buttonStyle(.borderless)
                            }
                        }
                        Button {
                            envPairs.append(KeyValuePair(key: "", value: ""))
                        } label: {
                            Label("Add", systemImage: "plus.circle")
                        }
                    }
                } else {
                    Section("HTTP Configuration") {
                        TextField("URL", text: $httpUrl)
                    }
                    Section("Headers") {
                        ForEach($headerPairs) { $pair in
                            HStack(alignment: .firstTextBaseline) {
                                TextField("Key", text: $pair.key)
                                TextField("Value", text: $pair.value)
                                Button {
                                    headerPairs.removeAll { $0.id == pair.id }
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundStyle(.secondary)
                                }
                                .buttonStyle(.borderless)
                            }
                        }
                        Button {
                            headerPairs.append(KeyValuePair(key: "", value: ""))
                        } label: {
                            Label("Add", systemImage: "plus.circle")
                        }
                    }
                }
            }
            .formStyle(.grouped)

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Save") { save() }
                    .buttonStyle(.borderedProminent)
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding()
        }
    }

    private func save() {
        let transport: MCPTransport
        if transportType == 0 {
            let args = argsText
                .split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            var env: [String: String] = [:]
            for pair in envPairs {
                let k = pair.key.trimmingCharacters(in: .whitespacesAndNewlines)
                if !k.isEmpty {
                    env[k] = pair.value
                }
            }
            transport = .stdio(command: command, args: args, env: env)
        } else {
            var headers: [String: String] = [:]
            for pair in headerPairs {
                let k = pair.key.trimmingCharacters(in: .whitespacesAndNewlines)
                if !k.isEmpty {
                    headers[k] = pair.value
                }
            }
            transport = .http(url: httpUrl, headers: headers)
        }

        let target: MCPServer
        if let existing = mcp {
            target = existing
        } else {
            target = MCPServer(name: name.trimmingCharacters(in: .whitespacesAndNewlines), serverDescription: serverDescription, transport: transport)
            modelContext.insert(target)
        }

        target.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        target.serverDescription = serverDescription
        target.transport = transport

        try? modelContext.save()
        onSave(target)
        dismiss()
    }
}
