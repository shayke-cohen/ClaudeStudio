import { randomUUID } from "crypto";
import { mkdirSync, existsSync } from "fs";
import { join } from "path";
import { homedir } from "os";

export interface SharedWorkspace {
  id: string;
  name: string;
  path: string;
  participantSessionIds: string[];
  createdAt: string;
}

export class WorkspaceStore {
  private workspaces = new Map<string, SharedWorkspace>();
  private baseDir: string;

  constructor() {
    this.baseDir = join(
      process.env.CLAUDPEER_DATA_DIR ?? join(homedir(), ".claudpeer"),
      "workspaces",
    );
    if (!existsSync(this.baseDir)) mkdirSync(this.baseDir, { recursive: true });
  }

  create(name: string, creatorSessionId: string): SharedWorkspace {
    const id = randomUUID();
    const wsPath = join(this.baseDir, id);
    mkdirSync(wsPath, { recursive: true });

    const workspace: SharedWorkspace = {
      id,
      name,
      path: wsPath,
      participantSessionIds: [creatorSessionId],
      createdAt: new Date().toISOString(),
    };
    this.workspaces.set(id, workspace);
    return workspace;
  }

  get(id: string): SharedWorkspace | undefined {
    return this.workspaces.get(id);
  }

  join(workspaceId: string, sessionId: string): SharedWorkspace | undefined {
    const ws = this.workspaces.get(workspaceId);
    if (!ws) return undefined;
    if (!ws.participantSessionIds.includes(sessionId)) {
      ws.participantSessionIds.push(sessionId);
    }
    return ws;
  }

  list(): SharedWorkspace[] {
    return Array.from(this.workspaces.values());
  }
}
