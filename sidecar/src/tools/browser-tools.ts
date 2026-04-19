import { z } from "zod";
import type { ToolContext } from "./tool-context.js";
import { logger } from "../logger.js";
import { createTextResult, defineSharedTool } from "./shared-tool.js";
import type { SidecarEvent } from "../types.js";

/**
 * Create all browser control tools.
 *
 * Session ID is obtained from the MCP tool call extra (extra?.sessionId) since
 * the browser server is not scoped to a single session at construction time.
 */
export function createBrowserTools(ctx: ToolContext) {
  return [
    // ─── browser_navigate ────────────────────────────────────────────────────
    defineSharedTool(
      "browser_navigate",
      "Navigate the embedded browser to a URL. Returns the page title and final URL after navigation completes.",
      {
        url: z.string().url().describe("The URL to navigate to"),
      },
      async (args, extra) => {
        const sessionId = extra?.sessionId ?? "";
        const commandType = "browser.navigate";
        logger.info("browser", `browser_navigate: session=${sessionId} url=${args.url}`);

        const result = await new Promise<string>((resolve) => {
          ctx.pendingBrowserResults.set(`${sessionId}:${commandType}`, resolve);
          ctx.broadcast({
            type: "browser.navigate",
            sessionId,
            url: args.url,
          } satisfies SidecarEvent);
        });

        return createTextResult(result);
      },
    ),

    // ─── browser_screenshot ──────────────────────────────────────────────────
    defineSharedTool(
      "browser_screenshot",
      "Capture a screenshot of the current browser view. Returns a base64-encoded PNG image description of what is visible.",
      {},
      async (_args, extra) => {
        const sessionId = extra?.sessionId ?? "";
        const commandType = "browser.screenshot";
        logger.info("browser", `browser_screenshot: session=${sessionId}`);

        const result = await new Promise<string>((resolve) => {
          ctx.pendingBrowserResults.set(`${sessionId}:${commandType}`, resolve);
          ctx.broadcast({
            type: "browser.screenshot",
            sessionId,
          } satisfies SidecarEvent);
        });

        return createTextResult(result);
      },
    ),

    // ─── browser_read_dom ────────────────────────────────────────────────────
    defineSharedTool(
      "browser_read_dom",
      "Read the current page DOM as simplified text. Returns the page title, URL, and a text representation of the visible page content useful for understanding structure and finding elements.",
      {},
      async (_args, extra) => {
        const sessionId = extra?.sessionId ?? "";
        const commandType = "browser.readDom";
        logger.info("browser", `browser_read_dom: session=${sessionId}`);

        const result = await new Promise<string>((resolve) => {
          ctx.pendingBrowserResults.set(`${sessionId}:${commandType}`, resolve);
          ctx.broadcast({
            type: "browser.readDom",
            sessionId,
          } satisfies SidecarEvent);
        });

        return createTextResult(result);
      },
    ),

    // ─── browser_click ───────────────────────────────────────────────────────
    defineSharedTool(
      "browser_click",
      "Click an element on the current page using a CSS selector. Returns confirmation and any resulting page changes.",
      {
        selector: z.string().describe("CSS selector for the element to click (e.g. '#submit-btn', '.nav-link', 'button[type=submit]')"),
      },
      async (args, extra) => {
        const sessionId = extra?.sessionId ?? "";
        const commandType = "browser.click";
        logger.info("browser", `browser_click: session=${sessionId} selector=${args.selector}`);

        const result = await new Promise<string>((resolve) => {
          ctx.pendingBrowserResults.set(`${sessionId}:${commandType}`, resolve);
          ctx.broadcast({
            type: "browser.click",
            sessionId,
            selector: args.selector,
          } satisfies SidecarEvent);
        });

        return createTextResult(result);
      },
    ),

    // ─── browser_type ────────────────────────────────────────────────────────
    defineSharedTool(
      "browser_type",
      "Type text into an input field on the current page. Clears the field first, then types the given text.",
      {
        selector: z.string().describe("CSS selector for the input element (e.g. '#search', 'input[name=email]')"),
        text: z.string().describe("Text to type into the field"),
      },
      async (args, extra) => {
        const sessionId = extra?.sessionId ?? "";
        const commandType = "browser.type";
        logger.info("browser", `browser_type: session=${sessionId} selector=${args.selector} text="${args.text.substring(0, 40)}..."`);

        const result = await new Promise<string>((resolve) => {
          ctx.pendingBrowserResults.set(`${sessionId}:${commandType}`, resolve);
          ctx.broadcast({
            type: "browser.type",
            sessionId,
            selector: args.selector,
            text: args.text,
          } satisfies SidecarEvent);
        });

        return createTextResult(result);
      },
    ),

    // ─── browser_scroll ──────────────────────────────────────────────────────
    defineSharedTool(
      "browser_scroll",
      "Scroll the page up or down by a given number of pixels.",
      {
        direction: z.enum(["up", "down"]).describe("Direction to scroll"),
        px: z.number().positive().describe("Number of pixels to scroll"),
      },
      async (args, extra) => {
        const sessionId = extra?.sessionId ?? "";
        const commandType = "browser.scroll";
        logger.info("browser", `browser_scroll: session=${sessionId} direction=${args.direction} px=${args.px}`);

        const result = await new Promise<string>((resolve) => {
          ctx.pendingBrowserResults.set(`${sessionId}:${commandType}`, resolve);
          ctx.broadcast({
            type: "browser.scroll",
            sessionId,
            direction: args.direction,
            px: args.px,
          } satisfies SidecarEvent);
        });

        return createTextResult(result);
      },
    ),

    // ─── browser_wait_for ────────────────────────────────────────────────────
    defineSharedTool(
      "browser_wait_for",
      "Wait for a CSS selector to appear in the DOM. Useful after navigation or clicking buttons that trigger dynamic content. Times out if the element does not appear.",
      {
        selector: z.string().describe("CSS selector to wait for"),
        timeoutMs: z.number().positive().optional().default(10000).describe("Maximum time to wait in milliseconds (default: 10000)"),
      },
      async (args, extra) => {
        const sessionId = extra?.sessionId ?? "";
        const commandType = "browser.waitFor";
        logger.info("browser", `browser_wait_for: session=${sessionId} selector=${args.selector} timeout=${args.timeoutMs}ms`);

        const result = await new Promise<string>((resolve) => {
          ctx.pendingBrowserResults.set(`${sessionId}:${commandType}`, resolve);
          ctx.broadcast({
            type: "browser.waitFor",
            sessionId,
            selector: args.selector,
            timeoutMs: args.timeoutMs ?? 10000,
          } satisfies SidecarEvent);
        });

        return createTextResult(result);
      },
    ),

    // ─── browser_get_console_logs ────────────────────────────────────────────
    defineSharedTool(
      "browser_get_console_logs",
      "Retrieve the browser console logs (errors, warnings, and info messages) from the current page session.",
      {},
      async (_args, extra) => {
        const sessionId = extra?.sessionId ?? "";
        const commandType = "browser.getConsoleLogs";
        logger.info("browser", `browser_get_console_logs: session=${sessionId}`);

        const result = await new Promise<string>((resolve) => {
          ctx.pendingBrowserResults.set(`${sessionId}:${commandType}`, resolve);
          ctx.broadcast({
            type: "browser.getConsoleLogs",
            sessionId,
          } satisfies SidecarEvent);
        });

        return createTextResult(result);
      },
    ),

    // ─── browser_get_network_logs ────────────────────────────────────────────
    defineSharedTool(
      "browser_get_network_logs",
      "Retrieve the network request/response log from the current page session. Useful for debugging API calls, checking request payloads, and monitoring network activity.",
      {},
      async (_args, extra) => {
        const sessionId = extra?.sessionId ?? "";
        const commandType = "browser.getNetworkLogs";
        logger.info("browser", `browser_get_network_logs: session=${sessionId}`);

        const result = await new Promise<string>((resolve) => {
          ctx.pendingBrowserResults.set(`${sessionId}:${commandType}`, resolve);
          ctx.broadcast({
            type: "browser.getNetworkLogs",
            sessionId,
          } satisfies SidecarEvent);
        });

        return createTextResult(result);
      },
    ),

    // ─── browser_yield_to_user (blocking) ────────────────────────────────────
    defineSharedTool(
      "browser_yield_to_user",
      "Pause agent control and hand the browser to the user with an explanatory message. The agent blocks until the user clicks Resume. Use this when the user needs to log in, complete a CAPTCHA, or perform an action the agent cannot automate.",
      {
        message: z.string().describe("Message shown to the user explaining what they need to do in the browser"),
      },
      async (args, extra) => {
        const sessionId = extra?.sessionId ?? "";
        logger.info("browser", `browser_yield_to_user: session=${sessionId} message="${args.message.substring(0, 80)}"`);

        const data = await new Promise<string>((resolve) => {
          ctx.pendingBrowserBlocking.set(sessionId, resolve);
          ctx.broadcast({
            type: "browser.yieldToUser",
            sessionId,
            message: args.message,
          } satisfies SidecarEvent);
        });

        return createTextResult("User resumed agent control." + (data ? " " + data : ""));
      },
    ),

    // ─── browser_render_html (blocking) ──────────────────────────────────────
    defineSharedTool(
      "browser_render_html",
      "Replace the browser content with custom HTML and hand control to the user. The agent blocks until the user clicks Resume or submits a form. Use this to display custom UI, collect structured input, or show a preview to the user.",
      {
        html: z.string().describe("Full HTML content to render in the browser"),
        title: z.string().optional().describe("Optional page title shown in the browser chrome"),
      },
      async (args, extra) => {
        const sessionId = extra?.sessionId ?? "";
        logger.info("browser", `browser_render_html: session=${sessionId} title="${args.title ?? "(untitled)"}" html length=${args.html.length}`);

        const data = await new Promise<string>((resolve) => {
          ctx.pendingBrowserBlocking.set(sessionId, resolve);
          ctx.broadcast({
            type: "browser.renderHtml",
            sessionId,
            html: args.html,
            title: args.title,
          } satisfies SidecarEvent);
        });

        return createTextResult("User resumed from rendered HTML." + (data ? " Submitted data: " + data : ""));
      },
    ),
  ];
}
