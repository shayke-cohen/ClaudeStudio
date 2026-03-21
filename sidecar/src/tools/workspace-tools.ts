import { tool } from "@anthropic-ai/claude-agent-sdk";
import { z } from "zod";
import type { ToolContext } from "./tool-context.js";

export function createWorkspaceTools(ctx: ToolContext, callingSessionId: string) {
  return [
    tool(
      "workspace_create",
      "Create a new shared workspace directory that multiple agents can read/write to using their standard file tools. Returns the workspace ID and filesystem path.",
      {
        name: z.string().describe("Human-readable name for the workspace (e.g. 'sorting-collab')"),
      },
      async (args) => {
        const workspace = ctx.workspaces.create(args.name, callingSessionId);
        return {
          content: [{
            type: "text" as const,
            text: JSON.stringify({
              workspace_id: workspace.id,
              path: workspace.path,
              name: workspace.name,
            }),
          }],
        };
      },
    ),

    tool(
      "workspace_join",
      "Join an existing shared workspace. Returns the filesystem path so you can read/write files there.",
      {
        workspace_id: z.string().describe("The workspace ID to join"),
      },
      async (args) => {
        const workspace = ctx.workspaces.join(args.workspace_id, callingSessionId);
        if (!workspace) {
          return {
            content: [{
              type: "text" as const,
              text: JSON.stringify({ error: "workspace_not_found", workspace_id: args.workspace_id }),
            }],
          };
        }
        return {
          content: [{
            type: "text" as const,
            text: JSON.stringify({
              workspace_id: workspace.id,
              path: workspace.path,
              name: workspace.name,
              participants: workspace.participantSessionIds.length,
            }),
          }],
        };
      },
    ),

    tool(
      "workspace_list",
      "List all available shared workspaces with their IDs, paths, and participant counts.",
      {},
      async () => {
        const workspaces = ctx.workspaces.list().map((ws) => ({
          workspace_id: ws.id,
          name: ws.name,
          path: ws.path,
          participants: ws.participantSessionIds.length,
          createdAt: ws.createdAt,
        }));
        return {
          content: [{
            type: "text" as const,
            text: JSON.stringify({ workspaces }),
          }],
        };
      },
    ),
  ];
}
