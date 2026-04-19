import { readFileSync, writeFileSync, mkdirSync, existsSync } from "fs";
import { join } from "path";
import { homedir } from "os";
import type { TaskWire } from "../types.js";

type ChangeListener = (task: TaskWire) => void;

export class TaskBoardStore {
  private tasks = new Map<string, TaskWire>();
  private listeners: ChangeListener[] = [];
  private persistPath: string;

  constructor(scope?: string) {
    const baseDir = process.env.ODYSSEY_DATA_DIR ?? process.env.CLAUDESTUDIO_DATA_DIR ?? join(homedir(), ".odyssey");
    const dir = join(baseDir, "taskboard");
    if (!existsSync(dir)) mkdirSync(dir, { recursive: true });
    this.persistPath = join(dir, `${scope ?? "global"}.json`);
    this.loadFromDisk();
  }

  create(task: Partial<TaskWire> & { title: string }): TaskWire {
    const now = new Date().toISOString();
    const entry: TaskWire = {
      id: task.id ?? crypto.randomUUID(),
      projectId: task.projectId,
      title: task.title,
      description: task.description ?? "",
      status: task.status ?? "backlog",
      priority: task.priority ?? "medium",
      labels: task.labels ?? [],
      result: task.result,
      parentTaskId: task.parentTaskId,
      assignedAgentId: task.assignedAgentId,
      assignedAgentName: task.assignedAgentName,
      assignedGroupId: task.assignedGroupId,
      conversationId: task.conversationId,
      createdAt: task.createdAt ?? now,
      startedAt: task.startedAt,
      completedAt: task.completedAt,
    };
    this.tasks.set(entry.id, entry);
    this.persistToDisk();
    this.notifyListeners(entry);
    return entry;
  }

  get(taskId: string): TaskWire | undefined {
    return this.tasks.get(taskId);
  }

  update(taskId: string, updates: Partial<TaskWire>): TaskWire | undefined {
    const existing = this.tasks.get(taskId);
    if (!existing) return undefined;

    const updated: TaskWire = { ...existing, ...updates, id: existing.id };

    // Auto-set timestamps on status transitions
    if (updates.status === "inProgress" && !updated.startedAt) {
      updated.startedAt = new Date().toISOString();
    }
    if ((updates.status === "done" || updates.status === "failed") && !updated.completedAt) {
      updated.completedAt = new Date().toISOString();
    }
    // Clear completedAt if moving back to active status
    if (updates.status === "ready" || updates.status === "backlog") {
      updated.completedAt = undefined;
      updated.startedAt = undefined;
      updated.assignedAgentId = undefined;
      updated.assignedAgentName = undefined;
      updated.assignedGroupId = undefined;
    }

    this.tasks.set(taskId, updated);
    this.persistToDisk();
    this.notifyListeners(updated);
    return updated;
  }

  claim(taskId: string, agentName: string): TaskWire | undefined {
    const existing = this.tasks.get(taskId);
    if (!existing) return undefined;
    if (existing.status !== "ready") return undefined; // already claimed or not ready

    const now = new Date().toISOString();
    const claimed: TaskWire = {
      ...existing,
      status: "inProgress",
      assignedAgentId: undefined,
      assignedAgentName: agentName,
      startedAt: now,
    };
    this.tasks.set(taskId, claimed);
    this.persistToDisk();
    this.notifyListeners(claimed);
    return claimed;
  }

  list(filter?: { status?: string; assignedTo?: string }): TaskWire[] {
    const results: TaskWire[] = [];
    for (const task of this.tasks.values()) {
      if (filter?.status && task.status !== filter.status) continue;
      if (filter?.assignedTo && task.assignedAgentName !== filter.assignedTo && task.assignedAgentId !== filter.assignedTo) continue;
      results.push(task);
    }
    return results;
  }

  getSubtasks(parentTaskId: string): TaskWire[] {
    const results: TaskWire[] = [];
    for (const task of this.tasks.values()) {
      if (task.parentTaskId === parentTaskId) results.push(task);
    }
    return results;
  }

  subscribe(callback: ChangeListener): () => void {
    this.listeners.push(callback);
    return () => {
      this.listeners = this.listeners.filter((l) => l !== callback);
    };
  }

  private notifyListeners(task: TaskWire): void {
    for (const listener of this.listeners) {
      listener(task);
    }
  }

  private loadFromDisk(): void {
    try {
      if (existsSync(this.persistPath)) {
        const data = JSON.parse(readFileSync(this.persistPath, "utf-8")) as Record<string, TaskWire>;
        for (const [key, task] of Object.entries(data)) {
          this.tasks.set(key, task);
        }
      }
    } catch {
      // Start fresh if file is corrupted
    }
  }

  private persistToDisk(): void {
    try {
      const obj: Record<string, TaskWire> = {};
      for (const [key, task] of this.tasks) {
        obj[key] = task;
      }
      writeFileSync(this.persistPath, JSON.stringify(obj, null, 2));
    } catch {
      // Non-fatal
    }
  }
}
