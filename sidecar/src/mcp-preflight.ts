import { existsSync } from "fs";
import type { AgentConfig, MCPServerConfig } from "./types.js";

const DEFAULT_PATH = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin";
const APPXRAY_DEFAULT_PORT = 19480;

export interface MCPCommandPreflight {
  name: string;
  transport: "stdio" | "http";
  command?: string;
  args?: string[];
  url?: string;
  resolvedCommandPath?: string | null;
  commandLaunchable: boolean;
  nodeRequired?: boolean;
  nodeResolvedPath?: string | null;
  nodeLaunchable?: boolean;
}

export interface AppXrayTargetPreflight {
  checked: boolean;
  appName: string;
  port: number;
  processRunning: boolean;
  portReachable: boolean;
  discoverabilityLikely: boolean;
}

export interface MCPPreflightReport {
  provider: string;
  effectivePath: string;
  resolvedMCPNames: string[];
  toolsetVisibleToSession: string[];
  probes: MCPCommandPreflight[];
  appxrayTarget: AppXrayTargetPreflight;
}

export function normalizedMCPPath(env: Record<string, string | undefined> = process.env): string {
  const currentPath = env.PATH?.trim();
  return currentPath && currentPath.length > 0 ? currentPath : DEFAULT_PATH;
}

export function buildMCPPreflightReport(config: AgentConfig): MCPPreflightReport {
  const effectivePath = normalizedMCPPath();
  const probes = config.mcpServers.map((mcp) => preflightMCPServer(mcp, effectivePath));
  const hasAppXray = config.mcpServers.some((mcp) => mcp.name === "AppXray");

  return {
    provider: config.provider ?? "claude",
    effectivePath,
    resolvedMCPNames: config.mcpServers.map((mcp) => mcp.name),
    toolsetVisibleToSession: config.mcpServers.map((mcp) => mcp.name),
    probes,
    appxrayTarget: hasAppXray
      ? probeAppXrayTarget(APPXRAY_DEFAULT_PORT)
      : {
          checked: false,
          appName: "ClaudeStudio",
          port: APPXRAY_DEFAULT_PORT,
          processRunning: false,
          portReachable: false,
          discoverabilityLikely: false,
        },
  };
}

function preflightMCPServer(mcp: MCPServerConfig, effectivePath: string): MCPCommandPreflight {
  if (mcp.command) {
    const resolvedCommandPath = resolveExecutable(mcp.command, effectivePath);
    const nodeRequired = isNPXCommand(mcp.command);
    const nodeResolvedPath = nodeRequired ? resolveExecutable("node", effectivePath) : null;

    return {
      name: mcp.name,
      transport: "stdio",
      command: mcp.command,
      args: mcp.args ?? [],
      resolvedCommandPath,
      commandLaunchable: resolvedCommandPath !== null && (!nodeRequired || nodeResolvedPath !== null),
      nodeRequired,
      nodeResolvedPath,
      nodeLaunchable: nodeRequired ? nodeResolvedPath !== null : undefined,
    };
  }

  return {
    name: mcp.name,
    transport: "http",
    url: mcp.url,
    commandLaunchable: Boolean(mcp.url),
  };
}

function resolveExecutable(command: string, effectivePath: string): string | null {
  if (command.includes("/")) {
    return existsSync(command) ? command : null;
  }

  try {
    const result = Bun.spawnSync(
      ["/usr/bin/env", "-i", `PATH=${effectivePath}`, "which", command],
      { stdout: "pipe", stderr: "pipe" },
    );
    if (result.exitCode !== 0) {
      return null;
    }
    const resolved = result.stdout.toString().trim();
    return resolved.length > 0 ? resolved : null;
  } catch {
    return null;
  }
}

function isNPXCommand(command: string): boolean {
  return command == "npx" || command.endsWith("/npx");
}

function probeAppXrayTarget(port: number): AppXrayTargetPreflight {
  const processRunning = commandSucceeds(["/usr/bin/pgrep", "-x", "ClaudeStudio"]);
  const portReachable = commandSucceeds(["/usr/bin/nc", "-z", "127.0.0.1", String(port)]);

  return {
    checked: true,
    appName: "ClaudeStudio",
    port,
    processRunning,
    portReachable,
    discoverabilityLikely: processRunning && portReachable,
  };
}

function commandSucceeds(cmd: string[]): boolean {
  try {
    const result = Bun.spawnSync(cmd, { stdout: "pipe", stderr: "pipe" });
    return result.exitCode === 0;
  } catch {
    return false;
  }
}
