import { createSdkMcpServer, tool } from "@anthropic-ai/claude-agent-sdk";
import { z } from "zod";
import { execFileSync } from "child_process";
import { existsSync, mkdirSync, readdirSync, readFileSync, unlinkSync, writeFileSync } from "fs";
import { homedir } from "os";
import { join } from "path";
import { logger } from "../logger.js";
import { defineSharedTool, createTextResult, toClaudeTool } from "./shared-tool.js";

function toAlwaysLoadTool(def: ReturnType<typeof defineSharedTool>) {
  return tool(def.name, def.description, def.inputSchema, async (args: any, extra: any) => def.execute(args, extra), { alwaysLoad: true });
}

const HOME = homedir();
const DATA_DIR = process.env.ODYSSEY_DATA_DIR ?? process.env.CLAUDESTUDIO_DATA_DIR ?? join(HOME, ".odyssey");
const CONFIG_DIR = join(DATA_DIR, "config");
const HTTP_PORT = parseInt(process.env.ODYSSEY_HTTP_PORT ?? process.env.CLAUDESTUDIO_HTTP_PORT ?? "9850", 10);
const BASE_URL = `http://127.0.0.1:${HTTP_PORT}`;

// ─── Git helpers ─────────────────────────────────────────────────────────────

function git(...args: string[]) {
  try {
    execFileSync("git", ["-C", CONFIG_DIR, ...args], { stdio: "pipe" });
  } catch {
    // best-effort — never blocks a write
  }
}

function gitCommit(message: string) {
  git("add", "-A");
  git("commit", "-m", message);
}

function slugify(name: string) {
  return name.toLowerCase().replace(/\s+/g, "-");
}

// ─── Config tools ─────────────────────────────────────────────────────────────

const listAgentsTool = defineSharedTool(
  "list_agents",
  "List all agents in the Odyssey config directory.",
  { enabled: z.boolean().optional().describe("Filter to enabled-only when true") },
  async ({ enabled }) => {
    const dir = join(CONFIG_DIR, "agents");
    if (!existsSync(dir)) return createTextResult({ agents: [] });
    const agents = readdirSync(dir)
      .filter((f) => f.endsWith(".json"))
      .flatMap((f) => {
        try {
          const d = JSON.parse(readFileSync(join(dir, f), "utf8"));
          if (enabled !== undefined && !!d.enabled !== enabled) return [];
          return [{ name: d.name ?? f.replace(".json", ""), description: d.agentDescription ?? "", enabled: d.enabled ?? true, model: d.model ?? "sonnet" }];
        } catch {
          return [];
        }
      });
    return createTextResult({ agents });
  },
);

const getAgentTool = defineSharedTool(
  "get_agent",
  "Get the full config for a named agent.",
  { name: z.string().describe("Agent name or slug") },
  async ({ name }) => {
    const dir = join(CONFIG_DIR, "agents");
    const slug = slugify(name);
    for (const candidate of [join(dir, `${slug}.json`), join(dir, `${name}.json`)]) {
      if (existsSync(candidate)) return createTextResult(JSON.parse(readFileSync(candidate, "utf8")));
    }
    if (existsSync(dir)) {
      for (const f of readdirSync(dir).filter((f) => f.endsWith(".json"))) {
        try {
          const d = JSON.parse(readFileSync(join(dir, f), "utf8"));
          if ((d.name ?? "").toLowerCase() === name.toLowerCase()) return createTextResult(d);
        } catch {}
      }
    }
    return createTextResult({ error: `Agent "${name}" not found` }, false);
  },
);

const createOrUpdateAgentTool = defineSharedTool(
  "create_or_update_agent",
  "Create or update an agent config. Merges fields into the existing config (or creates fresh). Commits to git — the app auto-reloads.",
  {
    name: z.string().describe("Agent display name"),
    fields: z.record(z.string(), z.unknown()).describe("Fields to set, e.g. { model, agentDescription, icon, color, skillNames, mcpServerNames }"),
  },
  async ({ name, fields }) => {
    const dir = join(CONFIG_DIR, "agents");
    mkdirSync(dir, { recursive: true });
    const slug = slugify(name);
    const filePath = join(dir, `${slug}.json`);
    const existing = existsSync(filePath) ? JSON.parse(readFileSync(filePath, "utf8")) : { name, enabled: true, model: "sonnet" };
    const updated = { ...existing, name, ...fields };
    writeFileSync(filePath, JSON.stringify(updated, null, 2));
    gitCommit(`agent: update ${slug}`);
    logger.info("odyssey-control", `create_or_update_agent: ${slug}`);
    return createTextResult({ ok: true, slug, path: filePath });
  },
);

const deleteAgentTool = defineSharedTool(
  "delete_agent",
  "Delete an agent config file. Commits to git.",
  { name: z.string() },
  async ({ name }) => {
    const slug = slugify(name);
    const filePath = join(CONFIG_DIR, "agents", `${slug}.json`);
    if (!existsSync(filePath)) return createTextResult({ error: `Agent "${name}" not found` }, false);
    unlinkSync(filePath);
    gitCommit(`agent: delete ${slug}`);
    return createTextResult({ ok: true });
  },
);

const listGroupsTool = defineSharedTool(
  "list_groups",
  "List all agent groups in the Odyssey config.",
  { enabled: z.boolean().optional() },
  async ({ enabled }) => {
    const dir = join(CONFIG_DIR, "groups");
    if (!existsSync(dir)) return createTextResult({ groups: [] });
    const groups = readdirSync(dir)
      .filter((f) => f.endsWith(".json"))
      .flatMap((f) => {
        try {
          const d = JSON.parse(readFileSync(join(dir, f), "utf8"));
          if (enabled !== undefined && !!d.enabled !== enabled) return [];
          return [{ name: d.name ?? f.replace(".json", ""), description: d.groupDescription ?? "", enabled: d.enabled ?? true }];
        } catch {
          return [];
        }
      });
    return createTextResult({ groups });
  },
);

const getGroupTool = defineSharedTool(
  "get_group",
  "Get the full config for a named group.",
  { name: z.string() },
  async ({ name }) => {
    const dir = join(CONFIG_DIR, "groups");
    const slug = slugify(name);
    for (const candidate of [join(dir, `${slug}.json`), join(dir, `${name}.json`)]) {
      if (existsSync(candidate)) return createTextResult(JSON.parse(readFileSync(candidate, "utf8")));
    }
    if (existsSync(dir)) {
      for (const f of readdirSync(dir).filter((f) => f.endsWith(".json"))) {
        try {
          const d = JSON.parse(readFileSync(join(dir, f), "utf8"));
          if ((d.name ?? "").toLowerCase() === name.toLowerCase()) return createTextResult(d);
        } catch {}
      }
    }
    return createTextResult({ error: `Group "${name}" not found` }, false);
  },
);

const createOrUpdateGroupTool = defineSharedTool(
  "create_or_update_group",
  "Create or update a group config. Merges fields into existing config. Commits to git — app auto-reloads.",
  {
    name: z.string(),
    fields: z.record(z.string(), z.unknown()).describe("Fields to set, e.g. { groupDescription, agentNames, coordinatorName, icon }"),
  },
  async ({ name, fields }) => {
    const dir = join(CONFIG_DIR, "groups");
    mkdirSync(dir, { recursive: true });
    const slug = slugify(name);
    const filePath = join(dir, `${slug}.json`);
    const existing = existsSync(filePath) ? JSON.parse(readFileSync(filePath, "utf8")) : { name, enabled: true };
    const updated = { ...existing, name, ...fields };
    writeFileSync(filePath, JSON.stringify(updated, null, 2));
    gitCommit(`group: update ${slug}`);
    return createTextResult({ ok: true, slug, path: filePath });
  },
);

const deleteGroupTool = defineSharedTool(
  "delete_group",
  "Delete a group config file. Commits to git.",
  { name: z.string() },
  async ({ name }) => {
    const slug = slugify(name);
    const filePath = join(CONFIG_DIR, "groups", `${slug}.json`);
    if (!existsSync(filePath)) return createTextResult({ error: `Group "${name}" not found` }, false);
    unlinkSync(filePath);
    gitCommit(`group: delete ${slug}`);
    return createTextResult({ ok: true });
  },
);

const listSkillsTool = defineSharedTool(
  "list_skills",
  "List all skills in the Odyssey config.",
  {},
  async () => {
    const dir = join(CONFIG_DIR, "skills");
    if (!existsSync(dir)) return createTextResult({ skills: [] });
    const skills = readdirSync(dir)
      .filter((name) => existsSync(join(dir, name, "SKILL.md")))
      .map((name) => ({ name }));
    return createTextResult({ skills });
  },
);

const getSkillTool = defineSharedTool(
  "get_skill",
  "Get the SKILL.md content for a named skill.",
  { name: z.string() },
  async ({ name }) => {
    const filePath = join(CONFIG_DIR, "skills", name, "SKILL.md");
    if (!existsSync(filePath)) return createTextResult({ error: `Skill "${name}" not found` }, false);
    return createTextResult(readFileSync(filePath, "utf8"));
  },
);

const updateSkillTool = defineSharedTool(
  "update_skill",
  "Write new SKILL.md content for a skill. Creates directory if needed. Commits to git.",
  {
    name: z.string(),
    content: z.string().describe("Full SKILL.md content including frontmatter"),
  },
  async ({ name, content }) => {
    const dir = join(CONFIG_DIR, "skills", name);
    mkdirSync(dir, { recursive: true });
    const filePath = join(dir, "SKILL.md");
    writeFileSync(filePath, content);
    gitCommit(`skill: update ${name}`);
    return createTextResult({ ok: true, path: filePath });
  },
);

// ─── Navigation tools ──────────────────────────────────────────────────────────

const openChatTool = defineSharedTool(
  "open_chat",
  "Open a new interactive chat session with an agent in the Odyssey app.",
  {
    agent_name: z.string().describe("Agent display name"),
    prompt: z.string().optional().describe("Initial message to auto-send when the chat opens"),
    autonomous: z.boolean().optional().describe("Run headlessly without user interaction"),
  },
  async ({ agent_name, prompt, autonomous }) => {
    try {
      const res = await fetch(`${BASE_URL}/api/v1/launch`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ type: "agent", name: agent_name, prompt, autonomous }),
      });
      const data = await res.json();
      logger.info("odyssey-control", `open_chat: ${agent_name}`);
      return createTextResult(data);
    } catch (e) {
      return createTextResult({ error: String(e) }, false);
    }
  },
);

const openGroupChatTool = defineSharedTool(
  "open_group_chat",
  "Open a new interactive chat session with an agent group in the Odyssey app.",
  {
    group_name: z.string().describe("Group display name"),
    prompt: z.string().optional(),
    autonomous: z.boolean().optional(),
  },
  async ({ group_name, prompt, autonomous }) => {
    try {
      const res = await fetch(`${BASE_URL}/api/v1/launch`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ type: "group", name: group_name, prompt, autonomous }),
      });
      const data = await res.json();
      logger.info("odyssey-control", `open_group_chat: ${group_name}`);
      return createTextResult(data);
    } catch (e) {
      return createTextResult({ error: String(e) }, false);
    }
  },
);

// ─── Project tools ─────────────────────────────────────────────────────────────

const listProjectsTool = defineSharedTool(
  "list_projects",
  "List recently opened projects in Odyssey.",
  {},
  async () => {
    const filePath = join(DATA_DIR, "recent-directories.json");
    if (!existsSync(filePath)) return createTextResult({ projects: [] });
    try {
      const paths = JSON.parse(readFileSync(filePath, "utf8")) as string[];
      const projects = paths.map((p) => ({ path: p, name: p.split("/").pop() ?? p }));
      return createTextResult({ projects });
    } catch {
      return createTextResult({ projects: [] });
    }
  },
);

const openProjectTool = defineSharedTool(
  "open_project",
  "Open a project in the Odyssey app by name or path.",
  { name: z.string().describe("Project name or full path") },
  async ({ name }) => {
    try {
      const res = await fetch(`${BASE_URL}/api/v1/launch`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ type: "project", name }),
      });
      const data = await res.json();
      return createTextResult(data);
    } catch (e) {
      return createTextResult({ error: String(e) }, false);
    }
  },
);

// ─── System tools ──────────────────────────────────────────────────────────────

const getWhatsNewTool = defineSharedTool(
  "get_whats_new",
  "Read the Odyssey release notes / what's new changelog.",
  {},
  async () => {
    const filePath = join(DATA_DIR, "whats-new.json");
    if (!existsSync(filePath)) return createTextResult({ entries: [] });
    try {
      return createTextResult(JSON.parse(readFileSync(filePath, "utf8")));
    } catch {
      return createTextResult({ entries: [] });
    }
  },
);

const getAppStatusTool = defineSharedTool(
  "get_app_status",
  "Get Odyssey sidecar status — active sessions, health, version.",
  {},
  async () => {
    try {
      const res = await fetch(`${BASE_URL}/api/v1/debug/state`);
      return createTextResult(await res.json());
    } catch (e) {
      return createTextResult({ error: String(e) }, false);
    }
  },
);

// ─── Server factory ────────────────────────────────────────────────────────────

export const odysseyControlToolDefinitions = [
  listAgentsTool, getAgentTool, createOrUpdateAgentTool, deleteAgentTool,
  listGroupsTool, getGroupTool, createOrUpdateGroupTool, deleteGroupTool,
  listSkillsTool, getSkillTool, updateSkillTool,
  openChatTool, openGroupChatTool,
  listProjectsTool, openProjectTool,
  getWhatsNewTool, getAppStatusTool,
];

export function createOdysseyControlServer() {
  const tools = odysseyControlToolDefinitions.map(toAlwaysLoadTool);
  const names = tools.map((t: any) => t.name).join(", ");
  logger.info("odyssey-control", `Creating server with ${tools.length} tools: [${names}]`);
  return createSdkMcpServer({ name: "odyssey_control", tools });
}
