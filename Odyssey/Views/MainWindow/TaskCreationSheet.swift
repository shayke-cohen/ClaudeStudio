import SwiftUI
import SwiftData

struct TaskCreationSheet: View {
    @EnvironmentObject private var appState: AppState
    @Environment(WindowState.self) private var windowState: WindowState
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var title = ""
    @State private var taskDescription = ""
    @State private var priority: TaskPriority = .medium
    @State private var labelsText = ""
    @State private var startImmediately = false

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("New Task")
                    .font(.headline)
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                    .stableXrayId("taskCreation.cancelButton")
            }
            .padding()

            Divider()

            // Form
            Form {
                TextField("Title", text: $title)
                    .multilineTextAlignment(.leading)
                    .stableXrayId("taskCreation.titleField")

                Section("Description") {
                    TextEditor(text: $taskDescription)
                        .frame(minHeight: 80)
                        .font(.body)
                        .stableXrayId("taskCreation.descriptionEditor")
                }

                Picker("Priority", selection: $priority) {
                    Text("Low").tag(TaskPriority.low)
                    Text("Medium").tag(TaskPriority.medium)
                    Text("High").tag(TaskPriority.high)
                    Text("Critical").tag(TaskPriority.critical)
                }
                .stableXrayId("taskCreation.priorityPicker")

                Section("Labels") {
                    TextField("e.g. ui, backend, auth", text: $labelsText)
                        .multilineTextAlignment(.leading)
                        .stableXrayId("taskCreation.labelsField")
                }

                Toggle("Start immediately with Orchestrator", isOn: $startImmediately)
                    .stableXrayId("taskCreation.startToggle")
            }
            .formStyle(.grouped)
            .padding(.horizontal)

            Divider()

            // Footer
            HStack {
                Spacer()
                Button(startImmediately ? "Create & Start" : "Create") {
                    let labels = labelsText
                        .split(separator: ",")
                        .map { $0.trimmingCharacters(in: .whitespaces) }
                        .filter { !$0.isEmpty }

                    appState.createTask(
                        title: title,
                        description: taskDescription,
                        priority: priority,
                        labels: labels,
                        markReady: startImmediately,
                        projectId: windowState.selectedProjectId
                    )

                    if startImmediately {
                        // Find the just-created task and run it
                        let descriptor = FetchDescriptor<TaskItem>(
                            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
                        )
                        if let task = try? modelContext.fetch(descriptor).first,
                           task.title == title {
                            appState.runTaskWithOrchestrator(task, modelContext: modelContext, windowState: windowState)
                        }
                    }

                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
                .help(title.trimmingCharacters(in: .whitespaces).isEmpty ? "Enter a task title to create the task." : "Create this task.")
                .stableXrayId("taskCreation.createButton")
            }
            .padding()
        }
        .frame(width: 420, height: 440)
    }
}
