import type {
  AgentConfig,
  MCPServerConfig,
  SessionMCPAvailability,
  SessionMCPServerState,
  SessionMCPToolInfo,
} from "./types.js";

type RawMcpStatusLike = {
  name?: string;
  status?: string;
  error?: string;
  tools?: Array<{ name?: string; description?: string }>;
};

export function normalizeMcpNamespace(name: string): string {
  const normalized = name
    .trim()
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, "_")
    .replace(/^_+|_+$/g, "");

  return normalized || "mcp";
}

export function parseQualifiedMcpToolName(toolName: string): { namespace: string; tool: string } | null {
  if (!toolName.startsWith("mcp__")) {
    return null;
  }

  const parts = toolName.split("__");
  if (parts.length < 3) {
    return null;
  }

  return {
    namespace: parts[1],
    tool: parts.slice(2).join("__"),
  };
}

export function buildConfiguredMcpInventory(config: AgentConfig): SessionMCPServerState[] {
  return config.mcpServers.map((mcp) => configuredMcpEntry(mcp));
}

export function mergeClaudeMcpInventory(
  config: AgentConfig,
  current: SessionMCPServerState[],
  statuses: RawMcpStatusLike[],
): SessionMCPServerState[] {
  const merged = mergeByNamespace(
    current.length > 0 ? current : buildConfiguredMcpInventory(config),
    config,
  );

  for (const status of statuses) {
    const name = status.name?.trim();
    if (!name) {
      continue;
    }

    const namespace = normalizeMcpNamespace(name);
    const existing = merged.get(namespace);
    merged.set(namespace, {
      name: existing?.name ?? name,
      namespace,
      source: existing?.configured ? "configured" : "sdk",
      transport: existing?.transport ?? "sdk",
      configured: existing?.configured ?? false,
      availability: normalizeAvailability(status.status, existing?.availability ?? "configured"),
      providerStatus: status.status,
      error: status.error ?? existing?.error,
      tools: mergeTools(existing?.tools, normalizeTools(status.tools)),
    });
  }

  return sortInventory(Array.from(merged.values()));
}

export function mergeCodexMcpInventory(
  config: AgentConfig,
  current: SessionMCPServerState[],
  statuses: RawMcpStatusLike[],
  mapStatusName: (name: string) => string,
): SessionMCPServerState[] {
  const merged = mergeByNamespace(
    current.length > 0 ? current : buildConfiguredMcpInventory(config),
    config,
  );

  for (const status of statuses) {
    const rawName = status.name?.trim();
    if (!rawName) {
      continue;
    }

    const name = mapStatusName(rawName);
    const namespace = normalizeMcpNamespace(name);
    const existing = merged.get(namespace);
    merged.set(namespace, {
      name: existing?.name ?? name,
      namespace,
      source: existing?.configured ? "configured" : "sdk",
      transport: existing?.transport ?? "stdio",
      configured: existing?.configured ?? false,
      availability: normalizeAvailability(status.status, existing?.availability ?? "configured"),
      providerStatus: status.status,
      error: status.error ?? existing?.error,
      tools: mergeTools(existing?.tools, normalizeTools(status.tools)),
    });
  }

  return sortInventory(Array.from(merged.values()));
}

export function observeMcpToolUse(
  inventory: SessionMCPServerState[],
  namespace: string,
  toolName: string,
): SessionMCPServerState[] {
  const byNamespace = new Map(inventory.map((entry) => [entry.namespace, entry] as const));
  const existing = byNamespace.get(namespace);

  if (!existing) {
    byNamespace.set(namespace, {
      name: namespace,
      namespace,
      source: "sdk",
      transport: "sdk",
      configured: false,
      availability: "loaded",
      tools: [{ name: toolName }],
    });
    return sortInventory(Array.from(byNamespace.values()));
  }

  byNamespace.set(namespace, {
    ...existing,
    availability: existing.availability === "configured" ? "loaded" : existing.availability,
    tools: mergeTools(existing.tools, [{ name: toolName }]),
  });

  return sortInventory(Array.from(byNamespace.values()));
}

function configuredMcpEntry(mcp: MCPServerConfig): SessionMCPServerState {
  return {
    name: mcp.name,
    namespace: normalizeMcpNamespace(mcp.name),
    source: "configured",
    transport: mcp.command ? "stdio" : "sse",
    configured: true,
    availability: "configured",
  };
}

function mergeByNamespace(
  current: SessionMCPServerState[],
  config: AgentConfig,
): Map<string, SessionMCPServerState> {
  const merged = new Map<string, SessionMCPServerState>();

  for (const entry of current) {
    merged.set(entry.namespace, { ...entry, tools: cloneTools(entry.tools) });
  }

  for (const mcp of config.mcpServers) {
    const namespace = normalizeMcpNamespace(mcp.name);
    const existing = merged.get(namespace);
    merged.set(namespace, {
      ...(existing ?? configuredMcpEntry(mcp)),
      name: existing?.name ?? mcp.name,
      namespace,
      source: "configured",
      transport: existing?.transport ?? (mcp.command ? "stdio" : "sse"),
      configured: true,
    });
  }

  return merged;
}

function normalizeAvailability(
  rawStatus: string | undefined,
  fallback: SessionMCPAvailability,
): SessionMCPAvailability {
  if (!rawStatus) {
    return fallback;
  }

  const status = rawStatus.trim().toLowerCase();
  if (status === "connected" || status === "ready" || status === "available") {
    return "loaded";
  }
  if (status === "needs-auth" || status === "needs_auth" || status === "auth_required") {
    return "needs-auth";
  }
  if (status === "pending" || status === "connecting" || status === "initializing") {
    return "pending";
  }
  if (status === "disabled") {
    return "disabled";
  }
  if (status === "failed" || status === "error" || status === "unavailable") {
    return status === "unavailable" ? "unavailable" : "failed";
  }
  return fallback;
}

function normalizeTools(
  tools: Array<{ name?: string; description?: string }> | undefined,
): SessionMCPToolInfo[] {
  if (!tools || tools.length === 0) {
    return [];
  }

  return tools
    .filter((tool) => typeof tool.name === "string" && tool.name.trim().length > 0)
    .map((tool) => ({
      name: tool.name!.trim(),
      ...(tool.description?.trim() ? { description: tool.description.trim() } : {}),
    }));
}

function cloneTools(tools: SessionMCPToolInfo[] | undefined): SessionMCPToolInfo[] | undefined {
  return tools?.map((tool) => ({ ...tool }));
}

function mergeTools(
  existing: SessionMCPToolInfo[] | undefined,
  incoming: SessionMCPToolInfo[],
): SessionMCPToolInfo[] | undefined {
  if ((!existing || existing.length === 0) && incoming.length === 0) {
    return existing;
  }

  const merged = new Map<string, SessionMCPToolInfo>();
  for (const tool of existing ?? []) {
    merged.set(tool.name, { ...tool });
  }
  for (const tool of incoming) {
    const prior = merged.get(tool.name);
    merged.set(tool.name, {
      name: tool.name,
      description: tool.description ?? prior?.description,
    });
  }

  return Array.from(merged.values()).sort((left, right) => left.name.localeCompare(right.name));
}

function sortInventory(entries: SessionMCPServerState[]): SessionMCPServerState[] {
  return entries.sort((left, right) => left.name.localeCompare(right.name));
}
