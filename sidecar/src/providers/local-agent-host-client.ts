import { spawn, type ChildProcessWithoutNullStreams } from "child_process";
import { join } from "path";
import { logger } from "../logger.js";

type JsonRpcResponse = {
  id: number | string | null;
  method?: string;
  params?: any;
  result?: any;
  error?: {
    code?: number;
    message?: string;
    data?: unknown;
  };
};

export interface LocalAgentHostClientOptions {
  hostBinaryPath?: string;
  packagePath?: string;
}

type RequestHandler = (params: any) => Promise<any>;

export class LocalAgentHostClient {
  private process: ChildProcessWithoutNullStreams | null = null;
  private startPromise: Promise<void> | null = null;
  private nextId = 1;
  private pending = new Map<number | string, {
    resolve: (value: any) => void;
    reject: (error: Error) => void;
  }>();
  private stdoutBuffer = "";
  private stderrBuffer = "";
  private readonly hostBinaryPath?: string;
  private readonly packagePath: string;
  private readonly handlers = new Map<string, RequestHandler>();

  constructor(options: LocalAgentHostClientOptions = {}) {
    this.hostBinaryPath =
      options.hostBinaryPath
      || process.env.ODYSSEY_LOCAL_AGENT_HOST_BINARY
      || process.env.CLAUDESTUDIO_LOCAL_AGENT_HOST_BINARY;
    this.packagePath = options.packagePath || join(import.meta.dir, "../../../Packages/OdysseyLocalAgent");
  }

  async start(): Promise<void> {
    if (this.startPromise) {
      return this.startPromise;
    }

    this.startPromise = this.startInternal();
    try {
      await this.startPromise;
    } catch (error) {
      this.startPromise = null;
      throw error;
    }
  }

  async call(method: string, params?: any): Promise<any> {
    await this.start();
    return this.sendRequestInternal(method, params);
  }

  registerHandler(method: string, handler: RequestHandler) {
    this.handlers.set(method, handler);
  }

  async stop(): Promise<void> {
    if (!this.process) {
      return;
    }
    this.process.kill();
    this.process = null;
    this.startPromise = null;
  }

  private async startInternal(): Promise<void> {
    const launchTarget = this.resolveLaunchTarget();
    const command = launchTarget.command;
    const args = launchTarget.args;

    logger.info("local-agent", `Starting local agent host with ${command}`, {
      packagePath: this.packagePath,
      hostBinaryPath: this.hostBinaryPath ?? null,
    });

    const child = spawn(command, args, {
      stdio: ["pipe", "pipe", "pipe"],
      env: {
        ...process.env,
        PATH: process.env.PATH?.trim() || "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin",
      },
    });

    this.process = child;
    child.stdout.setEncoding("utf8");
    child.stdout.on("data", (chunk: string) => {
      this.stdoutBuffer += chunk;
      this.flushStdout();
    });

    child.stderr.setEncoding("utf8");
    child.stderr.on("data", (chunk: string) => {
      this.stderrBuffer += chunk;
      const lines = this.stderrBuffer.split("\n");
      this.stderrBuffer = lines.pop() ?? "";
      for (const line of lines) {
        if (line.trim().length > 0) {
          logger.warn("local-agent", line.trim());
        }
      }
    });

    child.on("exit", (code, signal) => {
      const error = new Error(`local agent host exited (code=${code ?? "null"}, signal=${signal ?? "null"})`);
      for (const pending of this.pending.values()) {
        pending.reject(error);
      }
      this.pending.clear();
      this.process = null;
      this.startPromise = null;
    });

    await this.sendRequestInternal("initialize", {
      clientInfo: {
        name: "odyssey-sidecar",
        version: "0.1.0",
      },
    });
  }

  private resolveLaunchTarget(): { command: string; args: string[] } {
    if (!this.hostBinaryPath) {
      return {
        command: "/usr/bin/xcrun",
        args: ["swift", "run", "--package-path", this.packagePath, "OdysseyLocalAgentHost"],
      };
    }

    if (/\.(cjs|mjs|js)$/i.test(this.hostBinaryPath)) {
      return {
        command: process.execPath,
        args: [this.hostBinaryPath],
      };
    }

    return {
      command: this.hostBinaryPath,
      args: [],
    };
  }

  private sendRequest(method: string, params?: any): Promise<any> {
    return this.call(method, params);
  }

  private sendRequestInternal(method: string, params?: any): Promise<any> {
    const id = this.nextId++;
    return new Promise((resolve, reject) => {
      this.pending.set(id, { resolve, reject });
      this.write({
        id,
        method,
        ...(params !== undefined ? { params } : {}),
      });
    });
  }

  private flushStdout() {
    const lines = this.stdoutBuffer.split("\n");
    this.stdoutBuffer = lines.pop() ?? "";

    for (const rawLine of lines) {
      const line = rawLine.trim();
      if (!line) {
        continue;
      }

      try {
        this.handleIncoming(JSON.parse(line) as JsonRpcResponse);
      } catch (error: any) {
        logger.error("local-agent", `Failed to parse host message: ${error?.message ?? error}`, { line });
      }
    }
  }

  private handleIncoming(payload: JsonRpcResponse) {
    if (payload.method) {
      void this.handleRequest(payload);
      return;
    }

    const pending = this.pending.get(payload.id ?? "");
    if (!pending) {
      return;
    }

    this.pending.delete(payload.id ?? "");
    if (payload.error) {
      pending.reject(new Error(payload.error.message ?? "Unknown local agent host error"));
      return;
    }

    pending.resolve(payload.result);
  }

  private async handleRequest(payload: JsonRpcResponse) {
    const isNotification = payload.id == null;
    const handler = this.handlers.get(payload.method ?? "");
    if (!handler) {
      if (!isNotification) {
        this.write({
          id: payload.id,
          error: {
            code: -32601,
            message: `Unknown host callback method: ${payload.method ?? "unknown"}`,
          },
        });
      }
      return;
    }

    try {
      const result = await handler(payload.params ?? {});
      if (!isNotification) {
        this.write({ id: payload.id, result });
      }
    } catch (error: any) {
      if (!isNotification) {
        this.write({
          id: payload.id,
          error: {
            code: -32000,
            message: error?.message ?? "Local agent callback failed",
          },
        });
      }
    }
  }

  private write(payload: unknown) {
    if (!this.process?.stdin.writable) {
      throw new Error("local agent host stdin is not writable");
    }

    this.process.stdin.write(`${JSON.stringify(payload)}\n`);
  }
}
