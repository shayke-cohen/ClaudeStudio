import { readFileSync, writeFileSync, mkdirSync, existsSync } from "fs";
import { join } from "path";
import { homedir } from "os";
import type { BlackboardEntry } from "../types.js";

type ChangeListener = (entry: BlackboardEntry) => void;

export class BlackboardStore {
  private entries = new Map<string, BlackboardEntry>();
  private listeners: { pattern: string; callback: ChangeListener }[] = [];
  private persistPath: string;

  constructor(scope?: string) {
    const dir = join(homedir(), ".claudpeer", "blackboard");
    if (!existsSync(dir)) mkdirSync(dir, { recursive: true });
    this.persistPath = join(dir, `${scope ?? "global"}.json`);
    this.loadFromDisk();
  }

  write(key: string, value: string, writtenBy: string, workspaceId?: string): BlackboardEntry {
    const now = new Date().toISOString();
    const existing = this.entries.get(key);
    const entry: BlackboardEntry = {
      key,
      value,
      writtenBy,
      workspaceId,
      createdAt: existing?.createdAt ?? now,
      updatedAt: now,
    };
    this.entries.set(key, entry);
    this.persistToDisk();
    this.notifyListeners(entry);
    return entry;
  }

  read(key: string): BlackboardEntry | undefined {
    return this.entries.get(key);
  }

  query(pattern: string): BlackboardEntry[] {
    const regex = new RegExp("^" + pattern.replace(/\./g, "\\.").replace(/\*/g, ".*") + "$");
    const results: BlackboardEntry[] = [];
    for (const [key, entry] of this.entries) {
      if (regex.test(key)) results.push(entry);
    }
    return results;
  }

  keys(scope?: string): string[] {
    const allKeys = Array.from(this.entries.keys());
    if (!scope) return allKeys;
    return allKeys.filter((k) => {
      const entry = this.entries.get(k);
      return entry?.workspaceId === scope;
    });
  }

  subscribe(pattern: string, callback: ChangeListener): () => void {
    const listener = { pattern, callback };
    this.listeners.push(listener);
    return () => {
      this.listeners = this.listeners.filter((l) => l !== listener);
    };
  }

  private notifyListeners(entry: BlackboardEntry): void {
    for (const listener of this.listeners) {
      const regex = new RegExp(
        "^" + listener.pattern.replace(/\./g, "\\.").replace(/\*/g, ".*") + "$"
      );
      if (regex.test(entry.key)) {
        listener.callback(entry);
      }
    }
  }

  private loadFromDisk(): void {
    try {
      if (existsSync(this.persistPath)) {
        const data = JSON.parse(readFileSync(this.persistPath, "utf-8")) as Record<string, BlackboardEntry>;
        for (const [key, entry] of Object.entries(data)) {
          this.entries.set(key, entry);
        }
      }
    } catch {
      // Start fresh if file is corrupted
    }
  }

  private persistToDisk(): void {
    try {
      const obj: Record<string, BlackboardEntry> = {};
      for (const [key, entry] of this.entries) {
        obj[key] = entry;
      }
      writeFileSync(this.persistPath, JSON.stringify(obj, null, 2));
    } catch {
      // Non-fatal
    }
  }
}
