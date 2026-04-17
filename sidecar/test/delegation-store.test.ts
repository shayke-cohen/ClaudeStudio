import { describe, test, expect, beforeEach } from "bun:test";
import { DelegationStore } from "../src/stores/delegation-store.js";

describe("DelegationStore", () => {
  let store: DelegationStore;

  beforeEach(() => { store = new DelegationStore(); });

  test("defaults to off", () => {
    expect(store.get("session-1")).toEqual({ mode: "off" });
  });

  test("stores and retrieves mode", () => {
    store.set("session-1", { mode: "by_agents" });
    expect(store.get("session-1")).toEqual({ mode: "by_agents" });
  });

  test("resolveTarget: off mode returns nominated", () => {
    store.set("s1", { mode: "off" });
    expect(store.resolveTarget("s1", "Reviewer")).toBe("Reviewer");
  });

  test("resolveTarget: by_agents returns nominated", () => {
    store.set("s1", { mode: "by_agents" });
    expect(store.resolveTarget("s1", "Reviewer")).toBe("Reviewer");
  });

  test("resolveTarget: specific_agent overrides nominated", () => {
    store.set("s1", { mode: "specific_agent", targetAgentName: "PM" });
    expect(store.resolveTarget("s1", "Reviewer")).toBe("PM");
  });

  test("resolveTarget: coordinator uses stored targetAgentName", () => {
    store.set("s1", { mode: "coordinator", targetAgentName: "PM" });
    expect(store.resolveTarget("s1", "Reviewer")).toBe("PM");
  });

  test("resolveTarget: coordinator falls back to nominated if no targetAgentName", () => {
    store.set("s1", { mode: "coordinator" });
    expect(store.resolveTarget("s1", "Reviewer")).toBe("Reviewer");
  });
});
