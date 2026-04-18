/**
 * Structured JSON-line logger for the Odyssey sidecar.
 *
 * Each line written to stdout is a single JSON object:
 *   {"ts":"2026-03-26T12:01:02.123Z","level":"info","category":"ws","message":"Client connected"}
 *
 * The Swift app captures stdout → sidecar.log, and the DebugLogView parses
 * these lines for display and filtering.
 */

export type SidecarLogLevel = "debug" | "info" | "warn" | "error";

export interface LogEntry {
  ts: string;
  level: SidecarLogLevel;
  category: string;
  message: string;
  data?: Record<string, unknown>;
}

const LEVEL_ORDER: Record<SidecarLogLevel, number> = {
  debug: 0,
  info: 1,
  warn: 2,
  error: 3,
};

let currentLevel: SidecarLogLevel = "info";

const LOG_BUFFER_MAX = 500;
const logBuffer: LogEntry[] = [];

function pushToBuffer(entry: LogEntry): void {
  logBuffer.push(entry);
  if (logBuffer.length > LOG_BUFFER_MAX) logBuffer.shift();
}

/** Set the minimum log level. Messages below this level are suppressed. */
export function setLogLevel(level: SidecarLogLevel): void {
  if (level in LEVEL_ORDER) {
    currentLevel = level;
  }
}

/** Emit a structured log line to stdout/stderr. */
export function log(
  level: SidecarLogLevel,
  category: string,
  message: string,
  data?: Record<string, unknown>,
): void {
  if (LEVEL_ORDER[level] < LEVEL_ORDER[currentLevel]) return;

  const entry: LogEntry = {
    ts: new Date().toISOString(),
    level,
    category,
    message,
    ...(data ? { data } : {}),
  };
  pushToBuffer(entry);

  const line = JSON.stringify(entry);

  // Route to the appropriate console method so Bun/Node colouring still works
  // when running interactively, while the Swift app captures everything via
  // the redirected stdout/stderr file handles.
  switch (level) {
    case "error":
      console.error(line);
      break;
    case "warn":
      console.warn(line);
      break;
    default:
      console.log(line);
      break;
  }
}

export function getLogBuffer(opts?: { tail?: number; category?: string; level?: SidecarLogLevel }): LogEntry[] {
  let entries = [...logBuffer];
  if (opts?.category) entries = entries.filter((e) => e.category === opts.category);
  if (opts?.level) entries = entries.filter((e) => e.level === opts.level);
  if (opts?.tail && opts.tail > 0) entries = entries.slice(-opts.tail);
  return entries;
}

/** Convenience wrappers scoped by category. */
export const logger = {
  debug: (category: string, message: string, data?: Record<string, unknown>) =>
    log("debug", category, message, data),
  info: (category: string, message: string, data?: Record<string, unknown>) =>
    log("info", category, message, data),
  warn: (category: string, message: string, data?: Record<string, unknown>) =>
    log("warn", category, message, data),
  error: (category: string, message: string, data?: Record<string, unknown>) =>
    log("error", category, message, data),
};
