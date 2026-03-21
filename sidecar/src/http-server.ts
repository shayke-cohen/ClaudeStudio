import { BlackboardStore } from "./stores/blackboard-store.js";
import { SessionManager } from "./session-manager.js";

export class HttpServer {
  private server: ReturnType<typeof Bun.serve> | null = null;
  private blackboard: BlackboardStore;

  constructor(private port: number, blackboard: BlackboardStore) {
    this.blackboard = blackboard;
  }

  start(): void {
    this.server = Bun.serve({
      port: this.port,
      hostname: "127.0.0.1",
      fetch: (req) => this.handleRequest(req),
    });
    console.log(`[http] HTTP API listening on http://127.0.0.1:${this.port}`);
  }

  private async handleRequest(req: Request): Promise<Response> {
    const url = new URL(req.url);
    const path = url.pathname;

    // CORS headers for local development
    const headers = {
      "Content-Type": "application/json",
      "Access-Control-Allow-Origin": "*",
    };

    if (req.method === "OPTIONS") {
      return new Response(null, {
        headers: {
          ...headers,
          "Access-Control-Allow-Methods": "GET, POST, OPTIONS",
          "Access-Control-Allow-Headers": "Content-Type",
        },
      });
    }

    try {
      if (path === "/blackboard/health" || path === "/health") {
        return Response.json({ status: "ok", version: "0.1.0" }, { headers });
      }

      if (path === "/blackboard/read" && req.method === "GET") {
        const key = url.searchParams.get("key");
        if (!key) return Response.json({ error: "key required" }, { status: 400, headers });
        const entry = this.blackboard.read(key);
        if (!entry) return Response.json({ error: "not found" }, { status: 404, headers });
        return Response.json(entry, { headers });
      }

      if (path === "/blackboard/query" && req.method === "GET") {
        const pattern = url.searchParams.get("pattern") ?? "*";
        const entries = this.blackboard.query(pattern);
        return Response.json(entries, { headers });
      }

      if (path === "/blackboard/keys" && req.method === "GET") {
        const scope = url.searchParams.get("scope") ?? undefined;
        const keys = this.blackboard.keys(scope);
        return Response.json({ keys }, { headers });
      }

      if (path === "/blackboard/write" && req.method === "POST") {
        const body = (await req.json()) as {
          key?: string;
          value?: string;
          writtenBy?: string;
          scope?: string;
        };
        if (!body.key || body.value === undefined) {
          return Response.json({ error: "key and value required" }, { status: 400, headers });
        }
        const entry = this.blackboard.write(
          body.key,
          typeof body.value === "string" ? body.value : JSON.stringify(body.value),
          body.writtenBy ?? "external",
          body.scope
        );
        return Response.json(entry, { status: 201, headers });
      }

      return Response.json({ error: "not found" }, { status: 404, headers });
    } catch (err) {
      return Response.json(
        { error: err instanceof Error ? err.message : "internal error" },
        { status: 500, headers }
      );
    }
  }

  close(): void {
    this.server?.stop();
  }
}
