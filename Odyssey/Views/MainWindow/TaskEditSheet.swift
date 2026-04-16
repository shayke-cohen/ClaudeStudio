import SwiftUI
import SwiftData

struct TaskEditSheet: View {
    @EnvironmentObject private var appState: AppState
    @Environment(WindowState.self) private var windowState: WindowState
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @Bindable var task: TaskItem

    @State private var title: String
    @State private var taskDescription: String
    @State private var priority: TaskPriority
    @State private var labelsText: String
    @State private var status: TaskStatus

    init(task: TaskItem) {
        self.task = task
        _title = State(initialValue: task.title)
        _taskDescription = State(initialValue: task.taskDescription)
        _priority = State(initialValue: task.priority)
        _labelsText = State(initialValue: task.labels.joined(separator: ", "))
        _status = State(initialValue: task.status)
    }

    private var isEditable: Bool {
        task.status == .backlog || task.status == .ready
    }

    private var statusColor: Color {
        switch status {
        case .backlog: .gray
        case .ready: .blue
        case .inProgress: .orange
        case .done: .green
        case .failed: .red
        case .blocked: .yellow
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(isEditable ? "Edit Task" : "Task Details")
                    .font(.headline)
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                    .stableXrayId("taskEdit.cancelButton")
            }
            .padding()

            Divider()

            Form {
                // Status section — always visible
                Section("Status") {
                    HStack {
                        Text(status.rawValue.capitalized)
                            .font(.callout.weight(.medium))
                            .foregroundStyle(statusColor)

                        Spacer()

                        switch task.status {
                        case .backlog:
                            Button("Mark as Ready") {
                                status = .ready
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(.blue)
                            .stableXrayId("taskEdit.markReadyButton")

                        case .ready:
                            Button("Move to Backlog") {
                                status = .backlog
                            }
                            .buttonStyle(.bordered)
                            .stableXrayId("taskEdit.moveBacklogButton")

                        case .inProgress:
                            EmptyView()

                        case .blocked:
                            Button("Resume") {
                                status = .inProgress
                            }
                            .buttonStyle(.bordered)

                        case .done, .failed:
                            Button("Retry") {
                                status = .ready
                            }
                            .buttonStyle(.bordered)
                        }
                    }

                    if task.status == .backlog || task.status == .ready {
                        Button {
                            appState.runTaskWithOrchestrator(task, modelContext: modelContext, windowState: windowState)
                            dismiss()
                        } label: {
                            Label("Run with Orchestrator", systemImage: "play.fill")
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.purple)
                        .stableXrayId("taskEdit.runOrchestratorButton")
                    }

                    if let startedAt = task.startedAt {
                        LabeledContent("Started") {
                            Text(startedAt, style: .relative) + Text(" ago")
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                    if let completedAt = task.completedAt {
                        LabeledContent("Completed") {
                            Text(completedAt, style: .relative) + Text(" ago")
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                    if let result = task.result, !result.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Result")
                                .font(.caption.weight(.medium))
                            Text(result)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
                .stableXrayId("taskEdit.statusSection")

                // Editable fields — only for backlog/ready tasks
                if isEditable {
                    TextField("Title", text: $title)
                        .stableXrayId("taskEdit.titleField")

                    Section("Description") {
                        TextEditor(text: $taskDescription)
                            .frame(minHeight: 80)
                            .font(.body)
                            .stableXrayId("taskEdit.descriptionEditor")
                    }

                    Picker("Priority", selection: $priority) {
                        Text("Low").tag(TaskPriority.low)
                        Text("Medium").tag(TaskPriority.medium)
                        Text("High").tag(TaskPriority.high)
                        Text("Critical").tag(TaskPriority.critical)
                    }
                    .stableXrayId("taskEdit.priorityPicker")

                    TextField("Labels (comma-separated)", text: $labelsText)
                        .stableXrayId("taskEdit.labelsField")
                } else {
                    // Read-only display for non-editable tasks
                    Section("Details") {
                        LabeledContent("Title") {
                            Text(task.title)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        if !task.taskDescription.isEmpty {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Description")
                                    .font(.caption.weight(.medium))
                                Text(task.taskDescription)
                                    .font(.body)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                        LabeledContent("Priority") {
                            Text(task.priority.rawValue.capitalized)
                        }
                        if !task.labels.isEmpty {
                            LabeledContent("Labels") {
                                Text(task.labels.joined(separator: ", "))
                            }
                        }
                    }
                }
            }
            .formStyle(.grouped)
            .padding(.horizontal)

            Divider()

            HStack {
                Spacer()
                if isEditable {
                    Button("Save") {
                        task.title = title
                        task.taskDescription = taskDescription
                        task.priority = priority
                        task.labels = labelsText
                            .split(separator: ",")
                            .map { $0.trimmingCharacters(in: .whitespaces) }
                            .filter { !$0.isEmpty }
                        if status != task.status {
                            appState.updateTaskStatus(task, status: status)
                        }
                        try? modelContext.save()
                        dismiss()
                    }
                    .keyboardShortcut(.defaultAction)
                    .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
                    .stableXrayId("taskEdit.saveButton")
                } else if status != task.status {
                    Button("Save") {
                        appState.updateTaskStatus(task, status: status)
                        dismiss()
                    }
                    .keyboardShortcut(.defaultAction)
                    .stableXrayId("taskEdit.saveButton")
                } else {
                    Button("Cancel") { dismiss() }
                        .keyboardShortcut(.defaultAction)
                }
            }
            .padding()
        }
        .frame(width: 420, height: isEditable ? 520 : 400)
    }
}
